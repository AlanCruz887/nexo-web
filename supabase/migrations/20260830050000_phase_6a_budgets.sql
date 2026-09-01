-- Nexo Phase 6A: monthly budgets. Spend is derived read-only from two
-- existing sources -- never a second expense ledger:
--
--   Source A (non-MSI): financial_activity (Phase 3B), which already
--   excludes reversed events, resolves currency per account/card, and
--   carries category_id/personal_amount_minor for expense/card_charge/
--   card_refund. Any card_charge that belongs to an *active* installment
--   plan is excluded here -- it is represented by Source B instead, never
--   both.
--
--   Source B (MSI): installments with status = 'scheduled' on an *active*
--   plan, one row per monthly installment, attributed to the month of its
--   own due_statement_date. The personal share of each installment is
--   derived as principal_minor minus whatever receivable_due_items already
--   assigns to third parties for that exact installment_id -- the same
--   proportional-with-residue split Phase 5B already computed and tested.
--   No new ratio, no installment_allocations table, no recomputing
--   original_amount_minor / installment_count.
--
-- A budget itself is a target, not a financial fact: recurring definitions
-- are versioned by effective_from_month (a new limit is a NEW row, never
-- an UPDATE to history), and a specific-month exception is its own row
-- type, mutually exclusive with the recurring shape. See DOMAIN_RULES.md
-- §36 for the two invariants this enforces: MSI never double-counts
-- principal + installments, and changing a recurring limit never rewrites
-- past months.

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category_id text not null references public.categories (id),
  currency text not null references public.currencies (code),
  limit_minor bigint not null,
  -- Recurring version: effective_from_month required, period_month null.
  -- effective_to_month null means "still the current version"; set only by
  -- stop_recurring_budget to end a series without touching earlier rows.
  effective_from_month date,
  effective_to_month date,
  -- Specific-month exception: period_month required, the two effective_*
  -- columns null. Wins over any recurring resolution for that exact month.
  period_month date,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint budgets_limit_positive check (limit_minor > 0),
  constraint budgets_recurring_or_exception check (
    (period_month is null and effective_from_month is not null)
    or (period_month is not null and effective_from_month is null and effective_to_month is null)
  ),
  constraint budgets_effective_range_valid check (
    effective_to_month is null or effective_to_month >= effective_from_month
  ),
  constraint budgets_effective_from_is_month_start check (
    effective_from_month is null or effective_from_month = date_trunc('month', effective_from_month)::date
  ),
  constraint budgets_effective_to_is_month_start check (
    effective_to_month is null or effective_to_month = date_trunc('month', effective_to_month)::date
  ),
  constraint budgets_period_month_is_month_start check (
    period_month is null or period_month = date_trunc('month', period_month)::date
  )
);

-- At most one recurring version starting in a given month per category+currency.
create unique index budgets_recurring_start_unique
  on public.budgets (user_id, category_id, currency, effective_from_month)
  where period_month is null and archived_at is null;
-- At most one active exception for an exact month per category+currency.
create unique index budgets_specific_month_unique
  on public.budgets (user_id, category_id, currency, period_month)
  where period_month is not null and archived_at is null;

create index budgets_user_category_idx on public.budgets (user_id, category_id, currency)
  where archived_at is null;

create trigger budgets_set_updated_at
before update on public.budgets
for each row execute function private.set_updated_at();

alter table public.budgets enable row level security;
revoke all on table public.budgets from anon, authenticated;
-- Same pattern as accounts/contacts: only SELECT is granted directly. All
-- writes go through the SECURITY DEFINER RPCs below.
grant select on table public.budgets to authenticated;
grant all on table public.budgets to service_role;

create policy "Budgets are readable by owner"
on public.budgets
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Net personal spend per category/currency/month, derived exclusively from
-- financial_activity and installments -- no second source of truth for
-- "what was spent". See the header comment for the exact split.
create view public.budget_period_spend
with (security_invoker = true)
as
with non_msi as (
  select
    activity.user_id,
    activity.category_id,
    activity.currency,
    date_trunc('month', activity.occurred_on)::date as period_month,
    case
      when activity.kind in ('expense', 'card_charge') then activity.personal_amount_minor
      when activity.kind = 'card_refund' then -activity.personal_amount_minor
      else 0
    end as signed_minor
  from public.financial_activity activity
  where activity.kind in ('expense', 'card_charge', 'card_refund')
    and activity.category_id is not null
    -- An active MSI purchase is represented by its installments (below),
    -- never by its own card_charge amount here -- this is the exact split
    -- that prevents "personal_amount completo + mensualidades" happening
    -- at once.
    and not exists (
      select 1 from public.installment_plans plan
      where plan.purchase_event_id = activity.event_id and plan.status = 'active'
    )
), msi as (
  select
    plan.user_id,
    event.category_id,
    plan.currency,
    date_trunc('month', installment.due_statement_date)::date as period_month,
    (installment.principal_minor - coalesce(due.amount_minor, 0))::bigint as signed_minor
  from public.installments installment
  join public.installment_plans plan on plan.id = installment.plan_id and plan.status = 'active'
  join public.financial_events event on event.id = plan.purchase_event_id
  left join lateral (
    select sum(item.amount_minor) as amount_minor
    from public.receivable_due_items item
    where item.installment_id = installment.id
  ) due on true
  where installment.status = 'scheduled'
    and event.category_id is not null
)
select user_id, category_id, currency, period_month, sum(signed_minor)::bigint as spent_minor
from (select * from non_msi union all select * from msi) combined
group by user_id, category_id, currency, period_month;

revoke all on table public.budget_period_spend from anon, authenticated;
grant select on table public.budget_period_spend to authenticated;
grant all on table public.budget_period_spend to service_role;

-- Read contract for a month: resolves the exception-vs-recurring rule
-- (exact-month exception wins; otherwise the recurring version with the
-- latest effective_from_month <= the requested month, respecting
-- effective_to_month) and joins spend -- the frontend never decides which
-- row applies or subtracts anything itself.
create function public.get_budgets_for_period(p_month date default current_date, p_currency text default null)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  normalized_month date := date_trunc('month', p_month)::date;
  result jsonb;
begin
  with exceptions as (
    select id, category_id, currency, limit_minor
    from public.budgets
    where user_id = command_user_id and archived_at is null
      and (p_currency is null or currency = p_currency)
      and period_month = normalized_month
  ), recurring as (
    select distinct on (category_id, currency)
      id, category_id, currency, limit_minor
    from public.budgets
    where user_id = command_user_id and archived_at is null
      and (p_currency is null or currency = p_currency)
      and effective_from_month is not null
      and effective_from_month <= normalized_month
      and (effective_to_month is null or effective_to_month >= normalized_month)
    order by category_id, currency, effective_from_month desc
  ), resolved as (
    select
      coalesce(exception.id, recurring.id) as id,
      coalesce(exception.category_id, recurring.category_id) as category_id,
      coalesce(exception.currency, recurring.currency) as currency,
      coalesce(exception.limit_minor, recurring.limit_minor) as limit_minor,
      (exception.id is null) as is_recurring
    from recurring
    full join exceptions exception using (category_id, currency)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', resolved.id,
    'category_id', resolved.category_id,
    'category_name', category.name,
    'category_icon', category.icon,
    'currency', resolved.currency,
    'limit_minor', resolved.limit_minor::text,
    'is_recurring', resolved.is_recurring,
    'period_month', normalized_month,
    'spent_minor', coalesce(spend.spent_minor, 0)::text,
    'available_minor', (resolved.limit_minor - coalesce(spend.spent_minor, 0))::text,
    'percentage', case when resolved.limit_minor = 0 then 0
      else round((coalesce(spend.spent_minor, 0)::numeric / resolved.limit_minor::numeric) * 100)::int end
  ) order by category.sort_order, resolved.currency), '[]'::jsonb)
  into result
  from resolved
  join public.categories category on category.id = resolved.category_id
  left join public.budget_period_spend spend
    on spend.user_id = command_user_id
    and spend.category_id = resolved.category_id
    and spend.currency = resolved.currency
    and spend.period_month = normalized_month;
  return result;
end;
$$;

-- Read contract for "why does this budget say $X": every real movement
-- (Source A) plus one derived row per MSI installment (Source B) that
-- contributes to this category/currency/month. Installment rows are built
-- on the fly from installments/installment_plans -- never a synthetic
-- financial_events row.
create function public.get_budget_movements(p_category_id text, p_currency text, p_month date)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  normalized_month date := date_trunc('month', p_month)::date;
  result jsonb;
begin
  select coalesce(jsonb_agg(combined.row_data order by combined.occurred_on desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'row_kind', 'movement',
        'event_id', activity.event_id,
        'description', activity.description,
        'occurred_on', activity.occurred_on,
        'event_kind', activity.kind,
        'source_type', activity.source_type,
        'source_name', activity.source_name,
        'amount_minor', activity.amount_minor::text,
        'personal_amount_minor', activity.personal_amount_minor::text
      ) as row_data,
      activity.occurred_on as occurred_on
    from public.financial_activity activity
    where activity.user_id = command_user_id
      and activity.category_id = p_category_id
      and activity.currency = p_currency
      and activity.kind in ('expense', 'card_charge', 'card_refund')
      and date_trunc('month', activity.occurred_on)::date = normalized_month
      and not exists (
        select 1 from public.installment_plans plan
        where plan.purchase_event_id = activity.event_id and plan.status = 'active'
      )

    union all

    select
      jsonb_build_object(
        'row_kind', 'installment',
        'event_id', event.id,
        'plan_id', plan.id,
        'description', event.description,
        'occurred_on', installment.due_statement_date,
        'installment_number', installment.installment_number,
        'installment_count', plan.installment_count,
        'personal_amount_minor', (installment.principal_minor - coalesce(due.amount_minor, 0))::text
      ) as row_data,
      installment.due_statement_date as occurred_on
    from public.installments installment
    join public.installment_plans plan on plan.id = installment.plan_id and plan.status = 'active'
    join public.financial_events event on event.id = plan.purchase_event_id
    left join lateral (
      select sum(item.amount_minor) as amount_minor
      from public.receivable_due_items item
      where item.installment_id = installment.id
    ) due on true
    where plan.user_id = command_user_id
      and event.category_id = p_category_id
      and plan.currency = p_currency
      and installment.status = 'scheduled'
      and date_trunc('month', installment.due_statement_date)::date = normalized_month
  ) combined;
  return result;
end;
$$;

-- Creates either the FIRST recurring definition for a category+currency
-- (p_effective_from_month set) or a specific-month exception
-- (p_period_month set) -- exactly one of the two.
create function public.create_budget(
  p_category_id text, p_currency text, p_limit_minor bigint,
  p_effective_from_month date, p_period_month date,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  normalized_from date := case when p_effective_from_month is null then null
    else date_trunc('month', p_effective_from_month)::date end;
  normalized_period date := case when p_period_month is null then null
    else date_trunc('month', p_period_month)::date end;
  payload jsonb;
begin
  if p_limit_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if (normalized_from is null) = (normalized_period is null) then
    raise exception 'NEXO_BUDGET_MONTH_KIND_REQUIRED' using errcode = '22023';
  end if;
  if not exists (select 1 from public.categories where id = p_category_id and kind in ('expense', 'both')) then
    raise exception 'NEXO_CATEGORY_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.currencies where code = p_currency) then
    raise exception 'NEXO_CURRENCY_NOT_FOUND' using errcode = 'P0002';
  end if;

  payload := jsonb_build_object('category_id', p_category_id, 'currency', p_currency,
    'limit_minor', p_limit_minor::text, 'effective_from_month', normalized_from, 'period_month', normalized_period);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_budget', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.budgets (id, user_id, category_id, currency, limit_minor, effective_from_month, period_month)
  values (proposed_id, command_user_id, p_category_id, p_currency, p_limit_minor, normalized_from, normalized_period);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_created', 'budget', proposed_id, payload);
  return proposed_id;
end;
$$;

-- "Cambiar desde este mes": creates a NEW recurring version, never updates
-- the limit_minor of an existing row. Earlier versions (and the months
-- they already resolved) are untouched -- resolution simply starts
-- picking this new row once its own effective_from_month is reached.
create function public.update_recurring_budget_from_month(
  p_category_id text, p_currency text, p_limit_minor bigint, p_effective_from_month date,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  normalized_from date := date_trunc('month', p_effective_from_month)::date;
  payload jsonb;
begin
  if p_limit_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.budgets
    where user_id = command_user_id and category_id = p_category_id and currency = p_currency
      and archived_at is null and effective_from_month is not null
  ) then
    raise exception 'NEXO_BUDGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  payload := jsonb_build_object('category_id', p_category_id, 'currency', p_currency,
    'limit_minor', p_limit_minor::text, 'effective_from_month', normalized_from);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_recurring_budget_from_month', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.budgets (id, user_id, category_id, currency, limit_minor, effective_from_month)
  values (proposed_id, command_user_id, p_category_id, p_currency, p_limit_minor, normalized_from);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_recurring_version_created', 'budget', proposed_id, payload);
  return proposed_id;
end;
$$;

-- Edits the limit of an EXISTING specific-month exception in place. Safe
-- to mutate: an exception only ever describes one exact month, so there is
-- no history to rewrite. Recurring rows are rejected here on purpose.
create function public.update_budget_exception_limit(p_budget_id uuid, p_limit_minor bigint, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb;
  target public.budgets%rowtype;
begin
  select * into target from public.budgets
  where id = p_budget_id and user_id = command_user_id and archived_at is null;
  if not found then raise exception 'NEXO_BUDGET_NOT_FOUND' using errcode = 'P0002'; end if;
  if target.period_month is null then
    raise exception 'NEXO_USE_RECURRING_VERSION_INSTEAD' using errcode = '23514';
  end if;
  if p_limit_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;

  command_payload := jsonb_build_object('budget_id', p_budget_id, 'limit_minor', p_limit_minor::text);
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_budget_exception_limit', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_budget_id; end if;

  update public.budgets set limit_minor = p_limit_minor
  where id = p_budget_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_exception_limit_updated', 'budget', p_budget_id, command_payload);
  return p_budget_id;
end;
$$;

-- Ends a recurring series from a given month onward without touching any
-- earlier version: sets effective_to_month on whichever recurring row is
-- currently resolving for that month (the most recent effective_from_month
-- <= p_last_active_month). p_last_active_month is the LAST month the
-- budget should still apply -- the month after it, the category simply has
-- no recurring budget, exactly like "no fue presupuestada nunca".
create function public.stop_recurring_budget(
  p_category_id text, p_currency text, p_last_active_month date, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  normalized_last date := date_trunc('month', p_last_active_month)::date;
  target_id uuid;
  command_payload jsonb;
begin
  select id into target_id from public.budgets
  where user_id = command_user_id and category_id = p_category_id and currency = p_currency
    and archived_at is null and effective_from_month is not null
    and effective_from_month <= normalized_last
    and (effective_to_month is null or effective_to_month >= normalized_last)
  order by effective_from_month desc
  limit 1;
  if target_id is null then raise exception 'NEXO_BUDGET_NOT_FOUND' using errcode = 'P0002'; end if;

  command_payload := jsonb_build_object('category_id', p_category_id, 'currency', p_currency,
    'last_active_month', normalized_last);
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'stop_recurring_budget', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return target_id; end if;

  update public.budgets set effective_to_month = normalized_last
  where id = target_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_recurring_stopped', 'budget', target_id, command_payload);
  return target_id;
end;
$$;

-- Administrative archive/restore -- restricted to specific-month
-- exceptions on purpose. A recurring row is never archived directly: doing
-- so would drop it out of every month's resolution from its
-- effective_from_month forward, silently rewriting history. Use
-- stop_recurring_budget for that instead.
create function public.archive_budget(p_budget_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('budget_id', p_budget_id);
  target public.budgets%rowtype;
begin
  select * into target from public.budgets where id = p_budget_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_BUDGET_NOT_FOUND' using errcode = 'P0002'; end if;
  if target.period_month is null then
    raise exception 'NEXO_USE_STOP_RECURRING_BUDGET_INSTEAD' using errcode = '23514';
  end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'archive_budget', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_budget_id; end if;

  update public.budgets set archived_at = now()
  where id = p_budget_id and user_id = command_user_id and archived_at is null;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_archived', 'budget', p_budget_id, command_payload);
  return p_budget_id;
end;
$$;

create function public.restore_budget(p_budget_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('budget_id', p_budget_id);
  target public.budgets%rowtype;
begin
  select * into target from public.budgets where id = p_budget_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_BUDGET_NOT_FOUND' using errcode = 'P0002'; end if;
  if target.period_month is null then
    raise exception 'NEXO_USE_STOP_RECURRING_BUDGET_INSTEAD' using errcode = '23514';
  end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'restore_budget', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_budget_id; end if;

  if exists (
    select 1 from public.budgets
    where user_id = command_user_id and category_id = target.category_id and currency = target.currency
      and archived_at is null and id <> p_budget_id and period_month is not distinct from target.period_month
  ) then
    raise exception 'NEXO_BUDGET_ALREADY_EXISTS' using errcode = '23505';
  end if;

  update public.budgets set archived_at = null where id = p_budget_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'budget_restored', 'budget', p_budget_id, command_payload);
  return p_budget_id;
end;
$$;

revoke all on function public.get_budgets_for_period(date, text) from public, anon;
revoke all on function public.get_budget_movements(text, text, date) from public, anon;
revoke all on function public.create_budget(text, text, bigint, date, date, text) from public, anon;
revoke all on function public.update_recurring_budget_from_month(text, text, bigint, date, text) from public, anon;
revoke all on function public.update_budget_exception_limit(uuid, bigint, text) from public, anon;
revoke all on function public.stop_recurring_budget(text, text, date, text) from public, anon;
revoke all on function public.archive_budget(uuid, text) from public, anon;
revoke all on function public.restore_budget(uuid, text) from public, anon;

grant execute on function public.get_budgets_for_period(date, text) to authenticated;
grant execute on function public.get_budget_movements(text, text, date) to authenticated;
grant execute on function public.create_budget(text, text, bigint, date, date, text) to authenticated;
grant execute on function public.update_recurring_budget_from_month(text, text, bigint, date, text) to authenticated;
grant execute on function public.update_budget_exception_limit(uuid, bigint, text) to authenticated;
grant execute on function public.stop_recurring_budget(text, text, date, text) to authenticated;
grant execute on function public.archive_budget(uuid, text) to authenticated;
grant execute on function public.restore_budget(uuid, text) to authenticated;

-- Close the domain gap DOMAIN_RULES.md already documented but the RPC
-- never enforced: a direct refund against a purchase that belongs to a
-- still-active installment plan must be rejected. The correct existing
-- flow for undoing an MSI purchase is reverse_installment_purchase, which
-- reverses the full charge and cancels its remaining installments
-- atomically -- a partial card_refund cannot express "give back part of an
-- MSI principal" without desynchronizing the schedule, and Phase 4A never
-- built a redistribution policy for that. Nothing else about the refund
-- engine changes.
create or replace function public.create_card_refund(
  p_card_id uuid,
  p_amount_minor bigint,
  p_description text,
  p_category_id text,
  p_occurred_on date,
  p_original_event_id uuid,
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
  proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  target_card public.credit_cards%rowtype;
  original_amount bigint;
  refunded_amount bigint;
  baseline_date date;
  assigned_statement_date date;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  if p_original_event_id is not null then
    select event.amount_minor into original_amount
    from public.financial_events event
    join public.card_transaction_details detail on detail.financial_event_id = event.id
    where event.id = p_original_event_id and event.user_id = command_user_id
      and event.kind = 'card_charge' and detail.card_id = p_card_id;
    if not found then raise exception 'NEXO_ORIGINAL_PURCHASE_NOT_FOUND' using errcode = 'P0002'; end if;
    if exists (
      select 1 from public.installment_plans plan
      where plan.purchase_event_id = p_original_event_id and plan.status = 'active'
    ) then
      raise exception 'NEXO_REFUND_NOT_ALLOWED_FOR_ACTIVE_MSI'
        using errcode = '23514',
        hint = 'Usa reverse_installment_purchase para deshacer una compra a meses; un reembolso directo no puede redistribuir el plan.';
    end if;
    select coalesce(sum(event.amount_minor), 0) into refunded_amount
    from public.financial_events event
    join public.card_transaction_details detail on detail.financial_event_id = event.id
    where detail.related_event_id = p_original_event_id and event.kind = 'card_refund'
      and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id);
    if refunded_amount + p_amount_minor > original_amount then
      raise exception 'NEXO_REFUND_EXCEEDS_PURCHASE' using errcode = '23514';
    end if;
  end if;
  assigned_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (
    select 1 from public.card_statements where card_id = p_card_id and statement_date = assigned_statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  payload := jsonb_build_object(
    'card_id', p_card_id, 'amount_minor', p_amount_minor::text, 'description', normalized_description,
    'category_id', p_category_id, 'occurred_on', p_occurred_on,
    'original_event_id', p_original_event_id, 'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_card_refund', payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'card_refund', p_amount_minor, p_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, -p_amount_minor, 'impacting');
  insert into public.card_transaction_details (
    financial_event_id, user_id, card_id, statement_date, related_event_id
  ) values (
    proposed_event_id, command_user_id, p_card_id, assigned_statement_date, p_original_event_id
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_refund_created', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('statement_date', assigned_statement_date));
  return proposed_event_id;
end;
$$;
