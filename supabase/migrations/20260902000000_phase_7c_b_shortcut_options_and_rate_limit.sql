-- Phase 7C-B: HTTP layer groundwork, part 2 (SQL side). Adds the narrow
-- read RPC the Edge Function needs for "GET /shortcut-options" and wires
-- the rate-limit primitive built in 7C-A into both service_role-only
-- entry points. No HTTP/Edge Function code lives in this file -- see
-- supabase/functions/ for that; this migration only prepares what those
-- functions call.

-- ---------------------------------------------------------------------
-- 1) get_shortcut_options: the only way an Edge Function may read
--    accounts/cards/categories for a token. Never a raw service_role
--    select against accounts/credit_cards/categories from the Edge
--    Function -- this RPC resolves the token itself and returns
--    exactly the shape the Shortcut needs, nothing else.
-- ---------------------------------------------------------------------

create function public.get_shortcut_options(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_token_id uuid;
  resolved_user_id uuid;
  rate_limit_ok boolean;
begin
  select r.token_id, r.user_id into strict resolved_token_id, resolved_user_id
  from private.resolve_shortcut_token(p_token_hash, 'shortcut:options:read') r;

  -- Same rule as execute_shortcut_transaction: last_used_at reflects any
  -- request whose token itself validated successfully, independent of
  -- what happens next (including being rate-limited below).
  update public.shortcut_tokens set last_used_at = now() where id = resolved_token_id;

  -- Separate bucket namespace from transactions ('options:' vs 'tx:')
  -- so a burst of reads can never consume the budget meant for writes,
  -- or vice versa.
  rate_limit_ok := private.check_shortcut_rate_limit('options:' || resolved_token_id::text, 30);
  if not rate_limit_ok then
    raise exception 'NEXO_SHORTCUT_RATE_LIMITED' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'currency', a.currency) order by a.created_at)
      from public.accounts a
      where a.user_id = resolved_user_id and a.is_active
    ), '[]'::jsonb),
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'currency', c.currency) order by c.created_at)
      from public.credit_cards c
      where c.user_id = resolved_user_id and c.is_active
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', cat.id, 'name', cat.name) order by cat.sort_order)
      from public.categories cat
      where cat.kind in ('expense', 'both')
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_shortcut_options(text) from public, anon, authenticated;
grant execute on function public.get_shortcut_options(text) to service_role;

-- ---------------------------------------------------------------------
-- 1b) Generic, narrow, service_role-only entry point onto the same
--    atomic rate-limit primitive, for the ONE case that has no resolved
--    token_id yet to bucket by: an invalid-token request. The Edge
--    Function decides the bucket key (a trusted client-IP header if one
--    is genuinely available, or a small documented fallback otherwise
--    -- see supabase/functions/_shared/rate-limit.ts) and passes it
--    here; Postgres only ever sees an opaque bucket_key string, never a
--    raw IP interpreted at the SQL layer.
-- ---------------------------------------------------------------------

create function public.check_shortcut_abuse_bucket(p_bucket_key text, p_limit integer)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.check_shortcut_rate_limit(p_bucket_key, p_limit);
$$;

revoke all on function public.check_shortcut_abuse_bucket(text, integer) from public, anon, authenticated;
grant execute on function public.check_shortcut_abuse_bucket(text, integer) to service_role;

-- ---------------------------------------------------------------------
-- 1c) Transaction context lookup, scoped under shortcut:transactions:
--    write (not options:read) -- a write-only token must be able to
--    complete a purchase end to end without also needing read scope.
--    Returns exactly the two things the Edge Function needs before it
--    can safely call execute_shortcut_transaction, in a single round
--    trip: the source's REAL currency (never a client-supplied one, to
--    convert the decimal amount string with the correct scale) and the
--    user's profile timezone (to resolve "today" when transaction_date
--    is omitted, instead of guessing from the server's own clock).
--    Read-only: no ledger write, same ownership rule *_for_user already
--    enforces, so this is not a second financial engine -- just the one
--    lookup those functions would otherwise duplicate internally.
--    Shares the 'tx:' rate-limit bucket with execute_shortcut_
--    transaction (same budget, since one real submission normally calls
--    both exactly once).
-- ---------------------------------------------------------------------

create function public.get_shortcut_transaction_context(p_token_hash text, p_source_type text, p_source_id uuid)
returns table (currency text, timezone text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_token_id uuid;
  resolved_user_id uuid;
  resolved_currency text;
  resolved_timezone text;
  source_is_active boolean;
  rate_limit_ok boolean;
begin
  if p_source_type not in ('account', 'card') then
    raise exception 'NEXO_SHORTCUT_INVALID_SOURCE_TYPE' using errcode = '22023';
  end if;

  select r.token_id, r.user_id into strict resolved_token_id, resolved_user_id
  from private.resolve_shortcut_token(p_token_hash, 'shortcut:transactions:write') r;

  rate_limit_ok := private.check_shortcut_rate_limit('tx:' || resolved_token_id::text, 30);
  if not rate_limit_ok then
    raise exception 'NEXO_SHORTCUT_RATE_LIMITED' using errcode = '22023';
  end if;

  -- Table aliases + qualified columns below are load-bearing, not
  -- style: this function's own OUT/return column is also named
  -- "currency" (returns table (currency text, timezone text)), so an
  -- unqualified "currency" is genuinely ambiguous to PL/pgSQL between
  -- that and accounts.currency/credit_cards.currency -- confirmed by
  -- hitting "column reference \"currency\" is ambiguous" for real
  -- against a live instance before adding the aliases.
  if p_source_type = 'account' then
    select a.currency, a.is_active into resolved_currency, source_is_active
    from public.accounts a where a.id = p_source_id and a.user_id = resolved_user_id;
    if not found then raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
    if not source_is_active then raise exception 'NEXO_ACCOUNT_ARCHIVED' using errcode = '23514'; end if;
  else
    select c.currency, c.is_active into resolved_currency, source_is_active
    from public.credit_cards c where c.id = p_source_id and c.user_id = resolved_user_id;
    if not found then raise exception 'NEXO_CARD_NOT_FOUND' using errcode = 'P0002'; end if;
    if not source_is_active then raise exception 'NEXO_CARD_ARCHIVED' using errcode = '23514'; end if;
  end if;

  select p.timezone into strict resolved_timezone from public.profiles p where p.id = resolved_user_id;

  return query select resolved_currency, resolved_timezone;
end;
$$;

revoke all on function public.get_shortcut_transaction_context(text, text, uuid) from public, anon, authenticated;
grant execute on function public.get_shortcut_transaction_context(text, text, uuid) to service_role;

-- ---------------------------------------------------------------------
-- 2) Wire the 7C-A rate-limit primitive into execute_shortcut_transaction.
--    Checked right after the token resolves (bucket 'tx:' + token_id,
--    separate from the options bucket above), before the financial
--    engine is touched at all. A rate-limited request is reported the
--    same way any other post-token-resolution rejection is -- returned
--    as ok=false, never raised (same reasoning as every other rejection
--    in this function: raising would abort the transaction and could
--    take a would-be audit row down with it). It is deliberately NOT
--    written to shortcut_token_usage: throttling is not a domain-level
--    execution attempt, and logging it would blur "did this shortcut
--    execution ever really run" with "was this specific HTTP request
--    throttled", two different questions.
-- ---------------------------------------------------------------------

create or replace function public.execute_shortcut_transaction(
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
  rate_limit_ok boolean;
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

  rate_limit_ok := private.check_shortcut_rate_limit('tx:' || resolved_token_id::text, 30);
  if not rate_limit_ok then
    return query select false, null::uuid, 'NEXO_SHORTCUT_RATE_LIMITED'::text;
    return;
  end if;

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
