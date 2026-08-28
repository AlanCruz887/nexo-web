-- Phase 3A: credit cards, baselines, cycle engine, and statement snapshots.
-- Open cycles are derived projections; persisted statements are immutable financial
-- snapshots whose payment fields may only change through an audited RPC.

alter table public.financial_events
  drop constraint financial_events_kind_valid,
  drop constraint financial_events_amount_valid,
  drop constraint financial_events_personal_amount_valid;

alter table public.financial_events
  add constraint financial_events_kind_valid check (
    kind in (
      'opening', 'income', 'expense', 'adjustment', 'transfer', 'reversal',
      'card_charge', 'card_payment', 'card_refund', 'card_adjustment'
    )
  ),
  add constraint financial_events_amount_valid check (
    (kind in ('income', 'expense', 'transfer', 'reversal', 'card_charge', 'card_payment', 'card_refund') and amount_minor > 0)
    or (kind in ('opening', 'adjustment', 'card_adjustment') and amount_minor <> 0)
  ),
  add constraint financial_events_personal_amount_valid check (
    personal_amount_minor >= 0
    and (
      (kind = 'expense' and personal_amount_minor = amount_minor)
      or (kind <> 'expense' and personal_amount_minor = 0)
    )
  );

create table public.credit_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  issuer text not null,
  product_name text,
  currency text not null references public.currencies (code),
  credit_limit_minor bigint not null,
  statement_day smallint not null,
  payment_days_after_statement smallint not null,
  last4 text,
  visual_theme text not null default 'generic',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_cards_name_not_blank check (char_length(btrim(name)) between 1 and 80),
  constraint credit_cards_issuer_not_blank check (char_length(btrim(issuer)) between 1 and 100),
  constraint credit_cards_product_length check (product_name is null or char_length(btrim(product_name)) between 1 and 100),
  constraint credit_cards_limit_nonnegative check (credit_limit_minor >= 0),
  constraint credit_cards_statement_day_valid check (statement_day between 1 and 31),
  constraint credit_cards_payment_days_valid check (payment_days_after_statement between 0 and 90),
  constraint credit_cards_last4_format check (last4 is null or last4 ~ '^\d{4}$'),
  constraint credit_cards_theme_valid check (visual_theme in ('bbva_oro', 'banamex_clasica', 'banamex_joy', 'nu', 'generic'))
);

create index credit_cards_user_active_created_idx
  on public.credit_cards (user_id, is_active, created_at desc);

alter table public.credit_cards enable row level security;
revoke all on table public.credit_cards from anon, authenticated;
grant select on table public.credit_cards to authenticated;
grant all on table public.credit_cards to service_role;

create policy "Users can read their own credit cards"
on public.credit_cards for select to authenticated
using ((select auth.uid()) = user_id);

create table public.card_baselines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  card_id uuid not null unique references public.credit_cards (id) on delete restrict,
  policy text not null,
  baseline_date date not null,
  reported_bank_balance_minor bigint not null,
  excluded_statement_amount_minor bigint,
  baseline_balance_minor bigint not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint card_baselines_policy_valid check (policy in ('current_bank_balance', 'after_last_statement', 'specific_date')),
  constraint card_baselines_reported_nonnegative check (reported_bank_balance_minor >= 0),
  constraint card_baselines_excluded_nonnegative check (excluded_statement_amount_minor is null or excluded_statement_amount_minor >= 0),
  constraint card_baselines_balance_nonnegative check (baseline_balance_minor >= 0),
  constraint card_baselines_notes_length check (notes is null or char_length(notes) <= 2000),
  constraint card_baselines_policy_amounts_valid check (
    (policy = 'after_last_statement'
      and excluded_statement_amount_minor is not null
      and baseline_balance_minor = reported_bank_balance_minor - excluded_statement_amount_minor)
    or
    (policy in ('current_bank_balance', 'specific_date')
      and excluded_statement_amount_minor is null
      and baseline_balance_minor = reported_bank_balance_minor)
  )
);

create index card_baselines_user_card_idx on public.card_baselines (user_id, card_id);

alter table public.card_baselines enable row level security;
revoke all on table public.card_baselines from anon, authenticated;
grant select on table public.card_baselines to authenticated;
grant all on table public.card_baselines to service_role;

create policy "Users can read their own card baselines"
on public.card_baselines for select to authenticated
using ((select auth.uid()) = user_id);

create table public.card_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  card_id uuid not null references public.credit_cards (id) on delete restrict,
  amount_minor bigint not null,
  effect_scope text not null default 'impacting',
  created_at timestamptz not null default now(),
  constraint card_entries_amount_nonzero check (amount_minor <> 0),
  constraint card_entries_effect_scope_valid check (effect_scope in ('impacting', 'historical_non_impacting')),
  constraint card_entries_event_card_unique unique (financial_event_id, card_id)
);

create index card_entries_user_card_created_idx
  on public.card_entries (user_id, card_id, created_at desc);
create index card_entries_card_event_idx
  on public.card_entries (card_id, financial_event_id);

alter table public.card_entries enable row level security;
revoke all on table public.card_entries from anon, authenticated;
grant select on table public.card_entries to authenticated;
grant all on table public.card_entries to service_role;

create policy "Users can read their own card entries"
on public.card_entries for select to authenticated
using ((select auth.uid()) = user_id);

create table public.card_statements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  card_id uuid not null references public.credit_cards (id) on delete restrict,
  statement_date date not null,
  cycle_start date not null,
  cycle_end date not null,
  statement_balance_minor bigint not null,
  payment_due_date date not null,
  payment_to_avoid_interest_minor bigint not null,
  minimum_payment_minor bigint,
  amount_paid_minor bigint not null default 0,
  remaining_due_minor bigint not null,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint card_statements_card_date_unique unique (card_id, statement_date),
  constraint card_statements_cycle_valid check (cycle_start < cycle_end and cycle_end = statement_date),
  constraint card_statements_amounts_nonnegative check (
    statement_balance_minor >= 0
    and payment_to_avoid_interest_minor >= 0
    and (minimum_payment_minor is null or minimum_payment_minor >= 0)
    and amount_paid_minor >= 0
    and remaining_due_minor >= 0
  ),
  constraint card_statements_remaining_valid check (
    remaining_due_minor = greatest(statement_balance_minor - amount_paid_minor, 0)
  ),
  constraint card_statements_status_valid check (status in ('open', 'closed', 'paid')),
  constraint card_statements_status_remaining_valid check (
    (status = 'paid' and remaining_due_minor = 0)
    or (status in ('open', 'closed') and remaining_due_minor > 0)
    or (status = 'closed' and statement_balance_minor = 0 and remaining_due_minor = 0)
  )
);

create index card_statements_user_card_date_idx
  on public.card_statements (user_id, card_id, statement_date desc);

alter table public.card_statements enable row level security;
revoke all on table public.card_statements from anon, authenticated;
grant select on table public.card_statements to authenticated;
grant all on table public.card_statements to service_role;

create policy "Users can read their own card statements"
on public.card_statements for select to authenticated
using ((select auth.uid()) = user_id);

create trigger credit_cards_set_updated_at
before update on public.credit_cards
for each row execute function private.set_updated_at();

create trigger card_statements_set_updated_at
before update on public.card_statements
for each row execute function private.set_updated_at();

create trigger card_baselines_are_immutable
before update or delete on public.card_baselines
for each row execute function private.reject_financial_mutation();

create trigger card_entries_are_immutable
before update or delete on public.card_entries
for each row execute function private.reject_financial_mutation();

create function public.card_effective_statement_date(
  p_year integer,
  p_month integer,
  p_statement_day integer
)
returns date
language sql
immutable
strict
set search_path = ''
as $$
  select make_date(
    p_year,
    p_month,
    least(
      p_statement_day,
      extract(day from (make_date(p_year, p_month, 1) + interval '1 month - 1 day'))::integer
    )
  );
$$;

create function public.card_statement_for_date(
  p_transaction_date date,
  p_statement_day integer
)
returns date
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  candidate date;
  following_month date;
begin
  candidate := public.card_effective_statement_date(
    extract(year from p_transaction_date)::integer,
    extract(month from p_transaction_date)::integer,
    p_statement_day
  );
  if p_transaction_date < candidate then
    return candidate;
  end if;
  following_month := (date_trunc('month', p_transaction_date)::date + interval '1 month')::date;
  return public.card_effective_statement_date(
    extract(year from following_month)::integer,
    extract(month from following_month)::integer,
    p_statement_day
  );
end;
$$;

create function public.card_previous_statement_date(
  p_statement_date date,
  p_statement_day integer
)
returns date
language sql
immutable
strict
set search_path = ''
as $$
  select public.card_effective_statement_date(
    extract(year from (date_trunc('month', p_statement_date)::date - interval '1 month'))::integer,
    extract(month from (date_trunc('month', p_statement_date)::date - interval '1 month'))::integer,
    p_statement_day
  );
$$;

create function public.card_due_date(
  p_statement_date date,
  p_payment_days_after_statement integer
)
returns date
language sql
immutable
strict
set search_path = ''
as $$
  select p_statement_date + p_payment_days_after_statement;
$$;

create function public.card_cycle_for_date(
  p_transaction_date date,
  p_statement_day integer
)
returns table (statement_date date, cycle_start date, cycle_end date)
language sql
immutable
strict
set search_path = ''
as $$
  select
    target.statement_date,
    public.card_previous_statement_date(target.statement_date, p_statement_day),
    target.statement_date
  from (select public.card_statement_for_date(p_transaction_date, p_statement_day) as statement_date) target;
$$;

revoke all on function public.card_effective_statement_date(integer, integer, integer) from public, anon;
revoke all on function public.card_statement_for_date(date, integer) from public, anon;
revoke all on function public.card_previous_statement_date(date, integer) from public, anon;
revoke all on function public.card_due_date(date, integer) from public, anon;
revoke all on function public.card_cycle_for_date(date, integer) from public, anon;
grant execute on function public.card_effective_statement_date(integer, integer, integer) to authenticated;
grant execute on function public.card_statement_for_date(date, integer) to authenticated;
grant execute on function public.card_previous_statement_date(date, integer) to authenticated;
grant execute on function public.card_due_date(date, integer) to authenticated;
grant execute on function public.card_cycle_for_date(date, integer) to authenticated;

create function public.create_credit_card(
  p_name text,
  p_issuer text,
  p_product_name text,
  p_currency text,
  p_credit_limit_minor bigint,
  p_statement_day integer,
  p_payment_days_after_statement integer,
  p_last4 text,
  p_visual_theme text,
  p_baseline_policy text,
  p_baseline_date date,
  p_reported_bank_balance_minor bigint,
  p_excluded_statement_amount_minor bigint,
  p_baseline_notes text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_card_id uuid := gen_random_uuid();
  resolved_card_id uuid;
  baseline_id uuid := gen_random_uuid();
  normalized_name text := btrim(p_name);
  normalized_issuer text := btrim(p_issuer);
  normalized_product text := nullif(btrim(p_product_name), '');
  normalized_last4 text := nullif(btrim(p_last4), '');
  normalized_notes text := nullif(btrim(p_baseline_notes), '');
  effective_baseline_date date;
  comparable_balance bigint;
  normalized_excluded bigint;
  command_payload jsonb;
begin
  effective_baseline_date := case
    when p_baseline_policy = 'specific_date' then p_baseline_date
    else coalesce(p_baseline_date, current_date)
  end;
  if effective_baseline_date is null then
    raise exception 'NEXO_BASELINE_DATE_REQUIRED' using errcode = '22023';
  end if;
  normalized_excluded := case when p_baseline_policy = 'after_last_statement'
    then p_excluded_statement_amount_minor else null end;
  comparable_balance := case when p_baseline_policy = 'after_last_statement'
    then p_reported_bank_balance_minor - coalesce(p_excluded_statement_amount_minor, -1)
    else p_reported_bank_balance_minor end;
  if p_reported_bank_balance_minor < 0 or comparable_balance < 0 then
    raise exception 'NEXO_INVALID_BASELINE_AMOUNT' using errcode = '22023';
  end if;
  if p_baseline_policy = 'after_last_statement'
    and (p_excluded_statement_amount_minor is null or p_excluded_statement_amount_minor < 0) then
    raise exception 'NEXO_EXCLUDED_STATEMENT_REQUIRED' using errcode = '22023';
  end if;

  command_payload := jsonb_build_object(
    'name', normalized_name, 'issuer', normalized_issuer, 'product_name', normalized_product,
    'currency', p_currency, 'credit_limit_minor', p_credit_limit_minor::text,
    'statement_day', p_statement_day, 'payment_days_after_statement', p_payment_days_after_statement,
    'last4', normalized_last4, 'visual_theme', p_visual_theme,
    'baseline_policy', p_baseline_policy, 'baseline_date', effective_baseline_date,
    'reported_bank_balance_minor', p_reported_bank_balance_minor::text,
    'excluded_statement_amount_minor', normalized_excluded::text, 'baseline_notes', normalized_notes
  );
  resolved_card_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_credit_card', command_payload, proposed_card_id
  );
  if resolved_card_id <> proposed_card_id then return resolved_card_id; end if;

  insert into public.credit_cards (
    id, user_id, name, issuer, product_name, currency, credit_limit_minor,
    statement_day, payment_days_after_statement, last4, visual_theme
  ) values (
    proposed_card_id, command_user_id, normalized_name, normalized_issuer, normalized_product,
    p_currency, p_credit_limit_minor, p_statement_day, p_payment_days_after_statement,
    normalized_last4, p_visual_theme
  );
  insert into public.card_baselines (
    id, user_id, card_id, policy, baseline_date, reported_bank_balance_minor,
    excluded_statement_amount_minor, baseline_balance_minor, notes
  ) values (
    baseline_id, command_user_id, proposed_card_id, p_baseline_policy, effective_baseline_date,
    p_reported_bank_balance_minor, normalized_excluded, comparable_balance, normalized_notes
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values
    (command_user_id, 'card_created', 'credit_card', proposed_card_id, command_payload),
    (command_user_id, 'card_baseline_created', 'card_baseline', baseline_id,
      jsonb_build_object('card_id', proposed_card_id, 'policy', p_baseline_policy, 'baseline_balance_minor', comparable_balance::text));
  return proposed_card_id;
end;
$$;

create function public.update_credit_card(
  p_card_id uuid,
  p_name text,
  p_issuer text,
  p_product_name text,
  p_credit_limit_minor bigint,
  p_statement_day integer,
  p_payment_days_after_statement integer,
  p_last4 text,
  p_visual_theme text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_result_id uuid := gen_random_uuid();
  resolved_result_id uuid;
  command_payload jsonb := jsonb_build_object(
    'card_id', p_card_id, 'name', btrim(p_name), 'issuer', btrim(p_issuer),
    'product_name', nullif(btrim(p_product_name), ''), 'credit_limit_minor', p_credit_limit_minor::text,
    'statement_day', p_statement_day, 'payment_days_after_statement', p_payment_days_after_statement,
    'last4', nullif(btrim(p_last4), ''), 'visual_theme', p_visual_theme
  );
begin
  resolved_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_credit_card', command_payload, proposed_result_id
  );
  if resolved_result_id <> proposed_result_id then return p_card_id; end if;
  update public.credit_cards set
    name = btrim(p_name), issuer = btrim(p_issuer), product_name = nullif(btrim(p_product_name), ''),
    credit_limit_minor = p_credit_limit_minor, statement_day = p_statement_day,
    payment_days_after_statement = p_payment_days_after_statement,
    last4 = nullif(btrim(p_last4), ''), visual_theme = p_visual_theme
  where id = p_card_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  insert into public.audit_events (id, user_id, action, entity_type, entity_id, metadata)
  values (proposed_result_id, command_user_id, 'card_updated', 'credit_card', p_card_id, command_payload);
  return p_card_id;
end;
$$;

create function public.archive_credit_card(p_card_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  result_id uuid := gen_random_uuid();
  resolved_id uuid;
  payload jsonb := jsonb_build_object('card_id', p_card_id);
begin
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key, 'archive_credit_card', payload, result_id);
  if resolved_id <> result_id then return p_card_id; end if;
  update public.credit_cards set is_active = false
  where id = p_card_id and user_id = command_user_id and is_active;
  if found then
    insert into public.audit_events (id, user_id, action, entity_type, entity_id)
    values (result_id, command_user_id, 'card_archived', 'credit_card', p_card_id);
  elsif not exists (select 1 from public.credit_cards where id = p_card_id and user_id = command_user_id) then
    raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;
  return p_card_id;
end;
$$;

create function public.restore_credit_card(p_card_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  result_id uuid := gen_random_uuid();
  resolved_id uuid;
  payload jsonb := jsonb_build_object('card_id', p_card_id);
begin
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key, 'restore_credit_card', payload, result_id);
  if resolved_id <> result_id then return p_card_id; end if;
  update public.credit_cards set is_active = true
  where id = p_card_id and user_id = command_user_id and not is_active;
  if found then
    insert into public.audit_events (id, user_id, action, entity_type, entity_id)
    values (result_id, command_user_id, 'card_restored', 'credit_card', p_card_id);
  elsif not exists (select 1 from public.credit_cards where id = p_card_id and user_id = command_user_id) then
    raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;
  return p_card_id;
end;
$$;

create function public.close_card_statement(
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
  baseline public.card_baselines%rowtype;
  cycle_start_date date;
  due_date date;
  used_at_cut bigint;
  statement_balance bigint;
  payment_to_avoid bigint;
  payload jsonb;
begin
  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  if p_statement_date <> public.card_effective_statement_date(
    extract(year from p_statement_date)::integer,
    extract(month from p_statement_date)::integer,
    target_card.statement_day
  ) then raise exception 'NEXO_INVALID_STATEMENT_DATE' using errcode = '22023'; end if;
  select * into strict baseline from public.card_baselines
  where card_id = p_card_id and user_id = command_user_id;
  if p_statement_date <= baseline.baseline_date then
    raise exception 'NEXO_STATEMENT_BEFORE_BASELINE' using errcode = '22023';
  end if;

  payload := jsonb_build_object(
    'card_id', p_card_id, 'statement_date', p_statement_date,
    'payment_to_avoid_interest_minor', p_payment_to_avoid_interest_minor::text,
    'minimum_payment_minor', p_minimum_payment_minor::text
  );
  resolved_statement_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'close_card_statement', payload, proposed_statement_id
  );
  if resolved_statement_id <> proposed_statement_id then return resolved_statement_id; end if;
  if exists (select 1 from public.card_statements where card_id = p_card_id and statement_date = p_statement_date) then
    raise exception 'NEXO_STATEMENT_ALREADY_CLOSED' using errcode = '23505';
  end if;

  cycle_start_date := public.card_previous_statement_date(p_statement_date, target_card.statement_day);
  due_date := public.card_due_date(p_statement_date, target_card.payment_days_after_statement);
  select baseline.baseline_balance_minor + coalesce(sum(entry.amount_minor), 0)
  into used_at_cut
  from public.card_entries entry
  join public.financial_events event on event.id = entry.financial_event_id
  where entry.card_id = p_card_id
    and entry.user_id = command_user_id
    and entry.effect_scope = 'impacting'
    and event.occurred_on >= baseline.baseline_date
    and event.occurred_on < p_statement_date;
  statement_balance := greatest(used_at_cut, 0);
  payment_to_avoid := coalesce(p_payment_to_avoid_interest_minor, statement_balance);
  if payment_to_avoid < 0 or p_minimum_payment_minor < 0 then
    raise exception 'NEXO_INVALID_STATEMENT_AMOUNT' using errcode = '22023';
  end if;

  insert into public.card_statements (
    id, user_id, card_id, statement_date, cycle_start, cycle_end,
    statement_balance_minor, payment_due_date, payment_to_avoid_interest_minor,
    minimum_payment_minor, amount_paid_minor, remaining_due_minor, status
  ) values (
    proposed_statement_id, command_user_id, p_card_id, p_statement_date, cycle_start_date, p_statement_date,
    statement_balance, due_date, payment_to_avoid, p_minimum_payment_minor, 0, statement_balance,
    case when statement_balance = 0 then 'closed' else 'closed' end
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_statement_closed', 'card_statement', proposed_statement_id,
    jsonb_build_object('card_id', p_card_id, 'statement_date', p_statement_date, 'statement_balance_minor', statement_balance::text));
  return proposed_statement_id;
end;
$$;

create function public.update_card_statement(
  p_statement_id uuid,
  p_payment_to_avoid_interest_minor bigint,
  p_minimum_payment_minor bigint,
  p_amount_paid_minor bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  result_id uuid := gen_random_uuid();
  resolved_id uuid;
  target_statement public.card_statements%rowtype;
  remaining bigint;
  payload jsonb := jsonb_build_object(
    'statement_id', p_statement_id,
    'payment_to_avoid_interest_minor', p_payment_to_avoid_interest_minor::text,
    'minimum_payment_minor', p_minimum_payment_minor::text,
    'amount_paid_minor', p_amount_paid_minor::text
  );
begin
  resolved_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_card_statement', payload, result_id
  );
  if resolved_id <> result_id then return p_statement_id; end if;
  select * into target_statement from public.card_statements
  where id = p_statement_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_STATEMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_payment_to_avoid_interest_minor < 0
    or p_minimum_payment_minor < 0
    or p_amount_paid_minor < 0 then
    raise exception 'NEXO_INVALID_STATEMENT_AMOUNT' using errcode = '22023';
  end if;
  remaining := greatest(target_statement.statement_balance_minor - p_amount_paid_minor, 0);
  update public.card_statements set
    payment_to_avoid_interest_minor = p_payment_to_avoid_interest_minor,
    minimum_payment_minor = p_minimum_payment_minor,
    amount_paid_minor = p_amount_paid_minor,
    remaining_due_minor = remaining,
    status = case when remaining = 0 then 'paid' else 'closed' end
  where id = p_statement_id;
  insert into public.audit_events (id, user_id, action, entity_type, entity_id, metadata)
  values (result_id, command_user_id, 'card_statement_updated', 'card_statement', p_statement_id, payload);
  return p_statement_id;
end;
$$;

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
),
calculated as (
  select
    base.*,
    base.baseline_balance_minor + coalesce((
      select sum(entry.amount_minor)
      from public.card_entries entry
      where entry.card_id = base.id and entry.effect_scope = 'impacting'
    ), 0) as used_balance_minor,
    coalesce((
      select sum(entry.amount_minor)
      from public.card_entries entry
      join public.financial_events event on event.id = entry.financial_event_id
      where entry.card_id = base.id
        and entry.effect_scope = 'impacting'
        and event.kind in ('card_charge', 'card_refund', 'card_adjustment')
        and event.occurred_on >= public.card_previous_statement_date(base.next_statement_date, base.statement_day)
        and event.occurred_on < base.next_statement_date
    ), 0) as open_cycle_accumulated_minor
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
  order by statement.statement_date desc
  limit 1
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

revoke all on function public.create_credit_card(text, text, text, text, bigint, integer, integer, text, text, text, date, bigint, bigint, text, text) from public, anon;
revoke all on function public.update_credit_card(uuid, text, text, text, bigint, integer, integer, text, text, text) from public, anon;
revoke all on function public.archive_credit_card(uuid, text) from public, anon;
revoke all on function public.restore_credit_card(uuid, text) from public, anon;
revoke all on function public.close_card_statement(uuid, date, bigint, bigint, text) from public, anon;
revoke all on function public.update_card_statement(uuid, bigint, bigint, bigint, text) from public, anon;
grant execute on function public.create_credit_card(text, text, text, text, bigint, integer, integer, text, text, text, date, bigint, bigint, text, text) to authenticated;
grant execute on function public.update_credit_card(uuid, text, text, text, bigint, integer, integer, text, text, text) to authenticated;
grant execute on function public.archive_credit_card(uuid, text) to authenticated;
grant execute on function public.restore_credit_card(uuid, text) to authenticated;
grant execute on function public.close_card_statement(uuid, date, bigint, bigint, text) to authenticated;
grant execute on function public.update_card_statement(uuid, bigint, bigint, bigint, text) to authenticated;

create or replace function public.reverse_transaction(
  p_event_id uuid,
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
  original_kind text;
  command_payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  resolved_reversal_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_transaction', command_payload, proposed_reversal_id
  );
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;
  select kind into original_kind from public.financial_events
  where id = p_event_id and user_id = command_user_id;
  if original_kind is null then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_kind not in ('income', 'expense', 'adjustment') then
    raise exception 'NEXO_TRANSACTION_NOT_REVERSIBLE' using errcode = '23514';
  end if;
  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión de movimiento');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transaction_deleted', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', proposed_reversal_id)
  );
  return proposed_reversal_id;
end;
$$;

revoke all on function public.reverse_transaction(uuid, text) from public, anon;
grant execute on function public.reverse_transaction(uuid, text) to authenticated;
