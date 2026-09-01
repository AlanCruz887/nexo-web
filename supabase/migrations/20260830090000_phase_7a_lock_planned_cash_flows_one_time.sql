-- Phase 7A, part 2: lock planned_cash_flows down to one_time permanently
-- at the schema level.
--
-- The previous migration (20260830080000) already converted every existing
-- 'monthly' row into its recurring_rule equivalent and already enforces
-- 'one_time'-only at the RPC layer (create_planned_cash_flow/
-- update_planned_cash_flow reject anything else) and at the read layer
-- (get_financial_plan only reads recurrence = 'one_time'). This migration
-- adds the third, strongest layer: a database CHECK constraint that makes
-- 'monthly' structurally impossible to insert again, from any writer.
--
-- Split into its own migration, applied strictly after the data backfill,
-- so the constraint can never be tightened before every existing row has
-- already been converted -- "migrar primero los datos, luego reemplazar
-- el CHECK", not the other way around. scripts/test-db.sh runs a
-- dedicated checkpoint test (supabase/tests/_checkpoints/
-- planned_cash_flows_prelock.test.sql) immediately after the migration
-- above and before this one, so the migration function's behavior against
-- genuinely preexisting 'monthly' data is still exercised by an
-- automated test -- this constraint is not weakened for that reason.

-- Defensive re-run: idempotent by construction (private.migrate_planned_
-- cash_flow_monthly_rows only touches rows that don't already have a
-- migrated_from_planned_cash_flow_id), so this is a safe no-op if
-- 20260830080000 already converted everything, and a real safety net if
-- any 'monthly' row was somehow inserted directly (by service_role) in
-- the window between the two migrations.
select private.migrate_planned_cash_flow_monthly_rows();

alter table public.planned_cash_flows
  drop constraint planned_cash_flows_recurrence_valid,
  add constraint planned_cash_flows_recurrence_valid check (recurrence = 'one_time');

comment on column public.planned_cash_flows.recurrence is
  'Always ''one_time'' -- enforced by this CHECK since Phase 7A. Every recurring commitment lives in recurring_rules instead. The column is kept (rather than dropped) only because removing it is a breaking read-shape change with no functional benefit yet.';
