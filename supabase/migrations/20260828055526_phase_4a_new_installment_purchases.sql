-- Phase 4A: new MSI purchases. A purchase event is the only principal impact;
-- plans and installments are scheduling records with zero additional card entry.

create table public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  card_id uuid not null references public.credit_cards (id) on delete restrict,
  purchase_event_id uuid not null unique references public.financial_events (id) on delete restrict,
  original_amount_minor bigint not null,
  installment_count smallint not null,
  installment_amount_minor bigint not null,
  currency text not null references public.currencies (code),
  start_date date not null,
  first_statement_date date not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint installment_plans_amount_positive check (original_amount_minor > 0 and installment_amount_minor > 0),
  constraint installment_plans_count_valid check (installment_count between 2 and 60),
  constraint installment_plans_status_valid check (status in ('active', 'reversed'))
);

create table public.installments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null references public.installment_plans (id) on delete restrict,
  installment_number smallint not null,
  due_statement_date date not null,
  principal_minor bigint not null,
  status text not null default 'scheduled',
  created_at timestamptz not null default now(),
  constraint installments_number_positive check (installment_number > 0),
  constraint installments_principal_positive check (principal_minor > 0),
  constraint installments_status_valid check (status in ('scheduled', 'cancelled')),
  constraint installments_plan_number_unique unique (plan_id, installment_number),
  constraint installments_plan_statement_unique unique (plan_id, due_statement_date)
);

create table public.installment_plan_metadata_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null references public.installment_plans (id) on delete restrict,
  description text not null,
  category_id text references public.categories (id),
  notes text,
  created_at timestamptz not null default now(),
  constraint installment_metadata_description_valid check (char_length(btrim(description)) between 1 and 160),
  constraint installment_metadata_notes_valid check (notes is null or char_length(notes) <= 2000)
);

create index installment_plans_user_card_status_idx on public.installment_plans (user_id, card_id, status, created_at desc);
create index installments_user_plan_due_idx on public.installments (user_id, plan_id, due_statement_date);
create index installments_due_statement_idx on public.installments (due_statement_date, plan_id) where status = 'scheduled';
create index installment_metadata_plan_created_idx on public.installment_plan_metadata_revisions (plan_id, created_at desc);

alter table public.installment_plans enable row level security;
alter table public.installments enable row level security;
alter table public.installment_plan_metadata_revisions enable row level security;
revoke all on table public.installment_plans from anon, authenticated;
revoke all on table public.installments from anon, authenticated;
revoke all on table public.installment_plan_metadata_revisions from anon, authenticated;
grant select on table public.installment_plans to authenticated;
grant select on table public.installments to authenticated;
grant select on table public.installment_plan_metadata_revisions to authenticated;
grant all on table public.installment_plans to service_role;
grant all on table public.installments to service_role;
grant all on table public.installment_plan_metadata_revisions to service_role;

create policy "Users can read their own installment plans"
on public.installment_plans for select to authenticated
using ((select auth.uid()) = user_id);
create policy "Users can read their own installments"
on public.installments for select to authenticated
using ((select auth.uid()) = user_id);
create policy "Users can read their own installment metadata"
on public.installment_plan_metadata_revisions for select to authenticated
using ((select auth.uid()) = user_id);

create trigger installment_plans_set_updated_at
before update on public.installment_plans
for each row execute function private.set_updated_at();
create trigger installment_metadata_are_immutable
before update or delete on public.installment_plan_metadata_revisions
for each row execute function private.reject_financial_mutation();

create function private.reject_msi_refund()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.related_event_id is not null and exists (
    select 1 from public.installment_plans plan
    where plan.purchase_event_id = new.related_event_id and plan.status = 'active'
  ) then
    raise exception 'NEXO_MSI_REFUND_UNSUPPORTED' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger card_details_reject_msi_refund
before insert on public.card_transaction_details
for each row execute function private.reject_msi_refund();

create or replace function private.reverse_card_event(
  command_user_id uuid,
  original_event_id uuid,
  reversal_event_id uuid,
  reversal_description text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  original_event public.financial_events%rowtype;
begin
  select * into original_event
  from public.financial_events
  where id = original_event_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_CARD_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_event.kind not in ('card_charge', 'card_payment', 'card_refund') then
    raise exception 'NEXO_CARD_TRANSACTION_NOT_REVERSIBLE' using errcode = '23514';
  end if;
  if exists (select 1 from public.financial_events where reverses_event_id = original_event_id) then
    raise exception 'NEXO_TRANSACTION_ALREADY_REVERSED' using errcode = '23505';
  end if;
  if original_event.kind = 'card_charge'
    and exists (select 1 from public.installment_plans where purchase_event_id = original_event_id and status = 'active')
    and coalesce(current_setting('nexo.allow_msi_reversal', true), '') <> 'on' then
    raise exception 'NEXO_MSI_REVERSE_REQUIRED' using errcode = '23514';
  end if;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, occurred_on, notes, reverses_event_id
  ) values (
    reversal_event_id, command_user_id, 'reversal', original_event.amount_minor, 0,
    reversal_description, current_date, original_event.notes, original_event_id
  );
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  select command_user_id, reversal_event_id, card_id, -amount_minor, effect_scope
  from public.card_entries
  where financial_event_id = original_event_id and user_id = command_user_id;
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  select command_user_id, reversal_event_id, account_id, -amount_minor
  from public.account_entries
  where financial_event_id = original_event_id and user_id = command_user_id;
end;
$$;

create function public.create_installment_purchase(
  p_card_id uuid,
  p_amount_minor bigint,
  p_installment_count integer,
  p_installment_amount_minor bigint,
  p_description text,
  p_category_id text,
  p_occurred_on date,
  p_payment_method text,
  p_notes text,
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
  baseline_date date;
  first_statement_date date;
  monthly_amount bigint;
  final_amount bigint;
  installment_number integer;
  installment_statement_date date;
  month_cursor date;
  normalized_description text := nullif(btrim(p_description), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_installment_count < 2 or p_installment_count > 60 then
    raise exception 'NEXO_INVALID_INSTALLMENT_COUNT' using errcode = '22023';
  end if;
  if normalized_description is null or char_length(normalized_description) > 160 then
    raise exception 'NEXO_INVALID_DESCRIPTION' using errcode = '22023';
  end if;
  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'NEXO_NOTES_TOO_LONG' using errcode = '22023';
  end if;
  if p_payment_method is not null and p_payment_method not in ('physical_card', 'apple_pay', 'google_pay', 'online', 'other') then
    raise exception 'NEXO_INVALID_PAYMENT_METHOD' using errcode = '22023';
  end if;

  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date
  from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;

  first_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (
    select 1 from public.card_statements
    where card_id = p_card_id and statement_date = first_statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  monthly_amount := coalesce(p_installment_amount_minor, p_amount_minor / p_installment_count);
  if monthly_amount <= 0 then raise exception 'NEXO_INVALID_INSTALLMENT_AMOUNT' using errcode = '22023'; end if;
  final_amount := p_amount_minor - monthly_amount * (p_installment_count - 1);
  if final_amount <= 0 then raise exception 'NEXO_INVALID_INSTALLMENT_AMOUNT' using errcode = '22023'; end if;

  payload := jsonb_build_object(
    'card_id', p_card_id,
    'amount_minor', p_amount_minor::text,
    'installment_count', p_installment_count,
    'installment_amount_minor', monthly_amount::text,
    'description', normalized_description,
    'category_id', p_category_id,
    'occurred_on', p_occurred_on,
    'payment_method', p_payment_method,
    'notes', normalized_notes
  );
  resolved_plan_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_installment_purchase', payload, proposed_plan_id
  );
  if resolved_plan_id <> proposed_plan_id then return resolved_plan_id; end if;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'card_charge', p_amount_minor, p_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, p_amount_minor, 'impacting');
  insert into public.card_transaction_details (
    financial_event_id, user_id, card_id, payment_method, statement_date
  ) values (
    proposed_event_id, command_user_id, p_card_id, p_payment_method, first_statement_date
  );
  insert into public.installment_plans (
    id, user_id, card_id, purchase_event_id, original_amount_minor,
    installment_count, installment_amount_minor, currency, start_date,
    first_statement_date, status
  ) values (
    proposed_plan_id, command_user_id, p_card_id, proposed_event_id, p_amount_minor,
    p_installment_count, monthly_amount, target_card.currency, p_occurred_on,
    first_statement_date, 'active'
  );

  for installment_number in 1..p_installment_count loop
    month_cursor := first_statement_date + make_interval(months => installment_number - 1);
    installment_statement_date := public.card_effective_statement_date(
      extract(year from month_cursor)::integer,
      extract(month from month_cursor)::integer,
      target_card.statement_day
    );
    insert into public.installments (
      user_id, plan_id, installment_number, due_statement_date, principal_minor, status
    ) values (
      command_user_id, proposed_plan_id, installment_number, installment_statement_date,
      case when installment_number = p_installment_count then final_amount else monthly_amount end,
      'scheduled'
    );
  end loop;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values
    (command_user_id, 'installment_purchase_created', 'financial_event', proposed_event_id,
      payload || jsonb_build_object('plan_id', proposed_plan_id)),
    (command_user_id, 'installment_plan_created', 'installment_plan', proposed_plan_id,
      jsonb_build_object('purchase_event_id', proposed_event_id, 'additional_card_impact_minor', '0'));
  return proposed_plan_id;
end;
$$;

create function public.update_installment_plan_metadata(
  p_plan_id uuid,
  p_description text,
  p_category_id text,
  p_notes text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_revision_id uuid := gen_random_uuid();
  resolved_revision_id uuid;
  normalized_description text := nullif(btrim(p_description), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  if normalized_description is null or char_length(normalized_description) > 160 then
    raise exception 'NEXO_INVALID_DESCRIPTION' using errcode = '22023';
  end if;
  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'NEXO_NOTES_TOO_LONG' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.installment_plans
    where id = p_plan_id and user_id = command_user_id and status = 'active'
  ) then raise exception 'NEXO_INSTALLMENT_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  payload := jsonb_build_object(
    'plan_id', p_plan_id, 'description', normalized_description,
    'category_id', p_category_id, 'notes', normalized_notes
  );
  resolved_revision_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_installment_plan_metadata', payload, proposed_revision_id
  );
  if resolved_revision_id <> proposed_revision_id then return resolved_revision_id; end if;
  insert into public.installment_plan_metadata_revisions (
    id, user_id, plan_id, description, category_id, notes
  ) values (
    proposed_revision_id, command_user_id, p_plan_id, normalized_description, p_category_id, normalized_notes
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'installment_plan_updated', 'installment_plan', p_plan_id, payload);
  return proposed_revision_id;
end;
$$;

create function public.reverse_installment_purchase(
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
  ) then raise exception 'NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  resolved_reversal_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_installment_purchase', payload, proposed_reversal_id
  );
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;
  perform set_config('nexo.allow_msi_reversal', 'on', true);
  perform private.reverse_card_event(
    command_user_id, target_plan.purchase_event_id, proposed_reversal_id, 'Reversión de compra MSI'
  );
  update public.installment_plans set status = 'reversed' where id = p_plan_id;
  update public.installments set status = 'cancelled' where plan_id = p_plan_id and status = 'scheduled';
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'installment_purchase_reversed', 'installment_plan', p_plan_id,
    jsonb_build_object('purchase_event_id', target_plan.purchase_event_id, 'reversal_event_id', proposed_reversal_id));
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
  case
    when plan.status = 'reversed' or installment.status = 'cancelled' then 'cancelled'
    when statement.status = 'paid' then 'paid'
    when statement.id is not null then 'due'
    else 'scheduled'
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
  plan.created_at,
  plan.updated_at,
  card.name as card_name,
  coalesce(metadata.description, event.description) as description,
  coalesce(metadata.category_id, event.category_id) as category_id,
  category.name as category_name,
  coalesce(metadata.notes, event.notes) as notes,
  progress.paid_count,
  progress.pending_count,
  progress.remaining_principal_minor,
  next_installment.installment_number as current_installment_number,
  next_installment.principal_minor as current_installment_minor,
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
    count(*) filter (where schedule.effective_status = 'paid')::integer as paid_count,
    count(*) filter (where schedule.effective_status in ('scheduled', 'due'))::integer as pending_count,
    coalesce(sum(schedule.principal_minor) filter (where schedule.effective_status in ('scheduled', 'due')), 0) as remaining_principal_minor
  from public.installment_schedule schedule
  where schedule.plan_id = plan.id
) progress
left join lateral (
  select schedule.installment_number, schedule.principal_minor, schedule.due_statement_date
  from public.installment_schedule schedule
  where schedule.plan_id = plan.id and schedule.effective_status in ('scheduled', 'due')
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
  plan.notes as installment_notes
from public.financial_activity activity
left join public.installment_plan_summaries plan on plan.purchase_event_id = activity.event_id;

revoke all on table public.installment_schedule from anon, authenticated;
revoke all on table public.installment_plan_summaries from anon, authenticated;
revoke all on table public.financial_activity_enriched from anon, authenticated;
grant select on table public.installment_schedule to authenticated;
grant select on table public.installment_plan_summaries to authenticated;
grant select on table public.financial_activity_enriched to authenticated;
grant all on table public.installment_schedule to service_role;
grant all on table public.installment_plan_summaries to service_role;
grant all on table public.financial_activity_enriched to service_role;

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
    select coalesce(sum(installment.principal_minor), 0) as amount_minor
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
      then context.baseline_balance_minor else 0
    end + cycle.amount_minor + installments.amount_minor,
    0
  )
  from card_context context
  cross join cycle_activity cycle
  cross join installment_activity installments;
$$;

drop view public.card_current_cycles;
drop view public.card_summaries;

create view public.card_summaries
with (security_invoker = true)
as
with card_base as (
  select
    card.*,
    baseline.id as baseline_id,
    baseline.policy as baseline_policy,
    baseline.baseline_date,
    baseline.reported_bank_balance_minor,
    baseline.excluded_statement_amount_minor,
    baseline.baseline_balance_minor,
    greatest(
      public.card_statement_for_date(current_date, card.statement_day),
      coalesce(
        public.card_statement_for_date(
          (select max(statement.statement_date) from public.card_statements statement where statement.card_id = card.id),
          card.statement_day
        ),
        public.card_statement_for_date(current_date, card.statement_day)
      )
    ) as next_statement_date
  from public.credit_cards card
  join public.card_baselines baseline on baseline.card_id = card.id
), calculated as (
  select
    base.*,
    base.baseline_balance_minor + coalesce((
      select sum(entry.amount_minor) from public.card_entries entry
      where entry.card_id = base.id and entry.effect_scope = 'impacting'
    ), 0) as used_balance_minor,
    public.card_statement_preview_balance(base.id, base.next_statement_date) as open_cycle_accumulated_minor
  from card_base base
)
select
  calculated.*,
  calculated.credit_limit_minor - calculated.used_balance_minor as available_credit_minor,
  public.card_due_date(calculated.next_statement_date, calculated.payment_days_after_statement) as next_payment_due_date,
  latest.remaining_due_minor as current_payment_minor,
  latest.payment_due_date as current_payment_due_date,
  latest.id as current_statement_id,
  latest.statement_date as current_statement_date
from calculated
left join lateral (
  select statement.id, statement.statement_date, statement.remaining_due_minor, statement.payment_due_date
  from public.card_statements statement
  where statement.card_id = calculated.id and statement.status in ('closed', 'paid')
  order by statement.statement_date desc limit 1
) latest on true;

create view public.card_current_cycles
with (security_invoker = true)
as
select
  summary.id as card_id,
  summary.user_id,
  public.card_previous_statement_date(summary.next_statement_date, summary.statement_day) as cycle_start,
  summary.next_statement_date as cycle_end,
  summary.next_statement_date as statement_date,
  summary.next_payment_due_date as payment_due_date,
  summary.open_cycle_accumulated_minor
from public.card_summaries summary;

revoke all on table public.card_summaries from anon, authenticated;
revoke all on table public.card_current_cycles from anon, authenticated;
grant select on table public.card_summaries to authenticated;
grant select on table public.card_current_cycles to authenticated;
grant all on table public.card_summaries to service_role;
grant all on table public.card_current_cycles to service_role;

-- The statement timeline presents installments as schedule segments. The full
-- MSI purchase is intentionally excluded here so a statement never receives
-- both the original principal and its monthly installment.
drop view public.card_statement_activity_segments;

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
    and not exists (
      select 1 from public.installment_plans plan
      where plan.purchase_event_id = event.id and plan.status = 'active'
    )
), installment_segments as (
  select
    installment.id::text as segment_id,
    plan.purchase_event_id as event_id,
    plan.user_id,
    plan.card_id,
    'card_charge'::text as kind,
    'installment'::text as segment_kind,
    installment.principal_minor as amount_minor,
    summary.description || ' · Mensualidad ' || installment.installment_number::text ||
      ' de ' || plan.installment_count::text as description,
    plan.start_date as occurred_on,
    installment.due_statement_date as group_statement_date,
    public.card_previous_statement_date(installment.due_statement_date, card.statement_day) as cycle_start,
    installment.due_statement_date as cycle_end,
    null::text as source_account_name,
    card.is_active as source_is_active
  from public.installments installment
  join public.installment_plans plan on plan.id = installment.plan_id
  join public.installment_plan_summaries summary on summary.id = plan.id
  join public.credit_cards card on card.id = plan.card_id
  where plan.status = 'active' and installment.status = 'scheduled'
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
union all select * from installment_segments
union all select * from applied_payments
union all select * from advance_payments;

revoke all on table public.card_statement_activity_segments from anon, authenticated;
grant select on table public.card_statement_activity_segments to authenticated;
grant all on table public.card_statement_activity_segments to service_role;

revoke all on function public.create_installment_purchase(uuid, bigint, integer, bigint, text, text, date, text, text, text) from public, anon;
revoke all on function public.update_installment_plan_metadata(uuid, text, text, text, text) from public, anon;
revoke all on function public.reverse_installment_purchase(uuid, text) from public, anon;
grant execute on function public.create_installment_purchase(uuid, bigint, integer, bigint, text, text, date, text, text, text) to authenticated;
grant execute on function public.update_installment_plan_metadata(uuid, text, text, text, text) to authenticated;
grant execute on function public.reverse_installment_purchase(uuid, text) to authenticated;
