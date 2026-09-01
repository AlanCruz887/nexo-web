-- Nexo Phase 6B: savings goals. A goal is never income, never expense, and
-- never a second accounting of money. Its progress lives entirely in
-- goal_entries -- an append-only, signed ledger, same shape as
-- person_credit_entries (Phase 5B) -- with one deliberate divergence:
-- financial_event_id is nullable here, because the whole point of this
-- module is to also support money that was only ever mentally set aside
-- (a virtual reservation), never actually moved between accounts.
--
-- goal_entries.account_id identifies the real account that backs a given
-- reservation. It is NOT informational: a virtual contribution is checked,
-- transactionally, against that account's real balance minus whatever is
-- already reserved against it (by this goal or any other), using the exact
-- same accounts-row FOR UPDATE lock every other balance-mutating RPC in
-- this codebase already takes (create_transaction, create_transfer,
-- create_person_payment, create_card_payment). No new locking primitive.
--
-- Two things are computed at read time, never stored:
--   saved_minor   = SUM(goal_entries.amount_minor) -- the registered ledger.
--   backed_minor  = how much of that is still covered by the CURRENT real
--                   balance of the accounts backing it, distributed FIFO
--                   by the age of each still-alive reservation (not the
--                   goal's oldest historical contribution -- a lot that was
--                   fully withdrawn and re-contributed gets a fresh age).
-- saved_minor never changes because of unrelated spending; backed_minor is
-- the honest, separate answer to "is this still really there".

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  currency text not null references public.currencies (code),
  target_minor bigint not null,
  target_date date,
  linked_account_id uuid references public.accounts (id) on delete restrict,
  icon text,
  status text not null default 'active',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint goals_name_not_blank check (char_length(btrim(name)) between 1 and 120),
  constraint goals_target_positive check (target_minor > 0),
  constraint goals_status_valid check (status in ('active', 'paused')),
  constraint goals_icon_length check (icon is null or char_length(icon) <= 40)
);

create index goals_user_active_idx on public.goals (user_id, status) where archived_at is null;

create trigger goals_set_updated_at
before update on public.goals
for each row execute function private.set_updated_at();

alter table public.goals enable row level security;
revoke all on table public.goals from anon, authenticated;
grant select on table public.goals to authenticated;
grant all on table public.goals to service_role;

create policy "Goals are readable by owner"
on public.goals
for select
to authenticated
using ((select auth.uid()) = user_id);

-- The one ledger. entry_kind + reverses_entry_id follow the exact
-- direction-validity shape already used by person_credit_entries /
-- receivable_due_applications.
create table public.goal_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  goal_id uuid not null references public.goals (id) on delete restrict,
  account_id uuid not null references public.accounts (id) on delete restrict,
  financial_event_id uuid references public.financial_events (id) on delete restrict,
  amount_minor bigint not null check (amount_minor <> 0),
  entry_kind text not null check (entry_kind in ('contribution', 'withdrawal', 'reversal')),
  reverses_entry_id uuid references public.goal_entries (id) on delete restrict,
  occurred_on date not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint goal_entries_notes_length check (notes is null or char_length(notes) <= 2000),
  constraint goal_entries_direction_valid check (
    (entry_kind = 'contribution' and amount_minor > 0 and reverses_entry_id is null)
    or (entry_kind = 'withdrawal' and amount_minor < 0 and reverses_entry_id is null)
    or (entry_kind = 'reversal' and reverses_entry_id is not null)
  )
);

create index goal_entries_goal_idx on public.goal_entries (goal_id, occurred_on, created_at, id);
create index goal_entries_account_idx on public.goal_entries (account_id, occurred_on, created_at, id);
create index goal_entries_event_idx on public.goal_entries (financial_event_id);
create unique index goal_entries_reversal_unique on public.goal_entries (reverses_entry_id)
  where reverses_entry_id is not null;

alter table public.goal_entries enable row level security;
revoke all on table public.goal_entries from anon, authenticated;
grant select on table public.goal_entries to authenticated;
grant all on table public.goal_entries to service_role;

create policy "Goal entries are readable by owner"
on public.goal_entries
for select
to authenticated
using ((select auth.uid()) = user_id);

create trigger goal_entries_are_immutable
before update or delete on public.goal_entries
for each row execute function private.reject_financial_mutation();

-- Private helper: the exact core of create_transfer (Phase 2), duplicated
-- on purpose rather than calling the public RPC -- create_transfer owns
-- its own idempotency resolution under its own command_type, and nesting
-- it here would require a second, synthetic idempotency key for no real
-- benefit. This helper carries none of its own idempotency handling; the
-- caller (contribute_to_goal / withdraw_from_goal) already wraps the whole
-- compound operation in one idempotent command, exactly like
-- apply_person_amount_to_due_items is a non-idempotent-on-its-own helper
-- shared by create_person_payment and apply_person_credit.
create function private.execute_goal_transfer(
  command_user_id uuid, p_from_account_id uuid, p_to_account_id uuid,
  p_amount_minor bigint, p_description text, p_occurred_on date
)
returns uuid language plpgsql set search_path = '' as $$
declare
  proposed_event_id uuid := gen_random_uuid();
  account_count integer; currency_count integer; active_count integer;
begin
  -- Same deadlock-avoidance convention create_transfer already uses: lock
  -- both account rows in a single, id-ordered statement, never source-then-
  -- destination -- so a concurrent transfer/goal operation touching the
  -- same two accounts in the opposite direction can never deadlock against
  -- this.
  perform 1 from public.accounts
  where id in (p_from_account_id, p_to_account_id) and user_id = command_user_id
  order by id
  for update;

  select count(*), count(distinct currency), count(*) filter (where is_active)
  into account_count, currency_count, active_count
  from public.accounts
  where id in (p_from_account_id, p_to_account_id) and user_id = command_user_id;

  if account_count <> 2 then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if active_count <> 2 then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  if currency_count <> 1 then raise exception 'NEXO_TRANSFER_CURRENCY_MISMATCH' using errcode = '23514'; end if;

  insert into public.financial_events (id, user_id, kind, amount_minor, description, occurred_on)
  values (proposed_event_id, command_user_id, 'transfer', p_amount_minor, p_description, p_occurred_on);
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values
    (command_user_id, proposed_event_id, p_from_account_id, -p_amount_minor),
    (command_user_id, proposed_event_id, p_to_account_id, p_amount_minor);
  return proposed_event_id;
end;
$$;

-- Step 1 of the FIFO backing algorithm: for every still-alive contribution
-- (never reversed -- a reversed pair always sums to zero and is excluded
-- entirely, which is exactly why a fully-withdrawn-then-reversed lot never
-- resurfaces), how much of it remains after that SAME goal's own
-- withdrawals from that SAME account consumed the oldest lots first. This
-- is a read-time replay, not a stored allocation -- rebuildable from
-- goal_entries alone, same cumulative-allocation technique already used by
-- create_installment_receivable_due_items (Phase 5B) for splitting MSI
-- principal among third parties.
create view public.goal_lot_remaining
with (security_invoker = true)
as
with alive as (
  select ge.id, ge.user_id, ge.goal_id, ge.account_id, ge.entry_kind, ge.amount_minor,
    ge.occurred_on, ge.created_at
  from public.goal_entries ge
  where ge.entry_kind in ('contribution', 'withdrawal')
    and not exists (select 1 from public.goal_entries reversal where reversal.reverses_entry_id = ge.id)
), contributions as (
  select id, user_id, goal_id, account_id, amount_minor, occurred_on, created_at,
    sum(amount_minor) over (
      partition by goal_id, account_id order by occurred_on, created_at, id
      rows between unbounded preceding and current row
    ) as cumulative_through_minor
  from alive
  where entry_kind = 'contribution'
), withdrawn as (
  select goal_id, account_id, sum(-amount_minor)::bigint as total_withdrawn_minor
  from alive
  where entry_kind = 'withdrawal'
  group by goal_id, account_id
)
select
  contribution.id, contribution.user_id, contribution.goal_id, contribution.account_id,
  contribution.occurred_on, contribution.created_at,
  contribution.amount_minor as contributed_minor,
  (contribution.amount_minor - greatest(least(
    coalesce(withdrawn.total_withdrawn_minor, 0) - (contribution.cumulative_through_minor - contribution.amount_minor),
    contribution.amount_minor
  ), 0))::bigint as remaining_minor
from contributions contribution
left join withdrawn on withdrawn.goal_id = contribution.goal_id and withdrawn.account_id = contribution.account_id;

revoke all on table public.goal_lot_remaining from anon, authenticated;
grant select on table public.goal_lot_remaining to authenticated;
grant all on table public.goal_lot_remaining to service_role;

-- Step 2: across every goal sharing an account, the still-alive lots
-- (from step 1) compete for that account's CURRENT real balance, oldest
-- lot first -- a new contribution always gets a fresh age, never reusing a
-- fully-released lot's original priority.
create view public.goal_account_backing
with (security_invoker = true)
as
with alive_lots as (
  select * from public.goal_lot_remaining where remaining_minor > 0
), ordered as (
  select alive_lots.*,
    sum(remaining_minor) over (
      partition by account_id order by occurred_on, created_at, id
      rows between unbounded preceding and 1 preceding
    ) as reserved_before_minor
  from alive_lots
), account_balance as (
  select account_id, coalesce(sum(amount_minor), 0)::bigint as balance_minor
  from public.account_entries
  group by account_id
)
select
  ordered.id, ordered.user_id, ordered.goal_id, ordered.account_id, ordered.remaining_minor,
  greatest(least(
    coalesce(account_balance.balance_minor, 0) - coalesce(ordered.reserved_before_minor, 0),
    ordered.remaining_minor
  ), 0)::bigint as backed_minor
from ordered
left join account_balance on account_balance.account_id = ordered.account_id;

revoke all on table public.goal_account_backing from anon, authenticated;
grant select on table public.goal_account_backing to authenticated;
grant all on table public.goal_account_backing to service_role;

-- The read contract for a goal: registered progress, currently-backed
-- progress, and the monthly amount needed, all pre-computed so the
-- frontend never subtracts or ranks anything itself.
create view public.goal_balances
with (security_invoker = true)
as
select
  goal.id, goal.user_id, goal.name, goal.currency, goal.target_minor, goal.target_date,
  goal.linked_account_id, goal.icon, goal.status, goal.archived_at,
  goal.created_at, goal.updated_at,
  coalesce(saved.saved_minor, 0)::bigint as saved_minor,
  coalesce(backed.backed_minor, 0)::bigint as backed_minor,
  greatest(goal.target_minor - coalesce(saved.saved_minor, 0), 0)::bigint as remaining_minor,
  case when goal.target_minor = 0 then 0
    else round(coalesce(saved.saved_minor, 0)::numeric * 100 / goal.target_minor::numeric)::int end as percentage,
  (coalesce(saved.saved_minor, 0) >= goal.target_minor) as is_achieved,
  months.months_remaining,
  case
    when goal.target_date is null or coalesce(saved.saved_minor, 0) >= goal.target_minor then null
    else ceil(
      (goal.target_minor - coalesce(saved.saved_minor, 0))::numeric / months.months_remaining
    )::bigint
  end as recommended_monthly_minor
from public.goals goal
left join lateral (
  select sum(amount_minor)::bigint as saved_minor
  from public.goal_entries entry
  where entry.goal_id = goal.id
) saved on true
left join lateral (
  select sum(backing.backed_minor)::bigint as backed_minor
  from public.goal_account_backing backing
  where backing.goal_id = goal.id
) backed on true
left join lateral (
  select case
    when goal.target_date is null then null
    when goal.target_date <= current_date then 1
    else greatest(1, (
      extract(year from age(goal.target_date, current_date)) * 12
      + extract(month from age(goal.target_date, current_date))
      + case when extract(day from age(goal.target_date, current_date)) > 0 then 1 else 0 end
    )::int)
  end as months_remaining
) months on true;

revoke all on table public.goal_balances from anon, authenticated;
grant select on table public.goal_balances to authenticated;
grant all on table public.goal_balances to service_role;

-- Detail/movements list: every entry with the account's name (even
-- archived), whether it moved real money, and whether it was reversed.
create view public.goal_entry_activity
with (security_invoker = true)
as
select
  entry.id, entry.user_id, entry.goal_id, entry.entry_kind, entry.amount_minor,
  entry.occurred_on, entry.notes, entry.created_at, entry.reverses_entry_id,
  (exists (select 1 from public.goal_entries reversal where reversal.reverses_entry_id = entry.id)) as is_reversed,
  account.id as account_id, account.name as account_name, account.is_active as account_is_active,
  entry.financial_event_id,
  (entry.financial_event_id is not null) as is_real_movement
from public.goal_entries entry
join public.accounts account on account.id = entry.account_id;

revoke all on table public.goal_entry_activity from anon, authenticated;
grant select on table public.goal_entry_activity to authenticated;
grant all on table public.goal_entry_activity to service_role;

create function public.create_goal(
  p_name text, p_currency text, p_target_minor bigint, p_target_date date,
  p_linked_account_id uuid, p_icon text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  normalized_name text := btrim(p_name);
  normalized_icon text := nullif(btrim(coalesce(p_icon, '')), '');
  linked_currency text;
  payload jsonb;
begin
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_target_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if not exists (select 1 from public.currencies where code = p_currency) then
    raise exception 'NEXO_CURRENCY_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_linked_account_id is not null then
    select account.currency into linked_currency from public.accounts account
    where account.id = p_linked_account_id and account.user_id = command_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if linked_currency <> p_currency then raise exception 'NEXO_GOAL_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;

  payload := jsonb_build_object('name', normalized_name, 'currency', p_currency,
    'target_minor', p_target_minor::text, 'target_date', p_target_date,
    'linked_account_id', p_linked_account_id, 'icon', normalized_icon);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_goal', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.goals (id, user_id, name, currency, target_minor, target_date, linked_account_id, icon)
  values (proposed_id, command_user_id, normalized_name, p_currency, p_target_minor, p_target_date, p_linked_account_id, normalized_icon);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_created', 'goal', proposed_id, payload);
  return proposed_id;
end;
$$;

create function public.update_goal(
  p_goal_id uuid, p_name text, p_target_minor bigint, p_target_date date,
  p_linked_account_id uuid, p_icon text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  target_goal public.goals%rowtype;
  normalized_name text := btrim(p_name);
  normalized_icon text := nullif(btrim(coalesce(p_icon, '')), '');
  linked_currency text;
  command_payload jsonb;
begin
  select * into target_goal from public.goals
  where id = p_goal_id and user_id = command_user_id and archived_at is null;
  if not found then raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_target_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_linked_account_id is not null then
    select account.currency into linked_currency from public.accounts account
    where account.id = p_linked_account_id and account.user_id = command_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if linked_currency <> target_goal.currency then raise exception 'NEXO_GOAL_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;

  command_payload := jsonb_build_object('goal_id', p_goal_id, 'name', normalized_name,
    'target_minor', p_target_minor::text, 'target_date', p_target_date,
    'linked_account_id', p_linked_account_id, 'icon', normalized_icon);
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_goal', command_payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_goal_id; end if;

  update public.goals set
    name = normalized_name, target_minor = p_target_minor, target_date = p_target_date,
    linked_account_id = p_linked_account_id, icon = normalized_icon
  where id = p_goal_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_updated', 'goal', p_goal_id, command_payload);
  return p_goal_id;
end;
$$;

create function public.set_goal_status(p_goal_id uuid, p_status text, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('goal_id', p_goal_id, 'status', p_status);
begin
  if p_status not in ('active', 'paused') then
    raise exception 'NEXO_INVALID_GOAL_STATUS' using errcode = '22023'; end if;
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'set_goal_status', command_payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_goal_id; end if;

  update public.goals set status = p_status
  where id = p_goal_id and user_id = command_user_id and archived_at is null;
  if not found and not exists (select 1 from public.goals where id = p_goal_id and user_id = command_user_id) then
    raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_status_changed', 'goal', p_goal_id, command_payload);
  return p_goal_id;
end;
$$;

create function public.archive_goal(p_goal_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('goal_id', p_goal_id);
begin
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'archive_goal', command_payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_goal_id; end if;

  update public.goals set archived_at = now()
  where id = p_goal_id and user_id = command_user_id and archived_at is null;
  if not found and not exists (select 1 from public.goals where id = p_goal_id and user_id = command_user_id) then
    raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_archived', 'goal', p_goal_id, command_payload);
  return p_goal_id;
end;
$$;

create function public.restore_goal(p_goal_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('goal_id', p_goal_id);
begin
  perform 1 from public.goals where id = p_goal_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'restore_goal', command_payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_goal_id; end if;

  update public.goals set archived_at = null where id = p_goal_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_restored', 'goal', p_goal_id, command_payload);
  return p_goal_id;
end;
$$;

-- Contributes to a goal. p_move_real_money = false (default): a virtual
-- reservation -- locks the SAME account-row every balance-mutating RPC
-- locks, checks available = real_balance - currently_reserved, creates
-- ONLY a goal_entries row. p_move_real_money = true: reuses
-- private.execute_goal_transfer to actually move money
-- p_source_account_id -> goals.linked_account_id (which must exist),
-- atomically with the goal_entries row that references the resulting
-- financial_event_id.
create function public.contribute_to_goal(
  p_goal_id uuid, p_amount_minor bigint, p_source_account_id uuid,
  p_move_real_money boolean, p_occurred_on date, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_entry_id uuid := gen_random_uuid();
  resolved_entry_id uuid;
  target_goal public.goals%rowtype;
  source_account public.accounts%rowtype;
  real_balance_minor bigint;
  currently_reserved_minor bigint;
  transfer_event_id uuid;
  backing_account_id uuid;
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;

  -- Lock the goal first (consistent order across every goal RPC), so two
  -- concurrent contributions/withdrawals against the same goal serialize
  -- before either touches an account row.
  select * into target_goal from public.goals
  where id = p_goal_id and user_id = command_user_id and archived_at is null
  for update;
  if not found then raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;

  payload := jsonb_build_object('goal_id', p_goal_id, 'amount_minor', p_amount_minor::text,
    'source_account_id', p_source_account_id, 'move_real_money', p_move_real_money,
    'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_entry_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'contribute_to_goal', payload, proposed_entry_id);
  if resolved_entry_id <> proposed_entry_id then return resolved_entry_id; end if;

  if p_move_real_money then
    if target_goal.linked_account_id is null then
      raise exception 'NEXO_GOAL_HAS_NO_LINKED_ACCOUNT' using errcode = '23514';
    end if;
    perform 1 from public.accounts account
    where account.id = p_source_account_id and account.user_id = command_user_id
      and account.currency = target_goal.currency;
    if not found then raise exception 'NEXO_GOAL_CURRENCY_MISMATCH' using errcode = '23514'; end if;
    transfer_event_id := private.execute_goal_transfer(command_user_id, p_source_account_id,
      target_goal.linked_account_id, p_amount_minor, 'Aportación a meta: ' || target_goal.name, p_occurred_on);
    backing_account_id := target_goal.linked_account_id;
  else
    select * into source_account from public.accounts
    where id = p_source_account_id and user_id = command_user_id
    for update;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if not source_account.is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
    if source_account.currency <> target_goal.currency then
      raise exception 'NEXO_GOAL_CURRENCY_MISMATCH' using errcode = '23514'; end if;

    select coalesce(sum(entry.amount_minor), 0) into real_balance_minor
    from public.account_entries entry where entry.account_id = p_source_account_id;
    select coalesce(sum(entry.amount_minor), 0) into currently_reserved_minor
    from public.goal_entries entry where entry.account_id = p_source_account_id and entry.user_id = command_user_id;

    if p_amount_minor > (real_balance_minor - currently_reserved_minor) then
      raise exception 'NEXO_GOAL_RESERVATION_EXCEEDS_AVAILABLE' using errcode = '23514';
    end if;
    backing_account_id := p_source_account_id;
  end if;

  insert into public.goal_entries (
    id, user_id, goal_id, account_id, financial_event_id, amount_minor, entry_kind, occurred_on, notes
  ) values (
    proposed_entry_id, command_user_id, p_goal_id, backing_account_id, transfer_event_id,
    p_amount_minor, 'contribution', p_occurred_on, normalized_notes
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_contribution_created', 'goal', p_goal_id, payload);
  return proposed_entry_id;
end;
$$;

-- Withdraws from a goal. p_move_real_money = true requires an explicit
-- destination and moves money OUT of the goal's linked_account_id (the
-- only account real money can leave from), full amount, single row.
-- Virtual withdrawal: if p_account_id is given, releases from that
-- account only; otherwise walks the goal's still-alive lots
-- (goal_lot_remaining) oldest first, producing one row per account
-- touched. Never touches account_entries.
-- Returns the id of the FIRST goal_entries row created (same single-id
-- convention every other RPC in this codebase uses, e.g.
-- create_person_payment returns one event id even though it can touch
-- several receivable_due_applications rows). A FIFO virtual withdrawal can
-- still produce more than one row when it needs to release from several
-- accounts; the caller re-reads goal_entry_activity to see all of them --
-- the returned id is only "this operation succeeded, here is its first
-- effect", not an exhaustive manifest.
create function public.withdraw_from_goal(
  p_goal_id uuid, p_amount_minor bigint, p_account_id uuid,
  p_move_real_money boolean, p_destination_account_id uuid,
  p_occurred_on date, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_entry_id uuid := gen_random_uuid();
  resolved_entry_id uuid;
  target_goal public.goals%rowtype;
  saved_minor bigint;
  reserved_in_account bigint;
  transfer_event_id uuid;
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  payload jsonb;
  new_entry_id uuid;
  first_entry_id uuid;
  remaining_minor bigint := p_amount_minor;
  applied_minor bigint;
  lot record;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;

  select * into target_goal from public.goals
  where id = p_goal_id and user_id = command_user_id and archived_at is null
  for update;
  if not found then raise exception 'NEXO_GOAL_NOT_FOUND' using errcode = 'P0002'; end if;

  select coalesce(sum(entry.amount_minor), 0) into saved_minor
  from public.goal_entries entry where entry.goal_id = p_goal_id;
  if p_amount_minor > saved_minor then
    raise exception 'NEXO_GOAL_INSUFFICIENT_SAVED' using errcode = '23514';
  end if;

  payload := jsonb_build_object('goal_id', p_goal_id, 'amount_minor', p_amount_minor::text,
    'account_id', p_account_id, 'move_real_money', p_move_real_money,
    'destination_account_id', p_destination_account_id, 'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_entry_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'withdraw_from_goal', payload, proposed_entry_id);
  if resolved_entry_id <> proposed_entry_id then return resolved_entry_id; end if;

  if p_move_real_money then
    if target_goal.linked_account_id is null then
      raise exception 'NEXO_GOAL_HAS_NO_LINKED_ACCOUNT' using errcode = '23514'; end if;
    select coalesce(sum(entry.amount_minor), 0) into reserved_in_account
    from public.goal_entries entry
    where entry.goal_id = p_goal_id and entry.account_id = target_goal.linked_account_id;
    if p_amount_minor > reserved_in_account then
      raise exception 'NEXO_GOAL_INSUFFICIENT_RESERVATION_IN_ACCOUNT' using errcode = '23514'; end if;
    if p_destination_account_id is null then
      raise exception 'NEXO_GOAL_WITHDRAWAL_DESTINATION_REQUIRED' using errcode = '22023'; end if;

    transfer_event_id := private.execute_goal_transfer(command_user_id, target_goal.linked_account_id,
      p_destination_account_id, p_amount_minor, 'Retiro de meta: ' || target_goal.name, p_occurred_on);

    insert into public.goal_entries (
      id, user_id, goal_id, account_id, financial_event_id, amount_minor, entry_kind, occurred_on, notes
    ) values (
      proposed_entry_id, command_user_id, p_goal_id, target_goal.linked_account_id, transfer_event_id,
      -p_amount_minor, 'withdrawal', p_occurred_on, normalized_notes
    );
    first_entry_id := proposed_entry_id;
  elsif p_account_id is not null then
    select coalesce(sum(entry.amount_minor), 0) into reserved_in_account
    from public.goal_entries entry
    where entry.goal_id = p_goal_id and entry.account_id = p_account_id;
    if p_amount_minor > reserved_in_account then
      raise exception 'NEXO_GOAL_INSUFFICIENT_RESERVATION_IN_ACCOUNT' using errcode = '23514'; end if;

    insert into public.goal_entries (
      id, user_id, goal_id, account_id, financial_event_id, amount_minor, entry_kind, occurred_on, notes
    ) values (
      proposed_entry_id, command_user_id, p_goal_id, p_account_id, null,
      -p_amount_minor, 'withdrawal', p_occurred_on, normalized_notes
    );
    first_entry_id := proposed_entry_id;
  else
    for lot in
      select remaining.account_id, sum(remaining.remaining_minor) as available_minor,
        min(remaining.occurred_on) as oldest_on, min(remaining.created_at) as oldest_at
      from public.goal_lot_remaining remaining
      where remaining.goal_id = p_goal_id and remaining.user_id = command_user_id
      group by remaining.account_id
      having sum(remaining.remaining_minor) > 0
      order by min(remaining.occurred_on), min(remaining.created_at)
    loop
      exit when remaining_minor <= 0;
      applied_minor := least(remaining_minor, lot.available_minor);
      new_entry_id := case when first_entry_id is null then proposed_entry_id else gen_random_uuid() end;
      insert into public.goal_entries (
        id, user_id, goal_id, account_id, financial_event_id, amount_minor, entry_kind, occurred_on, notes
      ) values (
        new_entry_id, command_user_id, p_goal_id, lot.account_id, null,
        -applied_minor, 'withdrawal', p_occurred_on, normalized_notes
      );
      first_entry_id := coalesce(first_entry_id, new_entry_id);
      remaining_minor := remaining_minor - applied_minor;
    end loop;
    if remaining_minor > 0 then
      raise exception 'NEXO_GOAL_INSUFFICIENT_RESERVATION' using errcode = '23514';
    end if;
  end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_withdrawal_created', 'goal', p_goal_id, payload);
  return first_entry_id;
end;
$$;

-- Reverses a single goal_entries row. Append-only: never edits or deletes,
-- inserts one compensating row that always carries the original's
-- account_id forward. A contribution cannot be reversed once any later
-- withdrawal has already consumed part of its lot (goal_lot_remaining
-- would no longer show it fully intact) -- avoids the ambiguity of
-- reversing a partially-used lot. If the original moved real money, the
-- transfer is reversed atomically in the same transaction, locking both
-- accounts in id order like every other two-account operation here.
create function public.reverse_goal_entry(p_entry_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_reversal_id uuid := gen_random_uuid();
  resolved_reversal_id uuid;
  original public.goal_entries%rowtype;
  intact_remaining_minor bigint;
  reversal_transfer_id uuid;
  from_account_id uuid;
  to_account_id uuid;
  payload jsonb := jsonb_build_object('entry_id', p_entry_id);
begin
  select * into original from public.goal_entries where id = p_entry_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_GOAL_ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
  if original.entry_kind = 'reversal' then
    raise exception 'NEXO_GOAL_ENTRY_NOT_REVERSIBLE' using errcode = '23514'; end if;
  if exists (select 1 from public.goal_entries reversal where reversal.reverses_entry_id = p_entry_id) then
    raise exception 'NEXO_GOAL_ENTRY_ALREADY_REVERSED' using errcode = '23505'; end if;

  -- Lock the goal first, same order as contribute/withdraw.
  perform 1 from public.goals where id = original.goal_id and user_id = command_user_id for update;

  if original.entry_kind = 'contribution' then
    select remaining.remaining_minor into intact_remaining_minor
    from public.goal_lot_remaining remaining where remaining.id = original.id;
    if coalesce(intact_remaining_minor, 0) <> original.amount_minor then
      raise exception 'NEXO_GOAL_CONTRIBUTION_ALREADY_CONSUMED' using errcode = '23514';
    end if;
  end if;

  resolved_reversal_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_goal_entry', payload, proposed_reversal_id);
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;

  if original.financial_event_id is not null then
    select entry.account_id into from_account_id from public.account_entries entry
    where entry.financial_event_id = original.financial_event_id and entry.amount_minor < 0;
    select entry.account_id into to_account_id from public.account_entries entry
    where entry.financial_event_id = original.financial_event_id and entry.amount_minor > 0;
    perform 1 from public.accounts account
    where account.id in (from_account_id, to_account_id) and account.user_id = command_user_id
    order by account.id
    for update;

    reversal_transfer_id := gen_random_uuid();
    insert into public.financial_events (id, user_id, kind, amount_minor, description, occurred_on, reverses_event_id)
    values (reversal_transfer_id, command_user_id, 'reversal', abs(original.amount_minor),
      'Reversión de movimiento de meta', current_date, original.financial_event_id);
    insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
    select command_user_id, reversal_transfer_id, entry.account_id, -entry.amount_minor
    from public.account_entries entry where entry.financial_event_id = original.financial_event_id;
  end if;

  insert into public.goal_entries (
    id, user_id, goal_id, account_id, financial_event_id, amount_minor, entry_kind, reverses_entry_id, occurred_on, notes
  ) values (
    proposed_reversal_id, command_user_id, original.goal_id, original.account_id, reversal_transfer_id,
    -original.amount_minor, 'reversal', original.id, current_date, 'Reversión'
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'goal_entry_reversed', 'goal_entry', p_entry_id, payload);
  return proposed_reversal_id;
end;
$$;

revoke all on function public.create_goal(text, text, bigint, date, uuid, text, text) from public, anon;
revoke all on function public.update_goal(uuid, text, bigint, date, uuid, text, text) from public, anon;
revoke all on function public.set_goal_status(uuid, text, text) from public, anon;
revoke all on function public.archive_goal(uuid, text) from public, anon;
revoke all on function public.restore_goal(uuid, text) from public, anon;
revoke all on function public.contribute_to_goal(uuid, bigint, uuid, boolean, date, text, text) from public, anon;
revoke all on function public.withdraw_from_goal(uuid, bigint, uuid, boolean, uuid, date, text, text) from public, anon;
revoke all on function public.reverse_goal_entry(uuid, text) from public, anon;

grant execute on function public.create_goal(text, text, bigint, date, uuid, text, text) to authenticated;
grant execute on function public.update_goal(uuid, text, bigint, date, uuid, text, text) to authenticated;
grant execute on function public.set_goal_status(uuid, text, text) to authenticated;
grant execute on function public.archive_goal(uuid, text) to authenticated;
grant execute on function public.restore_goal(uuid, text) to authenticated;
grant execute on function public.contribute_to_goal(uuid, bigint, uuid, boolean, date, text, text) to authenticated;
grant execute on function public.withdraw_from_goal(uuid, bigint, uuid, boolean, uuid, date, text, text) to authenticated;
grant execute on function public.reverse_goal_entry(uuid, text) to authenticated;
