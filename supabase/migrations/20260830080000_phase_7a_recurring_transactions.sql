-- Nexo Phase 7A: recurring transactions ("Recurrentes"). A recurring rule is
-- an expectation/instruction, never a financial fact: defining one never
-- creates a financial_event, never touches a balance, never pays a card,
-- never marks anything as received or spent. Only CONFIRMING a specific
-- occurrence, through the existing financial engine, creates a real
-- movement -- exactly the same result as if the user had entered it by
-- hand. No parallel ledger exists anywhere in this file.
--
-- planned_cash_flows (6C) narrows to one_time-only from this phase forward.
-- Every recurring commitment lives here instead. get_financial_plan fuses
-- both sources internally so the frontend never deduplicates.

-- ---------------------------------------------------------------------
-- recurring_rules: identity + lifecycle only. Everything that can change
-- "a partir de una fecha" (amount, category, frequency, day(s), source)
-- lives in recurring_rule_versions, never here.
-- ---------------------------------------------------------------------

create table public.recurring_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  direction text not null,
  currency text not null references public.currencies (code),
  start_date date not null,
  end_date date,
  status text not null default 'active',
  archived_at timestamptz,
  subtype text,
  migrated_from_planned_cash_flow_id uuid unique references public.planned_cash_flows (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recurring_rules_name_not_blank check (char_length(btrim(name)) between 1 and 120),
  constraint recurring_rules_direction_valid check (direction in ('income', 'expense')),
  constraint recurring_rules_status_valid check (status in ('active', 'paused')),
  constraint recurring_rules_dates_valid check (end_date is null or end_date >= start_date),
  constraint recurring_rules_subtype_length check (subtype is null or char_length(subtype) <= 40)
);

comment on table public.recurring_rules is
  'A recurring expectation, never a ledger. Defining or editing a rule never creates a financial_event. Only confirm_recurring_occurrence, via the real engine, does.';
comment on column public.recurring_rules.migrated_from_planned_cash_flow_id is
  'Set only for rules created by the one-time monthly->recurring migration (private.migrate_planned_cash_flow_monthly_rows). Auditable origin, never reused for anything else.';

create index recurring_rules_user_status_idx on public.recurring_rules (user_id, status, archived_at);

alter table public.recurring_rules enable row level security;
revoke all on table public.recurring_rules from anon, authenticated;
grant select on table public.recurring_rules to authenticated;
grant all on table public.recurring_rules to service_role;

create policy "Recurring rules are readable by owner"
on public.recurring_rules for select to authenticated
using ((select auth.uid()) = user_id);

create trigger recurring_rules_set_updated_at
before update on public.recurring_rules
for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- recurring_rule_versions: append-only. update_recurring_rule always
-- INSERTs here, never UPDATEs an existing version. A confirmed/omitted
-- occurrence never re-reads this table -- it owns its own frozen
-- snapshot -- so editing here can never rewrite history.
-- ---------------------------------------------------------------------

create table public.recurring_rule_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null references public.recurring_rules (id) on delete restrict,
  effective_from_date date not null,
  amount_minor bigint not null,
  category_id text references public.categories (id),
  frequency text not null,
  day_of_month smallint,
  day_of_month_secondary smallint,
  account_id uuid references public.accounts (id) on delete restrict,
  card_id uuid references public.credit_cards (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint recurring_rule_versions_amount_positive check (amount_minor > 0),
  constraint recurring_rule_versions_frequency_valid check (
    frequency in ('weekly', 'biweekly', 'semimonthly', 'monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual')
  ),
  constraint recurring_rule_versions_day_of_month_valid check (day_of_month is null or day_of_month between 1 and 31),
  constraint recurring_rule_versions_day_of_month_secondary_valid check (day_of_month_secondary is null or day_of_month_secondary between 1 and 31),
  constraint recurring_rule_versions_day_of_month_required check (
    (frequency in ('weekly', 'biweekly') and day_of_month is null and day_of_month_secondary is null)
    or (frequency = 'semimonthly' and day_of_month is not null and day_of_month_secondary is not null)
    or (frequency in ('monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual') and day_of_month is not null and day_of_month_secondary is null)
  ),
  constraint recurring_rule_versions_source_valid check (not (account_id is not null and card_id is not null)),
  constraint recurring_rule_versions_unique_effective unique (rule_id, effective_from_date)
);

comment on column public.recurring_rule_versions.day_of_month_secondary is
  'semimonthly only. A value of 31 is a deliberate reuse of card_effective_statement_date''s clamp: it always resolves to that month''s true last day, so 31 is how "last day of month" is expressed without a separate sentinel.';

create index recurring_rule_versions_rule_effective_idx
  on public.recurring_rule_versions (rule_id, effective_from_date desc);

alter table public.recurring_rule_versions enable row level security;
revoke all on table public.recurring_rule_versions from anon, authenticated;
grant select on table public.recurring_rule_versions to authenticated;
grant all on table public.recurring_rule_versions to service_role;

create policy "Recurring rule versions are readable by owner"
on public.recurring_rule_versions for select to authenticated
using ((select auth.uid()) = user_id);

create trigger recurring_rule_versions_are_immutable
before update or delete on public.recurring_rule_versions
for each row execute function private.reject_financial_mutation();

-- ---------------------------------------------------------------------
-- recurring_rule_pauses: append-only. A pause always starts at
-- current_date (never retroactive -- pause_recurring_rule takes no date
-- parameter), so an occurrence that was already due before the pause
-- began can never be swallowed by it.
-- ---------------------------------------------------------------------

create table public.recurring_rule_pauses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null references public.recurring_rules (id) on delete restrict,
  paused_at date not null,
  resumed_at date,
  created_at timestamptz not null default now(),
  constraint recurring_rule_pauses_dates_valid check (resumed_at is null or resumed_at >= paused_at)
);

create unique index recurring_rule_pauses_open_unique
  on public.recurring_rule_pauses (rule_id) where resumed_at is null;
create index recurring_rule_pauses_rule_idx on public.recurring_rule_pauses (rule_id, paused_at);

alter table public.recurring_rule_pauses enable row level security;
revoke all on table public.recurring_rule_pauses from anon, authenticated;
grant select on table public.recurring_rule_pauses to authenticated;
grant all on table public.recurring_rule_pauses to service_role;

create policy "Recurring rule pauses are readable by owner"
on public.recurring_rule_pauses for select to authenticated
using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- recurring_occurrences: exists ONLY once a calendar slot is confirmed or
-- omitted. Everything else (next, pending, overdue) is derived, never
-- stored. expected_amount_minor/category_id are snapshotted the moment
-- this row is first created -- never re-read from the rule afterward.
-- ---------------------------------------------------------------------

create table public.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null references public.recurring_rules (id) on delete restrict,
  expected_date date not null,
  status text not null,
  expected_amount_minor bigint not null,
  category_id text references public.categories (id),
  notes text,
  created_at timestamptz not null default now(),
  constraint recurring_occurrences_status_valid check (status in ('confirmed', 'omitted')),
  constraint recurring_occurrences_amount_positive check (expected_amount_minor > 0),
  constraint recurring_occurrences_notes_length check (notes is null or char_length(notes) <= 2000),
  constraint recurring_occurrences_unique_slot unique (rule_id, expected_date)
);

create index recurring_occurrences_rule_date_idx on public.recurring_occurrences (rule_id, expected_date desc);
create index recurring_occurrences_user_status_idx on public.recurring_occurrences (user_id, status);

alter table public.recurring_occurrences enable row level security;
revoke all on table public.recurring_occurrences from anon, authenticated;
grant select on table public.recurring_occurrences to authenticated;
grant all on table public.recurring_occurrences to service_role;

create policy "Recurring occurrences are readable by owner"
on public.recurring_occurrences for select to authenticated
using ((select auth.uid()) = user_id);

create trigger recurring_occurrences_are_immutable
before update or delete on public.recurring_occurrences
for each row execute function private.reject_financial_mutation();

-- ---------------------------------------------------------------------
-- recurring_occurrence_events: append-only sub-ledger of every real
-- financial_event ever tied to one occurrence. A reversal never rewrites
-- this table -- it only makes an existing row's event "inactive" (derived,
-- via recurring_occurrence_current_event below), and a replacement is a
-- brand new row, never an overwrite.
-- ---------------------------------------------------------------------

create table public.recurring_occurrence_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  occurrence_id uuid not null references public.recurring_occurrences (id) on delete restrict,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  actual_amount_minor bigint not null,
  actual_date date not null,
  account_id uuid references public.accounts (id) on delete restrict,
  card_id uuid references public.credit_cards (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint recurring_occurrence_events_amount_positive check (actual_amount_minor > 0),
  constraint recurring_occurrence_events_source_valid check (
    (account_id is not null and card_id is null) or (account_id is null and card_id is not null)
  ),
  constraint recurring_occurrence_events_event_unique unique (financial_event_id)
);

create index recurring_occurrence_events_occurrence_idx
  on public.recurring_occurrence_events (occurrence_id, created_at desc);

alter table public.recurring_occurrence_events enable row level security;
revoke all on table public.recurring_occurrence_events from anon, authenticated;
grant select on table public.recurring_occurrence_events to authenticated;
grant all on table public.recurring_occurrence_events to service_role;

create policy "Recurring occurrence events are readable by owner"
on public.recurring_occurrence_events for select to authenticated
using ((select auth.uid()) = user_id);

create trigger recurring_occurrence_events_are_immutable
before update or delete on public.recurring_occurrence_events
for each row execute function private.reject_financial_mutation();

-- The only economically ACTIVE event per occurrence: the most recent one
-- whose financial_event has not been reversed. Never more than one row
-- per occurrence_id by construction (confirm_recurring_occurrence only
-- ever inserts a new event when the previous one is already reversed).
create view public.recurring_occurrence_current_event
with (security_invoker = true)
as
select distinct on (e.occurrence_id)
  e.occurrence_id, e.id as event_row_id, e.financial_event_id,
  e.actual_amount_minor, e.actual_date, e.account_id, e.card_id, e.created_at
from public.recurring_occurrence_events e
where not exists (
  select 1 from public.financial_events reversal where reversal.reverses_event_id = e.financial_event_id
)
order by e.occurrence_id, e.created_at desc;

revoke all on table public.recurring_occurrence_current_event from anon, authenticated;
grant select on table public.recurring_occurrence_current_event to authenticated;
grant all on table public.recurring_occurrence_current_event to service_role;

-- Detail/history read contract: every occurrence with its rule name, its
-- currently active event (if any, itself derived, never stored), and
-- whether the linked movement is reversed.
create view public.recurring_occurrence_activity
with (security_invoker = true)
as
select
  occ.id, occ.user_id, occ.rule_id, rule.name as rule_name, rule.currency, rule.direction,
  occ.expected_date, occ.status, occ.expected_amount_minor, occ.category_id, occ.notes, occ.created_at,
  current_event.financial_event_id, current_event.actual_amount_minor, current_event.actual_date,
  current_event.account_id, current_event.card_id,
  (
    exists (select 1 from public.recurring_occurrence_events e where e.occurrence_id = occ.id)
    and current_event.financial_event_id is null
  ) as is_reversed_without_replacement
from public.recurring_occurrences occ
join public.recurring_rules rule on rule.id = occ.rule_id
left join public.recurring_occurrence_current_event current_event on current_event.occurrence_id = occ.id;

revoke all on table public.recurring_occurrence_activity from anon, authenticated;
grant select on table public.recurring_occurrence_activity to authenticated;
grant all on table public.recurring_occurrence_activity to service_role;

-- ---------------------------------------------------------------------
-- Calendar engine: one pure, deterministic implementation for every
-- frequency, version-aware and pause-aware. Reused by get_recurring_
-- occurrences and by get_financial_plan -- never re-derived twice.
--
-- day_of_month clamping reuses card_effective_statement_date exactly
-- (same function tarjetas has used since Phase 3A) -- no new clamp logic.
-- weekly/biweekly are pure day arithmetic anchored at the rule's own
-- start_date forever, regardless of how many versions exist, so their
-- phase never drifts. monthly-family frequencies walk month-by-month from
-- the rule's start_date's month at the given step (1/2/3/6/12), so a
-- bimonthly/quarterly/semiannual rule's phase is likewise locked to its
-- original start_date, never to an arbitrary calendar epoch.
-- ---------------------------------------------------------------------

create function private.recurring_rule_occurrence_dates(
  p_rule_id uuid,
  p_range_start date,
  p_range_end date
)
returns table (occurred_on date, version_id uuid)
language sql
stable
strict
security invoker
set search_path = ''
as $$
  with rule as (
    select * from public.recurring_rules where id = p_rule_id
  ),
  versions as (
    select v.*,
      lead(v.effective_from_date) over (order by v.effective_from_date) as next_effective_from_date
    from public.recurring_rule_versions v
    where v.rule_id = p_rule_id
  ),
  ranges as (
    select
      v.id as version_id, v.frequency, v.day_of_month, v.day_of_month_secondary,
      greatest(v.effective_from_date, rule.start_date, p_range_start) as range_from,
      least(
        coalesce(v.next_effective_from_date, 'infinity'::date),
        coalesce(rule.end_date + 1, 'infinity'::date),
        p_range_end
      ) as range_to
    from versions v cross join rule
  ),
  weekly_candidates as (
    select r.version_id, (rule.start_date + (gs * 7)) as occurred_on
    from ranges r cross join rule
    cross join lateral generate_series(
      greatest(0, ceil((r.range_from - rule.start_date)::numeric / 7))::int,
      floor((r.range_to - 1 - rule.start_date)::numeric / 7)::int
    ) gs
    where r.frequency = 'weekly' and r.range_from < r.range_to
  ),
  biweekly_candidates as (
    select r.version_id, (rule.start_date + (gs * 14)) as occurred_on
    from ranges r cross join rule
    cross join lateral generate_series(
      greatest(0, ceil((r.range_from - rule.start_date)::numeric / 14))::int,
      floor((r.range_to - 1 - rule.start_date)::numeric / 14)::int
    ) gs
    where r.frequency = 'biweekly' and r.range_from < r.range_to
  ),
  monthly_family_months as (
    select r.version_id, r.frequency, r.day_of_month, r.day_of_month_secondary, r.range_from, r.range_to,
      gs as month_start
    from ranges r cross join rule
    cross join lateral generate_series(
      date_trunc('month', rule.start_date)::date,
      date_trunc('month', r.range_to - interval '1 day')::date,
      (
        case r.frequency
          when 'monthly' then 1 when 'semimonthly' then 1
          when 'bimonthly' then 2 when 'quarterly' then 3
          when 'semiannual' then 6 when 'annual' then 12
          else 1
        end || ' months'
      )::interval
    ) gs
    where r.frequency in ('monthly', 'semimonthly', 'bimonthly', 'quarterly', 'semiannual', 'annual')
      and r.range_from < r.range_to
  ),
  monthly_family_candidates as (
    select mfm.version_id,
      public.card_effective_statement_date(
        extract(year from mfm.month_start)::int, extract(month from mfm.month_start)::int, mfm.day_of_month
      ) as occurred_on
    from monthly_family_months mfm
    where mfm.day_of_month is not null

    union all

    select mfm.version_id,
      public.card_effective_statement_date(
        extract(year from mfm.month_start)::int, extract(month from mfm.month_start)::int, mfm.day_of_month_secondary
      ) as occurred_on
    from monthly_family_months mfm
    where mfm.frequency = 'semimonthly' and mfm.day_of_month_secondary is not null
  ),
  all_candidates as (
    select * from weekly_candidates
    union all select * from biweekly_candidates
    union all select * from monthly_family_candidates
  ),
  filtered as (
    select ac.occurred_on, ac.version_id
    from all_candidates ac
    join ranges r on r.version_id = ac.version_id
    where ac.occurred_on >= r.range_from and ac.occurred_on < r.range_to
  ),
  pauses as (
    select paused_at, coalesce(resumed_at, 'infinity'::date) as resumed_at
    from public.recurring_rule_pauses
    where rule_id = p_rule_id
  )
  select f.occurred_on, f.version_id
  from filtered f
  where not exists (
    select 1 from pauses p where f.occurred_on >= p.paused_at and f.occurred_on < p.resumed_at
  )
  order by f.occurred_on;
$$;

revoke all on function private.recurring_rule_occurrence_dates(uuid, date, date) from public, anon, authenticated;
grant execute on function private.recurring_rule_occurrence_dates(uuid, date, date) to service_role;

-- Authenticated-callable wrapper: same engine, ownership-checked, for the
-- "/recurrentes" UI timeline and for confirming/omitting (which must
-- validate a requested expected_date is genuinely a derivable slot).
create function public.get_recurring_occurrences(p_from_date date, p_to_date date)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  result jsonb;
begin
  if p_from_date is null or p_to_date is null or p_to_date <= p_from_date then
    raise exception 'NEXO_INVALID_DATE_RANGE' using errcode = '22023'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_id', rule.id, 'name', rule.name, 'direction', rule.direction, 'currency', rule.currency,
    'occurred_on', derived.occurred_on,
    'amount_minor', version.amount_minor::text, 'category_id', version.category_id,
    'account_id', version.account_id, 'card_id', version.card_id,
    'existing_occurrence_id', occ.id, 'existing_status', occ.status
  ) order by derived.occurred_on, rule.name), '[]'::jsonb)
  into result
  from public.recurring_rules rule
  cross join lateral private.recurring_rule_occurrence_dates(rule.id, p_from_date, p_to_date) derived
  join public.recurring_rule_versions version on version.id = derived.version_id
  left join public.recurring_occurrences occ on occ.rule_id = rule.id and occ.expected_date = derived.occurred_on
  where rule.user_id = command_user_id and rule.archived_at is null;
  -- No filter on rule.status here: a currently-paused rule already derives
  -- nothing for the paused interval via recurring_rule_pauses (the pause
  -- extends to "infinity" while open), but an occurrence that was already
  -- due BEFORE the pause began must still surface as pending. Gating on
  -- status='active' too would hide it -- the pauses table is the single
  -- source of truth for exclusion, not the status flag.

  return result;
end;
$$;

revoke all on function public.get_recurring_occurrences(date, date) from public, anon;
grant execute on function public.get_recurring_occurrences(date, date) to authenticated;

-- Advisory lock key for one (rule_id, expected_date) slot. Uses md5 (128
-- bits) over a namespaced, unambiguously-delimited input, truncated to
-- the first 64 bits and reinterpreted as a signed bigint, then the
-- single-key pg_advisory_xact_lock(bigint) overload -- one well-mixed
-- 64-bit digest of the full identity (namespace + both components),
-- rather than combining two independently-hashed 32-bit values (hashtext
-- on 'recurring_occurrence' as one key and hashtext on the concatenated
-- rule_id/date as the other), which mixes entropy less thoroughly for the
-- same 64 bits of total keyspace. ':' alone would not safely delimit
-- rule_id from expected_date (a truncated/malformed uuid could in theory
-- produce the same concatenation as a different uuid+date pair); using a
-- constant-length separator ('|rid|'/'|date|') around fixed-format,
-- fixed-length values (uuid is always 36 chars, date is always
-- ISO 'YYYY-MM-DD') removes that ambiguity entirely.
create function private.recurring_occurrence_lock_key(p_rule_id uuid, p_expected_date date)
returns bigint
language sql
immutable
strict
security invoker
set search_path = ''
as $$
  select ('x' || substr(md5('nexo.recurring_occurrence|rid|' || p_rule_id::text || '|date|' || p_expected_date::text), 1, 16))::bit(64)::bigint;
$$;

revoke all on function private.recurring_occurrence_lock_key(uuid, date) from public, anon, authenticated;
grant execute on function private.recurring_occurrence_lock_key(uuid, date) to service_role;

-- ---------------------------------------------------------------------
-- Write RPCs.
-- ---------------------------------------------------------------------

create function public.create_recurring_rule(
  p_name text, p_direction text, p_currency text, p_amount_minor bigint, p_category_id text,
  p_frequency text, p_day_of_month integer, p_day_of_month_secondary integer,
  p_account_id uuid, p_card_id uuid, p_start_date date, p_end_date date, p_subtype text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  proposed_version_id uuid := gen_random_uuid();
  resolved_id uuid;
  normalized_name text := btrim(p_name);
  normalized_subtype text := nullif(btrim(coalesce(p_subtype, '')), '');
  source_currency text;
  payload jsonb;
begin
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_direction not in ('income', 'expense') then
    raise exception 'NEXO_INVALID_DIRECTION' using errcode = '22023'; end if;
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if not exists (select 1 from public.currencies where code = p_currency) then
    raise exception 'NEXO_CURRENCY_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_frequency not in ('weekly', 'biweekly', 'semimonthly', 'monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual') then
    raise exception 'NEXO_INVALID_FREQUENCY' using errcode = '22023'; end if;
  if p_frequency in ('weekly', 'biweekly') and (p_day_of_month is not null or p_day_of_month_secondary is not null) then
    raise exception 'NEXO_DAY_OF_MONTH_NOT_APPLICABLE' using errcode = '22023'; end if;
  if p_frequency = 'semimonthly' and (p_day_of_month is null or p_day_of_month_secondary is null) then
    raise exception 'NEXO_DAY_OF_MONTH_REQUIRED' using errcode = '22023'; end if;
  if p_frequency in ('monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual')
    and (p_day_of_month is null or p_day_of_month_secondary is not null) then
    raise exception 'NEXO_DAY_OF_MONTH_REQUIRED' using errcode = '22023'; end if;
  if p_account_id is not null and p_card_id is not null then
    raise exception 'NEXO_RECURRING_SOURCE_AMBIGUOUS' using errcode = '23514'; end if;
  if p_card_id is not null and p_direction = 'income' then
    raise exception 'NEXO_INCOME_CANNOT_USE_CARD' using errcode = '23514'; end if;
  if p_start_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'NEXO_INVALID_DATE_RANGE' using errcode = '22023'; end if;
  if p_category_id is not null and not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'NEXO_CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;

  if p_account_id is not null then
    select currency into source_currency from public.accounts
    where id = p_account_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if source_currency <> p_currency then raise exception 'NEXO_RECURRING_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;
  if p_card_id is not null then
    select currency into source_currency from public.credit_cards
    where id = p_card_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
    if source_currency <> p_currency then raise exception 'NEXO_RECURRING_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;

  payload := jsonb_build_object('name', normalized_name, 'direction', p_direction, 'currency', p_currency,
    'amount_minor', p_amount_minor::text, 'category_id', p_category_id, 'frequency', p_frequency,
    'day_of_month', p_day_of_month, 'day_of_month_secondary', p_day_of_month_secondary,
    'account_id', p_account_id, 'card_id', p_card_id, 'start_date', p_start_date, 'end_date', p_end_date,
    'subtype', normalized_subtype);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_recurring_rule', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.recurring_rules (id, user_id, name, direction, currency, start_date, end_date, subtype)
  values (proposed_id, command_user_id, normalized_name, p_direction, p_currency, p_start_date, p_end_date, normalized_subtype);
  insert into public.recurring_rule_versions (
    id, user_id, rule_id, effective_from_date, amount_minor, category_id, frequency,
    day_of_month, day_of_month_secondary, account_id, card_id
  ) values (
    proposed_version_id, command_user_id, proposed_id, p_start_date, p_amount_minor, p_category_id, p_frequency,
    p_day_of_month, p_day_of_month_secondary, p_account_id, p_card_id
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_created', 'recurring_rule', proposed_id, payload);
  return proposed_id;
end;
$$;

-- "A partir de fecha": never mutates recurring_rule_versions. name/end_date
-- edit in place (cosmetic, no calendar effect). Any change to
-- amount/category/frequency/day(s)/source inserts a NEW version, guarded
-- so it can never erase or duplicate an occurrence already due today.
create function public.update_recurring_rule(
  p_rule_id uuid, p_name text, p_end_date date, p_effective_from_date date,
  p_amount_minor bigint, p_category_id text, p_frequency text,
  p_day_of_month integer, p_day_of_month_secondary integer,
  p_account_id uuid, p_card_id uuid, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  proposed_version_id uuid := gen_random_uuid();
  target_rule public.recurring_rules%rowtype;
  current_version public.recurring_rule_versions%rowtype;
  normalized_name text := btrim(p_name);
  source_currency text;
  version_changed boolean;
  last_protected_date date;
  payload jsonb;
begin
  select * into target_rule from public.recurring_rules
  where id = p_rule_id and user_id = command_user_id and archived_at is null;
  if not found then raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;
  if normalized_name = '' or char_length(normalized_name) > 120 then
    raise exception 'NEXO_INVALID_NAME' using errcode = '22023'; end if;
  if p_end_date is not null and p_end_date < target_rule.start_date then
    raise exception 'NEXO_INVALID_DATE_RANGE' using errcode = '22023'; end if;
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_frequency not in ('weekly', 'biweekly', 'semimonthly', 'monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual') then
    raise exception 'NEXO_INVALID_FREQUENCY' using errcode = '22023'; end if;
  if p_frequency in ('weekly', 'biweekly') and (p_day_of_month is not null or p_day_of_month_secondary is not null) then
    raise exception 'NEXO_DAY_OF_MONTH_NOT_APPLICABLE' using errcode = '22023'; end if;
  if p_frequency = 'semimonthly' and (p_day_of_month is null or p_day_of_month_secondary is null) then
    raise exception 'NEXO_DAY_OF_MONTH_REQUIRED' using errcode = '22023'; end if;
  if p_frequency in ('monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual')
    and (p_day_of_month is null or p_day_of_month_secondary is not null) then
    raise exception 'NEXO_DAY_OF_MONTH_REQUIRED' using errcode = '22023'; end if;
  if p_account_id is not null and p_card_id is not null then
    raise exception 'NEXO_RECURRING_SOURCE_AMBIGUOUS' using errcode = '23514'; end if;
  if p_card_id is not null and target_rule.direction = 'income' then
    raise exception 'NEXO_INCOME_CANNOT_USE_CARD' using errcode = '23514'; end if;
  if p_category_id is not null and not exists (select 1 from public.categories where id = p_category_id) then
    raise exception 'NEXO_CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_account_id is not null then
    select currency into source_currency from public.accounts where id = p_account_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if source_currency <> target_rule.currency then raise exception 'NEXO_RECURRING_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;
  if p_card_id is not null then
    select currency into source_currency from public.credit_cards where id = p_card_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
    if source_currency <> target_rule.currency then raise exception 'NEXO_RECURRING_CURRENCY_MISMATCH' using errcode = '23514'; end if;
  end if;

  select * into current_version from public.recurring_rule_versions
  where rule_id = p_rule_id order by effective_from_date desc limit 1;

  version_changed := (
    current_version.amount_minor, current_version.category_id, current_version.frequency,
    current_version.day_of_month, current_version.day_of_month_secondary,
    current_version.account_id, current_version.card_id
  ) is distinct from (
    p_amount_minor, p_category_id, p_frequency, p_day_of_month, p_day_of_month_secondary, p_account_id, p_card_id
  );

  if version_changed then
    if p_effective_from_date is null then raise exception 'NEXO_EFFECTIVE_FROM_REQUIRED' using errcode = '22023'; end if;
    if p_effective_from_date < current_date then
      raise exception 'NEXO_EFFECTIVE_FROM_TOO_EARLY' using errcode = '22023'; end if;

    select max(occurred_on) into last_protected_date
    from private.recurring_rule_occurrence_dates(p_rule_id, current_version.effective_from_date, current_date + 1);

    if p_frequency in ('monthly', 'semimonthly', 'bimonthly', 'quarterly', 'semiannual', 'annual') then
      if extract(day from p_effective_from_date) <> 1 then
        raise exception 'NEXO_EFFECTIVE_FROM_MUST_BE_MONTH_START' using errcode = '22023'; end if;
      if last_protected_date is not null
        and date_trunc('month', p_effective_from_date) <= date_trunc('month', last_protected_date) then
        raise exception 'NEXO_EFFECTIVE_FROM_TOO_EARLY' using errcode = '22023';
      end if;
    else
      if last_protected_date is not null and p_effective_from_date <= last_protected_date then
        raise exception 'NEXO_EFFECTIVE_FROM_TOO_EARLY' using errcode = '22023';
      end if;
    end if;
  end if;

  payload := jsonb_build_object('rule_id', p_rule_id, 'name', normalized_name, 'end_date', p_end_date,
    'effective_from_date', p_effective_from_date, 'amount_minor', p_amount_minor::text,
    'category_id', p_category_id, 'frequency', p_frequency, 'day_of_month', p_day_of_month,
    'day_of_month_secondary', p_day_of_month_secondary, 'account_id', p_account_id, 'card_id', p_card_id);
  resolved_command_result_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_recurring_rule', payload, proposed_command_result_id);
  if resolved_command_result_id <> proposed_command_result_id then return p_rule_id; end if;

  update public.recurring_rules set name = normalized_name, end_date = p_end_date
  where id = p_rule_id and user_id = command_user_id;

  if version_changed then
    insert into public.recurring_rule_versions (
      id, user_id, rule_id, effective_from_date, amount_minor, category_id, frequency,
      day_of_month, day_of_month_secondary, account_id, card_id
    ) values (
      proposed_version_id, command_user_id, p_rule_id, p_effective_from_date, p_amount_minor, p_category_id,
      p_frequency, p_day_of_month, p_day_of_month_secondary, p_account_id, p_card_id
    );
  end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_updated', 'recurring_rule', p_rule_id, payload);
  return p_rule_id;
end;
$$;

create function public.pause_recurring_rule(p_rule_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('rule_id', p_rule_id);
begin
  if not exists (
    select 1 from public.recurring_rules where id = p_rule_id and user_id = command_user_id and archived_at is null
  ) then raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'pause_recurring_rule', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_rule_id; end if;

  update public.recurring_rules set status = 'paused'
  where id = p_rule_id and user_id = command_user_id and status = 'active';
  if not exists (select 1 from public.recurring_rule_pauses where rule_id = p_rule_id and resumed_at is null) then
    insert into public.recurring_rule_pauses (user_id, rule_id, paused_at) values (command_user_id, p_rule_id, current_date);
  end if;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_paused', 'recurring_rule', p_rule_id, command_payload);
  return p_rule_id;
end;
$$;

create function public.resume_recurring_rule(p_rule_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('rule_id', p_rule_id);
begin
  if not exists (
    select 1 from public.recurring_rules where id = p_rule_id and user_id = command_user_id and archived_at is null
  ) then raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'resume_recurring_rule', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_rule_id; end if;

  update public.recurring_rules set status = 'active'
  where id = p_rule_id and user_id = command_user_id and status = 'paused';
  update public.recurring_rule_pauses set resumed_at = current_date
  where rule_id = p_rule_id and resumed_at is null;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_resumed', 'recurring_rule', p_rule_id, command_payload);
  return p_rule_id;
end;
$$;

create function public.archive_recurring_rule(p_rule_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('rule_id', p_rule_id);
begin
  if not exists (select 1 from public.recurring_rules where id = p_rule_id and user_id = command_user_id) then
    raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'archive_recurring_rule', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_rule_id; end if;

  update public.recurring_rules set archived_at = now()
  where id = p_rule_id and user_id = command_user_id and archived_at is null;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_archived', 'recurring_rule', p_rule_id, command_payload);
  return p_rule_id;
end;
$$;

create function public.restore_recurring_rule(p_rule_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('rule_id', p_rule_id);
begin
  if not exists (select 1 from public.recurring_rules where id = p_rule_id and user_id = command_user_id) then
    raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;

  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'restore_recurring_rule', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_rule_id; end if;

  update public.recurring_rules set archived_at = null where id = p_rule_id and user_id = command_user_id;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_rule_restored', 'recurring_rule', p_rule_id, command_payload);
  return p_rule_id;
end;
$$;

-- omit: marks one calendar slot as deliberately skipped. No financial
-- engine touched, no rule touched. Serialized by the same advisory lock
-- as confirm, so the two can never race on the same slot.
create function public.omit_recurring_occurrence(p_rule_id uuid, p_expected_date date, p_notes text, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  target_rule public.recurring_rules%rowtype;
  current_version public.recurring_rule_versions%rowtype;
  existing_occurrence public.recurring_occurrences%rowtype;
  has_active_event boolean;
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  payload jsonb;
begin
  perform pg_advisory_xact_lock(private.recurring_occurrence_lock_key(p_rule_id, p_expected_date));

  select * into target_rule from public.recurring_rules
  where id = p_rule_id and user_id = command_user_id and archived_at is null;
  if not found then raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;

  select * into existing_occurrence from public.recurring_occurrences
  where rule_id = p_rule_id and expected_date = p_expected_date;
  if found then
    if existing_occurrence.status = 'omitted' then return existing_occurrence.id; end if;
    select exists (select 1 from public.recurring_occurrence_current_event where occurrence_id = existing_occurrence.id)
    into has_active_event;
    if has_active_event then raise exception 'NEXO_OCCURRENCE_ALREADY_CONFIRMED' using errcode = '23514'; end if;
  end if;

  if not exists (
    select 1 from private.recurring_rule_occurrence_dates(p_rule_id, p_expected_date, p_expected_date + 1)
    where occurred_on = p_expected_date
  ) then raise exception 'NEXO_OCCURRENCE_DATE_INVALID' using errcode = '22023'; end if;

  select * into current_version from public.recurring_rule_versions
  where rule_id = p_rule_id and effective_from_date <= p_expected_date
  order by effective_from_date desc limit 1;

  payload := jsonb_build_object('rule_id', p_rule_id, 'expected_date', p_expected_date, 'notes', normalized_notes);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'omit_recurring_occurrence', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  insert into public.recurring_occurrences (id, user_id, rule_id, expected_date, status, expected_amount_minor, category_id, notes)
  values (proposed_id, command_user_id, p_rule_id, p_expected_date, 'omitted', current_version.amount_minor, current_version.category_id, normalized_notes);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_occurrence_omitted', 'recurring_occurrence', proposed_id, payload);
  return proposed_id;
end;
$$;

-- confirm: THE central RPC. Serializes on (rule_id, expected_date) via an
-- advisory transaction lock BEFORE anything else -- acquired before even
-- resolving idempotency -- so two genuinely concurrent first-confirmations
-- can never both proceed to create money. Everything after that point
-- (the real financial_event, its account_entries/card_entries, the
-- recurring_occurrences row, the recurring_occurrence_events row) happens
-- inside this same function call, i.e. the same transaction: any failure
-- anywhere aborts the whole thing with nothing orphaned, without any
-- explicit rollback code needed.
create function public.confirm_recurring_occurrence(
  p_rule_id uuid, p_expected_date date, p_actual_amount_minor bigint, p_actual_date date,
  p_source_account_id uuid, p_source_card_id uuid, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  target_rule public.recurring_rules%rowtype;
  current_version public.recurring_rule_versions%rowtype;
  existing_occurrence public.recurring_occurrences%rowtype;
  occurrence_existed boolean;
  has_active_event boolean;
  resolved_account_id uuid;
  resolved_card_id uuid;
  source_currency text;
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  new_financial_event_id uuid;
  new_event_row_id uuid := gen_random_uuid();
  resolved_occurrence_id uuid;
  payload jsonb;
begin
  perform pg_advisory_xact_lock(private.recurring_occurrence_lock_key(p_rule_id, p_expected_date));

  select * into target_rule from public.recurring_rules
  where id = p_rule_id and user_id = command_user_id and archived_at is null;
  if not found then raise exception 'NEXO_RECURRING_RULE_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_actual_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_actual_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_source_account_id is not null and p_source_card_id is not null then
    raise exception 'NEXO_RECURRING_SOURCE_AMBIGUOUS' using errcode = '23514'; end if;
  if p_source_card_id is not null and target_rule.direction = 'income' then
    raise exception 'NEXO_INCOME_CANNOT_USE_CARD' using errcode = '23514'; end if;

  select * into existing_occurrence from public.recurring_occurrences
  where rule_id = p_rule_id and expected_date = p_expected_date;
  occurrence_existed := found;

  if occurrence_existed then
    if existing_occurrence.status = 'confirmed' then
      select exists (select 1 from public.recurring_occurrence_current_event where occurrence_id = existing_occurrence.id)
      into has_active_event;
      if has_active_event then raise exception 'NEXO_OCCURRENCE_ALREADY_CONFIRMED' using errcode = '23514'; end if;
    end if;
    -- omitted, or confirmed-but-superseded (its only event was reversed): allowed to proceed.
  else
    if not exists (
      select 1 from private.recurring_rule_occurrence_dates(p_rule_id, p_expected_date, p_expected_date + 1)
      where occurred_on = p_expected_date
    ) then raise exception 'NEXO_OCCURRENCE_DATE_INVALID' using errcode = '22023'; end if;
  end if;

  select * into current_version from public.recurring_rule_versions
  where rule_id = p_rule_id and effective_from_date <= p_expected_date
  order by effective_from_date desc limit 1;

  -- Fuente: explícita de esta confirmación > predeterminada de la versión > rechazar.
  if p_source_account_id is not null or p_source_card_id is not null then
    resolved_account_id := p_source_account_id;
    resolved_card_id := p_source_card_id;
  else
    resolved_account_id := current_version.account_id;
    resolved_card_id := current_version.card_id;
  end if;
  if resolved_account_id is null and resolved_card_id is null then
    raise exception 'NEXO_RECURRING_RULE_HAS_NO_SOURCE' using errcode = '23514'; end if;
  if resolved_account_id is not null and resolved_card_id is not null then
    raise exception 'NEXO_RECURRING_SOURCE_AMBIGUOUS' using errcode = '23514'; end if;

  if resolved_account_id is not null then
    select currency into source_currency from public.accounts where id = resolved_account_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  else
    select currency into source_currency from public.credit_cards where id = resolved_card_id and user_id = command_user_id;
    if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  end if;
  if source_currency <> target_rule.currency then raise exception 'NEXO_RECURRING_CURRENCY_MISMATCH' using errcode = '23514'; end if;

  payload := jsonb_build_object('rule_id', p_rule_id, 'expected_date', p_expected_date,
    'actual_amount_minor', p_actual_amount_minor::text, 'actual_date', p_actual_date,
    'source_account_id', resolved_account_id, 'source_card_id', resolved_card_id, 'notes', normalized_notes);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'confirm_recurring_occurrence', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;

  if resolved_account_id is not null then
    new_financial_event_id := public.create_transaction(
      resolved_account_id, target_rule.direction, p_actual_amount_minor, target_rule.name,
      current_version.category_id, p_actual_date, normalized_notes,
      p_idempotency_key || ':transaction'
    );
  else
    new_financial_event_id := public.create_card_purchase(
      resolved_card_id, p_actual_amount_minor, target_rule.name, current_version.category_id,
      p_actual_date, null, normalized_notes, p_idempotency_key || ':card_purchase'
    );
  end if;

  if occurrence_existed then
    resolved_occurrence_id := existing_occurrence.id;
  else
    resolved_occurrence_id := proposed_id;
    insert into public.recurring_occurrences (id, user_id, rule_id, expected_date, status, expected_amount_minor, category_id, notes)
    values (resolved_occurrence_id, command_user_id, p_rule_id, p_expected_date, 'confirmed', current_version.amount_minor, current_version.category_id, normalized_notes);
  end if;

  insert into public.recurring_occurrence_events (
    id, user_id, occurrence_id, financial_event_id, actual_amount_minor, actual_date, account_id, card_id
  ) values (
    new_event_row_id, command_user_id, resolved_occurrence_id, new_financial_event_id, p_actual_amount_minor, p_actual_date,
    resolved_account_id, resolved_card_id
  );

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'recurring_occurrence_confirmed', 'recurring_occurrence', resolved_occurrence_id, payload);
  return resolved_occurrence_id;
end;
$$;

revoke all on function public.create_recurring_rule(text, text, text, bigint, text, text, integer, integer, uuid, uuid, date, date, text, text) from public, anon;
revoke all on function public.update_recurring_rule(uuid, text, date, date, bigint, text, text, integer, integer, uuid, uuid, text) from public, anon;
revoke all on function public.pause_recurring_rule(uuid, text) from public, anon;
revoke all on function public.resume_recurring_rule(uuid, text) from public, anon;
revoke all on function public.archive_recurring_rule(uuid, text) from public, anon;
revoke all on function public.restore_recurring_rule(uuid, text) from public, anon;
revoke all on function public.confirm_recurring_occurrence(uuid, date, bigint, date, uuid, uuid, text, text) from public, anon;
revoke all on function public.omit_recurring_occurrence(uuid, date, text, text) from public, anon;
grant execute on function public.create_recurring_rule(text, text, text, bigint, text, text, integer, integer, uuid, uuid, date, date, text, text) to authenticated;
grant execute on function public.update_recurring_rule(uuid, text, date, date, bigint, text, text, integer, integer, uuid, uuid, text) to authenticated;
grant execute on function public.pause_recurring_rule(uuid, text) to authenticated;
grant execute on function public.resume_recurring_rule(uuid, text) to authenticated;
grant execute on function public.archive_recurring_rule(uuid, text) to authenticated;
grant execute on function public.restore_recurring_rule(uuid, text) to authenticated;
grant execute on function public.confirm_recurring_occurrence(uuid, date, bigint, date, uuid, uuid, text, text) to authenticated;
grant execute on function public.omit_recurring_occurrence(uuid, date, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Migration from planned_cash_flows monthly rows. Idempotent, auditable,
-- callable more than once safely. The CHECK on planned_cash_flows.recurrence
-- is deliberately NOT tightened at the schema level (doing so would make
-- this exact function untestable against preexisting data in any later
-- test run, since migrations always apply before test files); the
-- 'one_time'-only rule is enforced at the RPC layer below and at
-- get_financial_plan's read layer.
-- ---------------------------------------------------------------------

create function private.migrate_planned_cash_flow_monthly_rows()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data record;
  new_rule_id uuid;
  migrated_count integer := 0;
begin
  for row_data in
    select * from public.planned_cash_flows
    where recurrence = 'monthly' and archived_at is null
      and not exists (
        select 1 from public.recurring_rules rr where rr.migrated_from_planned_cash_flow_id = planned_cash_flows.id
      )
  loop
    new_rule_id := gen_random_uuid();
    insert into public.recurring_rules (
      id, user_id, name, direction, currency, start_date, end_date, migrated_from_planned_cash_flow_id
    ) values (
      new_rule_id, row_data.user_id, row_data.name,
      case when row_data.amount_minor > 0 then 'income' else 'expense' end,
      row_data.currency, row_data.start_date, row_data.end_date, row_data.id
    );
    insert into public.recurring_rule_versions (
      user_id, rule_id, effective_from_date, amount_minor, category_id, frequency, day_of_month
    ) values (
      row_data.user_id, new_rule_id, row_data.start_date, abs(row_data.amount_minor), row_data.category_id,
      'monthly', extract(day from row_data.start_date)::smallint
    );
    update public.planned_cash_flows set archived_at = now() where id = row_data.id;
    migrated_count := migrated_count + 1;
  end loop;
  return migrated_count;
end;
$$;

revoke all on function private.migrate_planned_cash_flow_monthly_rows() from public, anon, authenticated;
grant execute on function private.migrate_planned_cash_flow_monthly_rows() to service_role;

select private.migrate_planned_cash_flow_monthly_rows();

-- ---------------------------------------------------------------------
-- planned_cash_flows accepts only one_time from this phase forward,
-- enforced at the RPC layer (see reasoning above for why the CHECK stays
-- untouched).
-- ---------------------------------------------------------------------

create or replace function public.create_planned_cash_flow(
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
  if p_recurrence <> 'one_time' then
    raise exception 'NEXO_PLANNED_CASH_FLOW_RECURRENCE_DEPRECATED' using errcode = '22023',
      hint = 'Usa create_recurring_rule para compromisos recurrentes desde Fase 7A.'; end if;
  if p_start_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_end_date is not null then
    raise exception 'NEXO_ONE_TIME_CANNOT_HAVE_END_DATE' using errcode = '22023'; end if;
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

create or replace function public.update_planned_cash_flow(
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
  if p_recurrence <> 'one_time' then
    raise exception 'NEXO_PLANNED_CASH_FLOW_RECURRENCE_DEPRECATED' using errcode = '22023',
      hint = 'Usa create_recurring_rule para compromisos recurrentes desde Fase 7A.'; end if;
  if p_start_date is null then raise exception 'NEXO_INVALID_DATE' using errcode = '22023'; end if;
  if p_end_date is not null then
    raise exception 'NEXO_ONE_TIME_CANNOT_HAVE_END_DATE' using errcode = '22023'; end if;
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

-- ---------------------------------------------------------------------
-- get_financial_plan: fuse recurring-derived (not-yet-materialized)
-- occurrences into the exact same flow_occurrences pipeline that already
-- feeds income/outflow totals, budget categorization, and the visible
-- planned_flows array. A single "not exists" against recurring_occurrences
-- is the entire anti-double-count switch: once a slot is confirmed or
-- omitted, it stops being derived here and, if confirmed, its real effect
-- flows through the card/account/budget engines exactly like AH/AI/AJ/AK
-- already prove for 6C -- zero special-casing needed beyond this filter.
-- ---------------------------------------------------------------------

create or replace function public.get_financial_plan(
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

  flows as (
    select * from public.planned_cash_flows
    where user_id = command_user_id and currency = p_currency and archived_at is null and recurrence = 'one_time'
  ),
  one_time_occurrences as (
    select f.id as flow_id, f.name, f.category_id, f.amount_minor, f.start_date as occurred_on
    from flows f
    where f.start_date >= p_as_of_date and f.start_date < horizon_end_exclusive
  ),
  recurring_candidates as (
    select rule.id as rule_id, rule.name, rule.direction, cand.occurred_on, version.amount_minor, version.category_id
    from public.recurring_rules rule
    cross join lateral private.recurring_rule_occurrence_dates(rule.id, p_as_of_date, horizon_end_exclusive) cand
    join public.recurring_rule_versions version on version.id = cand.version_id
    where rule.user_id = command_user_id and rule.currency = p_currency
      and rule.archived_at is null
      and not exists (
        select 1 from public.recurring_occurrences occ
        where occ.rule_id = rule.id and occ.expected_date = cand.occurred_on
      )
  ),
  recurring_occurrences_signed as (
    select rule_id as flow_id, name, category_id,
      (case when direction = 'income' then amount_minor else -amount_minor end)::bigint as amount_minor,
      occurred_on
    from recurring_candidates
  ),
  flow_occurrences as (
    select flow_id, name, category_id, amount_minor, occurred_on from one_time_occurrences
    union all
    select flow_id, name, category_id, amount_minor, occurred_on from recurring_occurrences_signed
  ),
  flow_month_totals as (
    select date_trunc('month', occurred_on)::date as month_start,
      coalesce(sum(amount_minor) filter (where amount_minor > 0), 0)::bigint as income_minor,
      coalesce(sum(-amount_minor) filter (where amount_minor < 0), 0)::bigint as outflow_minor
    from flow_occurrences
    group by 1
  ),

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
