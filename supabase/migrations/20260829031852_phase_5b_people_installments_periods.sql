-- Nexo Phase 5B: person obligations by collection period, shared MSI and credit balances.
-- Receivables remain the total nominal debt source of truth. Due items only schedule
-- when that existing principal is collectible and never create principal again.

alter table public.financial_events
  drop constraint financial_events_kind_valid,
  drop constraint financial_events_amount_valid,
  drop constraint financial_events_personal_amount_valid;

alter table public.financial_events
  add constraint financial_events_kind_valid check (
    kind in ('opening', 'income', 'expense', 'adjustment', 'transfer', 'reversal',
      'card_charge', 'card_payment', 'card_refund', 'card_adjustment', 'person_payment',
      'person_credit_application')
  ),
  add constraint financial_events_amount_valid check (
    (kind in ('income', 'expense', 'transfer', 'reversal', 'card_charge', 'card_payment',
      'card_refund', 'person_payment', 'person_credit_application') and amount_minor > 0)
    or (kind in ('opening', 'adjustment', 'card_adjustment') and amount_minor <> 0)
  ),
  add constraint financial_events_personal_amount_valid check (
    personal_amount_minor >= 0
    and (
      (kind in ('expense', 'card_charge') and personal_amount_minor <= amount_minor)
      or (kind = 'card_refund' and personal_amount_minor = amount_minor)
      or (kind not in ('expense', 'card_charge', 'card_refund') and personal_amount_minor = 0)
    )
  );

create table public.receivable_due_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  receivable_id uuid not null references public.receivables (id) on delete restrict,
  installment_id uuid references public.installments (id) on delete restrict,
  card_id uuid references public.credit_cards (id) on delete restrict,
  statement_date date,
  payment_due_date date not null,
  amount_minor bigint not null check (amount_minor > 0),
  sequence_number integer not null default 1 check (sequence_number > 0),
  created_at timestamptz not null default now(),
  constraint receivable_due_item_source_unique unique nulls not distinct (receivable_id, installment_id),
  constraint receivable_due_item_card_dates check (
    (card_id is null and statement_date is null)
    or (card_id is not null and statement_date is not null)
  )
);

create index receivable_due_items_contact_period_idx
  on public.receivable_due_items (user_id, payment_due_date, statement_date, receivable_id);
create index receivable_due_items_installment_idx on public.receivable_due_items (installment_id)
  where installment_id is not null;

create table public.receivable_due_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  due_item_id uuid not null references public.receivable_due_items (id) on delete restrict,
  receivable_id uuid not null references public.receivables (id) on delete restrict,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  amount_minor bigint not null check (amount_minor <> 0),
  application_kind text not null check (application_kind in ('payment', 'credit', 'reversal')),
  reverses_application_id uuid references public.receivable_due_applications (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint due_application_direction_valid check (
    (application_kind in ('payment', 'credit') and amount_minor > 0 and reverses_application_id is null)
    or (application_kind = 'reversal' and amount_minor < 0 and reverses_application_id is not null)
  )
);

create index due_applications_item_idx on public.receivable_due_applications (due_item_id, created_at);
create index due_applications_event_idx on public.receivable_due_applications (financial_event_id);
create unique index due_applications_reversal_unique on public.receivable_due_applications (reverses_application_id)
  where reverses_application_id is not null;

create table public.person_credit_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  contact_id uuid not null references public.contacts (id) on delete restrict,
  currency text not null references public.currencies (code),
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  amount_minor bigint not null check (amount_minor <> 0),
  entry_kind text not null check (entry_kind in ('credit_created', 'credit_applied', 'reversal')),
  reverses_entry_id uuid references public.person_credit_entries (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint person_credit_direction_valid check (
    (entry_kind = 'credit_created' and amount_minor > 0 and reverses_entry_id is null)
    or (entry_kind = 'credit_applied' and amount_minor < 0 and reverses_entry_id is null)
    or (entry_kind = 'reversal' and reverses_entry_id is not null)
  )
);

create index person_credit_contact_currency_idx
  on public.person_credit_entries (user_id, contact_id, currency, created_at);
create index person_credit_event_idx on public.person_credit_entries (financial_event_id);
create unique index person_credit_reversal_unique on public.person_credit_entries (reverses_entry_id)
  where reverses_entry_id is not null;

alter table public.receivable_due_items enable row level security;
alter table public.receivable_due_applications enable row level security;
alter table public.person_credit_entries enable row level security;
revoke all on table public.receivable_due_items, public.receivable_due_applications,
  public.person_credit_entries from anon, authenticated;
grant select on table public.receivable_due_items, public.receivable_due_applications,
  public.person_credit_entries to authenticated;
grant all on table public.receivable_due_items, public.receivable_due_applications,
  public.person_credit_entries to service_role;
create policy "Users can read their own receivable due items" on public.receivable_due_items
for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users can read their own due applications" on public.receivable_due_applications
for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users can read their own person credits" on public.person_credit_entries
for select to authenticated using ((select auth.uid()) = user_id);
create trigger receivable_due_items_are_immutable before update or delete on public.receivable_due_items
for each row execute function private.reject_financial_mutation();
create trigger due_applications_are_immutable before update or delete on public.receivable_due_applications
for each row execute function private.reject_financial_mutation();
create trigger person_credit_entries_are_immutable before update or delete on public.person_credit_entries
for each row execute function private.reject_financial_mutation();

-- Existing simple receivables receive one due item. Card purchases inherit the
-- official statement assignment; account purchases are due on their transaction date.
insert into public.receivable_due_items (
  user_id, receivable_id, card_id, statement_date, payment_due_date, amount_minor
)
select receivable.user_id, receivable.id, detail.card_id, detail.statement_date,
  case when detail.card_id is null then receivable.occurred_on
    else public.card_due_date(detail.statement_date, card.payment_days_after_statement) end,
  receivable.original_amount_minor
from public.receivables receivable
left join public.card_transaction_details detail on detail.financial_event_id = receivable.source_event_id
left join public.credit_cards card on card.id = detail.card_id
where not exists (select 1 from public.receivable_due_items item where item.receivable_id = receivable.id);

create function private.create_simple_receivable_due_items(command_user_id uuid, purchase_event_id uuid)
returns void language plpgsql set search_path = '' as $$
begin
  insert into public.receivable_due_items (
    user_id, receivable_id, card_id, statement_date, payment_due_date, amount_minor
  )
  select receivable.user_id, receivable.id, detail.card_id, detail.statement_date,
    case when detail.card_id is null then receivable.occurred_on
      else public.card_due_date(detail.statement_date, card.payment_days_after_statement) end,
    receivable.original_amount_minor
  from public.receivables receivable
  left join public.card_transaction_details detail on detail.financial_event_id = receivable.source_event_id
  left join public.credit_cards card on card.id = detail.card_id
  where receivable.user_id = command_user_id and receivable.source_event_id = purchase_event_id
    and not exists (select 1 from public.receivable_due_items item where item.receivable_id = receivable.id);
end;
$$;

create function private.create_installment_receivable_due_items(
  command_user_id uuid, target_plan_id uuid, purchase_event_id uuid
)
returns void language plpgsql set search_path = '' as $$
declare
  target_receivable record;
  installment_row record;
  allocated_before bigint;
  allocation_amount bigint;
  eligible_total bigint;
begin
  select coalesce(sum(principal_minor), 0) into eligible_total
  from public.installments
  where plan_id = target_plan_id and status = 'scheduled';
  if eligible_total <= 0 then return; end if;

  for target_receivable in
    select receivable.* from public.receivables receivable
    where receivable.user_id = command_user_id and receivable.source_event_id = purchase_event_id
    order by receivable.id
  loop
    allocated_before := 0;
    for installment_row in
      select installment.*, card.payment_days_after_statement,
        sum(installment.principal_minor) over (order by installment.installment_number) cumulative_principal,
        row_number() over (order by installment.installment_number desc) reverse_row
      from public.installments installment
      join public.installment_plans plan on plan.id = installment.plan_id
      join public.credit_cards card on card.id = plan.card_id
      where installment.plan_id = target_plan_id and installment.status = 'scheduled'
      order by installment.installment_number
    loop
      allocation_amount := case when installment_row.reverse_row = 1
        then target_receivable.original_amount_minor - allocated_before
        else (target_receivable.original_amount_minor * installment_row.cumulative_principal / eligible_total) - allocated_before end;
      if allocation_amount > 0 then
        insert into public.receivable_due_items (
          user_id, receivable_id, installment_id, card_id, statement_date,
          payment_due_date, amount_minor, sequence_number
        ) values (
          command_user_id, target_receivable.id, installment_row.id,
          (select card_id from public.installment_plans where id = target_plan_id),
          installment_row.due_statement_date,
          public.card_due_date(installment_row.due_statement_date, installment_row.payment_days_after_statement),
          allocation_amount, installment_row.installment_number
        );
        allocated_before := allocated_before + allocation_amount;
      end if;
    end loop;
    if allocated_before <> target_receivable.original_amount_minor then
      raise exception 'NEXO_INSTALLMENT_ALLOCATION_MISMATCH' using errcode = '23514';
    end if;
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (command_user_id, 'person_installment_obligation_created', 'receivable', target_receivable.id,
      jsonb_build_object('plan_id', target_plan_id, 'amount_minor', target_receivable.original_amount_minor::text));
  end loop;
end;
$$;

create view public.receivable_due_item_balances with (security_invoker = true) as
select item.id, item.user_id, item.receivable_id, receivable.contact_id, item.installment_id,
  item.card_id, item.statement_date, item.payment_due_date, item.amount_minor,
  coalesce(sum(application.amount_minor), 0)::bigint as paid_minor,
  (item.amount_minor - coalesce(sum(application.amount_minor), 0))::bigint as outstanding_minor,
  item.sequence_number, event.description, receivable.currency, item.created_at
from public.receivable_due_items item
join public.receivables receivable on receivable.id = item.receivable_id
join public.financial_events event on event.id = receivable.source_event_id
left join public.receivable_due_applications application on application.due_item_id = item.id
where not exists (
  select 1 from public.financial_events reversal
  where reversal.reverses_event_id = receivable.source_event_id
)
group by item.id, receivable.contact_id, event.description, receivable.currency;

create view public.person_credit_balances with (security_invoker = true) as
select contact.id as contact_id, contact.user_id, currency.code as currency,
  coalesce(sum(entry.amount_minor), 0)::bigint as credit_balance_minor
from public.contacts contact
cross join public.currencies currency
left join public.person_credit_entries entry on entry.contact_id = contact.id and entry.currency = currency.code
group by contact.id, currency.code
having coalesce(sum(entry.amount_minor), 0) <> 0;

revoke all on table public.receivable_due_item_balances, public.person_credit_balances from anon, authenticated;
grant select on table public.receivable_due_item_balances, public.person_credit_balances to authenticated;
grant all on table public.receivable_due_item_balances, public.person_credit_balances to service_role;

create function private.schedule_simple_purchase_receivable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.installment_plans where purchase_event_id = new.financial_event_id) then
    perform private.create_simple_receivable_due_items(new.user_id, new.financial_event_id);
  end if;
  return new;
end;
$$;
create trigger purchase_allocations_create_due_items
after insert on public.purchase_allocations
for each row execute function private.schedule_simple_purchase_receivable();

create function public.create_shared_installment_purchase(
  p_card_id uuid, p_amount_minor bigint, p_personal_amount_minor bigint, p_allocations jsonb,
  p_installment_count integer, p_installment_amount_minor bigint, p_description text,
  p_category_id text, p_occurred_on date, p_payment_method text, p_notes text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_plan_id uuid := gen_random_uuid();
  proposed_event_id uuid := gen_random_uuid(); resolved_plan_id uuid;
  target_card public.credit_cards%rowtype; baseline_date date; first_statement_date date;
  monthly_amount bigint; final_amount bigint; installment_number integer;
  installment_statement_date date; month_cursor date;
  normalized_description text := nullif(btrim(p_description), '');
  normalized_notes text := nullif(btrim(p_notes), ''); payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_installment_count < 2 or p_installment_count > 60 then
    raise exception 'NEXO_INVALID_INSTALLMENT_COUNT' using errcode = '22023'; end if;
  if normalized_description is null or char_length(normalized_description) > 160 then
    raise exception 'NEXO_INVALID_DESCRIPTION' using errcode = '22023'; end if;
  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'NEXO_NOTES_TOO_LONG' using errcode = '22023'; end if;
  if p_payment_method is not null and p_payment_method not in
    ('physical_card', 'apple_pay', 'google_pay', 'online', 'other') then
    raise exception 'NEXO_INVALID_PAYMENT_METHOD' using errcode = '22023'; end if;
  perform private.validate_purchase_split(command_user_id, p_amount_minor, p_personal_amount_minor, p_allocations);

  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  first_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (select 1 from public.card_statements where card_id = p_card_id and statement_date = first_statement_date)
  then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  monthly_amount := coalesce(p_installment_amount_minor, p_amount_minor / p_installment_count);
  final_amount := p_amount_minor - monthly_amount * (p_installment_count - 1);
  if monthly_amount <= 0 or final_amount <= 0 then
    raise exception 'NEXO_INVALID_INSTALLMENT_AMOUNT' using errcode = '22023'; end if;
  payload := jsonb_build_object('card_id', p_card_id, 'amount_minor', p_amount_minor::text,
    'personal_amount_minor', p_personal_amount_minor::text, 'allocations', p_allocations,
    'installment_count', p_installment_count, 'installment_amount_minor', monthly_amount::text,
    'description', normalized_description, 'category_id', p_category_id, 'occurred_on', p_occurred_on,
    'payment_method', p_payment_method, 'notes', normalized_notes);
  resolved_plan_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_shared_installment_purchase', payload, proposed_plan_id);
  if resolved_plan_id <> proposed_plan_id then return resolved_plan_id; end if;

  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'card_charge', p_amount_minor, p_personal_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes);
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, p_amount_minor, 'impacting');
  insert into public.card_transaction_details (financial_event_id, user_id, card_id, payment_method, statement_date)
  values (proposed_event_id, command_user_id, p_card_id, p_payment_method, first_statement_date);
  insert into public.installment_plans (id, user_id, card_id, purchase_event_id, original_amount_minor,
    installment_count, installment_amount_minor, currency, start_date, first_statement_date, status)
  values (proposed_plan_id, command_user_id, p_card_id, proposed_event_id, p_amount_minor,
    p_installment_count, monthly_amount, target_card.currency, p_occurred_on, first_statement_date, 'active');
  for installment_number in 1..p_installment_count loop
    month_cursor := first_statement_date + make_interval(months => installment_number - 1);
    installment_statement_date := public.card_effective_statement_date(
      extract(year from month_cursor)::integer, extract(month from month_cursor)::integer,
      target_card.statement_day);
    insert into public.installments (user_id, plan_id, installment_number, due_statement_date,
      principal_minor, status)
    values (command_user_id, proposed_plan_id, installment_number, installment_statement_date,
      case when installment_number = p_installment_count then final_amount else monthly_amount end,
      'scheduled');
  end loop;
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_card.currency, p_allocations);
  perform private.create_installment_receivable_due_items(command_user_id, proposed_plan_id, proposed_event_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata) values
    (command_user_id, 'installment_purchase_created', 'financial_event', proposed_event_id,
      payload || jsonb_build_object('plan_id', proposed_plan_id)),
    (command_user_id, 'installment_plan_created', 'installment_plan', proposed_plan_id,
      jsonb_build_object('purchase_event_id', proposed_event_id, 'additional_card_impact_minor', '0'));
  return proposed_plan_id;
end;
$$;

revoke all on function public.create_shared_installment_purchase(
  uuid, bigint, bigint, jsonb, integer, bigint, text, text, date, text, text, text
) from public, anon;
grant execute on function public.create_shared_installment_purchase(
  uuid, bigint, bigint, jsonb, integer, bigint, text, text, date, text, text, text
) to authenticated;

create function public.import_shared_historical_installment_plan(
  p_card_id uuid, p_description text, p_original_amount_minor bigint,
  p_remaining_personal_amount_minor bigint, p_allocations jsonb,
  p_installment_count integer, p_installment_amount_minor bigint,
  p_original_purchase_date date, p_current_installment_number integer,
  p_paid_before_count integer, p_reported_paid_amount_minor bigint,
  p_principal_paid_minor bigint, p_next_statement_date date, p_category_id text,
  p_notes text, p_included_in_opening_balance boolean, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_plan_id uuid := gen_random_uuid();
  proposed_event_id uuid := gen_random_uuid(); resolved_plan_id uuid;
  target_card public.credit_cards%rowtype; target_baseline public.card_baselines%rowtype;
  normalized_description text := nullif(btrim(p_description), '');
  normalized_notes text := nullif(btrim(p_notes), '');
  remaining_principal bigint; additional_impact bigint; reported_final bigint;
  paid_principal_regular bigint := 0; remaining_principal_regular bigint;
  principal_value bigint; reported_value bigint; installment_number integer;
  installment_statement_date date; month_cursor date; payload jsonb;
begin
  if p_original_amount_minor <= 0 or p_installment_amount_minor <= 0 then
    raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  if p_installment_count < 2 or p_installment_count > 60 then
    raise exception 'NEXO_INVALID_INSTALLMENT_COUNT' using errcode = '22023'; end if;
  if p_current_installment_number < 1 or p_current_installment_number > p_installment_count
    or p_paid_before_count <> p_current_installment_number - 1 then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_PROGRESS' using errcode = '22023'; end if;
  if p_reported_paid_amount_minor < 0 or p_principal_paid_minor < 0
    or p_principal_paid_minor >= p_original_amount_minor then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023'; end if;
  if (p_paid_before_count = 0 and p_principal_paid_minor <> 0)
    or (p_paid_before_count > 0 and p_principal_paid_minor < p_paid_before_count) then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023'; end if;
  if normalized_description is null or char_length(normalized_description) > 160 then
    raise exception 'NEXO_INVALID_DESCRIPTION' using errcode = '22023'; end if;
  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'NEXO_NOTES_TOO_LONG' using errcode = '22023'; end if;
  if p_original_purchase_date > current_date then
    raise exception 'NEXO_HISTORICAL_PURCHASE_IN_FUTURE' using errcode = '22023'; end if;

  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select * into strict target_baseline from public.card_baselines
  where card_id = p_card_id and user_id = command_user_id;
  if p_included_in_opening_balance and p_original_purchase_date > target_baseline.baseline_date then
    raise exception 'NEXO_HISTORICAL_MSI_NOT_IN_OPENING_PERIOD' using errcode = '22023'; end if;
  if public.card_effective_statement_date(extract(year from p_next_statement_date)::integer,
      extract(month from p_next_statement_date)::integer, target_card.statement_day) <> p_next_statement_date
    or p_next_statement_date < public.card_statement_for_date(target_baseline.baseline_date, target_card.statement_day) then
    raise exception 'NEXO_INVALID_STATEMENT_DATE' using errcode = '22023'; end if;

  remaining_principal := p_original_amount_minor - p_principal_paid_minor;
  perform private.validate_purchase_split(command_user_id, remaining_principal,
    p_remaining_personal_amount_minor, p_allocations);
  if remaining_principal < (p_installment_count - p_paid_before_count) then
    raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023'; end if;
  reported_final := p_original_amount_minor - p_installment_amount_minor * (p_installment_count - 1);
  if reported_final <= 0 then raise exception 'NEXO_INVALID_INSTALLMENT_AMOUNT' using errcode = '22023'; end if;
  if exists (
    select 1 from generate_series(p_current_installment_number, p_installment_count) number(installment_number)
    join public.card_statements statement on statement.card_id = p_card_id
      and statement.statement_date = public.card_effective_statement_date(
        extract(year from (p_next_statement_date + make_interval(months => number.installment_number - p_current_installment_number)))::integer,
        extract(month from (p_next_statement_date + make_interval(months => number.installment_number - p_current_installment_number)))::integer,
        target_card.statement_day)
  ) then raise exception 'NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  additional_impact := case when p_included_in_opening_balance then 0 else remaining_principal end;
  payload := jsonb_build_object('card_id', p_card_id, 'description', normalized_description,
    'original_amount_minor', p_original_amount_minor::text,
    'remaining_personal_amount_minor', p_remaining_personal_amount_minor::text,
    'allocations', p_allocations, 'installment_count', p_installment_count,
    'installment_amount_minor', p_installment_amount_minor::text,
    'original_purchase_date', p_original_purchase_date,
    'current_installment_number', p_current_installment_number,
    'paid_before_count', p_paid_before_count,
    'reported_paid_amount_minor', p_reported_paid_amount_minor::text,
    'principal_paid_minor', p_principal_paid_minor::text,
    'next_statement_date', p_next_statement_date, 'category_id', p_category_id,
    'notes', normalized_notes, 'included_in_opening_balance', p_included_in_opening_balance);
  resolved_plan_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'import_shared_historical_installment_plan', payload, proposed_plan_id);
  if resolved_plan_id <> proposed_plan_id then return resolved_plan_id; end if;

  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'card_adjustment', remaining_principal,
    0, normalized_description, p_category_id,
    target_baseline.baseline_date, normalized_notes);
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, remaining_principal,
    case when p_included_in_opening_balance then 'historical_non_impacting' else 'impacting' end);
  insert into public.installment_plans (id, user_id, card_id, purchase_event_id,
    original_amount_minor, installment_count, installment_amount_minor, currency, start_date,
    first_statement_date, status, origin, included_in_opening_balance,
    reported_paid_amount_minor, principal_paid_before_nexo_minor, initial_paid_before_count)
  values (proposed_plan_id, command_user_id, p_card_id, proposed_event_id,
    p_original_amount_minor, p_installment_count, p_installment_amount_minor, target_card.currency,
    p_original_purchase_date, p_next_statement_date, 'active', 'historical',
    p_included_in_opening_balance, p_reported_paid_amount_minor, p_principal_paid_minor,
    p_paid_before_count);
  if p_paid_before_count > 0 then
    paid_principal_regular := p_principal_paid_minor / p_paid_before_count; end if;
  remaining_principal_regular := remaining_principal / (p_installment_count - p_paid_before_count);
  for installment_number in 1..p_installment_count loop
    month_cursor := p_next_statement_date + make_interval(months => installment_number - p_current_installment_number);
    installment_statement_date := public.card_effective_statement_date(
      extract(year from month_cursor)::integer, extract(month from month_cursor)::integer,
      target_card.statement_day);
    reported_value := case when installment_number = p_installment_count then reported_final
      else p_installment_amount_minor end;
    principal_value := case
      when installment_number <= p_paid_before_count then
        case when installment_number = p_paid_before_count
          then p_principal_paid_minor - paid_principal_regular * (p_paid_before_count - 1)
          else paid_principal_regular end
      when installment_number = p_installment_count then
        remaining_principal - remaining_principal_regular *
          (p_installment_count - p_paid_before_count - 1)
      else remaining_principal_regular end;
    if principal_value <= 0 then
      raise exception 'NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS' using errcode = '22023'; end if;
    insert into public.installments (user_id, plan_id, installment_number, due_statement_date,
      principal_minor, reported_amount_minor, status)
    values (command_user_id, proposed_plan_id, installment_number, installment_statement_date,
      principal_value, reported_value,
      case when installment_number <= p_paid_before_count then 'paid_before_nexo' else 'scheduled' end);
  end loop;
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_card.currency, p_allocations);
  perform private.create_installment_receivable_due_items(command_user_id, proposed_plan_id, proposed_event_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'historical_installment_plan_imported', 'installment_plan', proposed_plan_id,
    payload || jsonb_build_object('purchase_event_id', proposed_event_id,
      'remaining_principal_minor', remaining_principal::text,
      'additional_card_impact_minor', additional_impact::text));
  return proposed_plan_id;
end;
$$;

revoke all on function public.import_shared_historical_installment_plan(
  uuid, text, bigint, bigint, jsonb, integer, bigint, date, integer, integer,
  bigint, bigint, date, text, text, boolean, text
) from public, anon;
grant execute on function public.import_shared_historical_installment_plan(
  uuid, text, bigint, bigint, jsonb, integer, bigint, date, integer, integer,
  bigint, bigint, date, text, text, boolean, text
) to authenticated;

create function private.apply_person_amount_to_due_items(
  command_user_id uuid, target_contact_id uuid, target_currency text,
  source_event_id uuid, available_amount bigint, source_kind text, application_date date
)
returns bigint language plpgsql set search_path = '' as $$
declare
  target_item record; applied_amount bigint; remaining_amount bigint := available_amount;
begin
  if source_kind not in ('payment', 'credit') then
    raise exception 'NEXO_INVALID_PERSON_APPLICATION_KIND' using errcode = '22023'; end if;
  for target_item in
    select balance.* from public.receivable_due_item_balances balance
    where balance.user_id = command_user_id and balance.contact_id = target_contact_id
      and balance.currency = target_currency and balance.outstanding_minor > 0
    order by
      case when balance.payment_due_date < application_date then 0 else 1 end,
      balance.payment_due_date, balance.statement_date nulls first,
      balance.sequence_number, balance.created_at, balance.id
  loop
    exit when remaining_amount = 0;
    applied_amount := least(remaining_amount, target_item.outstanding_minor);
    insert into public.receivable_due_applications (
      user_id, due_item_id, receivable_id, financial_event_id, amount_minor, application_kind
    ) values (command_user_id, target_item.id, target_item.receivable_id,
      source_event_id, applied_amount, source_kind);
    remaining_amount := remaining_amount - applied_amount;
  end loop;
  insert into public.receivable_entries (
    user_id, receivable_id, financial_event_id, amount_minor, entry_kind
  )
  select command_user_id, application.receivable_id, source_event_id,
    -sum(application.amount_minor), 'payment'
  from public.receivable_due_applications application
  where application.financial_event_id = source_event_id
    and application.user_id = command_user_id
    and application.application_kind = source_kind
  group by application.receivable_id
  on conflict (financial_event_id, receivable_id) do nothing;
  return remaining_amount;
end;
$$;

create or replace function public.create_person_payment(
  p_contact_id uuid, p_account_id uuid, p_amount_minor bigint, p_occurred_on date,
  p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; target_contact public.contacts%rowtype; target_account public.accounts%rowtype;
  unapplied_amount bigint; normalized_notes text := nullif(btrim(p_notes), ''); payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into target_contact from public.contacts
  where id = p_contact_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into target_account from public.accounts
  where id = p_account_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_account.is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  payload := jsonb_build_object('contact_id', p_contact_id, 'account_id', p_account_id,
    'amount_minor', p_amount_minor::text, 'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_person_payment', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'person_payment', p_amount_minor, 0,
    'Pago recibido de ' || target_contact.name, p_occurred_on, normalized_notes);
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, p_account_id, p_amount_minor);
  perform 1 from public.receivable_due_items item
  join public.receivables receivable on receivable.id = item.receivable_id
  where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    and receivable.currency = target_account.currency for update of item;
  unapplied_amount := private.apply_person_amount_to_due_items(command_user_id, p_contact_id,
    target_account.currency, proposed_event_id, p_amount_minor, 'payment', p_occurred_on);
  if unapplied_amount > 0 then
    insert into public.person_credit_entries (user_id, contact_id, currency,
      financial_event_id, amount_minor, entry_kind)
    values (command_user_id, p_contact_id, target_account.currency,
      proposed_event_id, unapplied_amount, 'credit_created');
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (command_user_id, 'person_credit_created', 'contact', p_contact_id,
      jsonb_build_object('payment_event_id', proposed_event_id,
        'amount_minor', unapplied_amount::text, 'currency', target_account.currency));
  end if;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata) values
    (command_user_id, 'person_payment_received', 'financial_event', proposed_event_id, payload),
    (command_user_id, 'person_payment_applied', 'financial_event', proposed_event_id,
      jsonb_build_object('applied_minor', (p_amount_minor - unapplied_amount)::text,
        'credit_minor', unapplied_amount::text));
  return proposed_event_id;
end;
$$;

create or replace function public.reverse_person_payment(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; payment_entry record; due_application record; credit_entry record;
  payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  perform 1 from public.financial_events where id = p_event_id and user_id = command_user_id
    and kind = 'person_payment' for update;
  if not found then raise exception 'NEXO_PERSON_PAYMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_person_payment', payload, reversal_event_id);
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de pago recibido');
  for payment_entry in select * from public.receivable_entries
    where financial_event_id = p_event_id and user_id = command_user_id and entry_kind = 'payment' for update
  loop
    insert into public.receivable_entries (user_id, receivable_id, financial_event_id,
      amount_minor, entry_kind, reverses_entry_id)
    values (command_user_id, payment_entry.receivable_id, reversal_event_id,
      -payment_entry.amount_minor, 'reversal', payment_entry.id);
  end loop;
  for due_application in select * from public.receivable_due_applications
    where financial_event_id = p_event_id and user_id = command_user_id
      and application_kind in ('payment', 'credit') for update
  loop
    insert into public.receivable_due_applications (user_id, due_item_id, receivable_id,
      financial_event_id, amount_minor, application_kind, reverses_application_id)
    values (command_user_id, due_application.due_item_id, due_application.receivable_id,
      reversal_event_id, -due_application.amount_minor, 'reversal', due_application.id);
  end loop;
  for credit_entry in select * from public.person_credit_entries
    where financial_event_id = p_event_id and user_id = command_user_id for update
  loop
    insert into public.person_credit_entries (user_id, contact_id, currency,
      financial_event_id, amount_minor, entry_kind, reverses_entry_id)
    values (command_user_id, credit_entry.contact_id, credit_entry.currency,
      reversal_event_id, -credit_entry.amount_minor, 'reversal', credit_entry.id);
  end loop;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_payment_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
$$;

create function public.apply_person_credit(
  p_contact_id uuid, p_currency text, p_amount_minor bigint, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; available_credit bigint; unapplied bigint; payload jsonb;
begin
  perform 1 from public.contacts where id = p_contact_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  select coalesce(sum(amount_minor), 0) into available_credit from public.person_credit_entries
  where user_id = command_user_id and contact_id = p_contact_id and currency = p_currency;
  if p_amount_minor <= 0 or p_amount_minor > available_credit then
    raise exception 'NEXO_INVALID_CREDIT_AMOUNT' using errcode = '22023'; end if;
  payload := jsonb_build_object('contact_id', p_contact_id, 'currency', p_currency,
    'amount_minor', p_amount_minor::text);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'apply_person_credit', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, occurred_on)
  values (proposed_event_id, command_user_id, 'person_credit_application', p_amount_minor, 0,
    'Aplicación de saldo a favor', current_date);
  perform 1 from public.receivable_due_items item
  join public.receivables receivable on receivable.id = item.receivable_id
  where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    and receivable.currency = p_currency for update of item;
  unapplied := private.apply_person_amount_to_due_items(command_user_id, p_contact_id,
    p_currency, proposed_event_id, p_amount_minor, 'credit', current_date);
  if unapplied <> 0 then raise exception 'NEXO_CREDIT_WITHOUT_ELIGIBLE_OBLIGATION' using errcode = '23514'; end if;
  insert into public.person_credit_entries (user_id, contact_id, currency,
    financial_event_id, amount_minor, entry_kind)
  values (command_user_id, p_contact_id, p_currency, proposed_event_id,
    -p_amount_minor, 'credit_applied');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_credit_applied', 'contact', p_contact_id,
    payload || jsonb_build_object('application_event_id', proposed_event_id));
  return proposed_event_id;
end;
$$;

revoke all on function public.apply_person_credit(uuid, text, bigint, text) from public, anon;
grant execute on function public.apply_person_credit(uuid, text, bigint, text) to authenticated;

create function public.get_person_collection_period(p_contact_id uuid, p_as_of_date date default current_date)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); result jsonb;
begin
  if not exists (select 1 from public.contacts where id = p_contact_id and user_id = command_user_id) then
    raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  with currencies as (
    select distinct receivable.currency
    from public.receivables receivable
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    union
    select entry.currency from public.person_credit_entries entry
    where entry.user_id = command_user_id and entry.contact_id = p_contact_id
  ), selected_statements as (
    select currency.currency, card.id as card_id,
      coalesce(
        min(item.statement_date) filter (where item.payment_due_date >= p_as_of_date),
        max(item.statement_date)
      ) as statement_date
    from currencies currency
    join public.receivables receivable on receivable.user_id = command_user_id
      and receivable.contact_id = p_contact_id and receivable.currency = currency.currency
    join public.receivable_due_items item on item.receivable_id = receivable.id and item.card_id is not null
    join public.credit_cards card on card.id = item.card_id
    group by currency.currency, card.id
  ), balances as (
    select balance.*,
      coalesce(sum(application.amount_minor) filter (where application.application_kind = 'credit'), 0)::bigint
        as credit_applied_minor
    from public.receivable_due_item_balances balance
    left join public.receivable_due_applications application on application.due_item_id = balance.id
    where balance.user_id = command_user_id and balance.contact_id = p_contact_id
    group by balance.id, balance.user_id, balance.receivable_id, balance.contact_id,
      balance.installment_id, balance.card_id, balance.statement_date,
      balance.payment_due_date, balance.amount_minor, balance.paid_minor,
      balance.outstanding_minor, balance.sequence_number, balance.description,
      balance.currency, balance.created_at
  ), eligible as (
    select balance.* from balances balance
    left join selected_statements selected on selected.currency = balance.currency
      and selected.card_id = balance.card_id
    where (balance.card_id is null)
      or (balance.payment_due_date < p_as_of_date and balance.outstanding_minor > 0)
      or (balance.statement_date = selected.statement_date)
  ), totals as (
    select receivable.currency,
      coalesce(sum(entry.amount_minor), 0)::bigint as total_outstanding_minor
    from public.receivables receivable
    join public.receivable_entries entry on entry.receivable_id = receivable.id
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    group by receivable.currency
  ), credits as (
    select currency, coalesce(sum(amount_minor), 0)::bigint credit_balance_minor
    from public.person_credit_entries
    where user_id = command_user_id and contact_id = p_contact_id group by currency
  )
  select jsonb_build_object(
    'as_of_date', p_as_of_date,
    'periods', coalesce(jsonb_agg(jsonb_build_object(
      'currency', currency.currency,
      'period_start', period.period_start,
      'payment_due_date', period.payment_due_date,
      'subtotal_minor', coalesce(period.subtotal_minor, 0)::text,
      'paid_minor', coalesce(period.paid_minor, 0)::text,
      'credit_applied_minor', coalesce(period.credit_applied_minor, 0)::text,
      'remaining_minor', coalesce(period.remaining_minor, 0)::text,
      'total_outstanding_minor', coalesce(total.total_outstanding_minor, 0)::text,
      'credit_balance_minor', coalesce(credit.credit_balance_minor, 0)::text,
      'concepts', coalesce(period.concepts, '[]'::jsonb)
    ) order by currency.currency), '[]'::jsonb)
  ) into result
  from currencies currency
  left join totals total on total.currency = currency.currency
  left join credits credit on credit.currency = currency.currency
  left join lateral (
    select min(coalesce(item.statement_date, item.payment_due_date)) as period_start,
      max(item.payment_due_date) as payment_due_date,
      sum(item.amount_minor)::bigint as subtotal_minor,
      sum(item.paid_minor)::bigint as paid_minor,
      sum(item.credit_applied_minor)::bigint as credit_applied_minor,
      sum(item.outstanding_minor)::bigint as remaining_minor,
      jsonb_agg(jsonb_build_object(
        'id', item.id, 'description', item.description,
        'statement_date', item.statement_date, 'payment_due_date', item.payment_due_date,
        'amount_minor', item.amount_minor::text, 'paid_minor', item.paid_minor::text,
        'outstanding_minor', item.outstanding_minor::text,
        'credit_applied_minor', item.credit_applied_minor::text,
        'installment_id', item.installment_id,
        'installment_number', item.sequence_number
      ) order by item.payment_due_date, item.sequence_number, item.created_at) as concepts
    from eligible item where item.currency = currency.currency
  ) period on true;
  return coalesce(result, jsonb_build_object('as_of_date', p_as_of_date, 'periods', '[]'::jsonb));
end;
$$;

create view public.person_installment_summaries with (security_invoker = true) as
select plan.id as plan_id, receivable.user_id, receivable.contact_id, plan.card_id,
  plan.origin, plan.installment_count, plan.currency, coalesce(metadata.description, event.description) as description,
  sum(item.amount_minor)::bigint as assigned_total_minor,
  sum(item.outstanding_minor)::bigint as outstanding_minor,
  min(item.sequence_number) filter (where item.outstanding_minor > 0) as current_installment_number,
  min(item.statement_date) filter (where item.outstanding_minor > 0) as current_statement_date,
  sum(item.outstanding_minor) filter (
    where item.statement_date = current_period.statement_date
  )::bigint as current_period_minor
from public.receivables receivable
join public.receivable_due_item_balances item on item.receivable_id = receivable.id
join public.installments installment on installment.id = item.installment_id
join public.installment_plans plan on plan.id = installment.plan_id
join public.financial_events event on event.id = plan.purchase_event_id
left join lateral (
  select revision.description from public.installment_plan_metadata_revisions revision
  where revision.plan_id = plan.id order by revision.created_at desc limit 1
) metadata on true
left join lateral (
  select min(candidate.statement_date) as statement_date
  from public.receivable_due_item_balances candidate
  where candidate.receivable_id = receivable.id and candidate.payment_due_date >= current_date
) current_period on true
where plan.status <> 'reversed'
group by plan.id, receivable.id, metadata.description, event.description, current_period.statement_date;

revoke all on table public.person_installment_summaries from anon, authenticated;
grant select on table public.person_installment_summaries to authenticated;
grant all on table public.person_installment_summaries to service_role;

create function public.record_person_statement_export(
  p_contact_id uuid, p_period_start date, p_period_end date, p_format text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); export_id uuid := gen_random_uuid();
  resolved_id uuid; payload jsonb;
begin
  if p_format not in ('pdf', 'xlsx', 'csv') then
    raise exception 'NEXO_INVALID_EXPORT_FORMAT' using errcode = '22023'; end if;
  if not exists (select 1 from public.contacts where id = p_contact_id and user_id = command_user_id) then
    raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  payload := jsonb_build_object('contact_id', p_contact_id, 'period_start', p_period_start,
    'period_end', p_period_end, 'format', p_format);
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'record_person_statement_export', payload, export_id);
  if resolved_id <> export_id then return resolved_id; end if;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_statement_exported', 'contact', p_contact_id,
    payload || jsonb_build_object('export_id', export_id));
  return export_id;
end;
$$;

revoke all on function public.get_person_collection_period(uuid, date) from public, anon;
revoke all on function public.record_person_statement_export(uuid, date, date, text, text) from public, anon;
grant execute on function public.get_person_collection_period(uuid, date) to authenticated;
grant execute on function public.record_person_statement_export(uuid, date, date, text, text) to authenticated;

create or replace function public.reverse_installment_purchase(p_plan_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_reversal_id uuid := gen_random_uuid();
  resolved_reversal_id uuid; target_plan public.installment_plans%rowtype;
  original_event public.financial_events%rowtype;
  payload jsonb := jsonb_build_object('plan_id', p_plan_id);
begin
  select * into target_plan from public.installment_plans
  where id = p_plan_id and user_id = command_user_id for update;
  if not found or target_plan.status <> 'active' then
    raise exception 'NEXO_INSTALLMENT_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.installments installment
    join public.card_statements statement on statement.card_id = target_plan.card_id
      and statement.statement_date = installment.due_statement_date
    where installment.plan_id = p_plan_id and installment.status = 'scheduled'
  ) then raise exception 'NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  resolved_reversal_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_installment_purchase', payload, proposed_reversal_id);
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;
  select * into strict original_event from public.financial_events
  where id = target_plan.purchase_event_id and user_id = command_user_id;
  if target_plan.origin = 'historical' then
    insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
      description, occurred_on, notes, reverses_event_id)
    values (proposed_reversal_id, command_user_id, 'reversal', original_event.amount_minor, 0,
      'Reversión de importación MSI histórica', current_date, original_event.notes, original_event.id);
    insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
    select command_user_id, proposed_reversal_id, entry.card_id, -entry.amount_minor, entry.effect_scope
    from public.card_entries entry where entry.financial_event_id = original_event.id
      and entry.user_id = command_user_id;
  else
    perform set_config('nexo.allow_msi_reversal', 'on', true);
    perform private.reverse_card_event(command_user_id, target_plan.purchase_event_id,
      proposed_reversal_id, 'Reversión de compra MSI');
  end if;
  perform private.reverse_purchase_receivables(command_user_id, target_plan.purchase_event_id,
    proposed_reversal_id);
  update public.installment_plans set status = 'reversed' where id = p_plan_id;
  update public.installments set status = 'cancelled'
  where plan_id = p_plan_id and status <> 'cancelled';
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id,
    case when exists (select 1 from public.purchase_allocations
      where financial_event_id = target_plan.purchase_event_id)
      then 'shared_installment_purchase_reversed'
      when target_plan.origin = 'historical' then 'historical_installment_plan_reversed'
      else 'installment_purchase_reversed' end,
    'installment_plan', p_plan_id,
    jsonb_build_object('purchase_event_id', target_plan.purchase_event_id,
      'reversal_event_id', proposed_reversal_id));
  return proposed_reversal_id;
end;
$$;
