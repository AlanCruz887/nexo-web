-- Phase 7C-A: shortcut tokens domain, the create_transaction/create_card_
-- purchase extraction into *_for_user helpers, and the narrow service_
-- role-only execution entry point. Covers cases A-Z from the design
-- brief. No HTTP layer exists yet -- everything here is exercised
-- directly at the SQL level, exactly as a future Edge Function would
-- call it.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90500000-0000-4000-8000-000000000001', 'shortcuts-a@example.test', '{}'),
  ('90500000-0000-4000-8000-000000000002', 'shortcuts-b@example.test', '{}');

create temporary table shortcut_ids (
  account_a uuid, card_a uuid, archived_account_a uuid, archived_card_a uuid,
  account_b uuid, card_b uuid,
  token_id_full uuid, token_hash_full text, token_plain_full text,
  token_id_readonly uuid, token_hash_readonly text,
  token_id_expired uuid, token_hash_expired text,
  token_id_second uuid, token_hash_second text
);
insert into shortcut_ids default values;
grant select, update on shortcut_ids to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90500000-0000-4000-8000-000000000001', true);

do $$
declare
  account_a_var uuid; card_a_var uuid; archived_account_var uuid; archived_card_var uuid;
begin
  account_a_var := public.create_account('Cuenta A', 'checking', 'MXN', 0, null, null, 'sh-account-a-01');
  card_a_var := public.create_credit_card('Tarjeta A', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'sh-card-a-01');
  archived_account_var := public.create_account('Cuenta Archivada', 'checking', 'MXN', 0, null, null, 'sh-account-arch-01');
  perform public.archive_account(archived_account_var, 'sh-account-arch-archive-01');
  archived_card_var := public.create_credit_card('Tarjeta Archivada', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'sh-card-arch-01');
  perform public.archive_credit_card(archived_card_var, 'sh-card-arch-archive-01');
  update shortcut_ids set account_a = account_a_var, card_a = card_a_var,
    archived_account_a = archived_account_var, archived_card_a = archived_card_var;
end;
$$;

select set_config('request.jwt.claim.sub', '90500000-0000-4000-8000-000000000002', true);
do $$
declare account_b_var uuid; card_b_var uuid;
begin
  account_b_var := public.create_account('Cuenta B', 'checking', 'MXN', 0, null, null, 'sh-account-b-01');
  card_b_var := public.create_credit_card('Tarjeta B', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'sh-card-b-01');
  update shortcut_ids set account_b = account_b_var, card_b = card_b_var;
end;
$$;

select set_config('request.jwt.claim.sub', '90500000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- CASO A: public.create_transaction still produces the exact same shape
-- of financial_event/account_entries it produced before the extraction.
-- ---------------------------------------------------------------------
do $$
declare
  ids shortcut_ids%rowtype;
  event_id uuid;
  ev public.financial_events%rowtype;
  entry_amount bigint;
begin
  select * into ids from shortcut_ids;
  event_id := public.create_transaction(ids.account_a, 'expense', 45000, 'Super', 'food', '2020-02-01', null, 'sh-caso-a-01');
  select * into strict ev from public.financial_events where id = event_id;
  select amount_minor into strict entry_amount from public.account_entries where financial_event_id = event_id;
  if ev.kind <> 'expense' or ev.amount_minor <> 45000 or ev.personal_amount_minor <> 45000 then
    raise exception 'CASO A: unexpected financial_events shape for create_transaction, got %', row(ev.kind, ev.amount_minor, ev.personal_amount_minor);
  end if;
  if entry_amount <> -45000 then
    raise exception 'CASO A: account_entries should be -45000, got %', entry_amount;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO B: public.create_card_purchase still produces the exact same
-- shape it produced before the extraction.
-- ---------------------------------------------------------------------
do $$
declare
  ids shortcut_ids%rowtype;
  event_id uuid;
  ev public.financial_events%rowtype;
  entry_amount bigint;
begin
  select * into ids from shortcut_ids;
  event_id := public.create_card_purchase(ids.card_a, 30000, 'Cena', 'food', '2020-02-02', null, null, 'sh-caso-b-01');
  select * into strict ev from public.financial_events where id = event_id;
  select amount_minor into strict entry_amount from public.card_entries where financial_event_id = event_id;
  if ev.kind <> 'card_charge' or ev.amount_minor <> 30000 or ev.personal_amount_minor <> 30000 then
    raise exception 'CASO B: unexpected financial_events shape for create_card_purchase, got %', row(ev.kind, ev.amount_minor, ev.personal_amount_minor);
  end if;
  if entry_amount <> 30000 then
    raise exception 'CASO B: card_entries should be 30000, got %', entry_amount;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO C: private.*_for_user enforce ownership themselves (not only
-- because the public wrapper resolves the right user) -- calling them
-- directly with a user id that does not own the source must still be
-- rejected exactly like the public RPC would reject a foreign account.
-- ---------------------------------------------------------------------
reset role;
do $$
declare ids shortcut_ids%rowtype;
begin
  select * into ids from shortcut_ids;
  begin
    perform private.create_transaction_for_user(
      '90500000-0000-4000-8000-000000000002', ids.account_a, 'expense', 1000, 'x', 'food', '2020-02-03', null, 'sh-caso-c-account-01'
    );
    raise exception 'CASO C: user B must not be able to spend from user A''s account via *_for_user';
  exception when others then
    if sqlerrm <> 'NEXO_ACCOUNT_NOT_FOUND' then raise; end if;
  end;
  begin
    perform private.create_card_purchase_for_user(
      '90500000-0000-4000-8000-000000000002', ids.card_a, 1000, 'x', 'food', '2020-02-03', null, null, 'sh-caso-c-card-01'
    );
    raise exception 'CASO C: user B must not be able to charge user A''s card via *_for_user';
  exception when others then
    if sqlerrm <> 'NEXO_CARD_NOT_FOUND' then raise; end if;
  end;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', '90500000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- Token fixtures: a full-scope token, an options-only token, and a
-- second full-scope token (for CASO J). CASO G (expired) is seeded by
-- direct insert below since creation has no expires_at parameter yet.
-- ---------------------------------------------------------------------
do $$
declare full_row record; readonly_row record; second_row record;
begin
  select * into full_row from public.create_shortcut_token('Mi iPhone', array['shortcut:options:read', 'shortcut:transactions:write']);
  select * into readonly_row from public.create_shortcut_token('Solo lectura', array['shortcut:options:read']);
  select * into second_row from public.create_shortcut_token('Segundo dispositivo', array['shortcut:options:read', 'shortcut:transactions:write']);
  update shortcut_ids set
    token_id_full = full_row.id, token_plain_full = full_row.token_plain,
    token_id_readonly = readonly_row.id,
    token_id_second = second_row.id;
end;
$$;

-- Compute the sha256 hashes independently (as the test's own oracle, the
-- same way a future Deno Edge Function would) and cross-check them
-- against what the table actually stored -- CASO Y6.
reset role;
do $$
declare ids shortcut_ids%rowtype; stored_hash text; computed_hash text;
begin
  select * into ids from shortcut_ids;
  select token_hash into stored_hash from public.shortcut_tokens where id = ids.token_id_full;
  computed_hash := encode(extensions.digest(ids.token_plain_full, 'sha256'), 'hex');
  if stored_hash <> computed_hash then
    raise exception 'CASO Y6: stored token_hash does not match independently computed sha256(token_plain)';
  end if;
  update shortcut_ids set token_hash_full = computed_hash;
end;
$$;
do $$
declare ids shortcut_ids%rowtype; h text;
begin
  select * into ids from shortcut_ids;
  select token_hash into h from public.shortcut_tokens where id = ids.token_id_readonly;
  update shortcut_ids set token_hash_readonly = h;
  select token_hash into h from public.shortcut_tokens where id = ids.token_id_second;
  update shortcut_ids set token_hash_second = h;
end;
$$;

-- CASO G fixture: an already-expired token, seeded directly (there is no
-- creation parameter for expires_at yet -- see report point 6).
do $$
declare new_id uuid := gen_random_uuid(); raw text := 'nexo_shortcut_test_expired_token_fixture'; h text;
begin
  h := encode(extensions.digest(raw, 'sha256'), 'hex');
  insert into public.shortcut_tokens (id, user_id, name, token_hash, scopes, expires_at)
  values (new_id, '90500000-0000-4000-8000-000000000001', 'Expirado', h,
    array['shortcut:options:read', 'shortcut:transactions:write'], now() - interval '1 hour');
  update shortcut_ids set token_id_expired = new_id, token_hash_expired = h;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO D: a valid token hash + sufficient scope resolves the right user.
-- ---------------------------------------------------------------------
do $$
declare ids shortcut_ids%rowtype; resolved record;
begin
  select * into ids from shortcut_ids;
  select * into strict resolved from private.resolve_shortcut_token(ids.token_hash_full, 'shortcut:transactions:write');
  if resolved.user_id <> '90500000-0000-4000-8000-000000000001' then
    raise exception 'CASO D: resolved wrong user_id, got %', resolved.user_id;
  end if;
end;
$$;

-- CASO E: an invalid (unknown) token hash fails.
do $$
begin
  perform private.resolve_shortcut_token(encode(extensions.digest('does-not-exist', 'sha256'), 'hex'), 'shortcut:transactions:write');
  raise exception 'CASO E: an unknown token hash must be rejected';
exception when others then
  if sqlerrm <> 'NEXO_SHORTCUT_TOKEN_INVALID' then raise; end if;
end;
$$;

-- CASO F: a revoked token fails, and CASO J: it does not affect the
-- other (second) token belonging to the same user.
do $$
declare ids shortcut_ids%rowtype;
begin
  select * into ids from shortcut_ids;
  perform public.revoke_shortcut_token(ids.token_id_readonly, 'sh-caso-f-revoke-01');
end;
$$;
do $$
declare ids shortcut_ids%rowtype;
begin
  select * into ids from shortcut_ids;
  begin
    perform private.resolve_shortcut_token(ids.token_hash_readonly, 'shortcut:options:read');
    raise exception 'CASO F: a revoked token must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_SHORTCUT_TOKEN_REVOKED' then raise; end if;
  end;
  -- CASO J: token_id_second was never revoked and must still resolve.
  perform private.resolve_shortcut_token(ids.token_hash_second, 'shortcut:transactions:write');
end;
$$;

-- CASO G: an expired token fails.
do $$
declare ids shortcut_ids%rowtype;
begin
  select * into ids from shortcut_ids;
  perform private.resolve_shortcut_token(ids.token_hash_expired, 'shortcut:transactions:write');
  raise exception 'CASO G: an expired token must be rejected';
exception when others then
  if sqlerrm <> 'NEXO_SHORTCUT_TOKEN_EXPIRED' then raise; end if;
end;
$$;

-- CASO H: a token without the required scope is rejected, even though
-- it is otherwise valid (options-only token asked for write).
do $$
declare ids shortcut_ids%rowtype;
begin
  select * into ids from shortcut_ids;
  perform private.resolve_shortcut_token(ids.token_hash_second, 'shortcut:options:read');
  -- (token_hash_second has both scopes -- sanity check it still works)
  begin
    perform private.resolve_shortcut_token(ids.token_hash_readonly, 'shortcut:transactions:write');
    raise exception 'CASO H: a read-only-scoped token must not resolve for a write scope';
  exception when others then
    if sqlerrm not in ('NEXO_SHORTCUT_SCOPE_DENIED', 'NEXO_SHORTCUT_TOKEN_REVOKED') then raise; end if;
    -- (token_id_readonly was revoked in CASO F; either failure mode is
    -- an acceptable rejection here since both must block execution --
    -- the scope check itself is exercised in isolation right below.)
  end;
end;
$$;

-- CASO H (isolated): a fresh, non-revoked, options-only token must be
-- rejected purely on scope grounds.
do $$
declare readonly2 record; hash2 text;
begin
  select * into readonly2 from public.create_shortcut_token('Solo lectura 2', array['shortcut:options:read']);
  hash2 := encode(extensions.digest(readonly2.token_plain, 'sha256'), 'hex');
  begin
    perform private.resolve_shortcut_token(hash2, 'shortcut:transactions:write');
    raise exception 'CASO H: scope-insufficient token must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_SHORTCUT_SCOPE_DENIED' then raise; end if;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90500000-0000-4000-8000-000000000001', true);

-- CASO I: list_shortcut_tokens never returns token_hash or the plaintext.
do $$
declare r record; found_forbidden boolean := false;
begin
  for r in select * from public.list_shortcut_tokens() loop
    if r::text ilike '%nexo_shortcut_%' then found_forbidden := true; end if;
  end loop;
  if found_forbidden then
    raise exception 'CASO I: list_shortcut_tokens leaked a plaintext-looking value';
  end if;
end;
$$;
-- Structural check: the function's declared TABLE(...) return signature
-- names exactly the safe columns, with no token_hash/token_plain at all.
do $$
declare result_signature text;
begin
  select pg_get_function_result(p.oid) into strict result_signature
  from pg_proc p
  where p.proname = 'list_shortcut_tokens' and p.pronamespace = 'public'::regnamespace;
  if result_signature is null or result_signature ilike '%hash%' or result_signature ilike '%token_plain%' then
    raise exception 'CASO I: list_shortcut_tokens return signature must never include token_hash/token_plain, got %', result_signature;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO K/L: execute_shortcut_transaction against an account and a card,
-- with an audit row created for each (CASO V, folded in here).
--
-- Result is a (ok, event_id, error_code) row rather than a bare uuid --
-- see the migration's comment on execute_shortcut_transaction for why a
-- domain rejection is reported this way instead of by raising: raising
-- would abort the whole enclosing transaction and take the just-written
-- shortcut_token_usage row down with it.
-- ---------------------------------------------------------------------
set local role service_role;
do $$
declare
  ids shortcut_ids%rowtype;
  result record;
  usage_row private.shortcut_token_usage%rowtype;
  entry_amount bigint;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'a0000000-0000-4000-8000-00000000000a', 'account', ids.account_a,
    45000, 'food', 'KFC', '2020-03-01'
  );
  if not result.ok or result.event_id is null then
    raise exception 'CASO K: expected ok=true with an event_id, got %', row(result.ok, result.event_id, result.error_code);
  end if;
  select amount_minor into strict entry_amount from public.account_entries where financial_event_id = result.event_id;
  if entry_amount <> -45000 then raise exception 'CASO K: expected -45000 in account_entries, got %', entry_amount; end if;
  select * into strict usage_row from private.shortcut_token_usage
    where token_id = ids.token_id_full and shortcut_execution_id = 'a0000000-0000-4000-8000-00000000000a';
  if usage_row.status <> 'success' or usage_row.financial_event_id <> result.event_id then
    raise exception 'CASO K/V: shortcut_token_usage row incoherent, got %', row(usage_row.status, usage_row.financial_event_id);
  end if;
end;
$$;

do $$
declare
  ids shortcut_ids%rowtype;
  result record;
  usage_row private.shortcut_token_usage%rowtype;
  entry_amount bigint;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'b0000000-0000-4000-8000-00000000000b', 'card', ids.card_a,
    12000, 'food', 'Starbucks', '2020-03-02'
  );
  if not result.ok or result.event_id is null then
    raise exception 'CASO L: expected ok=true with an event_id, got %', row(result.ok, result.event_id, result.error_code);
  end if;
  select amount_minor into strict entry_amount from public.card_entries where financial_event_id = result.event_id;
  if entry_amount <> 12000 then raise exception 'CASO L: expected 12000 in card_entries, got %', entry_amount; end if;
  select * into strict usage_row from private.shortcut_token_usage
    where token_id = ids.token_id_full and shortcut_execution_id = 'b0000000-0000-4000-8000-00000000000b';
  if usage_row.status <> 'success' or usage_row.financial_event_id <> result.event_id then
    raise exception 'CASO L/V: shortcut_token_usage row incoherent, got %', row(usage_row.status, usage_row.financial_event_id);
  end if;
end;
$$;

-- CASO M: an account belonging to another user is rejected, and no
-- financial_event/usage-success is created for it.
do $$
declare ids shortcut_ids%rowtype; result record; events_before integer; events_after integer;
begin
  select * into ids from shortcut_ids;
  select count(*) into events_before from public.financial_events;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'c0000000-0000-4000-8000-00000000000c', 'account', ids.account_b,
    1000, 'food', 'x', '2020-03-03'
  );
  if result.ok or result.error_code <> 'NEXO_ACCOUNT_NOT_FOUND' then
    raise exception 'CASO M: expected ok=false/NEXO_ACCOUNT_NOT_FOUND, got %', row(result.ok, result.error_code);
  end if;
  select count(*) into events_after from public.financial_events;
  if events_after <> events_before then raise exception 'CASO M: a rejected attempt must not create a financial_event'; end if;
end;
$$;

-- CASO N: a card belonging to another user is rejected.
do $$
declare ids shortcut_ids%rowtype; result record;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'd0000000-0000-4000-8000-00000000000d', 'card', ids.card_b,
    1000, 'food', 'x', '2020-03-04'
  );
  if result.ok or result.error_code <> 'NEXO_CARD_NOT_FOUND' then
    raise exception 'CASO N: expected ok=false/NEXO_CARD_NOT_FOUND, got %', row(result.ok, result.error_code);
  end if;
end;
$$;

-- CASO O: an archived account is rejected.
do $$
declare ids shortcut_ids%rowtype; result record;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'e0000000-0000-4000-8000-00000000000e', 'account', ids.archived_account_a,
    1000, 'food', 'x', '2020-03-05'
  );
  if result.ok or result.error_code <> 'NEXO_ACCOUNT_ARCHIVED' then
    raise exception 'CASO O: expected ok=false/NEXO_ACCOUNT_ARCHIVED, got %', row(result.ok, result.error_code);
  end if;
end;
$$;

-- CASO P: an archived card is rejected.
do $$
declare ids shortcut_ids%rowtype; result record;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, 'f0000000-0000-4000-8000-00000000000f', 'card', ids.archived_card_a,
    1000, 'food', 'x', '2020-03-06'
  );
  if result.ok or result.error_code <> 'NEXO_CARD_ARCHIVED' then
    raise exception 'CASO P: expected ok=false/NEXO_CARD_ARCHIVED, got %', row(result.ok, result.error_code);
  end if;
end;
$$;

-- CASO Q / U: an invalid category is rejected by the FK, and the
-- rejection is a total rollback -- no financial_event, no financial_
-- commands row for that key, and exactly one error row in shortcut_
-- token_usage (never a partial write).
do $$
declare
  ids shortcut_ids%rowtype;
  result record;
  events_before integer; events_after integer;
  usage_row private.shortcut_token_usage%rowtype;
begin
  select * into ids from shortcut_ids;
  select count(*) into events_before from public.financial_events;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, '10000000-0000-4000-8000-000000000001', 'account', ids.account_a,
    1000, 'no_existe_esta_categoria', 'x', '2020-03-07'
  );
  if result.ok then raise exception 'CASO Q: an invalid category_id must be rejected'; end if;
  select count(*) into events_after from public.financial_events;
  if events_after <> events_before then raise exception 'CASO Q/U: a rejected attempt must not create a financial_event'; end if;
  select * into strict usage_row from private.shortcut_token_usage
    where token_id = ids.token_id_full and shortcut_execution_id = '10000000-0000-4000-8000-000000000001';
  if usage_row.status <> 'error' or usage_row.financial_event_id is not null then
    raise exception 'CASO Q/U/V: expected a clean error audit row, got %', row(usage_row.status, usage_row.financial_event_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO R/S/T: idempotency and the append-only, non-multiplying audit
-- trail (CASO Y5 folded in).
-- ---------------------------------------------------------------------
do $$
declare
  ids shortcut_ids%rowtype;
  result_1 record; result_2 record; result_3 record;
  usage_count integer;
  usage_row private.shortcut_token_usage%rowtype;
begin
  select * into ids from shortcut_ids;
  select * into strict result_1 from public.execute_shortcut_transaction(
    ids.token_hash_full, '20000000-0000-4000-8000-000000000002', 'account', ids.account_a,
    9900, 'food', 'Repetido', '2020-03-08'
  );
  if not result_1.ok then raise exception 'CASO R setup: first execution must succeed, got %', result_1.error_code; end if;

  -- CASO R/T: same execution id, same payload, called again -- must
  -- return the exact same event, never create a second one.
  select * into strict result_2 from public.execute_shortcut_transaction(
    ids.token_hash_full, '20000000-0000-4000-8000-000000000002', 'account', ids.account_a,
    9900, 'food', 'Repetido', '2020-03-08'
  );
  if not result_2.ok or result_2.event_id <> result_1.event_id then
    raise exception 'CASO R/T: same shortcut_execution_id + same payload must return the same event, got % and %', result_1.event_id, result_2.event_id;
  end if;
  select count(*) into usage_count from public.account_entries where financial_event_id = result_1.event_id;
  if usage_count <> 1 then raise exception 'CASO T: exactly one account_entries row expected, got %', usage_count; end if;
  -- CASO Y5: exactly one shortcut_token_usage row for this execution,
  -- not duplicated by the retry.
  select count(*) into usage_count from private.shortcut_token_usage
    where token_id = ids.token_id_full and shortcut_execution_id = '20000000-0000-4000-8000-000000000002';
  if usage_count <> 1 then raise exception 'CASO Y5: expected exactly one shortcut_token_usage row, got %', usage_count; end if;

  -- CASO S: same execution id, different payload -> conflict, and the
  -- audit row must still say the original attempt succeeded (not
  -- regressed to 'error' by the conflicting retry).
  select * into strict result_3 from public.execute_shortcut_transaction(
    ids.token_hash_full, '20000000-0000-4000-8000-000000000002', 'account', ids.account_a,
    12345, 'food', 'Repetido', '2020-03-08'
  );
  if result_3.ok or result_3.error_code <> 'NEXO_IDEMPOTENCY_CONFLICT' then
    raise exception 'CASO S: expected ok=false/NEXO_IDEMPOTENCY_CONFLICT, got %', row(result_3.ok, result_3.error_code);
  end if;
  select * into strict usage_row from private.shortcut_token_usage
    where token_id = ids.token_id_full and shortcut_execution_id = '20000000-0000-4000-8000-000000000002';
  if usage_row.status <> 'success' or usage_row.financial_event_id <> result_1.event_id then
    raise exception 'CASO S: a conflicting retry must not erase the original success audit row, got %',
      row(usage_row.status, usage_row.financial_event_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO W: prior movements survive revocation -- revoking the token must
-- not touch the financial_event/account_entries it already created.
-- ---------------------------------------------------------------------
do $$
declare ids shortcut_ids%rowtype; before_amount bigint; after_amount bigint; result record; result_after record;
begin
  select * into ids from shortcut_ids;
  select * into strict result from public.execute_shortcut_transaction(
    ids.token_hash_full, '30000000-0000-4000-8000-000000000003', 'account', ids.account_a,
    500, 'food', 'Antes de revocar', '2020-03-09'
  );
  if not result.ok then raise exception 'CASO W setup: expected success, got %', result.error_code; end if;
  select amount_minor into strict before_amount from public.account_entries where financial_event_id = result.event_id;

  set local role authenticated;
  perform public.revoke_shortcut_token(ids.token_id_full, 'sh-caso-w-revoke-01');
  set local role service_role;

  select amount_minor into strict after_amount from public.account_entries where financial_event_id = result.event_id;
  if before_amount <> after_amount then
    raise exception 'CASO W: revoking a token must never alter a movement it already created';
  end if;

  begin
    select * into strict result_after from public.execute_shortcut_transaction(
      ids.token_hash_full, '40000000-0000-4000-8000-000000000004', 'account', ids.account_a,
      500, 'food', 'Despues de revocar', '2020-03-10'
    );
    raise exception 'CASO W: a revoked token must not be usable for new movements';
  exception when others then
    if sqlerrm <> 'NEXO_SHORTCUT_TOKEN_REVOKED' then raise; end if;
  end;
end;
$$;

-- CASO Y2: execute_shortcut_transaction is service_role-only -- neither
-- anon nor an authenticated end user can call it directly, regardless of
-- how valid their token hash is.
set local role authenticated;
do $$
declare ids shortcut_ids%rowtype; result record;
begin
  select * into ids from shortcut_ids;
  begin
    select * into result from public.execute_shortcut_transaction(
      ids.token_hash_second, '50000000-0000-4000-8000-000000000005', 'account', ids.account_a,
      100, 'food', 'x', '2020-03-11'
    );
    raise exception 'CASO Y2: authenticated must not be able to call execute_shortcut_transaction directly';
  exception when insufficient_privilege then
    null; -- expected
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO X/Y: atomic rate limit primitive.
-- ---------------------------------------------------------------------
reset role;
do $$
declare allowed boolean; i integer;
begin
  for i in 1..30 loop
    allowed := private.check_shortcut_rate_limit('sh-rate-test-bucket', 30);
    if not allowed then raise exception 'CASO X: request % of 30 should have been allowed', i; end if;
  end loop;
  allowed := private.check_shortcut_rate_limit('sh-rate-test-bucket', 30);
  if allowed then raise exception 'CASO X: the 31st request in the same window must be rejected'; end if;
end;
$$;

-- CASO Y: a different (earlier, synthetic) window for the same bucket
-- does not leak its count into the current window -- proves window
-- isolation without needing to wait for real wall-clock time to pass.
do $$
declare allowed boolean;
begin
  insert into private.shortcut_rate_limit_windows (bucket_key, window_start, request_count)
  values ('sh-rate-test-bucket-2', now() - interval '5 minutes', 999);
  allowed := private.check_shortcut_rate_limit('sh-rate-test-bucket-2', 30);
  if not allowed then
    raise exception 'CASO Y: a new window for the same bucket must start its own fresh count, not inherit an old window''s';
  end if;
end;
$$;

rollback;

select 'shortcut tokens: A-Z design cases, *_for_user extraction parity, and rate limit primitives passed' as result;
