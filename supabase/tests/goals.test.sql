-- Phase 6B: savings goals. Covers cases A-AB from the design brief plus the
-- permanent invariants for the FIFO backing algorithm.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90200000-0000-4000-8000-000000000001', 'goals-a@example.test', '{}'),
  ('90200000-0000-4000-8000-000000000002', 'goals-b@example.test', '{}');

create temporary table goal_ids (
  santander uuid, bbva uuid, usd_account uuid, japon uuid, emergencia uuid
);
insert into goal_ids default values;
grant select, update on goal_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000001', true);

do $$
declare santander_var uuid; bbva_var uuid; usd_var uuid; japon_var uuid; emergencia_var uuid;
begin
  santander_var := public.create_account('Santander', 'checking', 'MXN', 5000000, null, null, 'goal-account-santander-01');
  bbva_var := public.create_account('BBVA', 'checking', 'MXN', 0, null, null, 'goal-account-bbva-01');
  usd_var := public.create_account('Cuenta USD', 'checking', 'USD', 500000, null, null, 'goal-account-usd-01');

  -- CASO A: crear meta -> progreso $0.
  japon_var := public.create_goal('Viaje a Japón', 'MXN', 8000000, '2027-12-01'::date, null, null, 'goal-create-japon-01');
  emergencia_var := public.create_goal('Fondo de emergencia', 'MXN', 10000000, null, null, null, 'goal-create-emergencia-01');

  update goal_ids set santander = santander_var, bbva = bbva_var, usd_account = usd_var,
    japon = japon_var, emergencia = emergencia_var;
end;
$$;

do $$
declare ids goal_ids%rowtype; balance jsonb;
begin
  select * into ids from goal_ids;
  select to_jsonb(b) into balance from public.goal_balances b where b.id = ids.japon;
  if (balance->>'saved_minor')::bigint <> 0 then
    raise exception 'CASO A: progreso inicial deberia ser 0, es %', balance->>'saved_minor'; end if;
end;
$$;

-- CASO B/C: aportar $10,000 y luego $5,000 -> progreso $15,000.
do $$
declare ids goal_ids%rowtype;
begin
  select * into ids from goal_ids;
  perform public.contribute_to_goal(ids.japon, 1000000, ids.santander, false, '2026-08-01'::date, null, 'goal-caso-b-001');
  perform public.contribute_to_goal(ids.japon, 500000, ids.santander, false, '2026-08-02'::date, null, 'goal-caso-c-001');
end;
$$;

do $$
declare ids goal_ids%rowtype; balance jsonb;
begin
  select * into ids from goal_ids;
  select to_jsonb(b) into balance from public.goal_balances b where b.id = ids.japon;
  if (balance->>'saved_minor')::bigint <> 1500000 then
    raise exception 'CASO B/C: progreso deberia ser 1500000, es %', balance->>'saved_minor'; end if;
end;
$$;

-- CASO D: retirar $3,000 -> progreso $12,000.
do $$
declare ids goal_ids%rowtype; balance jsonb;
begin
  select * into ids from goal_ids;
  perform public.withdraw_from_goal(ids.japon, 300000, null, false, null, '2026-08-03'::date, null, 'goal-caso-d-001');
  select to_jsonb(b) into balance from public.goal_balances b where b.id = ids.japon;
  if (balance->>'saved_minor')::bigint <> 1200000 then
    raise exception 'CASO D: progreso deberia ser 1200000, es %', balance->>'saved_minor'; end if;
end;
$$;

-- CASO E: objetivo $10,000, progreso $12,000 -> 120%, sin truncar.
do $$
declare goal_id uuid; balance jsonb;
begin
  goal_id := public.create_goal('Meta pequeña', 'MXN', 1000000, null, null, null, 'goal-caso-e-001');
  perform public.contribute_to_goal(goal_id, 1200000, (select santander from goal_ids), false, '2026-08-04'::date, null, 'goal-caso-e-contrib-001');
  select to_jsonb(b) into balance from public.goal_balances b where b.id = goal_id;
  if (balance->>'percentage')::int <> 120 then
    raise exception 'CASO E: porcentaje deberia ser 120, es %', balance->>'percentage'; end if;
  if (balance->>'is_achieved')::boolean <> true then
    raise exception 'CASO E: is_achieved deberia ser true'; end if;
end;
$$;

-- CASO F/G: ninguna operación de meta crea income ni expense.
do $$
declare bad_count integer;
begin
  select count(*) into bad_count from public.financial_events
  where user_id = '90200000-0000-4000-8000-000000000001' and kind in ('income', 'expense');
  if bad_count <> 0 then
    raise exception 'CASO F/G: no deberia existir ningun income/expense creado por operaciones de meta, hay %', bad_count; end if;
end;
$$;

-- CASO H: transferencia real (aportación con p_move_real_money=true) no
-- cambia el patrimonio neto -- suma de saldos de cuentas antes y despues es igual.
do $$
declare
  goal_id uuid; total_before bigint; total_after bigint;
begin
  goal_id := public.create_goal('Meta con cuenta vinculada', 'MXN', 5000000,
    null, (select bbva from goal_ids), null, 'goal-caso-h-001');
  select coalesce(sum(balance_minor), 0) into total_before from public.account_balances
  where user_id = '90200000-0000-4000-8000-000000000001' and currency = 'MXN';
  perform public.contribute_to_goal(goal_id, 200000, (select santander from goal_ids), true, '2026-08-05'::date, null, 'goal-caso-h-contrib-001');
  select coalesce(sum(balance_minor), 0) into total_after from public.account_balances
  where user_id = '90200000-0000-4000-8000-000000000001' and currency = 'MXN';
  if total_before <> total_after then
    raise exception 'CASO H: el patrimonio (suma de saldos MXN) no debe cambiar por una transferencia real, antes=%, despues=%',
      total_before, total_after;
  end if;
end;
$$;

-- CASO I/X: meta MXN no acepta cuenta de respaldo en USD.
do $$
declare ids goal_ids%rowtype;
begin
  select * into ids from goal_ids;
  begin
    perform public.contribute_to_goal(ids.japon, 100000, ids.usd_account, false, '2026-08-06'::date, null, 'goal-caso-i-001');
    raise exception 'CASO I/X: no debio permitir una aportacion en moneda distinta';
  exception when others then
    if sqlerrm not like '%NEXO_GOAL_CURRENCY_MISMATCH%' then raise; end if;
  end;
end;
$$;

reset role;

-- CASO J: archivar la cuenta origen no borra la aportación histórica.
do $$
declare ids goal_ids%rowtype;
begin
  select * into ids from goal_ids;
  update public.accounts set is_active = false where id = ids.santander;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000001', true);

do $$
declare ids goal_ids%rowtype; historical_count integer; archived_shown boolean;
begin
  select * into ids from goal_ids;
  select count(*) into historical_count from public.goal_entry_activity
  where goal_id = ids.japon and account_id = ids.santander;
  if historical_count = 0 then
    raise exception 'CASO J: la aportacion historica de Santander no debe desaparecer al archivar la cuenta'; end if;
  select bool_and(not account_is_active) into archived_shown from public.goal_entry_activity
  where goal_id = ids.japon and account_id = ids.santander;
  if not archived_shown then
    raise exception 'CASO J: el detalle deberia reflejar que la cuenta esta archivada'; end if;

  -- W: cuenta archivada no acepta nuevas reservas.
  begin
    perform public.contribute_to_goal(ids.japon, 10000, ids.santander, false, '2026-08-07'::date, null, 'goal-caso-w-001');
    raise exception 'CASO W: no debio permitir reservar contra una cuenta archivada';
  exception when others then
    if sqlerrm not like '%NEXO_ACCOUNT_ARCHIVED%' then raise; end if;
  end;
end;
$$;

reset role;
-- Restaurar Santander para el resto de las pruebas.
do $$ begin update public.accounts set is_active = true where id = (select santander from goal_ids); end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000001', true);

-- CASO K: archivar una meta conserva su historial.
do $$
declare ids goal_ids%rowtype; count_before integer; count_after integer;
begin
  select * into ids from goal_ids;
  select count(*) into count_before from public.goal_entries where goal_id = ids.japon;
  perform public.archive_goal(ids.japon, 'goal-caso-k-archive-001');
  select count(*) into count_after from public.goal_entries where goal_id = ids.japon;
  if count_before <> count_after then
    raise exception 'CASO K: archivar la meta no debe alterar su historial de movimientos'; end if;
  if (select archived_at from public.goals where id = ids.japon) is null then
    raise exception 'CASO K: la meta deberia quedar marcada como archivada'; end if;
  perform public.restore_goal(ids.japon, 'goal-caso-k-restore-001');
end;
$$;

-- CASO L: reversión reconstruye el progreso correctamente.
do $$
declare
  goal_id uuid; entry_id uuid; before_saved bigint; after_saved bigint; after_reverse bigint;
begin
  goal_id := public.create_goal('Meta reversión', 'MXN', 2000000, null, null, null, 'goal-caso-l-001');
  entry_id := public.contribute_to_goal(goal_id, 500000, (select santander from goal_ids), false, '2026-08-08'::date, null, 'goal-caso-l-contrib-001');
  select saved_minor into after_saved from public.goal_balances where id = goal_id;
  if after_saved <> 500000 then raise exception 'CASO L: progreso tras aportar deberia ser 500000, es %', after_saved; end if;

  perform public.reverse_goal_entry(entry_id, 'goal-caso-l-reverse-001');
  select saved_minor into after_reverse from public.goal_balances where id = goal_id;
  if after_reverse <> 0 then raise exception 'CASO L: progreso tras revertir deberia ser 0, es %', after_reverse; end if;
end;
$$;

-- CASO AA: una misma goal_entry no puede revertirse dos veces.
do $$
declare
  goal_id uuid; entry_id uuid;
begin
  goal_id := public.create_goal('Meta AA', 'MXN', 1000000, null, null, null, 'goal-caso-aa-001');
  entry_id := public.contribute_to_goal(goal_id, 100000, (select santander from goal_ids), false, '2026-08-09'::date, null, 'goal-caso-aa-contrib-001');
  perform public.reverse_goal_entry(entry_id, 'goal-caso-aa-reverse-001');
  begin
    perform public.reverse_goal_entry(entry_id, 'goal-caso-aa-reverse-002');
    raise exception 'CASO AA: no debio permitir revertir la misma entrada dos veces';
  exception when others then
    if sqlerrm not like '%NEXO_GOAL_ENTRY_ALREADY_REVERSED%' then raise; end if;
  end;
end;
$$;

-- CASO N/O: cálculo de cantidad mensual con y sin target_date.
do $$
declare
  with_date uuid; without_date uuid; balance jsonb;
begin
  with_date := public.create_goal('Meta con fecha', 'MXN', 1200000, (current_date + interval '12 months')::date, null, null, 'goal-caso-n-001');
  without_date := public.create_goal('Meta sin fecha', 'MXN', 1200000, null, null, null, 'goal-caso-o-001');

  select to_jsonb(b) into balance from public.goal_balances b where b.id = with_date;
  if (balance->>'recommended_monthly_minor') is null then
    raise exception 'CASO N: deberia calcular una cantidad mensual cuando hay target_date'; end if;
  if (balance->>'months_remaining')::int < 11 or (balance->>'months_remaining')::int > 13 then
    raise exception 'CASO N: months_remaining fuera de rango esperado, es %', balance->>'months_remaining'; end if;

  select to_jsonb(b) into balance from public.goal_balances b where b.id = without_date;
  if (balance->>'recommended_monthly_minor') is not null or (balance->>'months_remaining') is not null then
    raise exception 'CASO O: sin target_date no debe haber calculo mensual'; end if;
  if (balance->>'saved_minor')::bigint <> 0 or (balance->>'percentage')::int <> 0 then
    raise exception 'CASO O: una meta sin target_date debe funcionar normalmente para el resto de sus campos'; end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASOS P/Q/R/S/T/U/V/W(ya cubierto arriba)/Y/Z/AB: respaldo por cuenta.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90200000-0000-4000-8000-000000000003', 'goals-backing@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000003', true);

do $$
declare
  santander_var uuid; goal_japon_var uuid; goal_emergencia_var uuid; entry_id uuid;
begin
  santander_var := public.create_account('Santander', 'checking', 'MXN', 1000000, null, null, 'backing-account-01');
  goal_japon_var := public.create_goal('Japón', 'MXN', 8000000, null, null, null, 'backing-goal-japon-01');
  goal_emergencia_var := public.create_goal('Emergencia', 'MXN', 10000000, null, null, null, 'backing-goal-emerg-01');

  -- CASO P: reservar 8000 de 10000 -> permitido.
  perform public.contribute_to_goal(goal_japon_var, 800000, santander_var, false, '2026-08-01'::date, null, 'backing-caso-p-001');

  -- CASO Q: intentar reservar 5000 mas (solo quedan 2000) -> rechazado.
  begin
    perform public.contribute_to_goal(goal_emergencia_var, 500000, santander_var, false, '2026-08-02'::date, null, 'backing-caso-q-001');
    raise exception 'CASO Q: no debio permitirse reservar mas de lo disponible';
  exception when others then
    if sqlerrm not like '%NEXO_GOAL_RESERVATION_EXCEEDS_AVAILABLE%' then raise; end if;
  end;

  -- CASO R: retirar virtualmente 3000 de Japon.
  perform public.withdraw_from_goal(goal_japon_var, 300000, null, false, null, '2026-08-03'::date, null, 'backing-caso-r-001');
  if (select saved_minor from public.goal_balances where id = goal_japon_var) <> 500000 then
    raise exception 'CASO R: Japon deberia quedar en 500000'; end if;
  if (select balance_minor from public.account_balances where id = santander_var) <> 1000000 then
    raise exception 'CASO R: el saldo real de Santander no debe cambiar por un retiro virtual'; end if;
  if (select coalesce(sum(amount_minor), 0) from public.goal_entries where account_id = santander_var) <> 500000 then
    raise exception 'CASO R: la reserva total contra Santander deberia quedar en 500000'; end if;

  -- Con los 300000 liberados, ahora si cabe la reserva de emergencia (2000+3000=5000<=5000 disponibles).
  perform public.contribute_to_goal(goal_emergencia_var, 500000, santander_var, false, '2026-08-04'::date, null, 'backing-caso-s-001');
  if (select coalesce(sum(amount_minor), 0) from public.goal_entries where account_id = santander_var) <> 1000000 then
    raise exception 'CASO S: la suma reservada nunca debe superar el saldo real (1000000)'; end if;
end;
$$;

-- CASO T: una meta con reservas de DOS cuentas distintas, sin perder trazabilidad.
-- Usa una cuenta nueva y amplia (no la Santander de P-S, que ya quedo
-- totalmente reservada por diseño de esa prueba) para no mezclar aritmética.
do $$
declare
  amplia_var uuid; bbva_var uuid; goal_id_var uuid; count_accounts integer;
begin
  amplia_var := public.create_account('Cuenta amplia', 'checking', 'MXN', 100000000, null, null, 'backing-account-amplia-01');
  bbva_var := public.create_account('BBVA', 'checking', 'MXN', 500000, null, null, 'backing-account-bbva-01');
  goal_id_var := public.create_goal('Multi cuenta', 'MXN', 900000, null, null, null, 'backing-goal-multi-01');
  perform public.contribute_to_goal(goal_id_var, 500000, amplia_var, false, '2026-08-05'::date, null, 'backing-caso-t-santander-001');
  perform public.contribute_to_goal(goal_id_var, 300000, bbva_var, false, '2026-08-06'::date, null, 'backing-caso-t-bbva-001');

  select count(distinct account_id) into count_accounts from public.goal_entry_activity where goal_id = goal_id_var and entry_kind = 'contribution';
  if count_accounts <> 2 then
    raise exception 'CASO T: la meta deberia tener trazabilidad de 2 cuentas distintas, tiene %', count_accounts; end if;
  if (select saved_minor from public.goal_balances where id = goal_id_var) <> 800000 then
    raise exception 'CASO T: el progreso deberia ser 800000 combinando ambas cuentas'; end if;
end;
$$;

-- CASO U: reversión de aportación virtual libera exactamente la reserva de
-- la cuenta correspondiente (y no otra).
do $$
declare
  bbva_id uuid; santander_id uuid; goal_id uuid; entry_santander uuid; entry_bbva uuid;
  reserved_santander_before bigint; reserved_santander_after bigint;
  reserved_bbva_before bigint; reserved_bbva_after bigint;
begin
  select id into santander_id from public.accounts where user_id = '90200000-0000-4000-8000-000000000003' and name = 'Cuenta amplia';
  select id into bbva_id from public.accounts where user_id = '90200000-0000-4000-8000-000000000003' and name = 'BBVA';
  goal_id := public.create_goal('Meta U', 'MXN', 900000, null, null, null, 'backing-goal-u-001');
  entry_santander := public.contribute_to_goal(goal_id, 100000, santander_id, false, '2026-08-07'::date, null, 'backing-caso-u-santander-001');
  entry_bbva := public.contribute_to_goal(goal_id, 100000, bbva_id, false, '2026-08-07'::date, null, 'backing-caso-u-bbva-001');

  select coalesce(sum(amount_minor), 0) into reserved_santander_before from public.goal_entries where account_id = santander_id;
  select coalesce(sum(amount_minor), 0) into reserved_bbva_before from public.goal_entries where account_id = bbva_id;

  perform public.reverse_goal_entry(entry_santander, 'backing-caso-u-reverse-001');

  select coalesce(sum(amount_minor), 0) into reserved_santander_after from public.goal_entries where account_id = santander_id;
  select coalesce(sum(amount_minor), 0) into reserved_bbva_after from public.goal_entries where account_id = bbva_id;

  if reserved_santander_after <> reserved_santander_before - 100000 then
    raise exception 'CASO U: la reversa deberia liberar exactamente 100000 de Santander'; end if;
  if reserved_bbva_after <> reserved_bbva_before then
    raise exception 'CASO U: la reversa de Santander no debe afectar la reserva de BBVA'; end if;
end;
$$;

-- CASO V: reversión de aportación real revierte meta + transferencia atómicamente.
do $$
declare
  bbva_id uuid; santander_id uuid; goal_id uuid; entry_id uuid; transfer_event uuid;
  santander_before bigint; bbva_before bigint; santander_after bigint; bbva_after bigint;
begin
  select id into santander_id from public.accounts where user_id = '90200000-0000-4000-8000-000000000003' and name = 'Cuenta amplia';
  select id into bbva_id from public.accounts where user_id = '90200000-0000-4000-8000-000000000003' and name = 'BBVA';
  goal_id := public.create_goal('Meta V', 'MXN', 900000, null, bbva_id, null, 'backing-goal-v-001');

  select balance_minor into santander_before from public.account_balances where id = santander_id;
  select balance_minor into bbva_before from public.account_balances where id = bbva_id;

  entry_id := public.contribute_to_goal(goal_id, 50000, santander_id, true, '2026-08-08'::date, null, 'backing-caso-v-contrib-001');
  select financial_event_id into transfer_event from public.goal_entries where id = entry_id;
  if transfer_event is null then raise exception 'CASO V: la aportacion real deberia tener financial_event_id'; end if;

  perform public.reverse_goal_entry(entry_id, 'backing-caso-v-reverse-001');

  select balance_minor into santander_after from public.account_balances where id = santander_id;
  select balance_minor into bbva_after from public.account_balances where id = bbva_id;
  if santander_after <> santander_before or bbva_after <> bbva_before then
    raise exception 'CASO V: revertir debe restaurar ambos saldos exactamente (Santander %/%, BBVA %/%)',
      santander_before, santander_after, bbva_before, bbva_after;
  end if;
  if (select saved_minor from public.goal_balances where id = goal_id) <> 0 then
    raise exception 'CASO V: el progreso de la meta debe volver a 0'; end if;
end;
$$;

-- CASO Y: una reserva antigua se retira completamente y luego se vuelve a
-- aportar. La nueva aportación NO conserva prioridad FIFO antigua.
do $$
declare
  santander_id uuid; goal_id_var uuid; old_lot_id uuid; new_lot_id uuid; alive_count integer; alive_id uuid;
begin
  select id into santander_id from public.accounts where user_id = '90200000-0000-4000-8000-000000000003' and name = 'Cuenta amplia';
  goal_id_var := public.create_goal('Meta Y', 'MXN', 900000, null, null, null, 'backing-goal-y-001');
  old_lot_id := public.contribute_to_goal(goal_id_var, 100000, santander_id, false, '2026-08-01'::date, null, 'backing-caso-y-old-001');
  perform public.withdraw_from_goal(goal_id_var, 100000, santander_id, false, null, '2026-08-02'::date, null, 'backing-caso-y-withdraw-001');
  new_lot_id := public.contribute_to_goal(goal_id_var, 100000, santander_id, false, '2026-08-15'::date, null, 'backing-caso-y-new-001');

  select count(*) into alive_count from public.goal_lot_remaining
  where goal_id = goal_id_var and account_id = santander_id and remaining_minor > 0;
  if alive_count <> 1 then
    raise exception 'CASO Y: solo debe quedar un lote vivo, hay %', alive_count; end if;

  select id into alive_id from public.goal_lot_remaining
  where goal_id = goal_id_var and account_id = santander_id and remaining_minor > 0;
  if alive_id <> new_lot_id then
    raise exception 'CASO Y: el lote vivo debe ser la aportacion nueva (%), no la antigua (%)', new_lot_id, old_lot_id;
  end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO Z: dos metas compiten por una cuenta cuyo saldo baja despues.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90200000-0000-4000-8000-000000000004', 'goals-z@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000004', true);

do $$
declare
  account_id uuid; goal_a uuid; goal_b uuid;
  backed_a bigint; backed_b bigint; saved_a bigint; saved_b bigint; account_balance bigint;
begin
  account_id := public.create_account('Cuenta Z', 'checking', 'MXN', 1000000, null, null, 'z-account-001');
  goal_a := public.create_goal('Meta A', 'MXN', 900000, null, null, null, 'z-goal-a-001');
  goal_b := public.create_goal('Meta B', 'MXN', 900000, null, null, null, 'z-goal-b-001');

  -- A reserva primero (mas antigua), B despues -- juntas llenan exactamente el saldo.
  perform public.contribute_to_goal(goal_a, 600000, account_id, false, '2026-08-01'::date, null, 'z-contrib-a-001');
  perform public.contribute_to_goal(goal_b, 400000, account_id, false, '2026-08-02'::date, null, 'z-contrib-b-001');

  -- El saldo real baja despues por un gasto normal, no relacionado a metas.
  perform public.create_transaction(account_id, 'expense', 400000, 'Gasto ajeno', 'food', '2026-08-10'::date, null, 'z-expense-001');

  select balance_minor into account_balance from public.account_balances where id = account_id;
  if account_balance <> 600000 then raise exception 'CASO Z: el saldo real deberia quedar en 600000'; end if;

  select saved_minor, backed_minor into saved_a, backed_a from public.goal_balances where id = goal_a;
  select saved_minor, backed_minor into saved_b, backed_b from public.goal_balances where id = goal_b;

  -- saved_minor NUNCA cambia por el gasto ajeno.
  if saved_a <> 600000 or saved_b <> 400000 then
    raise exception 'CASO Z: saved_minor no debe cambiar por un gasto ajeno (a=%, b=%)', saved_a, saved_b; end if;

  -- La meta mas antigua (A) se respalda primero por completo; a B no le
  -- alcanza -- backed_minor determinista, 0 <= backed <= saved para cada una.
  if backed_a <> 600000 then raise exception 'CASO Z: Meta A (mas antigua) deberia quedar respaldada al 100%%, backed=%', backed_a; end if;
  if backed_b <> 0 then raise exception 'CASO Z: Meta B deberia quedar sin respaldo (0), backed=%', backed_b; end if;
  if backed_a < 0 or backed_a > saved_a then raise exception 'CASO Z: invariante 0<=backed<=saved roto para A'; end if;
  if backed_b < 0 or backed_b > saved_b then raise exception 'CASO Z: invariante 0<=backed<=saved roto para B'; end if;
  if (backed_a + backed_b) > greatest(account_balance, 0) then
    raise exception 'CASO Z: la suma de backed_minor nunca debe superar el saldo real de la cuenta'; end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO AB: una operación real fallida a mitad de camino no deja goal_entry
-- sin transferencia ni transferencia sin goal_entry.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90200000-0000-4000-8000-000000000005', 'goals-ab@example.test', '{}'),
  ('90200000-0000-4000-8000-000000000006', 'goals-ab-other@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000005', true);

do $$
declare
  source_account uuid; goal_id_var uuid;
  entries_before integer; entries_after integer; transfer_events_before integer; transfer_events_after integer;
begin
  source_account := public.create_account('Origen', 'checking', 'MXN', 500000, null, null, 'ab-account-source-001');
  goal_id_var := public.create_goal('Meta AB', 'MXN', 900000, null, null, null, 'ab-goal-001');

  select count(*) into entries_before from public.goal_entries where goal_id = goal_id_var;
  select count(*) into transfer_events_before from public.financial_events
  where user_id = '90200000-0000-4000-8000-000000000005' and kind = 'transfer';

  -- linked_account_id nunca se configuro: debe fallar ANTES de tocar nada.
  begin
    perform public.contribute_to_goal(goal_id_var, 100000, source_account, true, '2026-08-01'::date, null, 'ab-fail-001');
    raise exception 'CASO AB: debio fallar por no tener linked_account_id';
  exception when others then
    if sqlerrm not like '%NEXO_GOAL_HAS_NO_LINKED_ACCOUNT%' then raise; end if;
  end;

  select count(*) into entries_after from public.goal_entries where goal_id = goal_id_var;
  select count(*) into transfer_events_after from public.financial_events
  where user_id = '90200000-0000-4000-8000-000000000005' and kind = 'transfer';

  if entries_before <> entries_after then
    raise exception 'CASO AB: una operacion fallida no debe dejar goal_entries huerfanas'; end if;
  if transfer_events_before <> transfer_events_after then
    raise exception 'CASO AB: una operacion fallida no debe dejar financial_events de transferencia huerfanos'; end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO M: RLS -- usuario A nunca lee ni modifica metas de usuario B.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90200000-0000-4000-8000-000000000007', 'goals-rls-a@example.test', '{}'),
  ('90200000-0000-4000-8000-000000000008', 'goals-rls-b@example.test', '{}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000007', true);
do $$
declare account_id uuid;
begin
  account_id := public.create_account('Cuenta A', 'checking', 'MXN', 100000, null, null, 'rls-account-a-001');
  perform public.create_goal('Meta de A', 'MXN', 500000, null, null, null, 'rls-goal-a-001');
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90200000-0000-4000-8000-000000000008', true);
do $$
declare visible_count integer; other_goal_id uuid;
begin
  select count(*) into visible_count from public.goals where name = 'Meta de A';
  if visible_count <> 0 then raise exception 'CASO M: el usuario B no deberia ver metas del usuario A'; end if;

  select count(*) into visible_count from public.goal_balances where name = 'Meta de A';
  if visible_count <> 0 then raise exception 'CASO M: el usuario B no deberia ver goal_balances del usuario A'; end if;

  select id into other_goal_id from public.goals where user_id = '90200000-0000-4000-8000-000000000007' limit 1;
  begin
    perform public.set_goal_status(coalesce(other_goal_id, gen_random_uuid()), 'paused', 'rls-b-attack-001');
    raise exception 'CASO M: el usuario B no deberia poder modificar una meta del usuario A';
  exception when others then
    if sqlerrm not like '%NEXO_GOAL_NOT_FOUND%' then raise; end if;
  end;
end;
$$;
reset role;
rollback;

select 'goals: A-AB cases and FIFO backing invariants passed' as result;
