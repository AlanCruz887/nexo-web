#!/usr/bin/env bash
set -euo pipefail

nexo_pg_tmp="$(mktemp -d /tmp/nexo-postgres.XXXXXX)"
nexo_pg_data="${nexo_pg_tmp}/data"
nexo_pg_socket="${nexo_pg_tmp}/socket"
nexo_pg_port="$((55400 + RANDOM % 100))"
nexo_pg_database="nexo_test"

mkdir -p "${nexo_pg_socket}"

cleanup() {
  if [[ -d "${nexo_pg_data}" ]]; then
    pg_ctl -D "${nexo_pg_data}" -m fast -w stop >/dev/null 2>&1 || true
  fi
  if [[ "${nexo_pg_tmp}" == /tmp/nexo-postgres.* && -d "${nexo_pg_tmp}" ]]; then
    rm -rf "${nexo_pg_tmp}"
  fi
}
trap cleanup EXIT

initdb -D "${nexo_pg_data}" -A trust -U postgres --no-locale >/dev/null
pg_ctl -D "${nexo_pg_data}" -o "-p ${nexo_pg_port} -k ${nexo_pg_socket}" -w start >/dev/null
createdb -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres "${nexo_pg_database}"

psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" <<'SQL'
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
  echo "Applying ${migration}"
  psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" -f "${migration}" >/dev/null

  # Checkpoint: planned_cash_flows.recurrence still accepts 'monthly' right
  # after this migration (it created recurring_rules and migrated existing
  # 'monthly' rows, but has not yet tightened the CHECK constraint -- that
  # happens in the next migration). Run the one test that genuinely needs a
  # raw 'monthly' row to exist in the table here, before the constraint
  # that would make such a row impossible to insert ever applies.
  if [[ "$(basename "${migration}")" == "20260830080000_phase_7a_recurring_transactions.sql" ]]; then
    echo "Running checkpoint supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql"
    psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" \
      -f supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql
  fi
done

for test_file in supabase/tests/*.test.sql; do
  echo "Running ${test_file}"
  psql -v ON_ERROR_STOP=1 -h "${nexo_pg_socket}" -p "${nexo_pg_port}" -U postgres -d "${nexo_pg_database}" -f "${test_file}"
done

echo "Clean PostgreSQL migration rebuild and RLS tests passed."
