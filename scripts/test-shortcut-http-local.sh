#!/usr/bin/env bash
# Real local HTTP verification for the 7C-B Edge Functions, per the
# explicit request to not stop at "TypeScript compiles". Builds, without
# Docker and without touching Supabase real:
#   1) an ephemeral bare Postgres cluster with every migration applied
#      (same technique as scripts/test-db.sh);
#   2) a real PostgREST instance in front of it (installed via
#      `brew install postgrest`), authenticating a minted local-only
#      service_role JWT;
#   3) the actual supabase/functions/shortcut-options and
#      shortcut-transactions/index.ts files, run directly with
#      `deno run` (the same Deno runtime Edge Functions use) against
#      that PostgREST instance;
# then fires real `curl` requests at them and checks the responses.
#
# `supabase functions serve` itself was attempted first and fails
# immediately in this environment: it requires Docker/Podman, neither of
# which is installed here (confirmed, not assumed). This script is the
# closest real substitute available without Docker: the exact same
# Edge Function code, actually served over HTTP by Deno, actually
# talking to a real Postgres through a real PostgREST, actually hit with
# curl -- just without Supabase CLI's own container sandbox around it.
set -euo pipefail

nexo_pg_tmp="$(mktemp -d /tmp/nexo-http-local.XXXXXX)"
nexo_pg_data="${nexo_pg_tmp}/data"
nexo_pg_socket="${nexo_pg_tmp}/socket"
nexo_pg_port="$((55700 + RANDOM % 100))"
nexo_pg_database="nexo_http_test"
pgrst_port="$((3900 + RANDOM % 100))"
proxy_port="$((4900 + RANDOM % 100))"
# Deno.serve() in the real Edge Function files takes no port argument on
# purpose (Supabase's own edge runtime assigns the port at deploy time,
# and correct function code should not hardcode one) -- so locally it
# always binds Deno's default, 8000. Functions are therefore run and
# curl-tested ONE AT A TIME below (start, curl, kill, start the next),
# never both bound to 8000 simultaneously.
fn_port="8000"
jwt_secret="local-only-test-secret-not-used-anywhere-real-0123456789"

pgrst_pid=""
proxy_pid=""
fn_pid=""

cleanup() {
  [[ -n "${fn_pid}" ]] && kill "${fn_pid}" >/dev/null 2>&1 || true
  [[ -n "${proxy_pid}" ]] && kill "${proxy_pid}" >/dev/null 2>&1 || true
  [[ -n "${pgrst_pid}" ]] && kill "${pgrst_pid}" >/dev/null 2>&1 || true
  if [[ -d "${nexo_pg_data}" ]]; then
    pg_ctl -D "${nexo_pg_data}" -m fast -w stop >/dev/null 2>&1 || true
  fi
  if [[ -z "${NEXO_KEEP_TMP:-}" && "${nexo_pg_tmp}" == /tmp/nexo-http-local.* && -d "${nexo_pg_tmp}" ]]; then
    rm -rf "${nexo_pg_tmp}"
  else
    echo "(debug) kept ${nexo_pg_tmp}"
  fi
}
trap cleanup EXIT

psql_() {
  psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" "$@"
}

echo "== 1) Booting bare Postgres and applying every migration =="
mkdir -p "${nexo_pg_socket}"
initdb -D "${nexo_pg_data}" -A trust -U postgres --no-locale >/dev/null
LC_ALL=C LANG=C pg_ctl -D "${nexo_pg_data}" -o "-p ${nexo_pg_port} -k ${nexo_pg_socket}" -w start >/dev/null
createdb -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres "${nexo_pg_database}"

psql_ >/dev/null <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create table auth.users (
  id uuid primary key, email text, raw_user_meta_data jsonb not null default '{}'::jsonb
);
SQL

for migration in supabase/migrations/*.sql; do
  psql_ -f "${migration}" >/dev/null
done
echo "Migrations applied."

echo "== 2) Seeding a user, active account/card, and a fixed test token =="
psql_ >/dev/null <<'SQL'
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90700000-0000-4000-8000-000000000001', 'http-local@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90700000-0000-4000-8000-000000000001', true);
do $$
begin
  perform public.create_account('Santander', 'checking', 'MXN', 0, null, null, 'http-account-01');
  perform public.create_credit_card('BBVA Oro', 'BBVA', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-01-01', 0, null, null, 'http-card-01');
end;
$$;
commit;
SQL
account_id="$(psql_ -X -A -t -c "select id from public.accounts where name = 'Santander';")"
account_id="${account_id// /}"

token_plain="nexo_shortcut_http_local_test_fixture_token_00000000000"
token_hash="$(printf '%s' "${token_plain}" | shasum -a 256 | awk '{print $1}')"
psql_ >/dev/null -c "
  insert into public.shortcut_tokens (user_id, name, token_hash, scopes)
  values ('90700000-0000-4000-8000-000000000001', 'HTTP local test token', '${token_hash}',
    array['shortcut:options:read', 'shortcut:transactions:write']);
"
echo "Seeded account=${account_id}, token_hash=${token_hash}"

echo "== 3) Minting a local-only service_role JWT (HS256, no library, Web Crypto) =="
service_role_jwt="$(JWT_SECRET_FOR_TEST="${jwt_secret}" deno run --allow-env scripts/_mint_test_jwt.ts)"
echo "Minted JWT (first 20 chars): ${service_role_jwt:0:20}..."

echo "== 4) Starting PostgREST =="
pgrst_config="${nexo_pg_tmp}/postgrest.conf"
cat > "${pgrst_config}" <<CONF
db-uri = "postgresql://postgres@127.0.0.1:${nexo_pg_port}/${nexo_pg_database}"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "${jwt_secret}"
server-port = ${pgrst_port}
server-host = "127.0.0.1"
CONF
postgrest "${pgrst_config}" > "${nexo_pg_tmp}/postgrest.log" 2>&1 &
pgrst_pid=$!
sleep 2
if ! curl -s -o /dev/null "http://127.0.0.1:${pgrst_port}/"; then
  echo "PostgREST did not come up. Log:"
  cat "${nexo_pg_tmp}/postgrest.log"
  exit 1
fi
echo "PostgREST is up on port ${pgrst_port}."

echo "== 4b) Starting the /rest/v1 -> PostgREST-root proxy (see scripts/_rest_v1_proxy.ts) =="
PROXY_TARGET="http://127.0.0.1:${pgrst_port}" PROXY_PORT="${proxy_port}" \
  deno run --allow-net --allow-env scripts/_rest_v1_proxy.ts > "${nexo_pg_tmp}/proxy.log" 2>&1 &
proxy_pid=$!
sleep 1
if ! curl -s -o /dev/null "http://127.0.0.1:${proxy_port}/rest/v1/"; then
  echo "Proxy did not come up. Log:"
  cat "${nexo_pg_tmp}/proxy.log"
  exit 1
fi
echo "Proxy is up on port ${proxy_port}, forwarding /rest/v1/* -> PostgREST."

failures=0
expect_status() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "  FAIL (${label}): expected HTTP ${expected}, got ${actual}"
    failures=$((failures + 1))
  else
    echo "  ok (${label}): HTTP ${actual}"
  fi
}

start_function() {
  local fn_dir="$1"
  [[ -n "${fn_pid}" ]] && { kill "${fn_pid}" >/dev/null 2>&1 || true; wait "${fn_pid}" 2>/dev/null || true; }
  SUPABASE_URL="http://127.0.0.1:${proxy_port}" \
  SUPABASE_SERVICE_ROLE_KEY="${service_role_jwt}" \
    deno run --allow-net --allow-env --allow-read "supabase/functions/${fn_dir}/index.ts" \
    > "${nexo_pg_tmp}/${fn_dir}.log" 2>&1 &
  fn_pid=$!
  for _ in $(seq 1 20); do
    curl -s -o /dev/null "http://127.0.0.1:${fn_port}" && break
    sleep 0.3
  done
}

echo ""
echo "== 5) shortcut-options: real curl requests against the real Deno.serve handler =="
start_function "shortcut-options"

echo "--- A: valid token -> expect 200 with accounts/cards/categories, no balances ---"
resp="$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${token_plain}" "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; body="$(echo "${resp}" | sed '$d')"
echo "  body: ${body}"
expect_status "A valid token" "200" "${status}"
if echo "${body}" | grep -qi "balance\|limit\|credit_limit"; then
  echo "  FAIL (A): response leaked a balance/limit field"
  failures=$((failures + 1))
fi

echo "--- B: invalid token -> expect 401 ---"
resp="$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer nexo_shortcut_totally_made_up_00000000000" "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; echo "  body: $(echo "${resp}" | sed '$d')"
expect_status "B invalid token" "401" "${status}"

echo "--- missing Authorization header -> expect 401 ---"
resp="$(curl -s -w "\n%{http_code}" "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; echo "  body: $(echo "${resp}" | sed '$d')"
expect_status "missing token" "401" "${status}"

echo "--- wrong method (POST) -> expect 405 ---"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"
expect_status "wrong method" "405" "${status}"

echo ""
echo "== 6) shortcut-transactions: real curl requests against the real Deno.serve handler =="
start_function "shortcut-transactions"

echo "--- F: valid account purchase, amount 450.50 -> expect 201, transaction_id present ---"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" -H "Content-Type: application/json" \
  -d "{\"shortcut_execution_id\":\"b0000000-0000-4000-8000-000000000001\",\"source_type\":\"account\",\"source_id\":\"${account_id}\",\"amount\":\"450.50\",\"category_id\":\"food\",\"description\":\"KFC\",\"transaction_date\":\"2026-09-01\"}" \
  "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; body="$(echo "${resp}" | sed '$d')"
echo "  body: ${body}"
expect_status "F valid account purchase" "201" "${status}"
if ! echo "${body}" | grep -q '"transaction_id"'; then
  echo "  FAIL (F): no transaction_id in response"
  failures=$((failures + 1))
fi

echo "--- U: retry same shortcut_execution_id + same payload -> expect success again, same transaction_id ---"
first_id="$(echo "${body}" | { grep -o '"transaction_id":"[^"]*"' || true; } | cut -d'"' -f4)"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" -H "Content-Type: application/json" \
  -d "{\"shortcut_execution_id\":\"b0000000-0000-4000-8000-000000000001\",\"source_type\":\"account\",\"source_id\":\"${account_id}\",\"amount\":\"450.50\",\"category_id\":\"food\",\"description\":\"KFC\",\"transaction_date\":\"2026-09-01\"}" \
  "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; body2="$(echo "${resp}" | sed '$d')"
retry_id="$(echo "${body2}" | { grep -o '"transaction_id":"[^"]*"' || true; } | cut -d'"' -f4)"
echo "  body: ${body2}"
if [[ "${first_id}" != "${retry_id}" || -z "${first_id}" ]]; then
  echo "  FAIL (U): retry returned a different transaction_id (${first_id} vs ${retry_id})"
  failures=$((failures + 1))
else
  echo "  ok (U): retry returned the same transaction_id, no duplicate movement"
fi

echo "--- V: same shortcut_execution_id, different amount -> expect 409 idempotency conflict ---"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" -H "Content-Type: application/json" \
  -d "{\"shortcut_execution_id\":\"b0000000-0000-4000-8000-000000000001\",\"source_type\":\"account\",\"source_id\":\"${account_id}\",\"amount\":\"999.00\",\"category_id\":\"food\",\"description\":\"KFC\",\"transaction_date\":\"2026-09-01\"}" \
  "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; echo "  body: $(echo "${resp}" | sed '$d')"
expect_status "V idempotency conflict" "409" "${status}"

echo "--- Q: invalid category -> expect 400 ---"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" -H "Content-Type: application/json" \
  -d "{\"shortcut_execution_id\":\"b0000000-0000-4000-8000-000000000002\",\"source_type\":\"account\",\"source_id\":\"${account_id}\",\"amount\":\"10.00\",\"category_id\":\"no_existe\",\"description\":\"x\",\"transaction_date\":\"2026-09-01\"}" \
  "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; echo "  body: $(echo "${resp}" | sed '$d')"
expect_status "Q invalid category" "400" "${status}"

echo "--- K: malformed UUID -> expect 400 ---"
resp="$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${token_plain}" -H "Content-Type: application/json" \
  -d "{\"shortcut_execution_id\":\"not-a-uuid\",\"source_type\":\"account\",\"source_id\":\"${account_id}\",\"amount\":\"10.00\",\"category_id\":\"food\",\"description\":\"x\"}" \
  "http://127.0.0.1:${fn_port}")"
status="$(echo "${resp}" | tail -n1)"; echo "  body: $(echo "${resp}" | sed '$d')"
expect_status "K malformed UUID" "400" "${status}"

echo "--- H: amount 450.50 minor-unit conversion, verified server-side against the account_entries row ---"
minor="$(psql_ -X -A -t -c "select amount_minor from public.account_entries where financial_event_id = '${first_id}';")"
minor="${minor// /}"
if [[ "${minor}" != "-45050" ]]; then
  echo "  FAIL (H): expected -45050 minor units, got ${minor}"
  failures=$((failures + 1))
else
  echo "  ok (H): 450.50 -> 45050 minor units confirmed in account_entries"
fi

echo ""
if [[ "${failures}" -gt 0 ]]; then
  echo "HTTP LOCAL TEST FAILED: ${failures} check(s) did not match expectations."
  exit 1
fi
echo "HTTP LOCAL TEST PASSED: all real curl requests against the real Deno.serve handlers behaved as expected."
