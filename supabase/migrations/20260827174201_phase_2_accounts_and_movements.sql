-- Nexo Phase 2: accounts, immutable financial events and atomic account entries.
-- Credit cards, statements, installments, contacts, receivables and budgets are
-- intentionally outside this migration.

create table public.categories (
  id text primary key,
  name text not null,
  kind text not null,
  icon text not null,
  sort_order smallint not null,
  created_at timestamptz not null default now(),
  constraint categories_id_format check (id ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint categories_name_not_blank check (char_length(btrim(name)) between 1 and 60),
  constraint categories_kind_valid check (kind in ('expense', 'income', 'both')),
  constraint categories_icon_not_blank check (char_length(btrim(icon)) between 1 and 40),
  constraint categories_sort_order_nonnegative check (sort_order >= 0)
);

insert into public.categories (id, name, kind, icon, sort_order)
values
  ('food', 'Comida', 'expense', 'utensils', 10),
  ('transport', 'Transporte', 'expense', 'car', 20),
  ('entertainment', 'Entretenimiento', 'expense', 'sparkles', 30),
  ('home', 'Casa', 'expense', 'house', 40),
  ('health', 'Salud', 'expense', 'heart-pulse', 50),
  ('technology', 'Tecnología', 'expense', 'laptop', 60),
  ('subscriptions', 'Suscripciones', 'expense', 'repeat', 70),
  ('other_expense', 'Otros', 'expense', 'ellipsis', 80),
  ('salary', 'Salario', 'income', 'briefcase-business', 90),
  ('other_income', 'Otros ingresos', 'income', 'circle-plus', 100),
  ('adjustment', 'Ajuste', 'both', 'sliders-horizontal', 110);

comment on table public.categories is
  'Small read-only system catalogue for Phase 2 movements; custom categories are future scope.';

alter table public.categories enable row level security;
revoke all on table public.categories from anon, authenticated;
grant select on table public.categories to authenticated;
grant all on table public.categories to service_role;

create policy "Categories are readable by authenticated users"
on public.categories
for select
to authenticated
using (true);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  type text not null,
  currency text not null references public.currencies (code),
  opening_balance_minor bigint not null default 0,
  institution text,
  last4 text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_name_not_blank check (char_length(btrim(name)) between 1 and 80),
  constraint accounts_type_valid check (type in ('checking', 'savings', 'cash', 'debit', 'investment', 'other')),
  constraint accounts_institution_length check (institution is null or char_length(btrim(institution)) between 1 and 100),
  constraint accounts_last4_format check (last4 is null or last4 ~ '^\d{4}$')
);

comment on column public.accounts.opening_balance_minor is
  'Original account baseline in minor units. Current balance is reconstructed from immutable entries.';

create index accounts_user_active_created_idx
  on public.accounts (user_id, is_active, created_at desc);

alter table public.accounts enable row level security;
revoke all on table public.accounts from anon, authenticated;
grant select on table public.accounts to authenticated;
grant all on table public.accounts to service_role;

create policy "Users can read their own accounts"
on public.accounts
for select
to authenticated
using ((select auth.uid()) = user_id);

create table public.financial_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  amount_minor bigint not null,
  personal_amount_minor bigint not null default 0,
  description text not null,
  category_id text references public.categories (id),
  occurred_on date not null,
  notes text,
  reverses_event_id uuid unique references public.financial_events (id),
  created_at timestamptz not null default now(),
  constraint financial_events_kind_valid check (kind in ('opening', 'income', 'expense', 'adjustment', 'transfer', 'reversal')),
  constraint financial_events_description_not_blank check (char_length(btrim(description)) between 1 and 160),
  constraint financial_events_notes_length check (notes is null or char_length(notes) <= 2000),
  constraint financial_events_amount_valid check (
    (kind in ('income', 'expense', 'transfer', 'reversal') and amount_minor > 0)
    or (kind in ('opening', 'adjustment') and amount_minor <> 0)
  ),
  constraint financial_events_personal_amount_valid check (
    personal_amount_minor >= 0
    and (
      (kind = 'expense' and personal_amount_minor = amount_minor)
      or (kind <> 'expense' and personal_amount_minor = 0)
    )
  ),
  constraint financial_events_reversal_link_valid check (
    (kind = 'reversal' and reverses_event_id is not null)
    or (kind <> 'reversal' and reverses_event_id is null)
  )
);

create index financial_events_user_occurred_idx
  on public.financial_events (user_id, occurred_on desc, created_at desc);
create index financial_events_user_kind_occurred_idx
  on public.financial_events (user_id, kind, occurred_on desc);

alter table public.financial_events enable row level security;
revoke all on table public.financial_events from anon, authenticated;
grant select on table public.financial_events to authenticated;
grant all on table public.financial_events to service_role;

create policy "Users can read their own financial events"
on public.financial_events
for select
to authenticated
using ((select auth.uid()) = user_id);

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  account_id uuid not null references public.accounts (id) on delete restrict,
  amount_minor bigint not null,
  created_at timestamptz not null default now(),
  constraint account_entries_amount_nonzero check (amount_minor <> 0),
  constraint account_entries_event_account_unique unique (financial_event_id, account_id)
);

comment on table public.account_entries is
  'Immutable signed account deltas. Their sum is the single source of truth for account balances.';

create index account_entries_user_account_created_idx
  on public.account_entries (user_id, account_id, created_at desc);
create index account_entries_financial_event_idx
  on public.account_entries (financial_event_id);

alter table public.account_entries enable row level security;
revoke all on table public.account_entries from anon, authenticated;
grant select on table public.account_entries to authenticated;
grant all on table public.account_entries to service_role;

create policy "Users can read their own account entries"
on public.account_entries
for select
to authenticated
using ((select auth.uid()) = user_id);

create table public.financial_commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  idempotency_key text not null,
  command_type text not null,
  payload jsonb not null,
  result_id uuid not null,
  created_at timestamptz not null default now(),
  constraint financial_commands_key_length check (char_length(idempotency_key) between 8 and 200),
  constraint financial_commands_type_length check (char_length(command_type) between 1 and 80),
  constraint financial_commands_user_key_unique unique (user_id, idempotency_key)
);

create index financial_commands_user_created_idx
  on public.financial_commands (user_id, created_at desc);

alter table public.financial_commands enable row level security;
revoke all on table public.financial_commands from anon, authenticated;
grant all on table public.financial_commands to service_role;

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  action text not null,
  entity_type text not null,
  entity_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint audit_events_action_length check (char_length(action) between 1 and 80),
  constraint audit_events_entity_type_length check (char_length(entity_type) between 1 and 60)
);

create index audit_events_user_created_idx
  on public.audit_events (user_id, created_at desc);

alter table public.audit_events enable row level security;
revoke all on table public.audit_events from anon, authenticated;
grant select on table public.audit_events to authenticated;
grant all on table public.audit_events to service_role;

create policy "Users can read their own audit events"
on public.audit_events
for select
to authenticated
using ((select auth.uid()) = user_id);

create table public.financial_event_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  financial_event_id uuid not null references public.financial_events (id) on delete restrict,
  notes text,
  created_at timestamptz not null default now(),
  constraint financial_event_notes_length check (notes is null or char_length(notes) <= 2000)
);

create index financial_event_notes_event_created_idx
  on public.financial_event_notes (financial_event_id, created_at desc);
create index financial_event_notes_user_created_idx
  on public.financial_event_notes (user_id, created_at desc);

alter table public.financial_event_notes enable row level security;
revoke all on table public.financial_event_notes from anon, authenticated;
grant select on table public.financial_event_notes to authenticated;
grant all on table public.financial_event_notes to service_role;

create policy "Users can read their own financial event notes"
on public.financial_event_notes
for select
to authenticated
using ((select auth.uid()) = user_id);

create function private.reject_financial_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'NEXO_IMMUTABLE_FINANCIAL_RECORD' using errcode = '23514';
end;
$$;

revoke all on function private.reject_financial_mutation() from public, anon, authenticated;

create trigger financial_events_are_immutable
before update or delete on public.financial_events
for each row execute function private.reject_financial_mutation();

create trigger account_entries_are_immutable
before update or delete on public.account_entries
for each row execute function private.reject_financial_mutation();

create trigger financial_commands_are_immutable
before update or delete on public.financial_commands
for each row execute function private.reject_financial_mutation();

create trigger audit_events_are_immutable
before update or delete on public.audit_events
for each row execute function private.reject_financial_mutation();

create trigger financial_event_notes_are_immutable
before update or delete on public.financial_event_notes
for each row execute function private.reject_financial_mutation();

create trigger accounts_set_updated_at
before update on public.accounts
for each row execute function private.set_updated_at();

create function private.resolve_financial_command(
  command_user_id uuid,
  command_key text,
  requested_type text,
  requested_payload jsonb,
  proposed_result_id uuid
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  existing_command public.financial_commands%rowtype;
begin
  if command_key is null or char_length(command_key) not between 8 and 200 then
    raise exception 'NEXO_INVALID_IDEMPOTENCY_KEY' using errcode = '22023';
  end if;

  insert into public.financial_commands (
    user_id, idempotency_key, command_type, payload, result_id
  ) values (
    command_user_id, command_key, requested_type, requested_payload, proposed_result_id
  )
  on conflict (user_id, idempotency_key) do nothing
  returning * into existing_command;

  if found then
    return proposed_result_id;
  end if;

  select * into strict existing_command
  from public.financial_commands
  where user_id = command_user_id and idempotency_key = command_key;

  if existing_command.command_type <> requested_type
    or existing_command.payload <> requested_payload then
    raise exception 'NEXO_IDEMPOTENCY_CONFLICT' using errcode = '22023';
  end if;

  return existing_command.result_id;
end;
$$;

revoke all on function private.resolve_financial_command(uuid, text, text, jsonb, uuid)
  from public, anon, authenticated;

create function private.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'NEXO_AUTH_REQUIRED' using errcode = '42501';
  end if;
  return current_user_id;
end;
$$;

revoke all on function private.require_user() from public, anon, authenticated;

create function public.create_account(
  p_name text,
  p_type text,
  p_currency text,
  p_opening_balance_minor bigint,
  p_institution text,
  p_last4 text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_account_id uuid := gen_random_uuid();
  resolved_account_id uuid;
  opening_event_id uuid;
  normalized_name text := btrim(p_name);
  normalized_institution text := nullif(btrim(p_institution), '');
  normalized_last4 text := nullif(btrim(p_last4), '');
  command_payload jsonb;
begin
  command_payload := jsonb_build_object(
    'name', normalized_name,
    'type', p_type,
    'currency', p_currency,
    'opening_balance_minor', p_opening_balance_minor::text,
    'institution', normalized_institution,
    'last4', normalized_last4
  );
  resolved_account_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_account', command_payload, proposed_account_id
  );
  if resolved_account_id <> proposed_account_id then return resolved_account_id; end if;

  insert into public.accounts (
    id, user_id, name, type, currency, opening_balance_minor, institution, last4
  ) values (
    proposed_account_id, command_user_id, normalized_name, p_type, p_currency,
    p_opening_balance_minor, normalized_institution, normalized_last4
  );

  if p_opening_balance_minor <> 0 then
    opening_event_id := gen_random_uuid();
    insert into public.financial_events (
      id, user_id, kind, amount_minor, description, occurred_on
    ) values (
      opening_event_id, command_user_id, 'opening', p_opening_balance_minor,
      'Saldo inicial de ' || normalized_name, current_date
    );
    insert into public.account_entries (
      user_id, financial_event_id, account_id, amount_minor
    ) values (
      command_user_id, opening_event_id, proposed_account_id, p_opening_balance_minor
    );
  end if;

  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'account_created', 'account', proposed_account_id, command_payload);

  return proposed_account_id;
end;
$$;

create function public.update_account(
  p_account_id uuid,
  p_name text,
  p_type text,
  p_institution text,
  p_last4 text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  normalized_name text := btrim(p_name);
  normalized_institution text := nullif(btrim(p_institution), '');
  normalized_last4 text := nullif(btrim(p_last4), '');
  command_payload jsonb;
begin
  command_payload := jsonb_build_object(
    'account_id', p_account_id,
    'name', normalized_name,
    'type', p_type,
    'institution', normalized_institution,
    'last4', normalized_last4
  );
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_account', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_account_id; end if;

  update public.accounts
  set name = normalized_name,
      type = p_type,
      institution = normalized_institution,
      last4 = normalized_last4
  where id = p_account_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;

  insert into public.audit_events (id, user_id, action, entity_type, entity_id, metadata)
  values (proposed_command_result_id, command_user_id, 'account_updated', 'account', p_account_id, command_payload);
  return p_account_id;
end;
$$;

create function public.archive_account(p_account_id uuid, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('account_id', p_account_id);
begin
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'archive_account', command_payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_account_id; end if;

  update public.accounts set is_active = false
  where id = p_account_id and user_id = command_user_id and is_active;
  if not found and not exists (
    select 1 from public.accounts where id = p_account_id and user_id = command_user_id
  ) then
    raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into public.audit_events (id, user_id, action, entity_type, entity_id)
  values (proposed_command_result_id, command_user_id, 'account_archived', 'account', p_account_id);
  return p_account_id;
end;
$$;

create function public.create_transaction(
  p_account_id uuid,
  p_kind text,
  p_amount_minor bigint,
  p_description text,
  p_category_id text,
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
  account_is_active boolean;
  signed_amount bigint;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  command_payload jsonb;
begin
  if p_kind not in ('income', 'expense', 'adjustment') then
    raise exception 'NEXO_INVALID_TRANSACTION_KIND' using errcode = '22023';
  end if;
  if (p_kind in ('income', 'expense') and p_amount_minor <= 0)
    or (p_kind = 'adjustment' and p_amount_minor = 0) then
    raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023';
  end if;

  command_payload := jsonb_build_object(
    'account_id', p_account_id,
    'kind', p_kind,
    'amount_minor', p_amount_minor::text,
    'description', normalized_description,
    'category_id', p_category_id,
    'occurred_on', p_occurred_on,
    'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_transaction', command_payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;

  select is_active into account_is_active
  from public.accounts
  where id = p_account_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not account_is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;

  signed_amount := case
    when p_kind = 'expense' then -p_amount_minor
    else p_amount_minor
  end;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, p_kind, p_amount_minor,
    case when p_kind = 'expense' then p_amount_minor else 0 end,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_event_id, p_account_id, signed_amount);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'transaction_created', 'financial_event', proposed_event_id, command_payload);
  return proposed_event_id;
end;
$$;

create function public.create_transfer(
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount_minor bigint,
  p_description text,
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
  account_count integer;
  currency_count integer;
  active_count integer;
  normalized_description text := coalesce(nullif(btrim(p_description), ''), 'Transferencia');
  normalized_notes text := nullif(btrim(p_notes), '');
  command_payload jsonb;
begin
  if p_from_account_id = p_to_account_id then
    raise exception 'NEXO_TRANSFER_SAME_ACCOUNT' using errcode = '22023';
  end if;
  if p_amount_minor <= 0 then
    raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023';
  end if;

  command_payload := jsonb_build_object(
    'from_account_id', p_from_account_id,
    'to_account_id', p_to_account_id,
    'amount_minor', p_amount_minor::text,
    'description', normalized_description,
    'occurred_on', p_occurred_on,
    'notes', normalized_notes
  );
  resolved_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'create_transfer', command_payload, proposed_event_id
  );
  if resolved_event_id <> proposed_event_id then return resolved_event_id; end if;

  perform 1
  from public.accounts
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

  insert into public.financial_events (
    id, user_id, kind, amount_minor, description, occurred_on, notes
  ) values (
    proposed_event_id, command_user_id, 'transfer', p_amount_minor,
    normalized_description, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values
    (command_user_id, proposed_event_id, p_from_account_id, -p_amount_minor),
    (command_user_id, proposed_event_id, p_to_account_id, p_amount_minor);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (command_user_id, 'transfer_created', 'financial_event', proposed_event_id, command_payload);
  return proposed_event_id;
end;
$$;

create function private.reverse_event(
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
  if not found then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_event.kind in ('opening', 'reversal') then
    raise exception 'NEXO_TRANSACTION_NOT_REVERSIBLE' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.financial_events where reverses_event_id = original_event_id
  ) then
    raise exception 'NEXO_TRANSACTION_ALREADY_REVERSED' using errcode = '23505';
  end if;

  insert into public.financial_events (
    id, user_id, kind, amount_minor, description, occurred_on, notes, reverses_event_id
  ) values (
    reversal_event_id, command_user_id, 'reversal', abs(original_event.amount_minor),
    reversal_description, current_date, original_event.notes, original_event_id
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  select command_user_id, reversal_event_id, account_id, -amount_minor
  from public.account_entries
  where financial_event_id = original_event_id and user_id = command_user_id;
end;
$$;

revoke all on function private.reverse_event(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function public.reverse_transaction(
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
  if original_kind = 'transfer' then raise exception 'NEXO_USE_TRANSFER_REVERSAL' using errcode = '23514'; end if;

  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión de movimiento');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transaction_reverted', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', proposed_reversal_id)
  );
  return proposed_reversal_id;
end;
$$;

create function public.reverse_transfer(
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
    command_user_id, p_idempotency_key, 'reverse_transfer', command_payload, proposed_reversal_id
  );
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;

  select kind into original_kind from public.financial_events
  where id = p_event_id and user_id = command_user_id;
  if original_kind is distinct from 'transfer' then
    raise exception 'NEXO_TRANSFER_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión de transferencia');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transfer_reversed', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', proposed_reversal_id)
  );
  return proposed_reversal_id;
end;
$$;

create function public.update_transaction(
  p_event_id uuid,
  p_amount_minor bigint,
  p_description text,
  p_category_id text,
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
  proposed_new_event_id uuid := gen_random_uuid();
  proposed_reversal_id uuid := gen_random_uuid();
  resolved_new_event_id uuid;
  original_event public.financial_events%rowtype;
  original_account_id uuid;
  signed_amount bigint;
  normalized_description text := btrim(p_description);
  normalized_notes text := nullif(btrim(p_notes), '');
  command_payload jsonb;
begin
  command_payload := jsonb_build_object(
    'event_id', p_event_id,
    'amount_minor', p_amount_minor::text,
    'description', normalized_description,
    'category_id', p_category_id,
    'occurred_on', p_occurred_on,
    'notes', normalized_notes
  );
  resolved_new_event_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_transaction', command_payload, proposed_new_event_id
  );
  if resolved_new_event_id <> proposed_new_event_id then return resolved_new_event_id; end if;

  select * into original_event from public.financial_events
  where id = p_event_id and user_id = command_user_id
  for update;
  if not found then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_event.kind not in ('income', 'expense', 'adjustment') then
    raise exception 'NEXO_TRANSACTION_NOT_EDITABLE' using errcode = '23514';
  end if;
  if (original_event.kind in ('income', 'expense') and p_amount_minor <= 0)
    or (original_event.kind = 'adjustment' and p_amount_minor = 0) then
    raise exception 'NEXO_INVALID_AMOUNT' using errcode = '22023';
  end if;

  select account_id into strict original_account_id
  from public.account_entries
  where financial_event_id = p_event_id and user_id = command_user_id;

  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión por edición');
  signed_amount := case when original_event.kind = 'expense' then -p_amount_minor else p_amount_minor end;
  insert into public.financial_events (
    id, user_id, kind, amount_minor, personal_amount_minor,
    description, category_id, occurred_on, notes
  ) values (
    proposed_new_event_id, command_user_id, original_event.kind, p_amount_minor,
    case when original_event.kind = 'expense' then p_amount_minor else 0 end,
    normalized_description, p_category_id, p_occurred_on, normalized_notes
  );
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values (command_user_id, proposed_new_event_id, original_account_id, signed_amount);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transaction_updated', 'financial_event', proposed_new_event_id,
    jsonb_build_object('replaces_event_id', p_event_id, 'reversal_event_id', proposed_reversal_id)
  );
  return proposed_new_event_id;
end;
$$;

create function public.update_transfer_notes(
  p_event_id uuid,
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
  proposed_note_id uuid := gen_random_uuid();
  resolved_note_id uuid;
  normalized_notes text := nullif(btrim(p_notes), '');
  command_payload jsonb := jsonb_build_object('event_id', p_event_id, 'notes', normalized_notes);
begin
  resolved_note_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'update_transfer_notes', command_payload, proposed_note_id
  );
  if resolved_note_id <> proposed_note_id then return resolved_note_id; end if;

  if not exists (
    select 1 from public.financial_events
    where id = p_event_id and user_id = command_user_id and kind = 'transfer'
  ) then
    raise exception 'NEXO_TRANSFER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.financial_events where reverses_event_id = p_event_id
  ) then
    raise exception 'NEXO_TRANSACTION_ALREADY_REVERSED' using errcode = '23505';
  end if;

  insert into public.financial_event_notes (id, user_id, financial_event_id, notes)
  values (proposed_note_id, command_user_id, p_event_id, normalized_notes);
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transaction_updated', 'financial_event', p_event_id,
    jsonb_build_object('field', 'notes', 'note_event_id', proposed_note_id)
  );
  return proposed_note_id;
end;
$$;

revoke all on function public.create_account(text, text, text, bigint, text, text, text) from public, anon;
revoke all on function public.update_account(uuid, text, text, text, text, text) from public, anon;
revoke all on function public.archive_account(uuid, text) from public, anon;
revoke all on function public.create_transaction(uuid, text, bigint, text, text, date, text, text) from public, anon;
revoke all on function public.create_transfer(uuid, uuid, bigint, text, date, text, text) from public, anon;
revoke all on function public.reverse_transaction(uuid, text) from public, anon;
revoke all on function public.reverse_transfer(uuid, text) from public, anon;
revoke all on function public.update_transaction(uuid, bigint, text, text, date, text, text) from public, anon;
revoke all on function public.update_transfer_notes(uuid, text, text) from public, anon;

grant execute on function public.create_account(text, text, text, bigint, text, text, text) to authenticated;
grant execute on function public.update_account(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.archive_account(uuid, text) to authenticated;
grant execute on function public.create_transaction(uuid, text, bigint, text, text, date, text, text) to authenticated;
grant execute on function public.create_transfer(uuid, uuid, bigint, text, date, text, text) to authenticated;
grant execute on function public.reverse_transaction(uuid, text) to authenticated;
grant execute on function public.reverse_transfer(uuid, text) to authenticated;
grant execute on function public.update_transaction(uuid, bigint, text, text, date, text, text) to authenticated;
grant execute on function public.update_transfer_notes(uuid, text, text) to authenticated;

create view public.account_balances
with (security_invoker = true)
as
select
  a.id,
  a.user_id,
  a.name,
  a.type,
  a.currency,
  a.opening_balance_minor,
  a.institution,
  a.last4,
  a.is_active,
  a.created_at,
  a.updated_at,
  coalesce(sum(e.amount_minor), 0)::bigint as balance_minor
from public.accounts a
left join public.account_entries e on e.account_id = a.id
group by a.id;

create view public.account_activity
with (security_invoker = true)
as
select
  event.id as event_id,
  event.user_id,
  event.kind,
  event.amount_minor,
  event.personal_amount_minor,
  event.description,
  event.category_id,
  category.name as category_name,
  event.occurred_on,
  coalesce(latest_note.notes, event.notes) as notes,
  event.created_at,
  entry.account_id,
  entry.amount_minor as account_delta_minor,
  account.name as account_name,
  account.type as account_type,
  account.currency,
  account.is_active as account_is_active
from public.financial_events event
join public.account_entries entry on entry.financial_event_id = event.id
join public.accounts account on account.id = entry.account_id
left join public.categories category on category.id = event.category_id
left join lateral (
  select note.notes
  from public.financial_event_notes note
  where note.financial_event_id = event.id
  order by note.created_at desc
  limit 1
) latest_note on true
where event.kind <> 'reversal'
  and not exists (
    select 1 from public.financial_events reversal
    where reversal.reverses_event_id = event.id
  );

revoke all on table public.account_balances from anon, authenticated;
revoke all on table public.account_activity from anon, authenticated;
grant select on table public.account_balances to authenticated;
grant select on table public.account_activity to authenticated;
grant all on table public.account_balances to service_role;
grant all on table public.account_activity to service_role;
