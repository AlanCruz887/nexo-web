-- Nexo Phase 5A: people, shared purchases and nominal receivables.
-- Purchase allocations are the only place where amount = personal + third parties.

alter table public.financial_events
  drop constraint financial_events_kind_valid,
  drop constraint financial_events_amount_valid,
  drop constraint financial_events_personal_amount_valid;

alter table public.financial_events
  add constraint financial_events_kind_valid check (
    kind in ('opening', 'income', 'expense', 'adjustment', 'transfer', 'reversal',
      'card_charge', 'card_payment', 'card_refund', 'card_adjustment', 'person_payment')
  ),
  add constraint financial_events_amount_valid check (
    (kind in ('income', 'expense', 'transfer', 'reversal', 'card_charge', 'card_payment', 'card_refund', 'person_payment') and amount_minor > 0)
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

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  email text,
  phone text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contacts_name_not_blank check (char_length(btrim(name)) between 1 and 120),
  constraint contacts_email_length check (email is null or char_length(email) <= 254),
  constraint contacts_phone_length check (phone is null or char_length(phone) <= 40),
  constraint contacts_notes_length check (notes is null or char_length(notes) <= 2000)
);

create index contacts_user_active_name_idx on public.contacts (user_id, is_active desc, name);
alter table public.contacts enable row level security;
revoke all on table public.contacts from anon, authenticated;
grant select on table public.contacts to authenticated;
grant all on table public.contacts to service_role;
create policy "Users can read their own contacts" on public.contacts
for select to authenticated using ((select auth.uid()) = user_id);
create trigger contacts_set_updated_at before update on public.contacts
for each row execute function private.set_updated_at();

create table public.receivables (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  contact_id uuid not null references public.contacts (id) on delete restrict,
  source_event_id uuid not null references public.financial_events (id) on delete restrict,
  original_amount_minor bigint not null check (original_amount_minor > 0),
  currency text not null references public.currencies (code),
  occurred_on date not null,
  created_at timestamptz not null default now(),
  constraint receivables_source_contact_unique unique (source_event_id, contact_id)
);

create index receivables_user_contact_currency_date_idx
  on public.receivables (user_id, contact_id, currency, occurred_on, created_at);
alter table public.receivables enable row level security;
revoke all on table public.receivables from anon, authenticated;
grant select on table public.receivables to authenticated;
grant all on table public.receivables to service_role;
create policy "Users can read their own receivables" on public.receivables
for select to authenticated using ((select auth.uid()) = user_id);

create table public.purchase_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  contact_id uuid not null references public.contacts (id) on delete restrict,
  receivable_id uuid not null unique references public.receivables (id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint purchase_allocations_event_contact_unique unique (financial_event_id, contact_id)
);

create index purchase_allocations_user_event_idx on public.purchase_allocations (user_id, financial_event_id);
create index purchase_allocations_user_contact_idx on public.purchase_allocations (user_id, contact_id, created_at desc);
alter table public.purchase_allocations enable row level security;
revoke all on table public.purchase_allocations from anon, authenticated;
grant select on table public.purchase_allocations to authenticated;
grant all on table public.purchase_allocations to service_role;
create policy "Users can read their own purchase allocations" on public.purchase_allocations
for select to authenticated using ((select auth.uid()) = user_id);

create table public.receivable_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  receivable_id uuid not null references public.receivables (id) on delete restrict,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  amount_minor bigint not null check (amount_minor <> 0),
  entry_kind text not null check (entry_kind in ('charge', 'payment', 'reversal')),
  reverses_entry_id uuid references public.receivable_entries (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint receivable_entries_event_receivable_unique unique (financial_event_id, receivable_id),
  constraint receivable_entries_direction_valid check (
    (entry_kind = 'charge' and amount_minor > 0 and reverses_entry_id is null)
    or (entry_kind = 'payment' and amount_minor < 0 and reverses_entry_id is null)
    or (entry_kind = 'reversal' and reverses_entry_id is not null)
  )
);

create index receivable_entries_user_receivable_idx on public.receivable_entries (user_id, receivable_id, created_at);
create index receivable_entries_user_event_idx on public.receivable_entries (user_id, financial_event_id);
create unique index receivable_entries_reversal_unique on public.receivable_entries (reverses_entry_id)
where reverses_entry_id is not null;
alter table public.receivable_entries enable row level security;
revoke all on table public.receivable_entries from anon, authenticated;
grant select on table public.receivable_entries to authenticated;
grant all on table public.receivable_entries to service_role;
create policy "Users can read their own receivable entries" on public.receivable_entries
for select to authenticated using ((select auth.uid()) = user_id);

create trigger receivables_are_immutable before update or delete on public.receivables
for each row execute function private.reject_financial_mutation();
create trigger purchase_allocations_are_immutable before update or delete on public.purchase_allocations
for each row execute function private.reject_financial_mutation();
create trigger receivable_entries_are_immutable before update or delete on public.receivable_entries
for each row execute function private.reject_financial_mutation();

create function private.validate_purchase_split(
  command_user_id uuid,
  purchase_amount_minor bigint,
  personal_amount_minor bigint,
  allocations jsonb
)
returns void language plpgsql set search_path = '' as $$
declare
  allocated_amount bigint;
  allocation_count integer;
  distinct_contact_count integer;
  owned_active_count integer;
begin
  if purchase_amount_minor <= 0 or personal_amount_minor < 0 or personal_amount_minor > purchase_amount_minor then
    raise exception 'NEXO_INVALID_PURCHASE_SPLIT' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(allocations, '[]'::jsonb)) <> 'array' then
    raise exception 'NEXO_INVALID_PURCHASE_SPLIT' using errcode = '22023';
  end if;
  select coalesce(sum((item->>'amount_minor')::bigint), 0), count(*), count(distinct (item->>'contact_id'))
  into allocated_amount, allocation_count, distinct_contact_count
  from jsonb_array_elements(coalesce(allocations, '[]'::jsonb)) item;
  if exists (
    select 1 from jsonb_array_elements(coalesce(allocations, '[]'::jsonb)) item
    where coalesce((item->>'amount_minor')::bigint, 0) <= 0 or nullif(item->>'contact_id', '') is null
  ) or allocation_count <> distinct_contact_count or purchase_amount_minor <> personal_amount_minor + allocated_amount then
    raise exception 'NEXO_PURCHASE_SPLIT_MISMATCH' using errcode = '23514';
  end if;
  select count(*) into owned_active_count from public.contacts contact
  where contact.user_id = command_user_id and contact.is_active
    and contact.id in (
      select (item->>'contact_id')::uuid from jsonb_array_elements(coalesce(allocations, '[]'::jsonb)) item
    );
  if owned_active_count <> allocation_count then
    raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002';
  end if;
end;
$$;

create function private.create_purchase_receivables(
  command_user_id uuid,
  purchase_event_id uuid,
  purchase_currency text,
  allocations jsonb
)
returns void language plpgsql set search_path = '' as $$
declare
  item jsonb;
  new_receivable_id uuid;
  target_contact_id uuid;
  target_amount bigint;
  purchase_date date;
begin
  select occurred_on into strict purchase_date from public.financial_events where id = purchase_event_id;
  for item in select * from jsonb_array_elements(coalesce(allocations, '[]'::jsonb)) loop
    target_contact_id := (item->>'contact_id')::uuid;
    target_amount := (item->>'amount_minor')::bigint;
    new_receivable_id := gen_random_uuid();
    insert into public.receivables (id, user_id, contact_id, source_event_id, original_amount_minor, currency, occurred_on)
    values (new_receivable_id, command_user_id, target_contact_id, purchase_event_id, target_amount, purchase_currency, purchase_date);
    insert into public.purchase_allocations (user_id, financial_event_id, contact_id, receivable_id, amount_minor)
    values (command_user_id, purchase_event_id, target_contact_id, new_receivable_id, target_amount);
    insert into public.receivable_entries (user_id, receivable_id, financial_event_id, amount_minor, entry_kind)
    values (command_user_id, new_receivable_id, purchase_event_id, target_amount, 'charge');
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (command_user_id, 'receivable_created', 'receivable', new_receivable_id,
      jsonb_build_object('source_event_id', purchase_event_id, 'contact_id', target_contact_id, 'amount_minor', target_amount::text));
  end loop;
end;
$$;

create function private.reverse_purchase_receivables(
  command_user_id uuid,
  purchase_event_id uuid,
  reversal_event_id uuid
)
returns void language plpgsql set search_path = '' as $$
declare
  target record;
  current_balance bigint;
begin
  for target in
    select receivable.*, entry.id as charge_entry_id
    from public.receivables receivable
    join public.receivable_entries entry on entry.receivable_id = receivable.id
      and entry.financial_event_id = purchase_event_id and entry.entry_kind = 'charge'
    where receivable.user_id = command_user_id and receivable.source_event_id = purchase_event_id
    order by receivable.id for update of receivable
  loop
    select coalesce(sum(amount_minor), 0) into current_balance
    from public.receivable_entries where receivable_id = target.id;
    if current_balance <> target.original_amount_minor then
      raise exception 'NEXO_RECEIVABLE_HAS_PAYMENTS' using errcode = '23514';
    end if;
    insert into public.receivable_entries (
      user_id, receivable_id, financial_event_id, amount_minor, entry_kind, reverses_entry_id
    ) values (
      command_user_id, target.id, reversal_event_id, -target.original_amount_minor, 'reversal', target.charge_entry_id
    );
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (command_user_id, 'receivable_reversed', 'receivable', target.id,
      jsonb_build_object('source_event_id', purchase_event_id, 'reversal_event_id', reversal_event_id));
  end loop;
end;
$$;

revoke all on function private.validate_purchase_split(uuid, bigint, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.create_purchase_receivables(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function private.reverse_purchase_receivables(uuid, uuid, uuid) from public, anon, authenticated;

create function public.create_contact(
  p_name text, p_email text, p_phone text, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_id uuid := gen_random_uuid();
  resolved_id uuid;
  payload jsonb := jsonb_build_object(
    'name', btrim(p_name), 'email', nullif(btrim(p_email), ''),
    'phone', nullif(btrim(p_phone), ''), 'notes', nullif(btrim(p_notes), '')
  );
begin
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key, 'create_contact', payload, proposed_id);
  if resolved_id <> proposed_id then return resolved_id; end if;
  insert into public.contacts (id, user_id, name, email, phone, notes)
  values (proposed_id, command_user_id, btrim(p_name), nullif(btrim(p_email), ''), nullif(btrim(p_phone), ''), nullif(btrim(p_notes), ''));
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_created', 'contact', proposed_id, payload);
  return proposed_id;
end;
$$;

create function public.update_contact(
  p_contact_id uuid, p_name text, p_email text, p_phone text, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  command_id uuid := gen_random_uuid();
  resolved_id uuid;
  payload jsonb := jsonb_build_object(
    'contact_id', p_contact_id, 'name', btrim(p_name), 'email', nullif(btrim(p_email), ''),
    'phone', nullif(btrim(p_phone), ''), 'notes', nullif(btrim(p_notes), '')
  );
begin
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key, 'update_contact', payload, command_id);
  if resolved_id <> command_id then return p_contact_id; end if;
  update public.contacts set name = btrim(p_name), email = nullif(btrim(p_email), ''),
    phone = nullif(btrim(p_phone), ''), notes = nullif(btrim(p_notes), '')
  where id = p_contact_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_updated', 'contact', p_contact_id, payload);
  return p_contact_id;
end;
$$;

create function public.set_contact_active(p_contact_id uuid, p_active boolean, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  command_id uuid := gen_random_uuid();
  resolved_id uuid;
  payload jsonb := jsonb_build_object('contact_id', p_contact_id, 'active', p_active);
begin
  resolved_id := private.resolve_financial_command(command_user_id, p_idempotency_key, 'set_contact_active', payload, command_id);
  if resolved_id <> command_id then return p_contact_id; end if;
  update public.contacts set is_active = p_active where id = p_contact_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, case when p_active then 'person_restored' else 'person_archived' end,
    'contact', p_contact_id, payload);
  return p_contact_id;
end;
$$;

revoke all on function public.create_contact(text, text, text, text, text) from public, anon;
revoke all on function public.update_contact(uuid, text, text, text, text, text) from public, anon;
revoke all on function public.set_contact_active(uuid, boolean, text) from public, anon;
grant execute on function public.create_contact(text, text, text, text, text) to authenticated;
grant execute on function public.update_contact(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.set_contact_active(uuid, boolean, text) to authenticated;

create function public.create_shared_account_purchase(
  p_account_id uuid,
  p_amount_minor bigint,
  p_personal_amount_minor bigint,
  p_allocations jsonb,
  p_description text,
  p_category_id text,
  p_occurred_on date,
  p_notes text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  target_account public.accounts%rowtype;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  select * into target_account from public.accounts
  where id = p_account_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_account.is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  perform private.validate_purchase_split(command_user_id, p_amount_minor, p_personal_amount_minor, p_allocations);
  payload := jsonb_build_object('account_id', p_account_id, 'amount_minor', p_amount_minor::text,
    'personal_amount_minor', p_personal_amount_minor::text, 'allocations', p_allocations,
    'description', normalized_description, 'category_id', p_category_id,
    'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_shared_account_purchase', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor, description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'expense', p_amount_minor, p_personal_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, p_account_id, -p_amount_minor);
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_account.currency, p_allocations);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'transaction_created', 'financial_event', proposed_event_id, payload);
  return proposed_event_id;
end;
$$;

create function public.update_shared_account_purchase(
  p_event_id uuid,
  p_amount_minor bigint,
  p_personal_amount_minor bigint,
  p_allocations jsonb,
  p_description text,
  p_category_id text,
  p_occurred_on date,
  p_notes text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  proposed_event_id uuid := gen_random_uuid();
  reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid;
  original_event public.financial_events%rowtype;
  target_account public.accounts%rowtype;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  payload jsonb;
begin
  select * into original_event from public.financial_events
  where id = p_event_id and user_id = command_user_id and kind = 'expense' for update;
  if not found then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  select account.* into strict target_account from public.account_entries entry
  join public.accounts account on account.id = entry.account_id
  where entry.financial_event_id = p_event_id and entry.user_id = command_user_id;
  perform private.validate_purchase_split(command_user_id, p_amount_minor, p_personal_amount_minor, p_allocations);
  payload := jsonb_build_object('event_id', p_event_id, 'amount_minor', p_amount_minor::text,
    'personal_amount_minor', p_personal_amount_minor::text, 'allocations', p_allocations,
    'description', normalized_description, 'category_id', p_category_id,
    'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_shared_account_purchase', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  perform private.reverse_event(command_user_id, p_event_id, reversal_event_id, 'Reversión por edición');
  perform private.reverse_purchase_receivables(command_user_id, p_event_id, reversal_event_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  select command_user_id, 'receivable_updated', 'receivable', receivable.id,
    jsonb_build_object('replaced_source_event_id', p_event_id, 'replacement_event_id', proposed_event_id)
  from public.receivables receivable where receivable.source_event_id = p_event_id and receivable.user_id = command_user_id;
  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor, description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'expense', p_amount_minor, p_personal_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, target_account.id, -p_amount_minor);
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_account.currency, p_allocations);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'transaction_updated', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('replaces_event_id', p_event_id, 'reversal_event_id', reversal_event_id));
  return proposed_event_id;
end;
$$;

revoke all on function public.create_shared_account_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text) from public, anon;
revoke all on function public.update_shared_account_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text) from public, anon;
grant execute on function public.create_shared_account_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text) to authenticated;
grant execute on function public.update_shared_account_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text) to authenticated;

create function public.create_shared_card_purchase(
  p_card_id uuid, p_amount_minor bigint, p_personal_amount_minor bigint, p_allocations jsonb,
  p_description text, p_category_id text, p_occurred_on date, p_payment_method text,
  p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; target_card public.credit_cards%rowtype; baseline_date date;
  assigned_statement_date date; normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), ''); normalized_method text := nullif(btrim(p_payment_method), '');
  payload jsonb;
begin
  select * into target_card from public.credit_cards where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  assigned_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (select 1 from public.card_statements where card_id = p_card_id and statement_date = assigned_statement_date)
  then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  perform private.validate_purchase_split(command_user_id, p_amount_minor, p_personal_amount_minor, p_allocations);
  payload := jsonb_build_object('card_id', p_card_id, 'amount_minor', p_amount_minor::text,
    'personal_amount_minor', p_personal_amount_minor::text, 'allocations', p_allocations,
    'description', normalized_description, 'category_id', p_category_id, 'occurred_on', p_occurred_on,
    'payment_method', normalized_method, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_shared_card_purchase', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'card_charge', p_amount_minor, p_personal_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes);
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, p_amount_minor, 'impacting');
  insert into public.card_transaction_details (financial_event_id, user_id, card_id, payment_method, statement_date)
  values (proposed_event_id, command_user_id, p_card_id, normalized_method, assigned_statement_date);
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_card.currency, p_allocations);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_created', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('statement_date', assigned_statement_date));
  return proposed_event_id;
end;
$$;

create function public.update_shared_card_purchase(
  p_event_id uuid, p_card_id uuid, p_amount_minor bigint, p_personal_amount_minor bigint,
  p_allocations jsonb, p_description text, p_category_id text, p_occurred_on date,
  p_payment_method text, p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_event_id uuid := gen_random_uuid();
  reversal_event_id uuid := gen_random_uuid(); resolved_event_id uuid;
  original_detail public.card_transaction_details%rowtype; target_card public.credit_cards%rowtype;
  baseline_date date; assigned_statement_date date; normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), ''); normalized_method text := nullif(btrim(p_payment_method), '');
  payload jsonb;
begin
  perform 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'card_charge' for update;
  if not found then raise exception 'NEXO_CARD_PURCHASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (select 1 from public.installment_plans where purchase_event_id = p_event_id and status = 'active')
  then raise exception 'NEXO_INSTALLMENT_PURCHASE_REQUIRES_PLAN_FLOW' using errcode = '23514'; end if;
  select * into strict original_detail from public.card_transaction_details
  where financial_event_id = p_event_id and user_id = command_user_id;
  if exists (select 1 from public.card_statements where card_id = original_detail.card_id and statement_date = original_detail.statement_date)
  then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  select * into target_card from public.credit_cards where id = p_card_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_card.is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  select baseline.baseline_date into strict baseline_date from public.card_baselines baseline
  where baseline.card_id = p_card_id and baseline.user_id = command_user_id;
  if p_occurred_on < baseline_date then raise exception 'NEXO_EVENT_BEFORE_BASELINE' using errcode = '22023'; end if;
  assigned_statement_date := public.card_statement_for_date(p_occurred_on, target_card.statement_day);
  if exists (select 1 from public.card_statements where card_id = p_card_id and statement_date = assigned_statement_date)
  then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  perform private.validate_purchase_split(command_user_id, p_amount_minor, p_personal_amount_minor, p_allocations);
  payload := jsonb_build_object('event_id', p_event_id, 'card_id', p_card_id,
    'amount_minor', p_amount_minor::text, 'personal_amount_minor', p_personal_amount_minor::text,
    'allocations', p_allocations, 'description', normalized_description, 'category_id', p_category_id,
    'occurred_on', p_occurred_on, 'payment_method', normalized_method, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'update_shared_card_purchase', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión por edición de compra');
  perform private.reverse_purchase_receivables(command_user_id, p_event_id, reversal_event_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  select command_user_id, 'receivable_updated', 'receivable', receivable.id,
    jsonb_build_object('replaced_source_event_id', p_event_id, 'replacement_event_id', proposed_event_id)
  from public.receivables receivable where receivable.source_event_id = p_event_id and receivable.user_id = command_user_id;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'card_charge', p_amount_minor, p_personal_amount_minor,
    normalized_description, p_category_id, p_occurred_on, normalized_notes);
  insert into public.card_entries (user_id, financial_event_id, card_id, amount_minor, effect_scope)
  values (command_user_id, proposed_event_id, p_card_id, p_amount_minor, 'impacting');
  insert into public.card_transaction_details (financial_event_id, user_id, card_id, payment_method, statement_date, related_event_id)
  values (proposed_event_id, command_user_id, p_card_id, normalized_method, assigned_statement_date, p_event_id);
  perform private.create_purchase_receivables(command_user_id, proposed_event_id, target_card.currency, p_allocations);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_updated', 'financial_event', proposed_event_id,
    payload || jsonb_build_object('replaces_event_id', p_event_id, 'reversal_event_id', reversal_event_id,
      'statement_date', assigned_statement_date));
  return proposed_event_id;
end;
$$;

revoke all on function public.create_shared_card_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text, text) from public, anon;
revoke all on function public.update_shared_card_purchase(uuid, uuid, bigint, bigint, jsonb, text, text, date, text, text, text) from public, anon;
grant execute on function public.create_shared_card_purchase(uuid, bigint, bigint, jsonb, text, text, date, text, text, text) to authenticated;
grant execute on function public.update_shared_card_purchase(uuid, uuid, bigint, bigint, jsonb, text, text, date, text, text, text) to authenticated;

create or replace function public.reverse_transaction(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_reversal_id uuid := gen_random_uuid();
  resolved_reversal_id uuid; original_kind text; payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  resolved_reversal_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_transaction', payload, proposed_reversal_id);
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;
  select kind into original_kind from public.financial_events where id = p_event_id and user_id = command_user_id;
  if original_kind is null then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_kind not in ('income', 'expense', 'adjustment') then
    raise exception 'NEXO_TRANSACTION_NOT_REVERSIBLE' using errcode = '23514'; end if;
  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión de movimiento');
  perform private.reverse_purchase_receivables(command_user_id, p_event_id, proposed_reversal_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'transaction_deleted', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', proposed_reversal_id));
  return proposed_reversal_id;
end;
$$;

create or replace function public.reverse_card_purchase(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; detail public.card_transaction_details%rowtype;
  payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  select * into detail from public.card_transaction_details where financial_event_id = p_event_id and user_id = command_user_id;
  if not found or not exists (select 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'card_charge')
  then raise exception 'NEXO_CARD_PURCHASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (select 1 from public.installment_plans where purchase_event_id = p_event_id and status = 'active')
  then raise exception 'NEXO_INSTALLMENT_PURCHASE_REQUIRES_PLAN_FLOW' using errcode = '23514'; end if;
  if exists (select 1 from public.card_statements where card_id = detail.card_id and statement_date = detail.statement_date)
  then raise exception 'NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED' using errcode = '23514'; end if;
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_card_purchase', payload, reversal_event_id);
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_card_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de compra con tarjeta');
  perform private.reverse_purchase_receivables(command_user_id, p_event_id, reversal_event_id);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'card_purchase_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
$$;

create function public.create_person_payment(
  p_contact_id uuid, p_account_id uuid, p_amount_minor bigint, p_occurred_on date,
  p_notes text, p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); proposed_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; target_contact public.contacts%rowtype; target_account public.accounts%rowtype;
  remaining_amount bigint := p_amount_minor; total_outstanding bigint; allocation_amount bigint;
  target_receivable record; normalized_notes text := nullif(btrim(p_notes), ''); payload jsonb;
begin
  if p_amount_minor <= 0 then raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023'; end if;
  select * into target_contact from public.contacts where id = p_contact_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into target_account from public.accounts where id = p_account_id and user_id = command_user_id for update;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not target_account.is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  perform 1 from public.receivables where user_id = command_user_id and contact_id = p_contact_id
    and currency = target_account.currency for update;
  select coalesce(sum(balance.amount_minor), 0) into total_outstanding
  from (
    select receivable.id, coalesce(sum(entry.amount_minor), 0) amount_minor
    from public.receivables receivable join public.receivable_entries entry on entry.receivable_id = receivable.id
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
      and receivable.currency = target_account.currency
    group by receivable.id
  ) balance;
  if p_amount_minor > total_outstanding then
    raise exception 'NEXO_PERSON_PAYMENT_EXCEEDS_BALANCE' using errcode = '23514';
  end if;
  payload := jsonb_build_object('contact_id', p_contact_id, 'account_id', p_account_id,
    'amount_minor', p_amount_minor::text, 'occurred_on', p_occurred_on, 'notes', normalized_notes);
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'create_person_payment', payload, proposed_event_id);
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on, notes)
  values (proposed_event_id, command_user_id, 'person_payment', p_amount_minor, 0,
    'Pago recibido de ' || target_contact.name, p_occurred_on, normalized_notes);
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, p_account_id, p_amount_minor);
  for target_receivable in
    select receivable.id, coalesce(sum(entry.amount_minor), 0) outstanding_minor
    from public.receivables receivable join public.receivable_entries entry on entry.receivable_id = receivable.id
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
      and receivable.currency = target_account.currency
    group by receivable.id, receivable.occurred_on, receivable.created_at
    having coalesce(sum(entry.amount_minor), 0) > 0
    order by receivable.occurred_on, receivable.created_at, receivable.id
  loop
    exit when remaining_amount = 0;
    allocation_amount := least(remaining_amount, target_receivable.outstanding_minor);
    insert into public.receivable_entries (user_id, receivable_id, financial_event_id, amount_minor, entry_kind)
    values (command_user_id, target_receivable.id, proposed_event_id, -allocation_amount, 'payment');
    remaining_amount := remaining_amount - allocation_amount;
    insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
    values (command_user_id, 'receivable_paid', 'receivable', target_receivable.id,
      jsonb_build_object('payment_event_id', proposed_event_id, 'amount_minor', allocation_amount::text));
  end loop;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_payment_recorded', 'financial_event', proposed_event_id, payload);
  return proposed_event_id;
end;
$$;

create function public.reverse_person_payment(p_event_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); reversal_event_id uuid := gen_random_uuid();
  resolved_event_id uuid; payment_entry record; payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  perform 1 from public.financial_events where id = p_event_id and user_id = command_user_id and kind = 'person_payment' for update;
  if not found then raise exception 'NEXO_PERSON_PAYMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  resolved_event_id := private.resolve_financial_command(command_user_id, p_idempotency_key,
    'reverse_person_payment', payload, reversal_event_id);
  if resolved_event_id <> reversal_event_id then return resolved_event_id; end if;
  perform private.reverse_event(command_user_id, p_event_id, reversal_event_id, 'Reversión de pago recibido');
  for payment_entry in select * from public.receivable_entries
    where financial_event_id = p_event_id and user_id = command_user_id and entry_kind = 'payment' for update
  loop
    insert into public.receivable_entries (user_id, receivable_id, financial_event_id, amount_minor, entry_kind, reverses_entry_id)
    values (command_user_id, payment_entry.receivable_id, reversal_event_id, -payment_entry.amount_minor,
      'reversal', payment_entry.id);
  end loop;
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'person_payment_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', reversal_event_id));
  return reversal_event_id;
end;
$$;

revoke all on function public.create_person_payment(uuid, uuid, bigint, date, text, text) from public, anon;
revoke all on function public.reverse_person_payment(uuid, text) from public, anon;
grant execute on function public.create_person_payment(uuid, uuid, bigint, date, text, text) to authenticated;
grant execute on function public.reverse_person_payment(uuid, text) to authenticated;

create view public.receivable_balances with (security_invoker = true) as
select receivable.id, receivable.user_id, receivable.contact_id, contact.name as contact_name,
  receivable.source_event_id, event.kind as source_kind, event.description,
  receivable.original_amount_minor, coalesce(sum(entry.amount_minor), 0)::bigint as outstanding_minor,
  (receivable.original_amount_minor - coalesce(sum(entry.amount_minor), 0))::bigint as paid_minor,
  receivable.currency, receivable.occurred_on, receivable.created_at,
  case when coalesce(sum(entry.amount_minor), 0) = 0 then 'paid' else 'open' end as status
from public.receivables receivable
join public.contacts contact on contact.id = receivable.contact_id
join public.financial_events event on event.id = receivable.source_event_id
join public.receivable_entries entry on entry.receivable_id = receivable.id
group by receivable.id, contact.name, event.kind, event.description;

create view public.contact_balance_summary with (security_invoker = true) as
select contact.id, contact.user_id, contact.name, contact.email, contact.phone, contact.notes,
  contact.is_active, contact.created_at, contact.updated_at,
  coalesce(balance.balances, '[]'::jsonb) as balances,
  activity.last_activity_on, activity.last_activity_description
from public.contacts contact
left join lateral (
  select jsonb_agg(jsonb_build_object('currency', grouped.currency,
    'outstanding_minor', grouped.outstanding_minor::text) order by grouped.currency) as balances
  from (
    select receivable.currency, sum(entry.amount_minor)::bigint as outstanding_minor
    from public.receivables receivable join public.receivable_entries entry on entry.receivable_id = receivable.id
    where receivable.contact_id = contact.id group by receivable.currency
    having sum(entry.amount_minor) <> 0
  ) grouped
) balance on true
left join lateral (
  select event.occurred_on as last_activity_on, event.description as last_activity_description
  from public.receivable_entries entry join public.financial_events event on event.id = entry.financial_event_id
  join public.receivables receivable on receivable.id = entry.receivable_id
  where receivable.contact_id = contact.id order by event.occurred_on desc, event.created_at desc limit 1
) activity on true;

create view public.contact_activity with (security_invoker = true) as
select event.id as event_id, receivable.contact_id, event.user_id, event.kind,
  sum(entry.amount_minor)::bigint as amount_minor, event.description, event.occurred_on,
  event.notes, event.created_at, receivable.currency,
  case when event.kind = 'person_payment' then 'payment' else 'purchase' end as activity_type
from public.receivable_entries entry
join public.receivables receivable on receivable.id = entry.receivable_id
join public.financial_events event on event.id = entry.financial_event_id
where event.kind <> 'reversal'
  and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id)
group by event.id, receivable.contact_id, receivable.currency;

create view public.purchase_allocation_details with (security_invoker = true) as
select allocation.financial_event_id, allocation.user_id,
  jsonb_agg(jsonb_build_object('contact_id', contact.id, 'contact_name', contact.name,
    'amount_minor', allocation.amount_minor::text) order by contact.name) as allocations
from public.purchase_allocations allocation join public.contacts contact on contact.id = allocation.contact_id
group by allocation.financial_event_id, allocation.user_id;

create view public.person_payment_activity with (security_invoker = true) as
select event.id as event_id, event.user_id, event.kind, event.amount_minor, event.personal_amount_minor,
  event.description, null::text as category_id, null::text as category_name, event.occurred_on,
  event.notes, event.created_at, 'account'::text as source_type, account.id as account_id,
  null::uuid as card_id, account.name as source_name, account.institution as source_detail,
  account.currency, entry.amount_minor as signed_amount_minor, null::text as payment_method,
  null::date as statement_date, null::uuid as related_event_id, account.is_active as source_is_active,
  null::uuid as source_account_id, null::text as source_account_name, null::uuid as destination_account_id,
  null::uuid as installment_plan_id, null::integer as installment_count,
  null::bigint as installment_amount_minor, null::text as installment_plan_status,
  null::text as installment_description, null::text as installment_category_id,
  null::text as installment_category_name, null::text as installment_notes,
  null::text as installment_origin
from public.financial_events event
join public.account_entries entry on entry.financial_event_id = event.id
join public.accounts account on account.id = entry.account_id
where event.kind = 'person_payment'
  and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id);

revoke all on table public.receivable_balances, public.contact_balance_summary,
  public.contact_activity, public.purchase_allocation_details, public.person_payment_activity from anon, authenticated;
grant select on table public.receivable_balances, public.contact_balance_summary,
  public.contact_activity, public.purchase_allocation_details, public.person_payment_activity to authenticated;
grant all on table public.receivable_balances, public.contact_balance_summary,
  public.contact_activity, public.purchase_allocation_details, public.person_payment_activity to service_role;
