-- Phase 4B: existing MSI plans. Historical imports preserve reported payments
-- separately from principal amortization and never synthesize purchases or
-- bank payments. Their only card-ledger effect is the remaining principal when
-- the user explicitly says it was not included in the opening balance.

drop view public.card_statement_activity_segments;
drop view public.financial_activity_enriched;
drop view public.installment_plan_summaries;
drop view public.installment_schedule;

alter table public.installment_plans
  add column origin text not null default 'new',
  add column included_in_opening_balance boolean not null default false,
  add column reported_paid_amount_minor bigint not null default 0,
  add column principal_paid_before_nexo_minor bigint not null default 0,
  add column initial_paid_before_count smallint not null default 0,
  add constraint installment_plans_origin_valid check (origin in ('new', 'historical')),
  add constraint installment_plans_historical_values_valid check (
    reported_paid_amount_minor >= 0
    and principal_paid_before_nexo_minor >= 0
    and principal_paid_before_nexo_minor <= original_amount_minor
    and initial_paid_before_count >= 0
    and initial_paid_before_count < installment_count
    and (
      (origin = 'new' and included_in_opening_balance = false
        and reported_paid_amount_minor = 0 and principal_paid_before_nexo_minor = 0
        and initial_paid_before_count = 0)
      or origin = 'historical'
    )
  );

alter table public.installments
  add column reported_amount_minor bigint,
  drop constraint installments_status_valid,
  add constraint installments_status_valid check (status in ('scheduled', 'paid_before_nexo', 'cancelled'));

update public.installments set reported_amount_minor = principal_minor;
alter table public.installments
  alter column reported_amount_minor set not null,
  add constraint installments_reported_amount_positive check (reported_amount_minor > 0);

create function private.default_installment_reported_amount()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.reported_amount_minor is null then
    new.reported_amount_minor := new.principal_minor;
  end if;
  return new;
end;
$$;

create trigger installments_default_reported_amount
before insert on public.installments
for each row execute function private.default_installment_reported_amount();

create function private.audit_historical_installment_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.installment_plans plan
    where plan.id = new.plan_id and plan.origin = 'historical'
  ) then
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (
      new.user_id, 'historical_installment_plan_corrected', 'installment_plan', new.plan_id,
      jsonb_build_object('metadata_revision_id', new.id, 'scope', 'metadata_only')
    );
  end if;
  return new;
end;
$$;

create trigger installment_metadata_audit_historical_correction
after insert on public.installment_plan_metadata_revisions
for each row execute function private.audit_historical_installment_metadata();

create function public.import_historical_installment_plan(
  p_card_id uuid,
  p_description text,
  p_original_amount_minor bigint,
  p_installment_count integer,
  p_installment_amount_minor bigint,
  p_original_purchase_date date,
  p_current_installment_number integer,
  p_paid_before_count integer,
  p_reported_paid_amount_minor bigint,
  p_principal_paid_minor bigint,
  p_next_statement_date date,
  p_category_id text,
  p_notes text,
  p_included_in_opening_balance boolean,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_plan_id uuid := gen_random_uuid();
  proposed_event_id uuid := gen_random_uuid();
  resolved_plan_id uuid;
  target_card public.credit_cards%rowtype;
  target_baseline public.card_baselines%rowtype;
  normalized_description text := nullif(btrim(p_description), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  remaining_principal bigint;
  additional_impact bigint;
  reported_final bigint;
  paid_principal_regular bigint := 0;
  remaining_principal_regular bigint;
  principal_value bigint;
  reported_value bigint;
  installment_number integer;
  installment_statement_date date;
  month_cursor date;
  payload jsonb;
begin
  if p_original_amount_minor <= 0 or p_installment_amount_minor <= 0 then
    raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023';
  end if;
  if p_installment_count < 2 or p_installment_count > 60 then
    raise exception 'NEXO_INVALID_INSTALLMENT_COUNT' using errcode = '22023';
  end if;
  if p_current_installment_number < 1 or p_current_installment_number > p_installment_count
    or p_paid_before_count <> p_current_installment_number - 1 then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_PROGRESS' using errcode = '22023';
  end if;
  if p_reported_paid_amount_minor < 0 or p_principal_paid_minor < 0
    or p_principal_paid_minor >= p_original_amount_minor then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023';
  end if;
  if (p_paid_before_count = 0 and p_principal_paid_minor <> 0)
    or (p_paid_before_count > 0 and p_principal_paid_minor < p_paid_before_count) then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023';
  end if;
  if normalized_description is null or char_length(normalized_description) > 160 then
    raise exception 'NEXO_INVALID_DESCRIPTION' using errcode = '22023';
  end if;
  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'NEXO_NOTES_TOO_LONG' using errcode = '22023';
  end if;
  if p_original_purchase_date > current_date then
    raise exception 'NEXO_HISTORICAL_PURCHASE_IN_FUTURE' using errcode = '22023';
  end if;

  select * into target_card
  from public.credit_cards
  where id = p_card_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;

  select * into strict target_baseline
  from public.card_baselines
  where card_id = p_card_id and user_id = command_user_id;

  if p_included_in_opening_balance and p_original_purchase_date > target_baseline.baseline_date then
    raise exception 'NEXO_HISTORICAL_MSI_NOT_IN_OPENING_PERIOD' using errcode = '22023';
  end if;
  if public.card_effective_statement_date(
      extract(year from p_next_statement_date)::integer,
      extract(month from p_next_statement_date)::integer,
      target_card.statement_day
    ) <> p_next_statement_date
    or p_next_statement_date < public.card_statement_for_date(target_baseline.baseline_date, target_card.statement_day) then
    raise exception 'NEXO_INVALID_STATEMENT_DATE' using errcode = '22023';
  end if;

  remaining_principal := p_original_amount_minor - p_principal_paid_minor;
  if remaining_principal < (p_installment_count - p_paid_before_count) then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023';
  end if;
  reported_final := p_original_amount_minor - p_installment_amount_minor * (p_installment_count - 1);
  if reported_final <= 0 then
    raise exception 'NEXO_INVALID_INSTALLMENT_AMOUNT' using errcode = '22023';
  end if;

  -- A current/future installment cannot be injected into an immutable statement.
  if exists (
    select 1
    from generate_series(p_current_installment_number, p_installment_count) number(installment_number)
    join public.card_statements statement
      on statement.card_id = p_card_id
      and statement.statement_date = public.card_effective_statement_date(
        extract(year from (p_next_statement_date + make_interval(months => number.installment_number - p_current_installment_number)))::integer,
        extract(month from (p_next_statement_date + make_interval(months => number.installment_number - p_current_installment_number)))::integer,
        target_card.statement_day
      )
  ) then
    raise exception 'NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514';
  end if;

  additional_impact := case when p_included_in_opening_balance then 0 else remaining_principal end;
  payload := jsonb_build_object(
    'card_id', p_card_id,
    'description', normalized_description,
    'original_amount_minor', p_original_amount_minor::text,
    'installment_count', p_installment_count,
    'installment_amount_minor', p_installment_amount_minor::text,
    'original_purchase_date', p_original_purchase_date,
    'current_installment_number', p_current_installment_number,
    'paid_before_count', p_paid_before_count,
    'reported_paid_amount_minor', p_reported_paid_amount_minor::text,
    'principal_paid_minor', p_principal_paid_minor::text,
    'next_statement_date', p_next_statement_date,
    'category_id', p_category_id,
    'notes', normalized_notes,
    'included_in_opening_balance', p_included_in_opening_balance
  );
  resolved_plan_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'import_historical_installment_plan', payload, proposed_plan_id
  );
  if resolved_plan_id <> proposed_plan_id then return resolved_plan_id; end if;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'card_adjustment', remaining_principal, 0,
    normalized_description, p_category_id, target_baseline.baseline_date, normalized_notes
  );
  insert into public.card_entries (
    user_id, financial_event_id, card_id, amount_minor, effect_scope
  ) values (
    command_user_id, proposed_event_id, p_card_id, remaining_principal,
    case when p_included_in_opening_balance then 'historical_non_impacting' else 'impacting' end
  );
  insert into public.installment_plans (
    id, user_id, card_id, purchase_event_id, original_amount_minor,
    installment_count, installment_amount_minor, currency, start_date,
    first_statement_date, status, origin, included_in_opening_balance,
    reported_paid_amount_minor, principal_paid_before_nexo_minor,
    initial_paid_before_count
  ) values (
    proposed_plan_id, command_user_id, p_card_id, proposed_event_id, p_original_amount_minor,
    p_installment_count, p_installment_amount_minor, target_card.currency, p_original_purchase_date,
    p_next_statement_date, 'active', 'historical', p_included_in_opening_balance,
    p_reported_paid_amount_minor, p_principal_paid_minor, p_paid_before_count
  );

  if p_paid_before_count > 0 then
    paid_principal_regular := p_principal_paid_minor / p_paid_before_count;
  end if;
  remaining_principal_regular := remaining_principal / (p_installment_count - p_paid_before_count);

  for installment_number in 1..p_installment_count loop
    month_cursor := p_next_statement_date + make_interval(months => installment_number - p_current_installment_number);
    installment_statement_date := public.card_effective_statement_date(
      extract(year from month_cursor)::integer,
      extract(month from month_cursor)::integer,
      target_card.statement_day
    );
    reported_value := case
      when installment_number = p_installment_count then reported_final
      else p_installment_amount_minor
    end;
    principal_value := case
      when installment_number <= p_paid_before_count then
        case when installment_number = p_paid_before_count
          then p_principal_paid_minor - paid_principal_regular * (p_paid_before_count - 1)
          else paid_principal_regular end
      when installment_number = p_installment_count then
        remaining_principal - remaining_principal_regular * (p_installment_count - p_paid_before_count - 1)
      else remaining_principal_regular
    end;
    if principal_value <= 0 then
      raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023';
    end if;
    insert into public.installments (
      user_id, plan_id, installment_number, due_statement_date,
      principal_minor, reported_amount_minor, status
    ) values (
      command_user_id, proposed_plan_id, installment_number, installment_statement_date,
      principal_value, reported_value,
      case when installment_number <= p_paid_before_count then 'paid_before_nexo' else 'scheduled' end
    );
  end loop;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'historical_installment_plan_imported', 'installment_plan', proposed_plan_id,
    payload || jsonb_build_object(
      'purchase_event_id', proposed_event_id,
      'remaining_principal_minor', remaining_principal::text,
      'additional_card_impact_minor', additional_impact::text
    )
  );
  return proposed_plan_id;
end;
$$;

create or replace function public.reverse_installment_purchase(
  p_plan_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_reversal_id uuid := gen_random_uuid();
  resolved_reversal_id uuid;
  target_plan public.installment_plans%rowtype;
  original_event public.financial_events%rowtype;
  payload jsonb := jsonb_build_object('plan_id', p_plan_id);
begin
  select * into target_plan from public.installment_plans
  where id = p_plan_id and user_id = command_user_id
  for update;
  if not found or target_plan.status <> 'active' then
    raise exception 'NEXO_INSTALLMENT_PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.installments installment
    join public.card_statements statement
      on statement.card_id = target_plan.card_id
      and statement.statement_date = installment.due_statement_date
    where installment.plan_id = p_plan_id
      and installment.status = 'scheduled'
  ) then
    raise exception 'NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514';
  end if;
  resolved_reversal_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_installment_purchase', payload, proposed_reversal_id
  );
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;

  if target_plan.origin = 'historical' then
    select * into strict original_event
    from public.financial_events
    where id = target_plan.purchase_event_id and user_id = command_user_id;
    insert into public.financial_events (
      id, user_id, kind, amount_minor, personal_amount_minor,
      description, occurred_on, notes, reverses_event_id
    ) values (
      proposed_reversal_id, command_user_id, 'reversal', original_event.amount_minor, 0,
      'Reversión de importación MSI histórica', current_date, original_event.notes, original_event.id
    );
    insert into public.card_entries (
      user_id, financial_event_id, card_id, amount_minor, effect_scope
    )
    select command_user_id, proposed_reversal_id, entry.card_id, -entry.amount_minor, entry.effect_scope
    from public.card_entries entry
    where entry.financial_event_id = original_event.id and entry.user_id = command_user_id;
  else
    perform set_config('nexo.allow_msi_reversal', 'on', true);
    perform private.reverse_card_event(
      command_user_id, target_plan.purchase_event_id, proposed_reversal_id, 'Reversión de compra MSI'
    );
  end if;

  update public.installment_plans set status = 'reversed' where id = p_plan_id;
  update public.installments set status = 'cancelled'
  where plan_id = p_plan_id and status <> 'cancelled';
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id,
    case when target_plan.origin = 'historical'
      then 'historical_installment_plan_reversed' else 'installment_purchase_reversed' end,
    'installment_plan', p_plan_id,
    jsonb_build_object(
      'purchase_event_id', target_plan.purchase_event_id,
      'reversal_event_id', proposed_reversal_id,
      'additional_card_impact_reversed_minor',
        case
          when target_plan.origin = 'historical' and target_plan.included_in_opening_balance then '0'
          when target_plan.origin = 'historical' then original_event.amount_minor::text
          else target_plan.original_amount_minor::text
        end
    )
  );
  return proposed_reversal_id;
end;
$$;

create view public.installment_schedule
with (security_invoker = true)
as
select
  installment.id,
  installment.user_id,
  installment.plan_id,
  installment.installment_number,
  installment.due_statement_date,
  installment.principal_minor,
  installment.reported_amount_minor,
  case
    when plan.status = 'reversed' or installment.status = 'cancelled' then 'reversed'
    when installment.status = 'paid_before_nexo' then 'paid_before_nexo'
    when statement.status = 'paid' then 'paid'
    when statement.id is not null then 'pending'
    else 'future'
  end as effective_status,
  statement.id as statement_id,
  statement.remaining_due_minor as statement_remaining_due_minor,
  installment.created_at
from public.installments installment
join public.installment_plans plan on plan.id = installment.plan_id
left join public.card_statements statement
  on statement.card_id = plan.card_id
  and statement.statement_date = installment.due_statement_date;

create view public.installment_plan_summaries
with (security_invoker = true)
as
select
  plan.id,
  plan.user_id,
  plan.card_id,
  plan.purchase_event_id,
  plan.original_amount_minor,
  plan.installment_count,
  plan.installment_amount_minor,
  plan.currency,
  plan.start_date,
  plan.first_statement_date,
  case when plan.status = 'active' and progress.paid_count = plan.installment_count then 'completed' else plan.status end as status,
  plan.origin,
  plan.included_in_opening_balance,
  plan.reported_paid_amount_minor,
  plan.principal_paid_before_nexo_minor,
  plan.initial_paid_before_count,
  case
    when plan.origin = 'historical' and plan.included_in_opening_balance then 0
    when plan.origin = 'historical' then plan.original_amount_minor - plan.principal_paid_before_nexo_minor
    else plan.original_amount_minor
  end as additional_card_impact_minor,
  plan.created_at,
  plan.updated_at,
  card.name as card_name,
  coalesce(metadata.description, event.description) as description,
  coalesce(metadata.category_id, event.category_id) as category_id,
  category.name as category_name,
  coalesce(metadata.notes, event.notes) as notes,
  progress.paid_before_nexo_count,
  progress.paid_in_nexo_count,
  progress.paid_count,
  progress.pending_count,
  progress.remaining_principal_minor,
  next_installment.installment_number as current_installment_number,
  next_installment.reported_amount_minor as current_installment_minor,
  next_installment.principal_minor as current_installment_principal_minor,
  next_installment.due_statement_date as next_statement_date
from public.installment_plans plan
join public.credit_cards card on card.id = plan.card_id
join public.financial_events event on event.id = plan.purchase_event_id
left join lateral (
  select revision.description, revision.category_id, revision.notes
  from public.installment_plan_metadata_revisions revision
  where revision.plan_id = plan.id
  order by revision.created_at desc, revision.id desc
  limit 1
) metadata on true
left join public.categories category on category.id = coalesce(metadata.category_id, event.category_id)
cross join lateral (
  select
    count(*) filter (where schedule.effective_status = 'paid_before_nexo')::integer as paid_before_nexo_count,
    count(*) filter (where schedule.effective_status = 'paid')::integer as paid_in_nexo_count,
    count(*) filter (where schedule.effective_status in ('paid_before_nexo', 'paid'))::integer as paid_count,
    count(*) filter (where schedule.effective_status in ('future', 'pending'))::integer as pending_count,
    coalesce(sum(schedule.principal_minor) filter (where schedule.effective_status in ('future', 'pending')), 0) as remaining_principal_minor
  from public.installment_schedule schedule
  where schedule.plan_id = plan.id
) progress
left join lateral (
  select schedule.installment_number, schedule.reported_amount_minor,
    schedule.principal_minor, schedule.due_statement_date
  from public.installment_schedule schedule
  where schedule.plan_id = plan.id and schedule.effective_status in ('future', 'pending')
  order by schedule.installment_number
  limit 1
) next_installment on true;

create view public.financial_activity_enriched
with (security_invoker = true)
as
select
  activity.*,
  plan.id as installment_plan_id,
  plan.installment_count,
  plan.installment_amount_minor,
  plan.status as installment_plan_status,
  plan.description as installment_description,
  plan.category_id as installment_category_id,
  plan.category_name as installment_category_name,
  plan.notes as installment_notes,
  plan.origin as installment_origin
from public.financial_activity activity
left join public.installment_plan_summaries plan on plan.purchase_event_id = activity.event_id;

create or replace function public.card_statement_preview_balance(
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
  ), included_historical_principal as (
    select coalesce(sum(plan.original_amount_minor - plan.principal_paid_before_nexo_minor), 0) as amount_minor
    from public.installment_plans plan
    where plan.card_id = p_card_id
      and plan.origin = 'historical'
      and plan.included_in_opening_balance
      and plan.status = 'active'
  ), cycle_activity as (
    select coalesce(sum(entry.amount_minor), 0) as amount_minor
    from card_context context
    join public.financial_events event
      on event.user_id = context.user_id
      and event.occurred_on >= greatest(context.cycle_start, context.baseline_date)
      and event.occurred_on < p_statement_date
      and event.kind in ('card_charge', 'card_refund', 'card_adjustment')
      and not exists (
        select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id
      )
      and not exists (
        select 1 from public.installment_plans plan
        where plan.purchase_event_id = event.id and plan.status = 'active'
      )
    join public.card_entries entry
      on entry.financial_event_id = event.id
      and entry.card_id = context.id
      and entry.effect_scope = 'impacting'
  ), installment_activity as (
    select coalesce(sum(installment.reported_amount_minor), 0) as amount_minor
    from public.installments installment
    join public.installment_plans plan on plan.id = installment.plan_id
    where plan.card_id = p_card_id
      and plan.status = 'active'
      and installment.status = 'scheduled'
      and installment.due_statement_date = p_statement_date
  )
  select greatest(
    case
      when context.baseline_date >= context.cycle_start and context.baseline_date < p_statement_date
      then greatest(context.baseline_balance_minor - included.amount_minor, 0)
      else 0
    end + cycle.amount_minor + installments.amount_minor,
    0
  )
  from card_context context
  cross join included_historical_principal included
  cross join cycle_activity cycle
  cross join installment_activity installments;
$$;

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
    event.id::text as segment_id, event.id as event_id, event.user_id, detail.card_id,
    event.kind, case when event.kind = 'card_charge' then 'purchase' else 'refund' end as segment_kind,
    event.amount_minor, event.description, event.occurred_on,
    detail.statement_date as group_statement_date,
    public.card_previous_statement_date(detail.statement_date, card.statement_day) as cycle_start,
    detail.statement_date as cycle_end, null::text as source_account_name,
    card.is_active as source_is_active
  from active_events event
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  where event.kind in ('card_charge', 'card_refund')
    and not exists (
      select 1 from public.installment_plans plan
      where plan.purchase_event_id = event.id and plan.status = 'active'
    )
), installment_segments as (
  select
    installment.id::text as segment_id, plan.purchase_event_id as event_id,
    plan.user_id, plan.card_id, 'card_charge'::text as kind,
    'installment'::text as segment_kind,
    installment.reported_amount_minor as amount_minor,
    summary.description || ' · Mensualidad ' || installment.installment_number::text ||
      ' de ' || plan.installment_count::text as description,
    plan.start_date as occurred_on,
    installment.due_statement_date as group_statement_date,
    public.card_previous_statement_date(installment.due_statement_date, card.statement_day) as cycle_start,
    installment.due_statement_date as cycle_end,
    null::text as source_account_name, card.is_active as source_is_active
  from public.installments installment
  join public.installment_plans plan on plan.id = installment.plan_id
  join public.installment_plan_summaries summary on summary.id = plan.id
  join public.credit_cards card on card.id = plan.card_id
  where plan.status = 'active' and installment.status = 'scheduled'
), applied_payments as (
  select
    event.id::text || ':statement:' || statement.id::text as segment_id,
    event.id as event_id, event.user_id, detail.card_id, event.kind,
    'payment_applied'::text as segment_kind, allocation.amount_minor,
    event.description, event.occurred_on, statement.statement_date as group_statement_date,
    statement.cycle_start, statement.cycle_end, account.name as source_account_name,
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
    event.id::text || ':advance' as segment_id, event.id as event_id,
    event.user_id, detail.card_id, event.kind, 'payment_advance'::text as segment_kind,
    classification.advance_amount_minor as amount_minor, event.description,
    event.occurred_on, classification.cycle_statement_date as group_statement_date,
    classification.cycle_start, classification.cycle_end,
    account.name as source_account_name, card.is_active as source_is_active
  from active_events event
  join public.card_payment_classifications classification on classification.event_id = event.id
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  left join public.accounts account on account.id = detail.source_account_id
  where event.kind = 'card_payment' and classification.advance_amount_minor > 0
)
select * from purchases_and_refunds
union all select * from installment_segments
union all select * from applied_payments
union all select * from advance_payments;

revoke all on table public.installment_schedule from anon, authenticated;
revoke all on table public.installment_plan_summaries from anon, authenticated;
revoke all on table public.financial_activity_enriched from anon, authenticated;
revoke all on table public.card_statement_activity_segments from anon, authenticated;
grant select on table public.installment_schedule to authenticated;
grant select on table public.installment_plan_summaries to authenticated;
grant select on table public.financial_activity_enriched to authenticated;
grant select on table public.card_statement_activity_segments to authenticated;
grant all on table public.installment_schedule to service_role;
grant all on table public.installment_plan_summaries to service_role;
grant all on table public.financial_activity_enriched to service_role;
grant all on table public.card_statement_activity_segments to service_role;

revoke all on function public.import_historical_installment_plan(
  uuid, text, bigint, integer, bigint, date, integer, integer,
  bigint, bigint, date, text, text, boolean, text
) from public, anon;
grant execute on function public.import_historical_installment_plan(
  uuid, text, bigint, integer, bigint, date, integer, integer,
  bigint, bigint, date, text, text, boolean, text
) to authenticated;
