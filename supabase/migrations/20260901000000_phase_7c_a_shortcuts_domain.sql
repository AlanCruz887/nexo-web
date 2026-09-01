-- Phase 7C-A: domain and authentication groundwork for iPhone Shortcuts
-- quick capture. NO HTTP layer yet (no Edge Functions) -- this migration
-- only prepares:
--   1) a same-behavior extraction of the transaction/card-purchase engine
--      into private.*_for_user(user_id, ...) helpers, so a future
--      shortcut-facing entry point can reuse the exact same financial
--      logic without duplicating it and without needing auth.uid() to be
--      set (public.create_transaction/public.create_card_purchase keep
--      their exact signatures, grants, behavior, and error codes -- they
--      become two-line wrappers around the extracted helpers);
--   2) shortcut_tokens: a revocable, hashed, scoped personal-token domain
--      for future Shortcuts, independent from Supabase session JWTs;
--   3) a service_role-only public.execute_shortcut_transaction(...) SQL
--      entry point that resolves a token, then dispatches to the same
--      *_for_user helpers -- never writes to the ledger directly;
--   4) private.shortcut_token_usage: an audit trail kept fully separate
--      from financial_commands, so idempotency semantics for the real
--      financial mutation are never touched by shortcut-specific
--      metadata;
--   5) private.shortcut_rate_limit_windows + private.check_shortcut_rate_
--      limit(...): the atomic Postgres primitives for rate limiting, not
--      yet wired into execute_shortcut_transaction (that integration,
--      together with the IP-bucket for invalid tokens, needs the Edge
--      Function request context and is deferred to Phase 7C-B).
--
-- Supabase pre-installs pgcrypto in the "extensions" schema; a bare
-- Postgres cluster (like the one scripts/test-db.sh builds locally) does
-- not have that schema at all, so create it defensively first. This is
-- a safe no-op against real Supabase, where it already exists.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1) Extract the transaction/card-purchase engine into *_for_user
--    helpers. Bodies below are byte-for-byte the previous public.create_
--    transaction/public.create_card_purchase bodies, with the single
--    change of taking the resolved user id as an explicit parameter
--    instead of deriving it from private.require_user() internally.
-- ---------------------------------------------------------------------

create function private.create_transaction_for_user(
  p_user_id uuid,
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
  command_user_id uuid := p_user_id;
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

revoke all on function private.create_transaction_for_user(uuid, uuid, text, bigint, text, text, date, text, text)
  from public, anon, authenticated;

create function private.create_card_purchase_for_user(
  p_user_id uuid,
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
  command_user_id uuid := p_user_id;
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

revoke all on function private.create_card_purchase_for_user(uuid, uuid, bigint, text, text, date, text, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Public wrappers: identical signature, grants, and (by construction,
-- since the body is unchanged financial logic) identical behavior. They
-- now only resolve the caller's identity and delegate.
-- ---------------------------------------------------------------------

create or replace function public.create_transaction(
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
begin
  return private.create_transaction_for_user(
    private.require_user(), p_account_id, p_kind, p_amount_minor, p_description,
    p_category_id, p_occurred_on, p_notes, p_idempotency_key
  );
end;
$$;

create or replace function public.create_card_purchase(
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
begin
  return private.create_card_purchase_for_user(
    private.require_user(), p_card_id, p_amount_minor, p_description, p_category_id,
    p_occurred_on, p_payment_method, p_notes, p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 2) shortcut_tokens: revocable, hashed, scoped personal tokens.
-- ---------------------------------------------------------------------

create table public.shortcut_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  token_hash text not null unique,
  scopes text[] not null default array['shortcut:options:read', 'shortcut:transactions:write'],
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  constraint shortcut_tokens_name_length check (char_length(btrim(name)) between 1 and 60),
  constraint shortcut_tokens_hash_format check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint shortcut_tokens_scopes_not_empty check (array_length(scopes, 1) > 0),
  constraint shortcut_tokens_scopes_known check (
    scopes <@ array['shortcut:options:read', 'shortcut:transactions:write']::text[]
  )
);

create index shortcut_tokens_user_id_idx on public.shortcut_tokens (user_id);

alter table public.shortcut_tokens enable row level security;
-- No grant to anon/authenticated at all, matching financial_commands:
-- every access goes through a SECURITY DEFINER RPC below, so a raw
-- select can never surface token_hash to any client, ever.
revoke all on table public.shortcut_tokens from anon, authenticated;
grant all on table public.shortcut_tokens to service_role;

-- ---------------------------------------------------------------------
-- 3) shortcut_token_usage: audit trail, deliberately separate from
--    financial_commands so shortcut-specific metadata never changes the
--    idempotency payload/hash that create_transaction/create_card_
--    purchase already compare. Unlike audit_events (append-only), this
--    table is upserted by (token_id, shortcut_execution_id): an
--    idempotent retry of the same shortcut execution must correct the
--    existing row (e.g. error -> success once the retry succeeds), never
--    insert a second one and never leave a stale status behind.
-- ---------------------------------------------------------------------

create table private.shortcut_token_usage (
  id uuid primary key default gen_random_uuid(),
  token_id uuid not null references public.shortcut_tokens (id) on delete cascade,
  shortcut_execution_id uuid not null,
  financial_event_id uuid references public.financial_events (id),
  status text not null,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shortcut_token_usage_status_valid check (status in ('success', 'error')),
  constraint shortcut_token_usage_error_code_length check (
    -- Generous on purpose: most values are short 'NEXO_*' codes, but an
    -- unexpected system-level error (e.g. a raw foreign_key_violation
    -- message, which routinely runs well past 120 chars) must still fit,
    -- or the audit INSERT itself would fail inside the exception handler
    -- that is supposed to record it -- silently leaving no audit row at
    -- all for exactly the failures most worth auditing.
    error_code is null or char_length(error_code) between 1 and 500
  ),
  constraint shortcut_token_usage_status_shape check (
    (status = 'success' and financial_event_id is not null and error_code is null)
    or (status = 'error' and financial_event_id is null)
  ),
  constraint shortcut_token_usage_unique_execution unique (token_id, shortcut_execution_id)
);

create index shortcut_token_usage_token_id_idx on private.shortcut_token_usage (token_id, created_at desc);

alter table private.shortcut_token_usage enable row level security;
-- private is not in PostgREST's exposed schemas (supabase/config.toml),
-- so this grant has zero HTTP-reachable surface -- it only lets
-- service_role-context tooling (and this migration's own test suite)
-- read the audit trail directly.
revoke all on table private.shortcut_token_usage from anon, authenticated;
-- Table-level grants alone are not reachable without schema-level USAGE
-- too (service_role is a real role here, not the schema owner -- every
-- private.* object used until now was only ever a function, always
-- called from inside another SECURITY DEFINER function running as the
-- owner, so this was never needed before).
grant usage on schema private to service_role;
grant all on table private.shortcut_token_usage to service_role;

-- ---------------------------------------------------------------------
-- 4) Rate limiting primitives -- atomic Postgres fixed-window counter.
--    Not wired into execute_shortcut_transaction yet: the per-token
--    integration and the per-IP bucket for invalid tokens both need the
--    Edge Function's request context, which does not exist until 7C-B.
--    Left here, tested standalone, ready to be called from either side.
-- ---------------------------------------------------------------------

create table private.shortcut_rate_limit_windows (
  bucket_key text not null,
  window_start timestamptz not null,
  request_count integer not null default 1,
  primary key (bucket_key, window_start)
);

alter table private.shortcut_rate_limit_windows enable row level security;
revoke all on table private.shortcut_rate_limit_windows from anon, authenticated;
grant all on table private.shortcut_rate_limit_windows to service_role;

create function private.check_shortcut_rate_limit(p_bucket_key text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_count integer;
begin
  if p_bucket_key is null or char_length(p_bucket_key) = 0 then
    raise exception 'NEXO_RATE_LIMIT_INVALID_BUCKET' using errcode = '22023';
  end if;
  if p_limit is null or p_limit <= 0 then
    raise exception 'NEXO_RATE_LIMIT_INVALID_LIMIT' using errcode = '22023';
  end if;

  insert into private.shortcut_rate_limit_windows (bucket_key, window_start, request_count)
  values (p_bucket_key, date_trunc('minute', now()), 1)
  on conflict (bucket_key, window_start) do update
    set request_count = private.shortcut_rate_limit_windows.request_count + 1
  returning request_count into current_count;

  return current_count <= p_limit;
end;
$$;

revoke all on function private.check_shortcut_rate_limit(text, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Token resolution -- hash in, minimal identity out. Never accepts a
--    plaintext token. Pure validation: no side effects (last_used_at is
--    updated by the caller, only once the resolved token is genuinely
--    put to use -- see execute_shortcut_transaction below), so a bare
--    resolve (e.g. a future read-only options call) and a failed scope
--    check never masquerade as "the token was used".
-- ---------------------------------------------------------------------

create function private.resolve_shortcut_token(p_token_hash text, p_required_scope text)
returns table (token_id uuid, user_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched public.shortcut_tokens%rowtype;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'NEXO_SHORTCUT_TOKEN_INVALID' using errcode = '22023';
  end if;

  select * into matched from public.shortcut_tokens where token_hash = p_token_hash;
  if not found then
    raise exception 'NEXO_SHORTCUT_TOKEN_INVALID' using errcode = '22023';
  end if;
  if matched.revoked_at is not null then
    raise exception 'NEXO_SHORTCUT_TOKEN_REVOKED' using errcode = '22023';
  end if;
  if matched.expires_at is not null and matched.expires_at <= now() then
    raise exception 'NEXO_SHORTCUT_TOKEN_EXPIRED' using errcode = '22023';
  end if;
  if p_required_scope is null or not (p_required_scope = any (matched.scopes)) then
    raise exception 'NEXO_SHORTCUT_SCOPE_DENIED' using errcode = '42501';
  end if;

  return query select matched.id, matched.user_id;
end;
$$;

revoke all on function private.resolve_shortcut_token(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6) Management RPCs for the authenticated web app.
-- ---------------------------------------------------------------------

-- create_shortcut_token is deliberately NOT routed through private.
-- resolve_financial_command/financial_commands. That mechanism promises
-- "same key + same payload -> same result returned again", which is the
-- right guarantee for money, but wrong here: the one thing a legitimate
-- retry could never get back is the plaintext token itself (by design,
-- it is never stored). Reusing idempotency here would either silently
-- return a second, different plaintext under the illusion of "the same
-- result" (breaking the idempotency contract) or return no plaintext at
-- all on retry (useless to the caller, and indistinguishable from a bug).
-- A double-submit instead just creates two tokens the user can rename or
-- revoke -- harmless, unlike a duplicated financial mutation.
create function public.create_shortcut_token(p_name text, p_scopes text[])
returns table (
  id uuid,
  token_plain text,
  name text,
  scopes text[],
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  new_id uuid := gen_random_uuid();
  effective_scopes text[] := coalesce(p_scopes, array['shortcut:options:read', 'shortcut:transactions:write']);
  raw_token text;
  raw_hash text;
  normalized_name text := btrim(p_name);
begin
  if array_length(effective_scopes, 1) is null or not (
    effective_scopes <@ array['shortcut:options:read', 'shortcut:transactions:write']::text[]
  ) then
    raise exception 'NEXO_SHORTCUT_SCOPE_INVALID' using errcode = '22023';
  end if;

  raw_token := 'nexo_shortcut_' || rtrim(
    replace(replace(encode(extensions.gen_random_bytes(32), 'base64'), '+', '-'), '/', '_'), '='
  );
  raw_hash := encode(extensions.digest(raw_token, 'sha256'), 'hex');

  insert into public.shortcut_tokens (id, user_id, name, token_hash, scopes)
  values (new_id, command_user_id, normalized_name, raw_hash, effective_scopes);

  return query
    select new_id, raw_token, normalized_name, effective_scopes, now(), null::timestamptz;
end;
$$;

create function public.list_shortcut_tokens()
returns table (
  id uuid,
  name text,
  scopes text[],
  created_at timestamptz,
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
begin
  return query
    select t.id, t.name, t.scopes, t.created_at, t.last_used_at, t.expires_at, t.revoked_at
    from public.shortcut_tokens t
    where t.user_id = command_user_id
    order by t.created_at desc;
end;
$$;

create function public.revoke_shortcut_token(p_token_id uuid, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  payload jsonb := jsonb_build_object('token_id', p_token_id);
begin
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'revoke_shortcut_token', payload, proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then return p_token_id; end if;

  update public.shortcut_tokens
    set revoked_at = coalesce(revoked_at, now())
    where id = p_token_id and user_id = command_user_id;
  if not found then raise exception 'NEXO_SHORTCUT_TOKEN_NOT_FOUND' using errcode = 'P0002'; end if;

  return p_token_id;
end;
$$;

revoke all on function public.create_shortcut_token(text, text[]) from public, anon;
revoke all on function public.list_shortcut_tokens() from public, anon;
revoke all on function public.revoke_shortcut_token(uuid, text) from public, anon;
grant execute on function public.create_shortcut_token(text, text[]) to authenticated;
grant execute on function public.list_shortcut_tokens() to authenticated;
grant execute on function public.revoke_shortcut_token(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7) Narrow, service_role-only execution entry point. No Edge Function
--    calls this yet (7C-B); it exists now so the SQL contract is fixed
--    and independently testable. Never touches account_entries/
--    card_entries/financial_events directly -- only through the *_for_
--    user helpers, exactly like any other caller of the real engine.
-- ---------------------------------------------------------------------

-- Returns a row instead of a bare uuid, and deliberately -- a domain-
-- level rejection (source not found/archived/wrong owner, invalid
-- category, idempotency conflict, ...) is reported by returning
-- ok=false, never by raising an uncaught exception. This is not a style
-- choice: a Postgres exception that escapes this function unhandled
-- aborts the whole enclosing transaction (the one PostgREST/a future
-- Edge Function's single RPC call runs in), which would silently take
-- the just-inserted shortcut_token_usage error row down with it --
-- exactly the "auditoría incoherente" the design explicitly rules out.
-- Only failures with no resolved token yet to audit against (bad
-- source_type, missing execution id, or a token that does not resolve
-- at all) still raise -- there is nothing coherent to log for those.
create function public.execute_shortcut_transaction(
  p_token_hash text,
  p_shortcut_execution_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_amount_minor bigint,
  p_category_id text,
  p_description text,
  p_transaction_date date
)
returns table (ok boolean, event_id uuid, error_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_token_id uuid;
  resolved_user_id uuid;
  resolved_event_id uuid;
  idempotency_key text := 'shortcut:' || p_shortcut_execution_id::text;
  caught_message text;
begin
  if p_source_type not in ('account', 'card') then
    raise exception 'NEXO_SHORTCUT_INVALID_SOURCE_TYPE' using errcode = '22023';
  end if;
  if p_shortcut_execution_id is null then
    raise exception 'NEXO_SHORTCUT_EXECUTION_ID_REQUIRED' using errcode = '22023';
  end if;

  select r.token_id, r.user_id into strict resolved_token_id, resolved_user_id
  from private.resolve_shortcut_token(p_token_hash, 'shortcut:transactions:write') r;

  update public.shortcut_tokens set last_used_at = now() where id = resolved_token_id;

  begin
    if p_source_type = 'account' then
      resolved_event_id := private.create_transaction_for_user(
        resolved_user_id, p_source_id, 'expense', p_amount_minor, p_description,
        p_category_id, p_transaction_date, null, idempotency_key
      );
    else
      resolved_event_id := private.create_card_purchase_for_user(
        resolved_user_id, p_source_id, p_amount_minor, p_description, p_category_id,
        p_transaction_date, null, null, idempotency_key
      );
    end if;
  exception when others then
    get stacked diagnostics caught_message = message_text;
    caught_message := left(caught_message, 500);
    -- A payload-mismatched retry of an execution_id that already
    -- succeeded surfaces here too (private.resolve_financial_command
    -- raises NEXO_IDEMPOTENCY_CONFLICT before touching the ledger). That
    -- retry is rejected and creates no second movement, but the
    -- original execution DID succeed -- the audit row must keep saying
    -- so. Only ever downgrade a row that is not already 'success'.
    insert into private.shortcut_token_usage (token_id, shortcut_execution_id, financial_event_id, status, error_code)
    values (resolved_token_id, p_shortcut_execution_id, null, 'error', caught_message)
    on conflict (token_id, shortcut_execution_id) do update
      set status = 'error', error_code = excluded.error_code, financial_event_id = null,
          updated_at = now()
      where private.shortcut_token_usage.status <> 'success';
    return query select false, null::uuid, caught_message;
    return;
  end;

  insert into private.shortcut_token_usage (token_id, shortcut_execution_id, financial_event_id, status, error_code)
  values (resolved_token_id, p_shortcut_execution_id, resolved_event_id, 'success', null)
  on conflict (token_id, shortcut_execution_id) do update
    set status = 'success', financial_event_id = excluded.financial_event_id, error_code = null,
        updated_at = now();

  return query select true, resolved_event_id, null::text;
end;
$$;

revoke all on function public.execute_shortcut_transaction(text, uuid, text, uuid, bigint, text, text, date)
  from public, anon, authenticated;
grant execute on function public.execute_shortcut_transaction(text, uuid, text, uuid, bigint, text, text, date)
  to service_role;
