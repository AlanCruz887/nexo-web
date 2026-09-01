-- Phase 7C-B (SQL side): public.get_shortcut_options, public.get_
-- shortcut_transaction_context, public.check_shortcut_abuse_bucket, and
-- the rate limit now wired into execute_shortcut_transaction /
-- get_shortcut_options. The HTTP layer itself (Edge Functions) is
-- verified separately by scripts/test-shortcut-http-local.sh (real curl
-- against the real Deno.serve handlers) and scripts/test-shortcut-
-- concurrency.sh (real two-process concurrency) -- neither fits this
-- single-connection psql harness, so they are not duplicated here.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90800000-0000-4000-8000-000000000001', 'http-layer-a@example.test', '{}'),
  ('90800000-0000-4000-8000-000000000002', 'http-layer-b@example.test', '{}');

create temporary table http_layer_ids (
  account_a uuid, card_a uuid, archived_account_a uuid, archived_card_a uuid,
  account_b uuid,
  token_full_hash text, token_options_only_hash text, token_write_only_hash text,
  fresh_token_plain text
);
insert into http_layer_ids default values;
grant select, update on http_layer_ids to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90800000-0000-4000-8000-000000000001', true);

do $$
declare
  account_a_var uuid; card_a_var uuid; archived_account_var uuid; archived_card_var uuid;
  full_row record; options_row record; write_row record;
begin
  account_a_var := public.create_account('Cuenta A', 'checking', 'MXN', 0, null, null, 'hl-account-a-01');
  card_a_var := public.create_credit_card('Tarjeta A', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'hl-card-a-01');
  archived_account_var := public.create_account('Cuenta Archivada', 'checking', 'MXN', 0, null, null, 'hl-account-arch-01');
  perform public.archive_account(archived_account_var, 'hl-account-arch-archive-01');
  archived_card_var := public.create_credit_card('Tarjeta Archivada', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'hl-card-arch-01');
  perform public.archive_credit_card(archived_card_var, 'hl-card-arch-archive-01');

  select * into full_row from public.create_shortcut_token('Completo', array['shortcut:options:read', 'shortcut:transactions:write']);
  select * into options_row from public.create_shortcut_token('Solo opciones', array['shortcut:options:read']);
  select * into write_row from public.create_shortcut_token('Solo escritura', array['shortcut:transactions:write']);

  update http_layer_ids set account_a = account_a_var, card_a = card_a_var,
    archived_account_a = archived_account_var, archived_card_a = archived_card_var;
end;
$$;

select set_config('request.jwt.claim.sub', '90800000-0000-4000-8000-000000000002', true);
do $$
declare account_b_var uuid;
begin
  account_b_var := public.create_account('Cuenta B', 'checking', 'MXN', 0, null, null, 'hl-account-b-01');
  update http_layer_ids set account_b = account_b_var;
end;
$$;

select set_config('request.jwt.claim.sub', '90800000-0000-4000-8000-000000000001', true);

reset role;
do $$
declare ids http_layer_ids%rowtype; h text;
begin
  select * into ids from http_layer_ids;
  select token_hash into h from public.shortcut_tokens where name = 'Completo'; update http_layer_ids set token_full_hash = h;
  select token_hash into h from public.shortcut_tokens where name = 'Solo opciones'; update http_layer_ids set token_options_only_hash = h;
  select token_hash into h from public.shortcut_tokens where name = 'Solo escritura'; update http_layer_ids set token_write_only_hash = h;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO options-A: only active accounts/cards, categories expense/both,
-- exactly the three top-level keys, nothing else (no balances/limits).
-- ---------------------------------------------------------------------
do $$
declare ids http_layer_ids%rowtype; result jsonb; account_count int; card_count int;
begin
  select * into ids from http_layer_ids;
  result := public.get_shortcut_options(ids.token_full_hash);
  if result::text ilike '%balance%' or result::text ilike '%limit%' or result::text ilike '%credit_limit%' then
    raise exception 'CASO options-A: leaked a balance/limit field, got %', result;
  end if;
  select jsonb_array_length(result->'accounts') into account_count;
  select jsonb_array_length(result->'cards') into card_count;
  if account_count <> 1 then raise exception 'CASO options-A: expected exactly 1 active account, got %', account_count; end if;
  if card_count <> 1 then raise exception 'CASO options-A: expected exactly 1 active card, got %', card_count; end if;
  if not (result->'accounts'->0 ? 'id' and result->'accounts'->0 ? 'name' and result->'accounts'->0 ? 'currency') then
    raise exception 'CASO options-A: account shape incorrect, got %', result->'accounts'->0;
  end if;
end;
$$;

-- CASO options-D: archived account/card never appear.
do $$
declare ids http_layer_ids%rowtype; result jsonb;
begin
  select * into ids from http_layer_ids;
  result := public.get_shortcut_options(ids.token_full_hash);
  if result::text ilike '%Cuenta Archivada%' or result::text ilike '%Tarjeta Archivada%' then
    raise exception 'CASO options-D: an archived account/card leaked into options, got %', result;
  end if;
end;
$$;

-- CASO options-C: a write-only token (no options:read scope) is rejected.
do $$
declare ids http_layer_ids%rowtype;
begin
  select * into ids from http_layer_ids;
  perform public.get_shortcut_options(ids.token_write_only_hash);
  raise exception 'CASO options-C: a write-only token must not resolve for options:read';
exception when others then
  if sqlerrm <> 'NEXO_SHORTCUT_SCOPE_DENIED' then raise; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO context-A: get_shortcut_transaction_context returns the source's
-- real currency and the caller's profile timezone.
-- ---------------------------------------------------------------------
do $$
declare ids http_layer_ids%rowtype; ctx record;
begin
  select * into ids from http_layer_ids;
  select * into strict ctx from public.get_shortcut_transaction_context(ids.token_full_hash, 'account', ids.account_a);
  if ctx.currency <> 'MXN' then raise exception 'CASO context-A: expected MXN, got %', ctx.currency; end if;
  if ctx.timezone is null or char_length(ctx.timezone) = 0 then
    raise exception 'CASO context-A: expected a non-empty timezone, got %', ctx.timezone;
  end if;
end;
$$;

-- CASO context-A (write-only token succeeds too -- transactions:write is
-- the correct scope for this lookup, not options:read).
do $$
declare ids http_layer_ids%rowtype; ctx record;
begin
  select * into ids from http_layer_ids;
  select * into strict ctx from public.get_shortcut_transaction_context(ids.token_write_only_hash, 'account', ids.account_a);
  if ctx.currency <> 'MXN' then raise exception 'CASO context-A (write-only token): expected MXN, got %', ctx.currency; end if;
end;
$$;

-- CASO context-B: another user's account is rejected.
do $$
declare ids http_layer_ids%rowtype;
begin
  select * into ids from http_layer_ids;
  perform public.get_shortcut_transaction_context(ids.token_full_hash, 'account', ids.account_b);
  raise exception 'CASO context-B: another user''s account must be rejected';
exception when others then
  if sqlerrm <> 'NEXO_ACCOUNT_NOT_FOUND' then raise; end if;
end;
$$;

-- CASO context-C: an archived card is rejected.
do $$
declare ids http_layer_ids%rowtype;
begin
  select * into ids from http_layer_ids;
  perform public.get_shortcut_transaction_context(ids.token_full_hash, 'card', ids.archived_card_a);
  raise exception 'CASO context-C: an archived card must be rejected';
exception when others then
  if sqlerrm <> 'NEXO_CARD_ARCHIVED' then raise; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO rate-A: check_shortcut_abuse_bucket is the same atomic primitive,
-- reachable generically (used by the Edge Function for invalid-token
-- throttling, where no token_id exists yet to bucket by).
-- ---------------------------------------------------------------------
do $$
declare allowed boolean; i integer;
begin
  for i in 1..10 loop
    allowed := public.check_shortcut_abuse_bucket('hl-abuse-bucket', 10);
    if not allowed then raise exception 'CASO rate-A: request % of 10 should have been allowed', i; end if;
  end loop;
  allowed := public.check_shortcut_abuse_bucket('hl-abuse-bucket', 10);
  if allowed then raise exception 'CASO rate-A: the 11th request in the same window must be rejected'; end if;
end;
$$;

-- CASO rate-B: the rate limit is genuinely wired into
-- get_shortcut_options (separate 'options:' bucket) -- the 31st call
-- with the SAME token in the same window is rejected. Uses its OWN
-- fresh token (never token_full_hash, already used by options-A/D above
-- in this same one-minute window -- reusing it here would make this
-- test's own setup calls count against the very budget being measured).
set local role authenticated;
select set_config('request.jwt.claim.sub', '90800000-0000-4000-8000-000000000001', true);
do $$
declare fresh_row record;
begin
  select * into fresh_row from public.create_shortcut_token('Rate limit options', array['shortcut:options:read']);
  update http_layer_ids set fresh_token_plain = fresh_row.token_plain;
end;
$$;
reset role;
-- Hashing happens here, as superuser: "authenticated" (correctly) has
-- no USAGE on the extensions schema, matching every other role in this
-- project that never needed pgcrypto directly -- only the token-issuing
-- RPC itself (running as its owner) computes a hash from a plaintext it
-- just generated. This mirrors that: the plaintext this test captured
-- is hashed the same way a real Edge Function would, outside of any
-- Postgres role that shouldn't have pgcrypto access to begin with.
do $$
declare plain text;
begin
  select fresh_token_plain into plain from http_layer_ids;
  update http_layer_ids set token_options_only_hash = encode(extensions.digest(plain, 'sha256'), 'hex');
end;
$$;

do $$
declare ids http_layer_ids%rowtype; i integer;
begin
  select * into ids from http_layer_ids;
  for i in 1..30 loop
    perform public.get_shortcut_options(ids.token_options_only_hash);
  end loop;
  begin
    perform public.get_shortcut_options(ids.token_options_only_hash);
    raise exception 'CASO rate-B: the 31st options request in one minute must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_SHORTCUT_RATE_LIMITED' then raise; end if;
  end;
end;
$$;

-- CASO rate-C: the rate limit is genuinely wired into execute_shortcut_
-- transaction ('tx:' bucket, shared with get_shortcut_transaction_
-- context) -- returned as ok=false, never raised (per the 7C-A design
-- decision), and never touches shortcut_token_usage. SET LOCAL ROLE
-- cannot appear inside a DO block (PL/pgSQL does not accept bare
-- utility commands), so the role switch to mint this fresh token is a
-- top-level statement, matching every other role switch in this file.
set local role authenticated;
select set_config('request.jwt.claim.sub', '90800000-0000-4000-8000-000000000001', true);
do $$
declare fresh_row record;
begin
  select * into fresh_row from public.create_shortcut_token('Rate limit tx', array['shortcut:transactions:write']);
  update http_layer_ids set fresh_token_plain = fresh_row.token_plain;
end;
$$;
reset role;
do $$
declare plain text;
begin
  select fresh_token_plain into plain from http_layer_ids;
  update http_layer_ids set token_write_only_hash = encode(extensions.digest(plain, 'sha256'), 'hex');
end;
$$;

do $$
declare
  ids http_layer_ids%rowtype;
  result record;
  i integer;
  usage_count_before integer; usage_count_after integer;
begin
  select * into ids from http_layer_ids;

  for i in 1..30 loop
    perform public.get_shortcut_transaction_context(ids.token_write_only_hash, 'account', ids.account_a);
  end loop;

  select count(*) into usage_count_before from private.shortcut_token_usage;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_write_only_hash, '60000000-0000-4000-8000-000000000001', 'account', ids.account_a,
    100, 'food', 'x', '2020-01-01'
  );
  select count(*) into usage_count_after from private.shortcut_token_usage;

  if result.ok or result.error_code <> 'NEXO_SHORTCUT_RATE_LIMITED' then
    raise exception 'CASO rate-C: expected ok=false/NEXO_SHORTCUT_RATE_LIMITED, got %', row(result.ok, result.error_code);
  end if;
  if usage_count_after <> usage_count_before then
    raise exception 'CASO rate-C: a rate-limited attempt must never write shortcut_token_usage';
  end if;
end;
$$;

rollback;

select 'shortcut HTTP-layer SQL side: options/context RPCs and wired-in rate limiting passed' as result;
