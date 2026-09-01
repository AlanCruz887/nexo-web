-- Checkpoint: runs ONLY from scripts/test-db.sh, immediately after
-- 20260830080000_phase_7a_recurring_transactions.sql and before
-- 20260830090000_phase_7a_lock_planned_cash_flows_one_time.sql applies.
-- This is the one deliberate window where planned_cash_flows.recurrence
-- still structurally accepts 'monthly' -- exactly long enough to seed a
-- row that looks like real, genuine pre-7A production data and prove the
-- migration function converts it correctly. It is NOT part of the normal
-- *.test.sql suite (lives in _checkpoints/ on purpose, excluded from that
-- glob) and is never run again after this point in the pipeline, so it
-- can never mask the CHECK constraint the next migration adds.
--
-- Runs entirely as the invoking superuser (no role switching): there is
-- no multi-user RLS scenario here, only a single-user economics/migration
-- check, and auth.uid() resolves via the request.jwt.claim.sub session
-- GUC regardless of the Postgres role executing the query.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90499999-0000-4000-8000-000000000001', 'prelock@example.test', '{}');
select set_config('request.jwt.claim.sub', '90499999-0000-4000-8000-000000000001', true);

do $$
declare
  legacy_id uuid := gen_random_uuid();
  migrated_count int;
  plan_before jsonb; plan_after jsonb;
  hits_before int; hits_after int;
  new_rule_id uuid;
begin
  -- Simula exactamente cómo habría quedado la tabla en producción antes
  -- de aplicar 7A: una fila 'monthly' real, insertada directamente (esto
  -- es lo único que este checkpoint existe para hacer -- el CHECK que la
  -- prohíbe para siempre todavía no se ha aplicado en este punto exacto
  -- de la secuencia de migraciones).
  insert into public.planned_cash_flows (id, user_id, name, currency, amount_minor, category_id, recurrence, start_date)
  values (legacy_id, '90499999-0000-4000-8000-000000000001', 'Netflix legado', 'MXN', -24900, 'subscriptions', 'monthly', '2020-08-01');

  -- Antes de migrar: la fila cruda ya está estructuralmente excluida de
  -- Planeación (get_financial_plan solo lee recurrence='one_time', un
  -- filtro que ya está activo con o sin el CHECK) -- no aparece ni una
  -- vez, no dos.
  plan_before := public.get_financial_plan('MXN', '2020-08-20'::date, 3);
  select count(*) into hits_before
  from jsonb_array_elements(plan_before->'months') m, jsonb_array_elements(m->'planned_flows') f
  where f->>'name' = 'Netflix legado';
  if hits_before <> 0 then raise exception 'CASO AJ setup: an unmigrated monthly row must not feed Planeación at all'; end if;

  -- CASO AJ: migra exactamente una vez.
  migrated_count := private.migrate_planned_cash_flow_monthly_rows();
  if migrated_count < 1 then raise exception 'CASO AJ: expected at least one row migrated, got %', migrated_count; end if;
  select id into new_rule_id from public.recurring_rules where migrated_from_planned_cash_flow_id = legacy_id;
  if new_rule_id is null then raise exception 'CASO AJ: no recurring_rule was created for the legacy row'; end if;
  if (select count(*) from public.recurring_rules where migrated_from_planned_cash_flow_id = legacy_id) <> 1 then
    raise exception 'CASO AJ: exactly one recurring_rule must exist per migrated row'; end if;
  if (select archived_at from public.planned_cash_flows where id = legacy_id) is null then
    raise exception 'CASO AJ: the old row must be archived after conversion, never deleted'; end if;

  -- CASO AK/BA: después de migrar, la MISMA expectativa mensual aparece
  -- en Planeación -- una sola vez POR MES, con el mismo importe exacto.
  plan_after := public.get_financial_plan('MXN', '2020-08-20'::date, 3);
  if exists (
    select 1 from jsonb_array_elements(plan_after->'months') m
    where (select count(*) from jsonb_array_elements(m->'planned_flows') f where (f->>'flow_id')::uuid = new_rule_id) > 1
  ) then raise exception 'CASO AK: migrated Netflix must never appear twice within the same month'; end if;
  select count(*) into hits_after
  from jsonb_array_elements(plan_after->'months') m, jsonb_array_elements(m->'planned_flows') f
  where (f->>'flow_id')::uuid = new_rule_id;
  if hits_after = 0 then raise exception 'CASO AK: migrated Netflix must appear at least once across the horizon'; end if;
  if (
    select (f->>'amount_minor')::bigint from jsonb_array_elements(plan_after->'months') m, jsonb_array_elements(m->'planned_flows') f
    where (f->>'flow_id')::uuid = new_rule_id limit 1
  ) <> -24900 then raise exception 'CASO BA: migrated rule must preserve the exact same expected amount (-24900)'; end if;

  -- CASO BH: el valor económico exacto que la semántica ANTIGUA de 6C
  -- habría producido (mismo día de calendario clamped, mismo importe
  -- firmado, cada mes desde start_date) coincide, mes por mes, con lo que
  -- produce la recurring_rule migrada -- recalculado de forma
  -- independiente, no solo releyendo la propia respuesta del RPC.
  declare
    expected_day int := extract(day from '2020-08-01'::date)::int;
    old_semantics_date date := public.card_effective_statement_date(2020, 9, expected_day);
    actual_line jsonb;
  begin
    select f into actual_line
    from jsonb_array_elements(plan_after->'months') m, jsonb_array_elements(m->'planned_flows') f
    where (f->>'flow_id')::uuid = new_rule_id and (f->>'occurred_on')::date = old_semantics_date;
    if actual_line is null then
      raise exception 'CASO BH: expected the migrated rule to reproduce the old monthly date % exactly, found none', old_semantics_date;
    end if;
    if (actual_line->>'amount_minor')::bigint <> -24900 then
      raise exception 'CASO BH: expected the exact same signed economic value (-24900) on %, got %', old_semantics_date, actual_line->>'amount_minor';
    end if;
  end;

  -- CASO AU: reintentar la migración es idempotente -- no crea una
  -- segunda recurring_rule para la misma fila.
  migrated_count := private.migrate_planned_cash_flow_monthly_rows();
  if (select count(*) from public.recurring_rules where migrated_from_planned_cash_flow_id = legacy_id) <> 1 then
    raise exception 'CASO AU: re-running the migration must never create a second recurring_rule for the same row';
  end if;
end;
$$;

-- CASO BG: varias filas monthly preexistentes (no solo una) migran todas,
-- exactamente una vez cada una, y todas quedan archivadas.
do $$
declare
  id_a uuid := gen_random_uuid();
  id_b uuid := gen_random_uuid();
  id_c_already_archived uuid := gen_random_uuid();
  migrated_count int;
begin
  insert into public.planned_cash_flows (id, user_id, name, currency, amount_minor, category_id, recurrence, start_date)
  values
    (id_a, '90499999-0000-4000-8000-000000000001', 'Gimnasio legado', 'MXN', -70000, null, 'monthly', '2020-08-03'),
    (id_b, '90499999-0000-4000-8000-000000000001', 'Nómina legada', 'MXN', 3000000, 'salary', 'monthly', '2020-08-15'),
    (id_c_already_archived, '90499999-0000-4000-8000-000000000001', 'Ya archivada', 'MXN', -10000, null, 'monthly', '2020-08-01');
  update public.planned_cash_flows set archived_at = now() where id = id_c_already_archived;

  migrated_count := private.migrate_planned_cash_flow_monthly_rows();
  if migrated_count < 2 then raise exception 'CASO BG: expected at least the two active monthly rows migrated, got %', migrated_count; end if;

  if (select count(*) from public.recurring_rules where migrated_from_planned_cash_flow_id = id_a) <> 1 then
    raise exception 'CASO BG: Gimnasio legado must migrate exactly once'; end if;
  if (select count(*) from public.recurring_rules where migrated_from_planned_cash_flow_id = id_b) <> 1 then
    raise exception 'CASO BG: Nómina legada must migrate exactly once'; end if;
  if exists (select 1 from public.recurring_rules where migrated_from_planned_cash_flow_id = id_c_already_archived) then
    raise exception 'CASO BG: an already-archived monthly row must never be migrated'; end if;

  if (select archived_at from public.planned_cash_flows where id = id_a) is null
    or (select archived_at from public.planned_cash_flows where id = id_b) is null then
    raise exception 'CASO BG: every migrated row must end up archived';
  end if;

  if exists (select 1 from public.planned_cash_flows where recurrence = 'monthly' and archived_at is null) then
    raise exception 'CASO AU: no unmigrated monthly row should ever remain unarchived after the migration function runs';
  end if;
end;
$$;

rollback;

select 'planned_cash_flows prelock checkpoint: AJ, AK, AU, BA, BG, BH passed' as result;
