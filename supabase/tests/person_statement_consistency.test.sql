-- Regression test for the reported "Estado de Princesa" inconsistency:
-- get_person_statement/get_person_collection_period showed
-- "a pagar este periodo" / "falta" larger than "te debe en total". Root
-- cause: receivable_due_items for simple (non-card) purchases stayed
-- eligible forever regardless of outstanding_minor, and any receivable
-- whose due item never learned about a payment it already reflects in
-- receivable_entries (exactly what the one-time 5B backfill produced for
-- pre-existing receivables) kept showing its full original amount as
-- still due. This test reproduces that exact shape by hand (the live
-- create_person_payment path cannot produce it -- due items are always
-- created atomically with the purchase now) and checks the fix on both
-- sides: the invariant holds after reconciliation, and normal payment
-- flows (full, partial, MSI) behave correctly without it.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('80000000-0000-4000-8000-000000000001', 'consistency@example.test', '{}');

create temporary table consistency_ids (contact_id uuid, boletos_due_item uuid, kfc_due_item uuid);
insert into consistency_ids default values;
grant select, update on consistency_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  account_id uuid; card_id uuid; princesa uuid;
  boletos_event uuid; kfc_event uuid; telefono_plan uuid;
  boletos_receivable uuid; kfc_receivable uuid;
  boletos_due_item_var uuid; kfc_due_item_var uuid;
begin
  account_id := public.create_account('Cobros', 'checking', 'MXN', 0, null, null, 'consistency-account');
  card_id := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-08-01', 0, null, null, 'consistency-card-001');
  princesa := public.create_contact('Princesa', null, null, null, 'consistency-princesa');

  -- "Boletos prueba": $2,000, 100% de Princesa.
  boletos_event := public.create_shared_account_purchase(account_id, 200000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', princesa, 'amount_minor', '200000')),
    'Boletos prueba', 'other_expense', '2026-08-10', null, 'consist-boletos');
  select id into boletos_receivable from public.receivables where source_event_id = boletos_event;
  select id into boletos_due_item_var from public.receivable_due_items where receivable_id = boletos_receivable;

  -- "KFC": $10,000 total, $7,000 de Princesa.
  kfc_event := public.create_shared_account_purchase(account_id, 1000000, 300000,
    jsonb_build_array(jsonb_build_object('contact_id', princesa, 'amount_minor', '700000')),
    'KFC', 'food', '2026-08-12', null, 'consist-kfc');
  select id into kfc_receivable from public.receivables where source_event_id = kfc_event;
  select id into kfc_due_item_var from public.receivable_due_items where receivable_id = kfc_receivable;

  -- "Telefono Gael": MSI $12,000/12, $8,000 de Princesa, $4,000 propios.
  telefono_plan := public.create_shared_installment_purchase(card_id, 1200000, 400000,
    jsonb_build_array(jsonb_build_object('contact_id', princesa, 'amount_minor', '800000')),
    12, 66667, 'Telefono Gael', 'other_expense', '2026-08-15', null, null, 'consist-telefono');

  -- Ambas compras se pagan por completo a traves del flujo real (post-fix,
  -- consistente en si mismo).
  perform public.create_person_payment(princesa, account_id, 200000, '2026-08-11', null, 'consist-pay-boletos');
  perform public.create_person_payment(princesa, account_id, 700000, '2026-08-13', null, 'consist-pay-kfc');

  if (select outstanding_minor from public.receivable_due_item_balances where id = boletos_due_item_var) <> 0 then
    raise exception 'Boletos prueba debio quedar en 0 tras pagarse por el flujo real'; end if;
  if (select outstanding_minor from public.receivable_due_item_balances where id = kfc_due_item_var) <> 0 then
    raise exception 'KFC debio quedar en 0 tras pagarse por el flujo real'; end if;

  update consistency_ids set contact_id = princesa, boletos_due_item = boletos_due_item_var, kfc_due_item = kfc_due_item_var;
end;
$$;

reset role;

-- Simula exactamente el estado que el backfill de 20260829031852 producia
-- para receivables PRE-EXISTENTES: el cronograma nunca se entera de un pago
-- que receivable_entries ya reflejaba. No se toca receivable_entries (sigue
-- siendo la fuente de verdad, y aqui permanece correcta todo el tiempo).
alter table public.receivable_due_applications disable trigger due_applications_are_immutable;
delete from public.receivable_due_applications
where due_item_id in (select boletos_due_item from consistency_ids union select kfc_due_item from consistency_ids);
alter table public.receivable_due_applications enable trigger due_applications_are_immutable;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  ids consistency_ids%rowtype; statement jsonb; mxn_period jsonb;
begin
  select * into ids from consistency_ids;

  -- Confirma que el estado simulado efectivamente rompe el invariante --
  -- si esto no fuera cierto, el resto de la prueba no probaria nada.
  statement := public.get_person_statement(ids.contact_id, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if (mxn_period->>'remaining_minor')::bigint <= (mxn_period->>'total_outstanding_minor')::bigint then
    raise exception 'la reproduccion no rompio el invariante; el escenario de prueba ya no es valido'; end if;
end;
$$;

reset role;

-- La reconciliacion (parte de la migracion 20260830020000) corrige el
-- estado ya roto sin tocar receivable_entries ni borrar historial.
select private.reconcile_simple_receivable_due_item_history();

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  ids consistency_ids%rowtype; statement jsonb; mxn_period jsonb; concept_count integer;
begin
  select * into ids from consistency_ids;

  if (select outstanding_minor from public.receivable_due_item_balances where id = ids.boletos_due_item) <> 0 then
    raise exception 'Boletos prueba deberia quedar en 0 tras reconciliar'; end if;
  if (select outstanding_minor from public.receivable_due_item_balances where id = ids.kfc_due_item) <> 0 then
    raise exception 'KFC deberia quedar en 0 tras reconciliar'; end if;

  statement := public.get_person_statement(ids.contact_id, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';

  -- EL INVARIANTE CRITICO: nunca puede faltar mas de lo que realmente se debe.
  if (mxn_period->>'remaining_minor')::bigint > (mxn_period->>'total_outstanding_minor')::bigint then
    raise exception 'INVARIANTE VIOLADO: remaining_minor (%) > total_outstanding_minor (%)',
      mxn_period->>'remaining_minor', mxn_period->>'total_outstanding_minor'; end if;
  if (mxn_period->>'remaining_minor')::bigint < 0 then
    raise exception 'remaining_minor nunca puede ser negativo'; end if;

  -- Boletos prueba y KFC, ya saldados, siguen listadas en el desglose del
  -- periodo (para que se entienda de que se compuso "Total del periodo"),
  -- pero con pendiente exactamente 0 -- nunca como si siguieran debiendose.
  select count(*) into concept_count from jsonb_array_elements(mxn_period->'concepts') concept
    where concept->>'description' in ('Boletos prueba', 'KFC') and (concept->>'outstanding_minor')::bigint = 0;
  if concept_count <> 2 then
    raise exception 'Boletos prueba y KFC deberian seguir listadas, con pendiente 0'; end if;

  -- Cada columna debe reconciliar matematicamente: correspondia = pagado + pendiente.
  if exists (
    select 1 from jsonb_array_elements(mxn_period->'concepts') concept
    where (concept->>'amount_minor')::bigint <> (concept->>'paid_minor')::bigint + (concept->>'outstanding_minor')::bigint
  ) then raise exception 'un concepto no reconcilia: correspondia <> pagado + pendiente'; end if;
  if (mxn_period->>'subtotal_minor')::bigint <> (mxn_period->>'paid_minor')::bigint + (mxn_period->>'remaining_minor')::bigint then
    raise exception 'el periodo no reconcilia: total del periodo <> cubierto + pendiente'; end if;

  -- Solo Telefono Gael debe seguir contribuyendo a la deuda total.
  if (mxn_period->>'total_outstanding_minor')::bigint <> 800000 then
    raise exception 'la deuda total deberia seguir siendo exactamente la de Telefono Gael (800000)'; end if;

  -- La reconciliacion se ve reflejada en su propio campo (900000 = 200000 + 700000),
  -- nunca mezclada con pagos reales.
  if (mxn_period->>'reconciled_minor')::bigint <> 900000 then
    raise exception 'reconciled_minor deberia ser exactamente 900000 (Boletos + KFC)'; end if;

  -- Las aplicaciones de reconciliacion NUNCA aparecen como "Pagos recibidos".
  if exists (select 1 from jsonb_array_elements(statement->'payments') payment
      where (payment->>'amount_minor')::bigint in (200000, 700000)) then
    raise exception 'la reconciliacion no debe aparecer como si la persona hubiera hecho un pago nuevo'; end if;
end;
$$;

reset role;

-- Correr la reconciliacion de nuevo no debe cambiar nada (idempotencia).
select private.reconcile_simple_receivable_due_item_history();

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
do $$
declare ids consistency_ids%rowtype;
begin
  select * into ids from consistency_ids;
  if (select outstanding_minor from public.receivable_due_item_balances where id = ids.boletos_due_item) <> 0 then
    raise exception 'reconciliar dos veces no debe alterar un item ya reconciliado'; end if;
end;
$$;

reset role;

-- CASO 12: compra para persona pagada por completo -- no puede seguir
-- apareciendo como pendiente.
set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
do $$
declare
  account_id uuid; person_id uuid; purchase_event uuid; statement jsonb; period jsonb;
begin
  account_id := (select id from public.accounts where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  person_id := public.create_contact('Pago Total', null, null, null, 'consist-pago-total');
  purchase_event := public.create_shared_account_purchase(account_id, 700000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '700000')),
    'Compra pagada por completo', 'other_expense', '2026-08-20', null, 'consist-full-purchase');
  perform public.create_person_payment(person_id, account_id, 700000, '2026-08-21', null, 'consist-full-payment');

  statement := public.get_person_statement(person_id, '2026-08-28');
  select value into period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if period is not null and (period->>'remaining_minor')::bigint <> 0 then
    raise exception 'una compra saldada al 100%% no debe dejar nada pendiente en el periodo'; end if;
  -- Sigue listada (para que el desglose explique de que se compuso el
  -- periodo), pero con pendiente exactamente 0 -- nunca como si aun se debiera.
  if period is not null and exists (
    select 1 from jsonb_array_elements(period->'concepts') concept where (concept->>'outstanding_minor')::bigint <> 0
  ) then raise exception 'una compra saldada al 100%% no debe tener pendiente distinto de 0'; end if;
  if (select coalesce(sum(outstanding_minor), 0) from public.receivable_balances where contact_id = person_id) <> 0 then
    raise exception 'te debe deberia ser exactamente 0 tras el pago total'; end if;
end;
$$;

-- CASO 13: pago parcial -- debe faltar exactamente el remanente, nunca el
-- importe original completo.
do $$
declare
  account_id uuid; person_id uuid; statement jsonb; period jsonb;
begin
  account_id := (select id from public.accounts where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  person_id := public.create_contact('Pago Parcial', null, null, null, 'consist-pago-parcial');
  perform public.create_shared_account_purchase(account_id, 700000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '700000')),
    'Compra parcial', 'other_expense', '2026-08-20', null, 'consist-partial-purchase');
  perform public.create_person_payment(person_id, account_id, 200000, '2026-08-21', null, 'consist-partial-payment');

  statement := public.get_person_statement(person_id, '2026-08-28');
  select value into period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if (period->>'total_outstanding_minor')::bigint <> 500000 then
    raise exception 'deuda total deberia ser exactamente 500000 (700000 - 200000)'; end if;
  if (period->>'remaining_minor')::bigint <> 500000 then
    raise exception 'falta deberia ser exactamente 500000, nunca los 700000 originales'; end if;
  if (period->>'paid_minor')::bigint <> 200000 then
    raise exception 'pagado deberia ser exactamente 200000'; end if;
end;
$$;

-- CASO 14: mensualidad de MSI pagada -- el periodo la refleja pagada, la
-- deuda total baja, y el siguiente periodo no la duplica.
do $$
declare
  account_id uuid; card_id uuid; person_id uuid; plan_id uuid;
  statement jsonb; period jsonb; total_before bigint; total_after bigint;
begin
  account_id := (select id from public.accounts where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  card_id := (select id from public.credit_cards where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  person_id := public.create_contact('MSI Puntual', null, null, null, 'consist-msi-puntual');
  plan_id := public.create_shared_installment_purchase(card_id, 960000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '960000')),
    12, 80000, 'Plan puntual', 'other_expense', '2026-08-15', null, null, 'consist-msi-plan');

  statement := public.get_person_statement(person_id, '2026-08-28');
  select value into period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  total_before := (period->>'total_outstanding_minor')::bigint;
  if (period->>'remaining_minor')::bigint <> 80000 then
    raise exception 'la primera mensualidad deberia ser exactamente 80000'; end if;

  perform public.create_person_payment(person_id, account_id, 80000, '2026-08-29', null, 'consist-msi-payment');

  statement := public.get_person_statement(person_id, '2026-08-28');
  select value into period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  total_after := (period->>'total_outstanding_minor')::bigint;
  if total_before - total_after <> 80000 then
    raise exception 'la deuda total deberia bajar exactamente en 80000 tras pagar la mensualidad'; end if;
  if (period->>'paid_minor')::bigint <> 80000 then
    raise exception 'pagado este periodo deberia reflejar la mensualidad cubierta'; end if;
  if not exists (
    select 1 from jsonb_array_elements(period->'concepts') concept where (concept->>'outstanding_minor')::bigint = 0
  ) then raise exception 'la mensualidad cubierta deberia seguir listada, con pendiente 0'; end if;
end;
$$;

-- CASO 15: FIFO limpio (sin desincronizacion historica) de un pago que no
-- alcanza para dos deudas nunca aplica mas de lo recibido, en ningun
-- reparto posible.
do $$
declare
  account_id uuid; person_id uuid; event_id uuid; total_applied bigint;
begin
  account_id := (select id from public.accounts where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  person_id := public.create_contact('FIFO Limpio', null, null, null, 'consist-fifo-limpio');
  perform public.create_shared_account_purchase(account_id, 700000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '700000')),
    'Deuda grande', 'other_expense', '2026-08-01', null, 'consist-fifo-a');
  perform public.create_shared_account_purchase(account_id, 200000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '200000')),
    'Deuda chica', 'other_expense', '2026-08-02', null, 'consist-fifo-b');
  event_id := public.create_person_payment(person_id, account_id, 650000, '2026-08-14', null, 'consist-fifo-pay');

  select coalesce(sum(amount_minor), 0) into total_applied
  from public.receivable_due_applications where financial_event_id = event_id and application_kind = 'payment';
  if total_applied <> 650000 then
    raise exception 'un pago de 650000 sobre 700000+200000 debe aplicar exactamente 650000, no %', total_applied; end if;
end;
$$;

-- CASO 16: pago que excede la deuda total genera saldo a favor real, nunca
-- una aplicacion por encima de lo recibido.
do $$
declare
  account_id uuid; person_id uuid; event_id uuid; total_applied bigint; credit_generated bigint;
begin
  account_id := (select id from public.accounts where user_id = '80000000-0000-4000-8000-000000000001' limit 1);
  person_id := public.create_contact('Pago Excedente', null, null, null, 'consist-pago-excedente');
  perform public.create_shared_account_purchase(account_id, 900000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '900000')),
    'Deuda exacta', 'other_expense', '2026-08-01', null, 'consist-excedente-compra');
  event_id := public.create_person_payment(person_id, account_id, 1000000, '2026-08-14', null, 'consist-excedente-pago');

  select coalesce(sum(amount_minor), 0) into total_applied
  from public.receivable_due_applications where financial_event_id = event_id and application_kind = 'payment';
  select coalesce(sum(amount_minor), 0) into credit_generated
  from public.person_credit_entries where financial_event_id = event_id and entry_kind = 'credit_created';
  if total_applied <> 900000 then raise exception 'deberia aplicar exactamente 900000, no %', total_applied; end if;
  if credit_generated <> 100000 then raise exception 'deberia generar 100000 de saldo a favor, no %', credit_generated; end if;
  if total_applied + credit_generated <> 1000000 then
    raise exception 'aplicado + saldo a favor debe sumar exactamente lo recibido (1000000)'; end if;
end;
$$;

-- CASO 17 (el bug reportado): dos cuentas por cobrar ya saldadas
-- historicamente por un evento antiguo, mas un pago nuevo, mas pequeno,
-- que el cronograma (todavia sin reconciliar) trata como si aun se
-- debieran por completo. Antes del fix del 20260830040000, esto atribuia
-- el hueco historico completo al evento nuevo, inflando "Cubierto" mas
-- alla de "Total del periodo" y dejando "Pendiente"/"Te debe en total" en
-- negativo. Reproduce el reporte real palabra por palabra: sum(payment)
-- para el evento nuevo termina en 900000 mientras el evento solo trajo
-- 650000.
create temporary table caso17_ids (account_id uuid, princesa_id uuid, boletos_receivable uuid, kfc_receivable uuid, old_event uuid);
insert into caso17_ids default values;
grant select, update on caso17_ids to authenticated;

do $$
declare
  account_id_var uuid; princesa_id_var uuid;
  boletos_event uuid; kfc_event uuid;
  boletos_receivable_var uuid; kfc_receivable_var uuid;
begin
  account_id_var := public.create_account('Santander', 'checking', 'MXN', 0, null, null, 'consist-caso17-account');
  princesa_id_var := public.create_contact('Princesa Caso17', null, null, null, 'consist-caso17-princesa');

  boletos_event := public.create_shared_account_purchase(account_id_var, 200000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', princesa_id_var, 'amount_minor', '200000')),
    'Boletos caso17', 'other_expense', '2026-06-01', null, 'consist-caso17-boletos');
  select id into boletos_receivable_var from public.receivables where source_event_id = boletos_event;

  kfc_event := public.create_shared_account_purchase(account_id_var, 1000000, 300000,
    jsonb_build_array(jsonb_build_object('contact_id', princesa_id_var, 'amount_minor', '700000')),
    'KFC caso17', 'food', '2026-06-02', null, 'consist-caso17-kfc');
  select id into kfc_receivable_var from public.receivables where source_event_id = kfc_event;

  update caso17_ids set account_id = account_id_var, princesa_id = princesa_id_var,
    boletos_receivable = boletos_receivable_var, kfc_receivable = kfc_receivable_var, old_event = gen_random_uuid();
end;
$$;

reset role;

-- Pago historico real de $9,000 que ya salda ambas por completo, fuera del
-- seguimiento por due item (exactamente el shape del backfill 5B) --
-- insertado directamente porque simula datos anteriores a que este
-- seguimiento existiera, no algo que la app produce hoy.
do $$
declare ids caso17_ids%rowtype;
begin
  select * into ids from caso17_ids;
  insert into public.financial_events (id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on, created_at)
  values (ids.old_event, '80000000-0000-4000-8000-000000000001', 'person_payment', 900000, 0,
    'Pago historico caso17', '2026-07-01', '2026-07-01 09:00:00+00');
  insert into public.account_entries (user_id, financial_event_id, account_id, amount_minor)
  values ('80000000-0000-4000-8000-000000000001', ids.old_event, ids.account_id, 900000);
  insert into public.receivable_entries (user_id, receivable_id, financial_event_id, amount_minor, entry_kind, created_at)
  values
    ('80000000-0000-4000-8000-000000000001', ids.boletos_receivable, ids.old_event, -200000, 'payment', '2026-07-01 09:00:00+00'),
    ('80000000-0000-4000-8000-000000000001', ids.kfc_receivable, ids.old_event, -700000, 'payment', '2026-07-01 09:00:00+00');
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  ids caso17_ids%rowtype;
  new_event_id uuid; new_event_amount bigint; applied_to_new bigint;
  statement jsonb; mxn_period jsonb;
begin
  select * into ids from caso17_ids;

  -- El pago nuevo, real, mas pequeno que el hueco historico acumulado.
  new_event_id := public.create_person_payment(ids.princesa_id, ids.account_id, 650000, '2026-08-28', null, 'consist-caso17-pago-nuevo');

  select amount_minor into new_event_amount from public.financial_events where id = new_event_id;
  select coalesce(sum(amount_minor), 0) into applied_to_new
  from public.receivable_due_applications
  where financial_event_id = new_event_id and application_kind in ('payment', 'credit', 'reconciliation');
  if applied_to_new > new_event_amount then
    raise exception 'INVARIANTE ROTO: % aplicados contra un evento que solo trajo %', applied_to_new, new_event_amount; end if;

  statement := public.get_person_statement(ids.princesa_id, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if (mxn_period->>'remaining_minor')::bigint < 0 then raise exception 'pendiente no puede ser negativo'; end if;
  if (mxn_period->>'total_outstanding_minor')::bigint < 0 then raise exception 'te debe en total no puede ser negativo'; end if;
  if (mxn_period->>'paid_minor')::bigint > (mxn_period->>'subtotal_minor')::bigint then
    raise exception 'cubierto no puede superar el total del periodo'; end if;
end;
$$;

reset role;

-- CASO 18: reconciliar 1, 2 o 10 veces nunca aumenta el dinero aplicado
-- (idempotencia real, no solo "no truena").
do $$
declare total_after_first bigint; total_after_many bigint; i integer;
begin
  select coalesce(sum(amount_minor), 0) into total_after_first
  from public.receivable_due_applications where application_kind = 'reconciliation';
  for i in 1..10 loop
    perform private.reconcile_simple_receivable_due_item_history();
  end loop;
  select coalesce(sum(amount_minor), 0) into total_after_many
  from public.receivable_due_applications where application_kind = 'reconciliation';
  if total_after_many <> total_after_first then
    raise exception 'reconciliar repetidamente no debe cambiar el total aplicado (antes %, despues %)',
      total_after_first, total_after_many; end if;
end;
$$;

rollback;
select 'person statement consistency: eligible/total invariant, reconciliation and payment cases passed' as result;
