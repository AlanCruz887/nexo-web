-- Advance card payments are derived from the immutable payment event minus its
-- real allocations. Their open-cycle association is temporal and never a fake
-- foreign key to a statement that does not exist yet.

create view public.card_payment_classifications
with (security_invoker = true)
as
with active_payments as (
  select event.*
  from public.financial_events event
  where event.kind = 'card_payment'
    and not exists (
      select 1 from public.financial_events reversal
      where reversal.reverses_event_id = event.id
    )
), classified as (
  select
    event.id as event_id,
    event.user_id,
    detail.card_id,
    detail.source_account_id,
    event.amount_minor,
    event.occurred_on,
    coalesce(allocation.applied_amount_minor, 0) as applied_amount_minor,
    greatest(event.amount_minor - coalesce(allocation.applied_amount_minor, 0), 0) as advance_amount_minor,
    public.card_statement_for_date(event.occurred_on, card.statement_day) as cycle_statement_date,
    card.statement_day
  from active_payments event
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  left join lateral (
    select sum(item.amount_minor) as applied_amount_minor
    from public.card_statement_payment_allocations item
    where item.financial_event_id = event.id and item.amount_minor > 0
  ) allocation on true
)
select
  classified.event_id,
  classified.user_id,
  classified.card_id,
  classified.source_account_id,
  classified.amount_minor,
  classified.applied_amount_minor,
  classified.advance_amount_minor,
  case
    when classified.advance_amount_minor = classified.amount_minor then 'advance'
    when classified.advance_amount_minor > 0 then 'mixed'
    else 'applied'
  end as payment_state,
  public.card_previous_statement_date(classified.cycle_statement_date, classified.statement_day) as cycle_start,
  classified.cycle_statement_date as cycle_end,
  classified.cycle_statement_date
from classified;

create view public.card_statement_activity_segments
with (security_invoker = true)
as
with active_events as (
  select event.*
  from public.financial_events event
  where event.kind <> 'reversal'
    and not exists (
      select 1 from public.financial_events reversal
      where reversal.reverses_event_id = event.id
    )
), purchases_and_refunds as (
  select
    event.id::text as segment_id,
    event.id as event_id,
    event.user_id,
    detail.card_id,
    event.kind,
    case when event.kind = 'card_charge' then 'purchase' else 'refund' end as segment_kind,
    event.amount_minor,
    event.description,
    event.occurred_on,
    detail.statement_date as group_statement_date,
    public.card_previous_statement_date(detail.statement_date, card.statement_day) as cycle_start,
    detail.statement_date as cycle_end,
    null::text as source_account_name,
    card.is_active as source_is_active
  from active_events event
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  where event.kind in ('card_charge', 'card_refund')
), applied_payments as (
  select
    event.id::text || ':statement:' || statement.id::text as segment_id,
    event.id as event_id,
    event.user_id,
    detail.card_id,
    event.kind,
    'payment_applied'::text as segment_kind,
    allocation.amount_minor,
    event.description,
    event.occurred_on,
    statement.statement_date as group_statement_date,
    statement.cycle_start,
    statement.cycle_end,
    account.name as source_account_name,
    card.is_active as source_is_active
  from active_events event
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  join public.card_statement_payment_allocations allocation
    on allocation.financial_event_id = event.id and allocation.amount_minor > 0
  join public.card_statements statement on statement.id = allocation.statement_id
  left join public.accounts account on account.id = detail.source_account_id
  where event.kind = 'card_payment'
), advance_payments as (
  select
    event.id::text || ':advance' as segment_id,
    event.id as event_id,
    event.user_id,
    detail.card_id,
    event.kind,
    'payment_advance'::text as segment_kind,
    classification.advance_amount_minor as amount_minor,
    event.description,
    event.occurred_on,
    classification.cycle_statement_date as group_statement_date,
    classification.cycle_start,
    classification.cycle_end,
    account.name as source_account_name,
    card.is_active as source_is_active
  from active_events event
  join public.card_payment_classifications classification on classification.event_id = event.id
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  left join public.accounts account on account.id = detail.source_account_id
  where event.kind = 'card_payment' and classification.advance_amount_minor > 0
)
select * from purchases_and_refunds
union all select * from applied_payments
union all select * from advance_payments;

revoke all on table public.card_payment_classifications from anon, authenticated;
revoke all on table public.card_statement_activity_segments from anon, authenticated;
grant select on table public.card_payment_classifications to authenticated;
grant select on table public.card_statement_activity_segments to authenticated;
grant all on table public.card_payment_classifications to service_role;
grant all on table public.card_statement_activity_segments to service_role;

create or replace function public.close_card_statement(
  p_card_id uuid,
  p_statement_date date,
  p_payment_to_avoid_interest_minor bigint,
  p_minimum_payment_minor bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_statement_id uuid := gen_random_uuid();
  resolved_statement_id uuid;
  target_card public.credit_cards%rowtype;
  pending_statement_date date;
  cycle_start_date date;
  due_date date;
  statement_balance bigint;
  payment_to_avoid bigint;
  remaining_statement bigint;
  advance_applied bigint := 0;
  allocation_amount bigint;
  advance_payment record;
  payload jsonb;
begin
  select * into target_card
  from public.credit_cards
  where id = p_card_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;

  payload := jsonb_build_object(
    'card_id', p_card_id,
    'statement_date', p_statement_date,
    'payment_to_avoid_interest_minor', p_payment_to_avoid_interest_minor::text,
    'minimum_payment_minor', p_minimum_payment_minor::text
  );
  resolved_statement_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'close_card_statement', payload, proposed_statement_id
  );
  if resolved_statement_id <> proposed_statement_id then return resolved_statement_id; end if;

  if p_statement_date <> public.card_effective_statement_date(
    extract(year from p_statement_date)::integer,
    extract(month from p_statement_date)::integer,
    target_card.statement_day
  ) then raise exception 'NEXO_INVALID_STATEMENT_DATE' using errcode = '22023'; end if;
  if p_statement_date > current_date then
    raise exception 'NEXO_STATEMENT_NOT_DUE' using errcode = '22023';
  end if;

  pending_statement_date := public.card_next_pending_statement_date(p_card_id, current_date);
  if pending_statement_date is null then
    raise exception 'NEXO_NO_STATEMENT_DUE' using errcode = '22023';
  end if;
  if p_statement_date <> pending_statement_date then
    raise exception 'NEXO_STATEMENT_OUT_OF_ORDER' using errcode = '22023';
  end if;

  cycle_start_date := public.card_previous_statement_date(p_statement_date, target_card.statement_day);
  due_date := public.card_due_date(p_statement_date, target_card.payment_days_after_statement);
  statement_balance := public.card_statement_preview_balance(p_card_id, p_statement_date);
  if statement_balance is null then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  payment_to_avoid := coalesce(p_payment_to_avoid_interest_minor, statement_balance);
  if payment_to_avoid < 0 or p_minimum_payment_minor < 0 then
    raise exception 'NEXO_INVALID_STATEMENT_AMOUNT' using errcode = '22023';
  end if;

  insert into public.card_statements (
    id, user_id, card_id, statement_date, cycle_start, cycle_end,
    statement_balance_minor, payment_due_date, payment_to_avoid_interest_minor,
    minimum_payment_minor, amount_paid_minor, remaining_due_minor, status
  ) values (
    proposed_statement_id, command_user_id, p_card_id, p_statement_date,
    cycle_start_date, p_statement_date, statement_balance, due_date,
    payment_to_avoid, p_minimum_payment_minor, 0, statement_balance, 'closed'
  );

  remaining_statement := statement_balance;
  for advance_payment in
    select
      event.id as event_id,
      event.amount_minor - coalesce(sum(allocation.amount_minor) filter (where allocation.amount_minor > 0), 0) as available_minor
    from public.financial_events event
    join public.card_transaction_details detail on detail.financial_event_id = event.id
    left join public.card_statement_payment_allocations allocation on allocation.financial_event_id = event.id
    where event.user_id = command_user_id
      and event.kind = 'card_payment'
      and detail.card_id = p_card_id
      and event.occurred_on >= cycle_start_date
      and event.occurred_on < p_statement_date
      and not exists (
        select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id
      )
    group by event.id, event.amount_minor, event.occurred_on, event.created_at
    having event.amount_minor - coalesce(sum(allocation.amount_minor) filter (where allocation.amount_minor > 0), 0) > 0
    order by event.occurred_on, event.created_at
  loop
    exit when remaining_statement = 0;
    allocation_amount := least(advance_payment.available_minor, remaining_statement);
    insert into public.card_statement_payment_allocations (
      user_id, financial_event_id, statement_id, amount_minor
    ) values (
      command_user_id, advance_payment.event_id, proposed_statement_id, allocation_amount
    );
    remaining_statement := remaining_statement - allocation_amount;
    advance_applied := advance_applied + allocation_amount;
  end loop;

  if advance_applied > 0 then
    update public.card_statements set
      amount_paid_minor = advance_applied,
      remaining_due_minor = remaining_statement,
      status = case when remaining_statement = 0 then 'paid' else 'closed' end
    where id = proposed_statement_id;
  end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'card_statement_closed', 'card_statement', proposed_statement_id,
    jsonb_build_object(
      'card_id', p_card_id,
      'statement_date', p_statement_date,
      'statement_balance_minor', statement_balance::text,
      'advance_payments_applied_minor', advance_applied::text
    )
  );
  return proposed_statement_id;
end;
$$;
