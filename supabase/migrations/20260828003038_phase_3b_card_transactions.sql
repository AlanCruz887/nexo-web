-- Nexo Phase 3B: operational credit-card purchases, payments, refunds and
-- unified activity. MSI, contacts, receivables and shared purchases remain out
-- of scope. All financial mutations are immutable command -> event -> entries.

alter table public.financial_events
  drop constraint financial_events_personal_amount_valid;

alter table public.financial_events
  add constraint financial_events_personal_amount_valid check (
    personal_amount_minor >= 0
    and (
      (kind in ('expense', 'card_charge', 'card_refund') and personal_amount_minor = amount_minor)
      or (kind not in ('expense', 'card_charge', 'card_refund') and personal_amount_minor = 0)
    )
  );

create table public.card_transaction_details (
  financial_event_id uuid primary key references public.financial_events (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete cascade,
  card_id uuid not null references public.credit_cards (id) on delete restrict,
  source_account_id uuid references public.accounts (id) on delete restrict,
  payment_method text,
  statement_date date,
  related_event_id uuid references public.financial_events (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint card_transaction_details_payment_method_valid check (
    payment_method is null or payment_method in ('physical_card', 'apple_pay', 'google_pay', 'online', 'other')
  )
);

comment on table public.card_transaction_details is
  'Immutable card-operation metadata. statement_date is assigned only by the central cycle engine.';

create index card_transaction_details_user_card_created_idx
  on public.card_transaction_details (user_id, card_id, created_at desc);
create index card_transaction_details_related_event_idx
  on public.card_transaction_details (related_event_id) where related_event_id is not null;

alter table public.card_transaction_details enable row level security;
revoke all on table public.card_transaction_details from anon, authenticated;
grant select on table public.card_transaction_details to authenticated;
grant all on table public.card_transaction_details to service_role;
create policy "Users can read their own card transaction details"
on public.card_transaction_details for select to authenticated
using ((select auth.uid()) = user_id);

create table public.card_statement_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  statement_id uuid not null references public.card_statements (id) on delete restrict,
  amount_minor bigint not null,
  reverses_allocation_id uuid references public.card_statement_payment_allocations (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint card_statement_payment_allocations_nonzero check (amount_minor <> 0),
  constraint card_statement_payment_allocations_direction check (
    (amount_minor > 0 and reverses_allocation_id is null)
    or (amount_minor < 0 and reverses_allocation_id is not null)
  ),
  constraint card_statement_payment_allocations_event_statement_unique unique (financial_event_id, statement_id)
);

comment on table public.card_statement_payment_allocations is
  'Immutable signed allocation ledger. Positive rows apply card payments; negative rows reverse a prior allocation.';

create index card_statement_payment_allocations_user_statement_idx
  on public.card_statement_payment_allocations (user_id, statement_id, created_at desc);
create unique index card_statement_payment_allocations_reversal_unique
  on public.card_statement_payment_allocations (reverses_allocation_id)
  where reverses_allocation_id is not null;

alter table public.card_statement_payment_allocations enable row level security;
revoke all on table public.card_statement_payment_allocations from anon, authenticated;
grant select on table public.card_statement_payment_allocations to authenticated;
grant all on table public.card_statement_payment_allocations to service_role;
create policy "Users can read their own card payment allocations"
on public.card_statement_payment_allocations for select to authenticated
using ((select auth.uid()) = user_id);

create trigger card_transaction_details_are_immutable
before update or delete on public.card_transaction_details
for each row execute function private.reject_financial_mutation();

create trigger card_statement_payment_allocations_are_immutable
before update or delete on public.card_statement_payment_allocations
for each row execute function private.reject_financial_mutation();

create function private.reverse_card_event(
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

revoke all on function private.reverse_card_event(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function public.create_card_purchase(
  p_card_id uuid,
  p_amount_minor bigint,
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
  proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  target_card public.credit_cards%rowtype;
  baseline_date date;
  assigned_statement_date date;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  normalized_method text := nullif(btrim(p_payment_method), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date
  from public.card_baselines baseline where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  assigned_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (
    select 1 from public.card_statements where card_id = p_card_id and statement_date = assigned_statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  payload := jsonb_build_object(
    'card_id', p_card_id, 'amount_minor', p_amount_minor::text, 'description', normalized_description,
    'category_id', p_category_id, 'occurred_on', p_occurred_on,
    'payment_method', normalized_method, 'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_card_purchase', payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;

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
    proposed_event_id, command_user_id, p_card_id, normalized_method, assigned_statement_date
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_created', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('statement_date', assigned_statement_date));
  return proposed_event_id;
end;
$$;

create function public.update_card_purchase(
  p_event_id uuid,
  p_card_id uuid,
  p_amount_minor bigint,
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
  proposed_event_id uuid := gen_random_uuid();
  reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  original_event public.financial_events%rowtype;
  original_detail public.card_transaction_details%rowtype;
  target_card public.credit_cards%rowtype;
  baseline_date date;
  assigned_statement_date date;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  normalized_method text := nullif(btrim(p_payment_method), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into original_event from public.financial_events
  where id = p_event_id and user_id = command_user_id and kind = 'card_charge' for update;
  if not found then raise exception 'NEXO_CARD_PURCHASE_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into strict original_detail from public.card_transaction_details
  where financial_event_id = p_event_id and user_id = command_user_id;
  if exists (select 1 from public.financial_events where reverses_event_id = p_event_id) then
    raise exception 'NEXO_TRANSACTION_ALREADY_REVERSED' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.card_statements
    where card_id = original_detail.card_id and statement_date = original_detail.statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date
  from public.card_baselines baseline where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  assigned_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (
    select 1 from public.card_statements where card_id = p_card_id and statement_date = assigned_statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;

  payload := jsonb_build_object(
    'event_id', p_event_id, 'card_id', p_card_id, 'amount_minor', p_amount_minor::text,
    'description', normalized_description, 'category_id', p_category_id, 'occurred_on', p_occurred_on,
    'payment_method', normalized_method, 'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_card_purchase', payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;

  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión por edición de compra');
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
    financial_event_id, user_id, card_id, payment_method, statement_date, related_event_id
  ) values (
    proposed_event_id, command_user_id, p_card_id, normalized_method, assigned_statement_date, p_event_id
  );
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_updated', 'financial_event', proposed_event_id,
    jsonb_build_object('replaces_event_id', p_event_id, 'reversal_event_id', reversal_event_id,
      'statement_date', assigned_statement_date));
  return proposed_event_id;
end;
$$;

create function public.reverse_card_purchase(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  detail public.card_transaction_details%rowtype;
  payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  select * into detail from public.card_transaction_details
  where financial_event_id = p_event_id and user_id = command_user_id;
  if not found or not exists (
    select 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'card_charge'
  ) then raise exception 'NEXO_CARD_PURCHASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.card_statements where card_id = detail.card_id and statement_date = detail.statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_card_purchase', payload, reversal_event_id
  );
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de compra con tarjeta');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
$$;

create function public.create_card_payment(
  p_card_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_occurred_on date,
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
  target_account public.accounts%rowtype;
  baseline_date date;
  remaining_to_allocate bigint := p_amount_minor;
  allocation_amount bigint;
  target_statement public.card_statements%rowtype;
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into target_card from public.credit_cards
  where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select * into target_account from public.accounts
  where id = p_source_account_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_account.is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  if target_account.currency <> target_card.currency then
    raise exception 'NEXO_CURRENCY_MISMATCH' using errcode = '23514';
  end if;
  select baseline.baseline_date into strict baseline_date from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;

  payload := jsonb_build_object(
    'card_id', p_card_id, 'source_account_id', p_source_account_id,
    'amount_minor', p_amount_minor::text, 'occurred_on', p_occurred_on, 'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_card_payment', payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'card_payment', p_amount_minor, 0,
    'Pago a ' || target_card.name, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, p_source_account_id, -p_amount_minor);
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, -p_amount_minor, 'impacting');
  insert into public.card_transaction_details (
    financial_event_id, user_id, card_id, source_account_id
  ) values (
    proposed_event_id, command_user_id, p_card_id, p_source_account_id
  );

  for target_statement in
    select * from public.card_statements
    where card_id = p_card_id and user_id = command_user_id and remaining_due_minor > 0
    order by payment_due_date, statement_date
    for update
  loop
    exit when remaining_to_allocate = 0;
    allocation_amount := least(remaining_to_allocate, target_statement.remaining_due_minor);
    insert into public.card_statement_payment_allocations (
      user_id, financial_event_id, statement_id, amount_minor
    ) values (
      command_user_id, proposed_event_id, target_statement.id, allocation_amount
    );
    update public.card_statements set
      amount_paid_minor = amount_paid_minor + allocation_amount,
      remaining_due_minor = remaining_due_minor - allocation_amount,
      status = case when remaining_due_minor - allocation_amount = 0 then 'paid' else 'closed' end
    where id = target_statement.id;
    remaining_to_allocate := remaining_to_allocate - allocation_amount;
  end loop;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_payment_created', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('unallocated_credit_minor', remaining_to_allocate::text));
  return proposed_event_id;
end;
$$;

create function public.reverse_card_payment(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  allocation public.card_statement_payment_allocations%rowtype;
  payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  if not exists (
    select 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'card_payment'
  ) then raise exception 'NEXO_CARD_PAYMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_card_payment', payload, reversal_event_id
  );
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de pago de tarjeta');

  for allocation in
    select * from public.card_statement_payment_allocations
    where financial_event_id = p_event_id and user_id = command_user_id and amount_minor > 0
    order by created_at for update
  loop
    update public.card_statements set
      amount_paid_minor = greatest(amount_paid_minor - allocation.amount_minor, 0),
      remaining_due_minor = least(statement_balance_minor, remaining_due_minor + allocation.amount_minor),
      status = 'closed'
    where id = allocation.statement_id;
    insert into public.card_statement_payment_allocations (
      user_id, financial_event_id, statement_id, amount_minor, reverses_allocation_id
    ) values (
      command_user_id, reversal_event_id, allocation.statement_id, -allocation.amount_minor, allocation.id
    );
  end loop;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_payment_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
$$;

create function public.create_card_refund(
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

create function public.reverse_card_refund(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  detail public.card_transaction_details%rowtype;
  payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  select * into detail from public.card_transaction_details
  where financial_event_id = p_event_id and user_id = command_user_id;
  if not found or not exists (
    select 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'card_refund'
  ) then raise exception 'NEXO_CARD_REFUND_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.card_statements where card_id = detail.card_id and statement_date = detail.statement_date
  ) then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_card_refund', payload, reversal_event_id
  );
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de reembolso');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_refund_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
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
    coalesce((
      select sum(entry.amount_minor)
      from public.card_entries entry
      join public.financial_events event on event.id = entry.financial_event_id
      where entry.card_id = base.id and entry.effect_scope = 'impacting'
        and event.kind in ('card_charge', 'card_refund', 'card_adjustment')
        and event.occurred_on >= public.card_previous_statement_date(base.next_statement_date, base.statement_day)
        and event.occurred_on < base.next_statement_date
        and not exists (
          select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id
        )
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
  order by statement.statement_date desc limit 1
) latest on true;

create view public.card_current_cycles
with (security_invoker = true)
as
select
  summary.id as card_id, summary.user_id,
  public.card_previous_statement_date(summary.next_statement_date, summary.statement_day) as cycle_start,
  summary.next_statement_date as cycle_end,
  summary.next_statement_date as statement_date,
  summary.next_payment_due_date as payment_due_date,
  summary.open_cycle_accumulated_minor
from public.card_summaries summary;

create view public.financial_activity
with (security_invoker = true)
as
with active_events as (
  select event.* from public.financial_events event
  where event.kind <> 'reversal'
    and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id)
), account_events as (
  select
    event.id as event_id, event.user_id, event.kind, event.amount_minor, event.personal_amount_minor,
    event.description, event.category_id, category.name as category_name, event.occurred_on,
    coalesce(latest_note.notes, event.notes) as notes, event.created_at,
    'account'::text as source_type, account.id as account_id, null::uuid as card_id,
    account.name as source_name, account.institution as source_detail, account.currency,
    entry.amount_minor as signed_amount_minor, null::text as payment_method,
    null::date as statement_date, null::uuid as related_event_id,
    account.is_active as source_is_active, null::uuid as source_account_id, null::text as source_account_name,
    null::uuid as destination_account_id
  from active_events event
  join public.account_entries entry on entry.financial_event_id = event.id
  join public.accounts account on account.id = entry.account_id
  left join public.categories category on category.id = event.category_id
  left join lateral (
    select note.notes from public.financial_event_notes note
    where note.financial_event_id = event.id order by note.created_at desc limit 1
  ) latest_note on true
  where event.kind in ('opening', 'income', 'expense', 'adjustment')
), transfer_events as (
  select
    event.id as event_id, event.user_id, event.kind, event.amount_minor, event.personal_amount_minor,
    event.description, event.category_id, null::text as category_name, event.occurred_on,
    coalesce(latest_note.notes, event.notes) as notes, event.created_at,
    'transfer'::text as source_type, null::uuid as account_id, null::uuid as card_id,
    coalesce(source_account.name, 'Cuenta') || ' → ' || coalesce(destination_account.name, 'Cuenta') as source_name,
    'Transferencia'::text as source_detail, source_account.currency,
    0::bigint as signed_amount_minor, null::text as payment_method,
    null::date as statement_date, null::uuid as related_event_id,
    (source_account.is_active and destination_account.is_active) as source_is_active,
    source_account.id as source_account_id, source_account.name as source_account_name,
    destination_account.id as destination_account_id
  from active_events event
  left join public.account_entries source_entry on source_entry.financial_event_id = event.id and source_entry.amount_minor < 0
  left join public.accounts source_account on source_account.id = source_entry.account_id
  left join public.account_entries destination_entry on destination_entry.financial_event_id = event.id and destination_entry.amount_minor > 0
  left join public.accounts destination_account on destination_account.id = destination_entry.account_id
  left join lateral (
    select note.notes from public.financial_event_notes note
    where note.financial_event_id = event.id order by note.created_at desc limit 1
  ) latest_note on true
  where event.kind = 'transfer'
), card_events as (
  select
    event.id as event_id, event.user_id, event.kind, event.amount_minor, event.personal_amount_minor,
    event.description, event.category_id, category.name as category_name, event.occurred_on,
    event.notes, event.created_at,
    'card'::text as source_type, null::uuid as account_id, card.id as card_id,
    card.name as source_name,
    case when event.kind = 'card_payment' then coalesce(account.name, 'Cuenta') || ' → ' || card.name
      else card.issuer end as source_detail,
    card.currency,
    case when event.kind = 'card_charge' then -event.amount_minor
      when event.kind = 'card_refund' then event.amount_minor
      else event.amount_minor end as signed_amount_minor,
    detail.payment_method, coalesce(detail.statement_date, payment_statement.statement_date) as statement_date, detail.related_event_id,
    card.is_active as source_is_active, detail.source_account_id, account.name as source_account_name,
    null::uuid as destination_account_id
  from active_events event
  join public.card_transaction_details detail on detail.financial_event_id = event.id
  join public.credit_cards card on card.id = detail.card_id
  left join public.accounts account on account.id = detail.source_account_id
  left join public.categories category on category.id = event.category_id
  left join lateral (
    select max(statement.statement_date) as statement_date
    from public.card_statement_payment_allocations allocation
    join public.card_statements statement on statement.id = allocation.statement_id
    where allocation.financial_event_id = event.id and allocation.amount_minor > 0
  ) payment_statement on true
  where event.kind in ('card_charge', 'card_payment', 'card_refund')
)
select * from account_events
union all select * from transfer_events
union all select * from card_events;

revoke all on table public.card_summaries from anon, authenticated;
revoke all on table public.card_current_cycles from anon, authenticated;
revoke all on table public.financial_activity from anon, authenticated;
grant select on table public.card_summaries to authenticated;
grant select on table public.card_current_cycles to authenticated;
grant select on table public.financial_activity to authenticated;
grant all on table public.card_summaries to service_role;
grant all on table public.card_current_cycles to service_role;
grant all on table public.financial_activity to service_role;

revoke all on function public.create_card_purchase(uuid, bigint, text, text, date, text, text, text) from public, anon;
revoke all on function public.update_card_purchase(uuid, uuid, bigint, text, text, date, text, text, text) from public, anon;
revoke all on function public.reverse_card_purchase(uuid, text) from public, anon;
revoke all on function public.create_card_payment(uuid, uuid, bigint, date, text, text) from public, anon;
revoke all on function public.reverse_card_payment(uuid, text) from public, anon;
revoke all on function public.create_card_refund(uuid, bigint, text, text, date, uuid, text, text) from public, anon;
revoke all on function public.reverse_card_refund(uuid, text) from public, anon;
grant execute on function public.create_card_purchase(uuid, bigint, text, text, date, text, text, text) to authenticated;
grant execute on function public.update_card_purchase(uuid, uuid, bigint, text, text, date, text, text, text) to authenticated;
grant execute on function public.reverse_card_purchase(uuid, text) to authenticated;
grant execute on function public.create_card_payment(uuid, uuid, bigint, date, text, text) to authenticated;
grant execute on function public.reverse_card_payment(uuid, text) to authenticated;
grant execute on function public.create_card_refund(uuid, bigint, text, text, date, uuid, text, text) to authenticated;
grant execute on function public.reverse_card_refund(uuid, text) to authenticated;
