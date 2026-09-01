-- Nexo Phase 6C: financial planning ("Planeación"). A liquidity PROJECTION,
-- never accounting: nothing in this file creates financial_events,
-- account_entries, card_statements, installments, goal_entries, budgets, or
-- receivable_entries. Every number here is either read straight from the
-- existing financial engine (accounts, cards, budgets, goals, receivables)
-- or derived, in-memory, from planned_cash_flows -- the one genuinely new
-- table, which is explicitly NOT a financial_event and never becomes one
-- automatically.
--
-- Anti-double-count rules baked into this migration (see DOMAIN_RULES.md
-- Fase 6C for the full narrative):
--   1. saldo inicial subtracts REAL goal backing (goal_account_backing),
--      never nominal saved_minor -- a goal can never make liquidity go
--      negative "on paper" beyond what the account actually lost.
--   2. card obligations: statement cerrado > preview del corte > (nothing
--      else). card_statement_preview_balance already folds a cycle's own
--      non-MSI spend and its own due-that-cycle MSI installment into one
--      number -- never listed twice, never summed with a closed statement.
--   3. planned_cash_flows with a category_id only ever consume part of that
--      category's REMAINING flexible room (get_budgets_for_period's
--      available_minor) -- never added on top of the full limit.
--   4. goal recommendations are a pure, non-persisted simulation
--      (projected_saved_minor) seeded from today's real saved_minor and
--      advanced month over month only within this one RPC call.

create table public.planned_cash_flows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  currency text not null references public.currencies (code),
  amount_minor bigint not null,
  category_id text references public.categories (id),
  recurrence text not null,
  start_date date not null,
  end_date date,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint planned_cash_flows_name_not_blank check (char_length(btrim(name)) between 1 and 120),
  constraint planned_cash_flows_amount_nonzero check (amount_minor <> 0),
  constraint planned_cash_flows_recurrence_valid check (recurrence in ('one_time', 'monthly')),
  constraint planned_cash_flows_dates_valid check (end_date is null or end_date >= start_date),
  constraint planned_cash_flows_one_time_no_end check (recurrence = 'monthly' or end_date is null)
);

comment on table public.planned_cash_flows is
  'Manually declared future income/expense intentions for Planeación. Never a financial_event; never auto-converted into one. recurrence is intentionally minimal (one_time/monthly, no RRULE) -- this is not a subscriptions engine.';
comment on column public.planned_cash_flows.category_id is
  'Only load-bearing for negative (outflow) rows: it makes this flow consume part of that category''s remaining flexible budget instead of being added on top of it. Null on a negative row means it sits entirely outside budgets. Ignored for positive (income) rows.';

create index planned_cash_flows_user_currency_idx
  on public.planned_cash_flows (user_id, currency, archived_at);

alter table public.planned_cash_flows enable row level security;
revoke all on table public.planned_cash_flows from anon, authenticated;
grant select on table public.planned_cash_flows to authenticated;
grant all on table public.planned_cash_flows to service_role;

create policy "Planned cash flows are readable by owner"
on public.planned_cash_flows
for select
to authenticated
using ((select auth.uid()) = user_id);

create trigger planned_cash_flows_set_updated_at
before update on public.planned_cash_flows
for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Write RPCs: ownership + idempotency + validation, same shape as every
-- other command in the codebase. planned_cash_flows is plain user input
-- (not a financial ledger), so it is editable in place -- no versioning,
-- no immutability trigger.
-- ---------------------------------------------------------------------

create function public.create_planned_cash_flow(
  p_name text, p_currency text, p_amount_minor bigint, p_category_id text,
  p_recurrence text, p_start_date date, p_end_date date, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  normalized_name text := btrim(p_name);
  payload jsonb;
begin
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_amount_minor = 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if not exists (select 1 from public.currencies where code = p_currency) then
    raise exception 'NEXO_CURRENCY_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_recurrence not in ('one_time', 'monthly') then
    raise exception 'NEXO_INVALID_RECURRENCE' using errcode = '22023'; end if;
  if p_start_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_recurrence = 'one_time' and p_end_date is not null then
    raise exception 'NEXO_ONE_TIME_CANNOT_HAVE_END_DATE' using errcode = '22023'; end if;
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'NEXO_INVALID_DATE_RANGE' using errcode = '22023'; end if;
  if p_category_id is not null and not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'NEXO_CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;

  payload := jsonb_build_object('name', normalized_name, 'currency', p_currency,
    'amount_minor', p_amount_minor::text, 'category_id', p_category_id,
    'recurrence', p_recurrence, 'start_date', p_start_date, 'end_date', p_end_date);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_planned_cash_flow', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.planned_cash_flows
    (id, user_id, name, currency, amount_minor, category_id, recurrence, start_date, end_date)
  values
    (proposed_id, command_user_id, normalized_name, p_currency, p_amount_minor, p_category_id, p_recurrence, p_start_date, p_end_date);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'planned_cash_flow_created', 'planned_cash_flow', proposed_id, payload);
  return proposed_id;
end;
$$;

create function public.update_planned_cash_flow(
  p_flow_id uuid, p_name text, p_amount_minor bigint, p_category_id text,
  p_recurrence text, p_start_date date, p_end_date date, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  normalized_name text := btrim(p_name);
  payload jsonb;
begin
  if not exists (
    select 1 from public.planned_cash_flows
    where id = p_flow_id and user_id = command_user_id and archived_at is null
  ) then raise exception 'NEXO_PLANNED_CASH_FLOW_NOT_FOUND' using errcode = 'P0002'; end if;
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_amount_minor = 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_recurrence not in ('one_time', 'monthly') then
    raise exception 'NEXO_INVALID_RECURRENCE' using errcode = '22023'; end if;
  if p_start_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_recurrence = 'one_time' and p_end_date is not null then
    raise exception 'NEXO_ONE_TIME_CANNOT_HAVE_END_DATE' using errcode = '22023'; end if;
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'NEXO_INVALID_DATE_RANGE' using errcode = '22023'; end if;
  if p_category_id is not null and not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'NEXO_CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;

  payload := jsonb_build_object('flow_id', p_flow_id, 'name', normalized_name,
    'amount_minor', p_amount_minor::text, 'category_id', p_category_id,
    'recurrence', p_recurrence, 'start_date', p_start_date, 'end_date', p_end_date);
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_planned_cash_flow', payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_flow_id; end if;

  update public.planned_cash_flows set
    name = normalized_name, amount_minor = p_amount_minor, category_id = p_category_id,
    recurrence = p_recurrence, start_date = p_start_date, end_date = p_end_date
  where id = p_flow_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'planned_cash_flow_updated', 'planned_cash_flow', p_flow_id, payload);
  return p_flow_id;
end;
$$;

create function public.archive_planned_cash_flow(p_flow_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('flow_id', p_flow_id);
begin
  if not exists (select 1 from public.planned_cash_flows where id = p_flow_id and user_id = command_user_id) then
    raise exception 'NEXO_PLANNED_CASH_FLOW_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'archive_planned_cash_flow', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_flow_id; end if;

  update public.planned_cash_flows set archived_at = now()
  where id = p_flow_id and user_id = command_user_id and archived_at is null;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'planned_cash_flow_archived', 'planned_cash_flow', p_flow_id, command_payload);
  return p_flow_id;
end;
$$;

create function public.restore_planned_cash_flow(p_flow_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('flow_id', p_flow_id);
begin
  if not exists (select 1 from public.planned_cash_flows where id = p_flow_id and user_id = command_user_id) then
    raise exception 'NEXO_PLANNED_CASH_FLOW_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'restore_planned_cash_flow', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_flow_id; end if;

  update public.planned_cash_flows set archived_at = null where id = p_flow_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'planned_cash_flow_restored', 'planned_cash_flow', p_flow_id, command_payload);
  return p_flow_id;
end;
$$;

revoke all on function public.create_planned_cash_flow(text, text, bigint, text, text, date, date, text) from public, anon;
revoke all on function public.update_planned_cash_flow(uuid, text, bigint, text, text, date, date, text) from public, anon;
revoke all on function public.archive_planned_cash_flow(uuid, text) from public, anon;
revoke all on function public.restore_planned_cash_flow(uuid, text) from public, anon;
grant execute on function public.create_planned_cash_flow(text, text, bigint, text, text, date, date, text) to authenticated;
grant execute on function public.update_planned_cash_flow(uuid, text, bigint, text, text, date, date, text) to authenticated;
grant execute on function public.archive_planned_cash_flow(uuid, text) to authenticated;
grant execute on function public.restore_planned_cash_flow(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- get_financial_plan: the one read RPC behind Planeación. Everything is
-- computed in a single deterministic pass parameterized by p_as_of_date --
-- no dependency on current_date anywhere in this function, so tests can
-- pin a date and get reproducible output. Returns full traceability: every
-- aggregate in the response is accompanied by the line items that sum to
-- it, so the frontend never has to trust an unexplained number.
-- ---------------------------------------------------------------------

create function public.get_financial_plan(
  p_currency text,
  p_as_of_date date default current_date,
  p_horizon_months integer default 6
)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  horizon_end_exclusive date;
  saldo_en_cuentas_minor bigint;
  apartado_respaldado_minor bigint;
  disponible_sin_comprometer_minor bigint;
  accounts_json jsonb;
  faltante_total_minor bigint;
  faltante_por_meta_json jsonb;
  result jsonb;
begin
  if p_horizon_months not in (3, 6, 12) then
    raise exception 'NEXO_INVALID_HORIZON' using errcode = '22023'; end if;
  if not exists (select 1 from public.currencies where code = p_currency) then
    raise exception 'NEXO_CURRENCY_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_as_of_date is null then
    raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;

  horizon_end_exclusive := (date_trunc('month', p_as_of_date)::date + (p_horizon_months::text || ' months')::interval)::date;

  -- Saldo inicial: real account balances minus REAL goal backing (never
  -- nominal saved_minor). goal_account_backing already guarantees
  -- sum(backed_minor per account) <= max(balance, 0), so
  -- disponible_sin_comprometer can never go negative "because of a goal" --
  -- only because the account itself is genuinely overdrawn.
  select
    coalesce(sum(a.balance_minor), 0)::bigint,
    coalesce(sum(coalesce(bk.backed_minor, 0)), 0)::bigint,
    coalesce(sum(a.balance_minor - coalesce(bk.backed_minor, 0)), 0)::bigint,
    coalesce(jsonb_agg(jsonb_build_object(
      'account_id', a.id, 'name', a.name,
      'balance_minor', a.balance_minor::text,
      'backed_minor', coalesce(bk.backed_minor, 0)::text,
      'available_minor', (a.balance_minor - coalesce(bk.backed_minor, 0))::text
    ) order by a.name), '[]'::jsonb)
  into saldo_en_cuentas_minor, apartado_respaldado_minor, disponible_sin_comprometer_minor, accounts_json
  from (
    select acc.id, acc.name, coalesce(sum(e.amount_minor), 0)::bigint as balance_minor
    from public.accounts acc
    left join public.account_entries e on e.account_id = acc.id and e.user_id = command_user_id
    where acc.user_id = command_user_id and acc.currency = p_currency and acc.is_active
    group by acc.id, acc.name
  ) a
  left join (
    select account_id, sum(backed_minor)::bigint as backed_minor
    from public.goal_account_backing
    where user_id = command_user_id
    group by account_id
  ) bk on bk.account_id = a.id;

  -- Faltante de respaldo: informative only, never subtracted again from
  -- disponible_sin_comprometer, never turned into an automatic outflow.
  select
    coalesce(sum(gb.saved_minor - gb.backed_minor), 0)::bigint,
    coalesce(jsonb_agg(jsonb_build_object(
      'goal_id', gb.id, 'name', gb.name, 'shortfall_minor', (gb.saved_minor - gb.backed_minor)::text
    ) order by gb.name) filter (where (gb.saved_minor - gb.backed_minor) <> 0), '[]'::jsonb)
  into faltante_total_minor, faltante_por_meta_json
  from public.goal_balances gb
  where gb.user_id = command_user_id and gb.currency = p_currency and gb.archived_at is null;

  with recursive
  months as (
    select gs as month_index,
      (date_trunc('month', p_as_of_date)::date + (gs::text || ' months')::interval)::date as month_start
    from generate_series(0, p_horizon_months - 1) as gs
  ),

  -- Cards: statement cerrado > preview del corte, one envelope per
  -- statement_date, bucketed by payment_due_date's month -- never
  -- statement_date's month. card_statement_preview_balance already folds
  -- that cycle's non-MSI spend and its own due-that-cycle MSI installment
  -- into one figure (verified by reading its body), so no separate MSI
  -- line is ever added on top of a preview or a closed statement.
  card_cuts as (
    select
      card.id as card_id, card.name, card.statement_day, card.payment_days_after_statement,
      public.card_effective_statement_date(
        extract(year from (public.card_statement_for_date(p_as_of_date, card.statement_day) + (n::text || ' months')::interval))::int,
        extract(month from (public.card_statement_for_date(p_as_of_date, card.statement_day) + (n::text || ' months')::interval))::int,
        card.statement_day
      ) as statement_date
    from public.credit_cards card
    cross join generate_series(0, p_horizon_months + 3) as n
    where card.user_id = command_user_id and card.currency = p_currency and card.is_active
  ),
  card_cuts_due as (
    select cc.card_id, cc.name, cc.statement_date,
      public.card_due_date(cc.statement_date, cc.payment_days_after_statement) as payment_due_date
    from card_cuts cc
  ),
  card_amounts as (
    select
      ccd.card_id, ccd.name, ccd.statement_date, ccd.payment_due_date,
      date_trunc('month', ccd.payment_due_date)::date as due_month,
      (stmt.id is not null) as is_closed,
      coalesce(stmt.remaining_due_minor, public.card_statement_preview_balance(ccd.card_id, ccd.statement_date))::bigint as amount_minor
    from card_cuts_due ccd
    left join public.card_statements stmt
      on stmt.card_id = ccd.card_id and stmt.statement_date = ccd.statement_date and stmt.user_id = command_user_id
    where date_trunc('month', ccd.payment_due_date)::date between (select min(month_start) from months) and (select max(month_start) from months)
  ),
  card_month_totals as (
    select due_month as month_start, sum(amount_minor)::bigint as card_obligations_total_minor
    from card_amounts
    group by 1
  ),

  -- Planned cash flows: expand one_time/monthly occurrences within
  -- [p_as_of_date, horizon_end_exclusive). A monthly flow reuses
  -- card_effective_statement_date to clamp its day to the last valid day
  -- of a shorter month (same philosophy as card cutoffs -- 31 ene -> 28/29
  -- feb -> 31 mar, no permanent drift to day 28).
  flows as (
    select * from public.planned_cash_flows
    where user_id = command_user_id and currency = p_currency and archived_at is null
  ),
  flow_occurrences_raw as (
    select f.id as flow_id, f.name, f.category_id, f.amount_minor, f.end_date, f.start_date as occurred_on
    from flows f
    where f.recurrence = 'one_time'
      and f.start_date >= p_as_of_date and f.start_date < horizon_end_exclusive

    union all

    select f.id as flow_id, f.name, f.category_id, f.amount_minor, f.end_date,
      public.card_effective_statement_date(
        extract(year from gs.month_start)::int,
        extract(month from gs.month_start)::int,
        extract(day from f.start_date)::int
      ) as occurred_on
    from flows f
    cross join lateral generate_series(
      date_trunc('month', greatest(f.start_date, p_as_of_date))::timestamp,
      date_trunc('month', least(coalesce(f.end_date, horizon_end_exclusive - 1), horizon_end_exclusive - 1))::timestamp,
      interval '1 month'
    ) as gs(month_start)
    where f.recurrence = 'monthly'
  ),
  flow_occurrences as (
    select flow_id, name, category_id, amount_minor, occurred_on
    from flow_occurrences_raw
    where occurred_on >= p_as_of_date
      and occurred_on < horizon_end_exclusive
      and occurred_on <= coalesce(end_date, 'infinity'::date)
  ),
  flow_month_totals as (
    select date_trunc('month', occurred_on)::date as month_start,
      coalesce(sum(amount_minor) filter (where amount_minor > 0), 0)::bigint as income_minor,
      coalesce(sum(-amount_minor) filter (where amount_minor < 0), 0)::bigint as outflow_minor
    from flow_occurrences
    group by 1
  ),

  -- Budgets: reuse get_budgets_for_period as-is (already nets MSI out of
  -- available_minor for any month). A categorized planned outflow consumes
  -- part of that remaining room -- never added on top of the full limit.
  budget_rows as (
    select m.month_index, m.month_start,
      (elem->>'category_id') as category_id,
      (elem->>'category_name') as category_name,
      (elem->>'category_icon') as category_icon,
      (elem->>'limit_minor')::bigint as limit_minor,
      (elem->>'spent_minor')::bigint as spent_minor,
      (elem->>'available_minor')::bigint as available_minor
    from months m
    cross join lateral jsonb_array_elements(public.get_budgets_for_period(m.month_start, p_currency)) elem
  ),
  planned_categorized as (
    select date_trunc('month', occurred_on)::date as month_start, category_id,
      sum(-amount_minor)::bigint as planned_categorized_minor
    from flow_occurrences
    where category_id is not null and amount_minor < 0
    group by 1, 2
  ),
  budget_flexible as (
    select br.month_index, br.month_start, br.category_id, br.category_name, br.category_icon,
      br.limit_minor, br.spent_minor, br.available_minor,
      coalesce(pc.planned_categorized_minor, 0)::bigint as planned_categorized_minor,
      greatest(br.available_minor - coalesce(pc.planned_categorized_minor, 0), 0)::bigint as flexible_additional_minor
    from budget_rows br
    left join planned_categorized pc on pc.month_start = br.month_start and pc.category_id = br.category_id
  ),
  budget_month_totals as (
    select month_index, sum(flexible_additional_minor)::bigint as flexible_additional_total_minor
    from budget_flexible
    group by 1
  ),

  -- Goals: pure, non-persisted recursive simulation. Seeded from today's
  -- real saved_minor; only if the scenario assumes the recommended amount
  -- was actually set aside does next month's calculation see it.
  goal_seed as (
    select
      g.id as goal_id, g.status, g.target_minor, g.target_date,
      coalesce(gb.saved_minor, 0)::bigint as saved_minor,
      (case
        when g.target_date is null then null
        when g.target_date <= p_as_of_date then 1
        else greatest(1, (
          extract(year from age(g.target_date, p_as_of_date)) * 12
          + extract(month from age(g.target_date, p_as_of_date))
          + case when extract(day from age(g.target_date, p_as_of_date)) > 0 then 1 else 0 end
        )::int)
      end) as months_remaining_at_start
    from public.goals g
    left join public.goal_balances gb on gb.id = g.id
    where g.user_id = command_user_id and g.currency = p_currency and g.archived_at is null
  ),
  goal_state as (
    select
      seed.goal_id, seed.status, seed.target_minor, seed.target_date,
      0 as month_index,
      seed.saved_minor as projected_saved_minor,
      seed.months_remaining_at_start,
      (case
        when seed.status = 'paused' then 0::bigint
        when seed.target_date is null then null::bigint
        when seed.saved_minor >= seed.target_minor then 0::bigint
        else ceil((seed.target_minor - seed.saved_minor)::numeric / seed.months_remaining_at_start)::bigint
      end) as recommended_minor
    from goal_seed seed

    union all

    select
      prev.goal_id, prev.status, prev.target_minor, prev.target_date,
      prev.month_index + 1,
      (prev.projected_saved_minor + coalesce(prev.recommended_minor, 0))::bigint,
      prev.months_remaining_at_start,
      (case
        when prev.status = 'paused' then 0::bigint
        when prev.target_date is null then null::bigint
        when (prev.projected_saved_minor + coalesce(prev.recommended_minor, 0)) >= prev.target_minor then 0::bigint
        else ceil(
          (prev.target_minor - (prev.projected_saved_minor + coalesce(prev.recommended_minor, 0)))::numeric
          / greatest(1, prev.months_remaining_at_start - (prev.month_index + 1))
        )::bigint
      end)
    from goal_state prev
    where prev.month_index < p_horizon_months - 1
  ),
  goal_month_totals as (
    select month_index, coalesce(sum(recommended_minor), 0)::bigint as recommended_total_minor
    from goal_state
    group by 1
  ),

  -- Expected collections: bucketed straight from receivable_due_item_balances
  -- (the same fully-netted-of-payments figure the per-contact statement
  -- uses), never funneled through income. Overdue items still land in the
  -- current month rather than disappearing.
  collections as (
    select
      greatest(date_trunc('month', balance.payment_due_date)::date, (select min(month_start) from months)) as month_start,
      balance.contact_id, contact.name as contact_name,
      sum(balance.outstanding_minor)::bigint as outstanding_minor
    from public.receivable_due_item_balances balance
    join public.contacts contact on contact.id = balance.contact_id and contact.user_id = command_user_id
    where balance.user_id = command_user_id and balance.currency = p_currency
      and balance.outstanding_minor > 0
      and balance.payment_due_date < horizon_end_exclusive
    group by 1, 2, 3
  ),
  collection_month_totals as (
    select month_start, sum(outstanding_minor)::bigint as expected_collections_total_minor
    from collections
    group by 1
  ),

  month_calc as (
    select
      m.month_index, m.month_start,
      coalesce(cmt.card_obligations_total_minor, 0)::bigint as card_obligations_total_minor,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'card_id', ca.card_id, 'name', ca.name, 'statement_date', ca.statement_date,
          'payment_due_date', ca.payment_due_date, 'is_closed', ca.is_closed,
          'amount_minor', ca.amount_minor::text
        ) order by ca.payment_due_date), '[]'::jsonb)
       from card_amounts ca where ca.due_month = m.month_start and ca.amount_minor <> 0) as card_obligations,

      coalesce(fmt.income_minor, 0)::bigint as planned_income_total_minor,
      coalesce(fmt.outflow_minor, 0)::bigint as planned_outflow_total_minor,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'flow_id', fo.flow_id, 'name', fo.name, 'category_id', fo.category_id,
          'amount_minor', fo.amount_minor::text, 'occurred_on', fo.occurred_on
        ) order by fo.occurred_on), '[]'::jsonb)
       from flow_occurrences fo where date_trunc('month', fo.occurred_on)::date = m.month_start) as planned_flows,

      coalesce(bmt.flexible_additional_total_minor, 0)::bigint as flexible_additional_total_minor,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'category_id', bf.category_id, 'category_name', bf.category_name, 'category_icon', bf.category_icon,
          'limit_minor', bf.limit_minor::text, 'spent_minor', bf.spent_minor::text,
          'available_minor', bf.available_minor::text,
          'planned_categorized_minor', bf.planned_categorized_minor::text,
          'flexible_additional_minor', bf.flexible_additional_minor::text
        ) order by bf.category_name), '[]'::jsonb)
       from budget_flexible bf where bf.month_index = m.month_index) as budgets,

      coalesce(gmt.recommended_total_minor, 0)::bigint as goals_recommended_total_minor,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'goal_id', gst.goal_id, 'name', g.name, 'status', gst.status,
          'target_minor', gst.target_minor::text, 'target_date', gst.target_date,
          'target_date_passed', (gst.target_date is not null and gst.target_date < p_as_of_date),
          'recommended_minor', coalesce(gst.recommended_minor, 0)::text,
          'projected_saved_minor', gst.projected_saved_minor::text
        ) order by g.name), '[]'::jsonb)
       from goal_state gst join public.goals g on g.id = gst.goal_id and g.user_id = command_user_id
       where gst.month_index = m.month_index) as goals,

      coalesce(colmt.expected_collections_total_minor, 0)::bigint as expected_collections_total_minor,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'contact_id', col.contact_id, 'contact_name', col.contact_name,
          'outstanding_minor', col.outstanding_minor::text
        ) order by col.contact_name), '[]'::jsonb)
       from collections col where col.month_start = m.month_start) as expected_collections
    from months m
    left join card_month_totals cmt on cmt.month_start = m.month_start
    left join flow_month_totals fmt on fmt.month_start = m.month_start
    left join budget_month_totals bmt on bmt.month_index = m.month_index
    left join goal_month_totals gmt on gmt.month_index = m.month_index
    left join collection_month_totals colmt on colmt.month_start = m.month_start
  ),

  month_running as (
    select mc.*,
      (mc.planned_income_total_minor - mc.planned_outflow_total_minor - mc.card_obligations_total_minor) as base_net,
      (mc.planned_income_total_minor - mc.planned_outflow_total_minor - mc.card_obligations_total_minor
        - mc.flexible_additional_total_minor - mc.goals_recommended_total_minor) as planned_net,
      (mc.planned_income_total_minor - mc.planned_outflow_total_minor - mc.card_obligations_total_minor
        - mc.flexible_additional_total_minor - mc.goals_recommended_total_minor
        + mc.expected_collections_total_minor) as pwc_net
    from month_calc mc
  ),

  -- Three fully independent scenario chains, each anchored at the SAME
  -- real saldo_inicial but diverging from month 0 onward. base_closing
  -- never becomes planned_opening, and vice versa.
  month_final as (
    select mr.*,
      (disponible_sin_comprometer_minor + sum(mr.base_net) over (order by mr.month_index rows between unbounded preceding and current row))::bigint as base_closing,
      (disponible_sin_comprometer_minor + sum(mr.base_net) over (order by mr.month_index rows between unbounded preceding and current row) - mr.base_net)::bigint as base_opening,
      (disponible_sin_comprometer_minor + sum(mr.planned_net) over (order by mr.month_index rows between unbounded preceding and current row))::bigint as planned_closing,
      (disponible_sin_comprometer_minor + sum(mr.planned_net) over (order by mr.month_index rows between unbounded preceding and current row) - mr.planned_net)::bigint as planned_opening,
      (disponible_sin_comprometer_minor + sum(mr.pwc_net) over (order by mr.month_index rows between unbounded preceding and current row))::bigint as pwc_closing,
      (disponible_sin_comprometer_minor + sum(mr.pwc_net) over (order by mr.month_index rows between unbounded preceding and current row) - mr.pwc_net)::bigint as pwc_opening
    from month_running mr
  )

  select jsonb_build_object(
    'as_of_date', p_as_of_date,
    'currency', p_currency,
    'horizon_months', p_horizon_months,
    'saldo_inicial', jsonb_build_object(
      'accounts', accounts_json,
      'saldo_en_cuentas_minor', saldo_en_cuentas_minor::text,
      'apartado_respaldado_minor', apartado_respaldado_minor::text,
      'disponible_sin_comprometer_minor', disponible_sin_comprometer_minor::text,
      'faltante_de_respaldo_minor', faltante_total_minor::text,
      'faltante_de_respaldo_por_meta', faltante_por_meta_json
    ),
    'months', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'month_index', mf.month_index,
        'month_start', mf.month_start,
        'card_obligations', mf.card_obligations,
        'card_obligations_total_minor', mf.card_obligations_total_minor::text,
        'planned_flows', mf.planned_flows,
        'planned_income_total_minor', mf.planned_income_total_minor::text,
        'planned_outflow_total_minor', mf.planned_outflow_total_minor::text,
        'budgets', mf.budgets,
        'flexible_additional_total_minor', mf.flexible_additional_total_minor::text,
        'goals', mf.goals,
        'goals_recommended_total_minor', mf.goals_recommended_total_minor::text,
        'expected_collections', mf.expected_collections,
        'expected_collections_total_minor', mf.expected_collections_total_minor::text,
        'base', jsonb_build_object('opening_minor', mf.base_opening::text, 'closing_minor', mf.base_closing::text),
        'planned', jsonb_build_object('opening_minor', mf.planned_opening::text, 'closing_minor', mf.planned_closing::text),
        'planned_with_collections', jsonb_build_object('opening_minor', mf.pwc_opening::text, 'closing_minor', mf.pwc_closing::text)
      ) order by mf.month_index), '[]'::jsonb)
      from month_final mf
    )
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_financial_plan(text, date, integer) from public, anon;
grant execute on function public.get_financial_plan(text, date, integer) to authenticated;
