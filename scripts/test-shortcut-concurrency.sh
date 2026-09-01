#!/usr/bin/env bash
# Real concurrency check for public.execute_shortcut_transaction, closing
# the pending item from 7C-A: two genuinely separate OS processes/DB
# connections firing the SAME shortcut_execution_id + same payload at
# (as close to) the same instant as the OS scheduler allows, repeated
# across several trials. Never a "call it twice sequentially" stand-in --
# each trial is two real, independently-connecting `psql` processes
# launched in the background nearly simultaneously.
#
# Does not depend on Supabase real. Builds its own ephemeral bare
# Postgres cluster (same technique as scripts/test-db.sh), applies every
# migration, tears everything down on exit.
set -euo pipefail

nexo_pg_tmp="$(mktemp -d /tmp/nexo-postgres-concurrency.XXXXXX)"
nexo_pg_data="${nexo_pg_tmp}/data"
nexo_pg_socket="${nexo_pg_tmp}/socket"
nexo_pg_port="$((55600 + RANDOM % 100))"
nexo_pg_database="nexo_concurrency_test"
trials="${1:-20}"

mkdir -p "${nexo_pg_socket}"

cleanup() {
  if [[ -d "${nexo_pg_data}" ]]; then
    pg_ctl -D "${nexo_pg_data}" -m fast -w stop >/dev/null 2>&1 || true
  fi
  if [[ "${nexo_pg_tmp}" == /tmp/nexo-postgres-concurrency.* && -d "${nexo_pg_tmp}" ]]; then
    rm -rf "${nexo_pg_tmp}"
  fi
}
trap cleanup EXIT

psql_() {
  psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" "$@"
}

initdb -D "${nexo_pg_data}" -A trust -U postgres --no-locale >/dev/null
LC_ALL=C LANG=C pg_ctl -D "${nexo_pg_data}" -o "-p ${nexo_pg_port} -k ${nexo_pg_socket}" -w start >/dev/null
createdb -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres "${nexo_pg_database}"

psql_ <<'SQL' >/dev/null
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);
SQL

for migration in supabase/migrations/*.sql; do
  psql_ -f "${migration}" >/dev/null
done

echo "Schema ready. Seeding fixture..."

# Explicit begin/commit (not the throwaway begin/rollback the *.test.sql
# files use): SET LOCAL and set_config(..., true) are both transaction-
# scoped, and this data needs to actually persist for the concurrent
# trials that follow in separate connections/sessions afterward.
psql_ >/dev/null <<'SQL'
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90600000-0000-4000-8000-000000000001', 'concurrency@example.test', '{}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '90600000-0000-4000-8000-000000000001', true);

do $$
begin
  perform public.create_account('Cuenta concurrencia', 'checking', 'MXN', 0, null, null, 'conc-account-01');
end;
$$;
commit;
SQL

account_id="$(psql_ -X -A -t -c "select id from public.accounts where name = 'Cuenta concurrencia';")"
account_id="${account_id// /}"

echo "Fixture ready: account=${account_id}"
echo "Running ${trials} concurrent trials (two real psql processes per trial, same shortcut_execution_id + same payload)..."
echo "Each trial gets its own fresh token, so the 30/min-per-token rate limiter (also real, also wired in) never confounds this specific test."

failures=0
for trial in $(seq 1 "${trials}"); do
  execution_id="a0000000-0000-4000-8000-$(printf '%012d' "${trial}")"

  # A fresh, real token per trial -- execute_shortcut_transaction takes a
  # HASH, never the plaintext. A real create_shortcut_token call would
  # generate its own random bytes server-side and hand the plaintext
  # back once; this script instead seeds a fixed, trial-specific
  # plaintext directly (superuser insert, bypassing the RPC) so it can
  # be hashed the same way a real caller would.
  token_plain="nexo_shortcut_concurrency_trial_${trial}_fixture_token"
  token_hash="$(printf '%s' "${token_plain}" | shasum -a 256 | awk '{print $1}')"
  psql_ >/dev/null -c "
    insert into public.shortcut_tokens (user_id, name, token_hash, scopes)
    values ('90600000-0000-4000-8000-000000000001', 'Token trial ${trial}', '${token_hash}',
      array['shortcut:options:read', 'shortcut:transactions:write']);
  "

  out1="${nexo_pg_tmp}/trial-${trial}-a.out"
  out2="${nexo_pg_tmp}/trial-${trial}-b.out"

  psql_ -X -A -t -c "
    set local role service_role;
    select ok, event_id, error_code
    from public.execute_shortcut_transaction(
      '${token_hash}', '${execution_id}', 'account', '${account_id}',
      1000, 'food', 'Concurrencia real', '2020-01-15'
    );
  " > "${out1}" 2>&1 &
  pid1=$!

  psql_ -X -A -t -c "
    set local role service_role;
    select ok, event_id, error_code
    from public.execute_shortcut_transaction(
      '${token_hash}', '${execution_id}', 'account', '${account_id}',
      1000, 'food', 'Concurrencia real', '2020-01-15'
    );
  " > "${out2}" 2>&1 &
  pid2=$!

  wait "${pid1}" "${pid2}"

  event_count="$(psql_ -X -A -t -c "
    select count(*) from public.account_entries ae
    join private.shortcut_token_usage u on u.financial_event_id = ae.financial_event_id
    where u.shortcut_execution_id = '${execution_id}';
  ")"
  usage_count="$(psql_ -X -A -t -c "
    select count(*) from private.shortcut_token_usage where shortcut_execution_id = '${execution_id}';
  ")"

  if [[ "${event_count// /}" != "1" || "${usage_count// /}" != "1" ]]; then
    echo "TRIAL ${trial}: FAIL -- account_entries rows for this execution=${event_count}, usage rows=${usage_count}"
    echo "  process A output: $(cat "${out1}")"
    echo "  process B output: $(cat "${out2}")"
    failures=$((failures + 1))
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  echo "CONCURRENCY TEST FAILED: ${failures} of ${trials} trials produced more than one movement/usage row for the same execution id."
  exit 1
fi

echo "CONCURRENCY TEST PASSED: ${trials}/${trials} trials -- exactly one financial_event and one shortcut_token_usage row per shortcut_execution_id, even with two genuinely concurrent processes."
