-- Statements close chronologically from the card control date. The normal close
-- flow can only close an effective statement date that has already arrived.

create function public.card_next_pending_statement_date(
  p_card_id uuid,
  p_as_of_date date
)
returns date
language sql
stable
strict
security invoker
set search_path = ''
as $$
  with card_context as (
    select card.id, card.statement_day, baseline.baseline_date
    from public.credit_cards card
    join public.card_baselines baseline on baseline.card_id = card.id
    where card.id = p_card_id
  ), candidates as (
    select distinct public.card_effective_statement_date(
      extract(year from month_start)::integer,
      extract(month from month_start)::integer,
      context.statement_day
    ) as statement_date
    from card_context context
    cross join lateral generate_series(
      date_trunc('month', context.baseline_date::timestamp),
      date_trunc('month', p_as_of_date::timestamp),
      interval '1 month'
    ) month_start
  )
  select min(candidate.statement_date)
  from candidates candidate
  join card_context context on true
  where candidate.statement_date > context.baseline_date
    and candidate.statement_date <= p_as_of_date
    and not exists (
      select 1
      from public.card_statements statement
      where statement.card_id = context.id
        and statement.statement_date = candidate.statement_date
    );
$$;

create function public.card_statement_preview_balance(
  p_card_id uuid,
  p_statement_date date
)
returns bigint
language sql
stable
strict
security invoker
set search_path = ''
as $$
  with card_context as (
    select
      card.id,
      card.user_id,
      card.statement_day,
      baseline.baseline_date,
      baseline.baseline_balance_minor,
      public.card_previous_statement_date(p_statement_date, card.statement_day) as cycle_start
    from public.credit_cards card
    join public.card_baselines baseline on baseline.card_id = card.id
    where card.id = p_card_id
  )
  select greatest(
    case
      when context.baseline_date >= context.cycle_start
        and context.baseline_date < p_statement_date
      then context.baseline_balance_minor
      else 0
    end
    + coalesce(sum(entry.amount_minor) filter (where event.id is not null), 0),
    0
  )
  from card_context context
  left join public.financial_events event
    on event.user_id = context.user_id
    and event.occurred_on >= greatest(context.cycle_start, context.baseline_date)
    and event.occurred_on < p_statement_date
    and event.kind in ('card_charge', 'card_refund', 'card_adjustment')
    and not exists (
      select 1
      from public.financial_events reversal
      where reversal.reverses_event_id = event.id
    )
  left join public.card_entries entry
    on entry.financial_event_id = event.id
    and entry.card_id = context.id
    and entry.effect_scope = 'impacting'
  group by context.baseline_date, context.cycle_start, context.baseline_balance_minor;
$$;

revoke all on function public.card_next_pending_statement_date(uuid, date) from public, anon;
revoke all on function public.card_statement_preview_balance(uuid, date) from public, anon;
grant execute on function public.card_next_pending_statement_date(uuid, date) to authenticated;
grant execute on function public.card_statement_preview_balance(uuid, date) to authenticated;

create view public.card_statement_close_candidates
with (security_invoker = true)
as
select
  card.id as card_id,
  card.user_id,
  pending.statement_date,
  public.card_previous_statement_date(pending.statement_date, card.statement_day) as cycle_start,
  pending.statement_date as cycle_end,
  public.card_due_date(pending.statement_date, card.payment_days_after_statement) as payment_due_date,
  public.card_statement_preview_balance(card.id, pending.statement_date) as statement_balance_minor
from public.credit_cards card
cross join lateral (
  select public.card_next_pending_statement_date(card.id, current_date) as statement_date
) pending
where pending.statement_date is not null;

revoke all on table public.card_statement_close_candidates from anon, authenticated;
grant select on table public.card_statement_close_candidates to authenticated;
grant all on table public.card_statement_close_candidates to service_role;

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
  ) then
    raise exception 'NEXO_INVALID_STATEMENT_DATE' using errcode = '22023';
  end if;
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
  if statement_balance is null then
    raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;
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

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'card_statement_closed', 'card_statement', proposed_statement_id,
    jsonb_build_object(
      'card_id', p_card_id,
      'statement_date', p_statement_date,
      'statement_balance_minor', statement_balance::text
    )
  );
  return proposed_statement_id;
end;
$$;
