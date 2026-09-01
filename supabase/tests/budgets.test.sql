-- Phase 6A: budgets. Covers cases A-S from the design brief plus the
-- explicit anti-double-counting invariant for MSI.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000001', 'budgets-a@example.test', '{}'),
  ('90100000-0000-4000-8000-000000000002', 'budgets-b@example.test', '{}');

create temporary table budget_ids (
  account_mxn uuid, account_usd uuid, card_mxn uuid, princesa uuid
);
insert into budget_ids default values;
grant select, update on budget_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000001', true);

do $$
declare account_mxn_var uuid; account_usd_var uuid; card_mxn_var uuid; princesa_var uuid;
begin
  account_mxn_var := public.create_account('Cobros', 'checking', 'MXN', 0, null, null, 'bud-account-mxn-01');
  account_usd_var := public.create_account('Ahorros USD', 'checking', 'USD', 0, null, null, 'bud-account-usd-01');
  card_mxn_var := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-06-01', 0, null, null, 'bud-card-mxn-001');
  princesa_var := public.create_contact('Princesa', null, null, null, 'bud-princesa-001');
  update budget_ids set account_mxn = account_mxn_var, account_usd = account_usd_var,
    card_mxn = card_mxn_var, princesa = princesa_var;
end;
$$;

-- CASO A: compra personal $1,000 -> +$1,000.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_transaction(ids.account_mxn, 'expense', 100000, 'Super', 'food', '2026-08-05', null, 'bud-caso-a-001');
end;
$$;

-- CASO B: compra 100% para otra persona, personal_amount=0 -> +$0.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_shared_account_purchase(ids.account_mxn, 200000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', ids.princesa, 'amount_minor', '200000')),
    'Regalo Princesa', 'food', '2026-08-06', null, 'bud-caso-b-001');
end;
$$;

-- CASO C: compra compartida $10,000, personal $3,000 -> +$3,000.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_shared_account_purchase(ids.account_mxn, 1000000, 300000,
    jsonb_build_array(jsonb_build_object('contact_id', ids.princesa, 'amount_minor', '700000')),
    'Cena compartida', 'food', '2026-08-07', null, 'bud-caso-c-001');
end;
$$;

-- CASO D: pago recibido de persona -> +$0 (no aparece en food en absoluto).
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_person_payment(ids.princesa, ids.account_mxn, 100000, '2026-08-08', null, 'bud-caso-d-001');
end;
$$;

-- CASO E: pago de tarjeta -> +$0. Necesita una compra de tarjeta primero.
do $$
declare ids budget_ids%rowtype; charge_event uuid;
begin
  select * into ids from budget_ids;
  charge_event := public.create_card_purchase(ids.card_mxn, 50000, 'Cena tarjeta', 'food', '2026-08-09', null, null, 'bud-caso-e-charge-01');
  perform public.create_card_payment(ids.card_mxn, ids.account_mxn, 50000, '2026-08-10', null, 'bud-caso-e-pay-001');
end;
$$;

-- CASO F: transferencia -> +$0.
do $$
declare ids budget_ids%rowtype; other_account uuid;
begin
  select * into ids from budget_ids;
  other_account := public.create_account('Otra cuenta', 'savings', 'MXN', 0, null, null, 'bud-caso-f-account-01');
  perform public.create_transfer(ids.account_mxn, other_account, 50000, 'Ahorro', '2026-08-11', null, 'bud-caso-f-001');
end;
$$;

-- CASO G: reembolso $500 sobre compra de tarjeta $1,000 -> el mes reduce $500 neto.
do $$
declare ids budget_ids%rowtype; charge_event uuid;
begin
  select * into ids from budget_ids;
  charge_event := public.create_card_purchase(ids.card_mxn, 100000, 'Ropa', 'technology', '2026-08-12', null, null, 'bud-caso-g-charge-01');
  perform public.create_card_refund(ids.card_mxn, 50000, 'Devolucion parcial', 'technology', '2026-08-13', charge_event, null, 'bud-caso-g-refund-01');
end;
$$;

-- CASO H: reversion de compra -> elimina el impacto por completo.
do $$
declare ids budget_ids%rowtype; event_id uuid;
begin
  select * into ids from budget_ids;
  event_id := public.create_transaction(ids.account_mxn, 'expense', 900000, 'Compra que se revierte', 'entertainment', '2026-08-14', null, 'bud-caso-h-001');
  perform public.reverse_transaction(event_id, 'bud-caso-h-reverse-001');
end;
$$;

-- CASO I / S: dos monedas nunca se agregan.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_transaction(ids.account_usd, 'expense', 20000, 'Compra USD', 'food', '2026-08-15', null, 'bud-caso-i-001');
end;
$$;

-- CASO K: transaction_date decide el periodo, no created_at. Movimiento con
-- occurred_on en julio no debe contar en agosto.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_transaction(ids.account_mxn, 'expense', 500000, 'Julio', 'food', '2026-07-20', null, 'bud-caso-k-001');
end;
$$;

-- Presupuesto recurrente de Comida (food) $6,000 MXN desde agosto.
do $$
declare ids budget_ids%rowtype;
begin
  select * into ids from budget_ids;
  perform public.create_budget('food', 'MXN', 600000, '2026-08-01'::date, null, 'bud-budget-food-001');
  perform public.create_budget('technology', 'MXN', 300000, '2026-08-01'::date, null, 'bud-budget-tech-001');
  perform public.create_budget('entertainment', 'MXN', 500000, '2026-08-01'::date, null, 'bud-budget-ent-001');
  perform public.create_budget('food', 'USD', 100000, '2026-08-01'::date, null, 'bud-budget-food-usd-001');
end;
$$;

do $$
declare
  ids budget_ids%rowtype; budgets_mxn jsonb; food jsonb; tech jsonb; ent jsonb; budgets_usd jsonb; food_usd jsonb;
begin
  select * into ids from budget_ids;
  budgets_mxn := public.get_budgets_for_period('2026-08-01'::date, 'MXN');
  select value into food from jsonb_array_elements(budgets_mxn) value where value->>'category_id' = 'food';
  select value into tech from jsonb_array_elements(budgets_mxn) value where value->>'category_id' = 'technology';
  select value into ent from jsonb_array_elements(budgets_mxn) value where value->>'category_id' = 'entertainment';

  -- A ($1,000) + C personal ($3,000) + la compra de tarjeta de CASO E ($500,
  -- categoria food, es un gasto personal real -- lo que CASO E prueba es que
  -- SU PAGO de tarjeta no suma nada mas encima) = $4,500. B, D, F y el pago
  -- de tarjeta de E no contribuyen. K (julio) no contribuye a agosto.
  if (food->>'spent_minor')::bigint <> 450000 then
    raise exception 'CASO A/B/C/D/E/F/K: food deberia ser 450000, es %', food->>'spent_minor'; end if;

  -- G: compra 1,000 - reembolso 500 = neto 500.
  if (tech->>'spent_minor')::bigint <> 50000 then
    raise exception 'CASO G: technology deberia ser 50000 (neto tras reembolso), es %', tech->>'spent_minor'; end if;

  -- H: compra revertida no debe aparecer.
  if (ent->>'spent_minor')::bigint <> 0 then
    raise exception 'CASO H: entertainment deberia ser 0 tras revertir, es %', ent->>'spent_minor'; end if;

  -- I/S: la compra de $200 USD no debe sumarse ni aparecer en el bloque MXN.
  budgets_usd := public.get_budgets_for_period('2026-08-01'::date, 'USD');
  select value into food_usd from jsonb_array_elements(budgets_usd) value where value->>'category_id' = 'food';
  if (food_usd->>'spent_minor')::bigint <> 20000 then
    raise exception 'CASO I/S: food USD deberia ser 20000, es %', food_usd->>'spent_minor'; end if;
  if food->>'currency' <> 'MXN' or food_usd->>'currency' <> 'USD' then
    raise exception 'CASO I/S: las monedas no deben mezclarse en un mismo bloque'; end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO M: MSI personal $12,000/12, 100% mio. Cada mensualidad debe consumir
-- exactamente $1,000, nunca $12,000 completos en el mes de compra.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000003', 'budgets-msi@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000003', true);

do $$
declare
  card_id uuid; plan_id uuid; princesa_id uuid; installment_sum bigint; first_month_spend jsonb; row_data jsonb;
  budgets_aug jsonb; tech jsonb;
begin
  card_id := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-06-01', 0, null, null, 'bud-msi-card-001');
  plan_id := public.create_shared_installment_purchase(card_id, 1200000, 1200000, '[]'::jsonb,
    12, 100000, 'Laptop', 'technology', '2026-08-05', null, null, 'bud-msi-personal-001');

  perform public.create_budget('technology', 'MXN', 200000, '2026-08-01'::date, null, 'bud-msi-budget-001');

  -- El mes de la COMPRA (agosto) no debe llevarse el principal completo:
  -- solo la mensualidad cuyo due_statement_date cae en agosto.
  budgets_aug := public.get_budgets_for_period('2026-08-01'::date, 'MXN');
  select value into tech from jsonb_array_elements(budgets_aug) value where value->>'category_id' = 'technology';
  if (tech->>'spent_minor')::bigint <> 100000 then
    raise exception 'CASO M: agosto deberia mostrar solo 1 mensualidad de 100000, no el principal completo; vino %',
      tech->>'spent_minor';
  end if;

  -- Suma de las 12 mensualidades (recorriendo los 12 meses de due_statement_date) debe ser exactamente 1,200,000.
  select coalesce(sum((value->>'spent_minor')::bigint), 0) into installment_sum
  from (
    select public.get_budgets_for_period((date_trunc('month', '2026-08-01'::date) + make_interval(months => offset_month))::date, 'MXN') as period
    from generate_series(0, 11) as offset_month
  ) periods,
  lateral (select value from jsonb_array_elements(periods.period) value where value->>'category_id' = 'technology') spend;
  if installment_sum <> 1200000 then
    raise exception 'CASO M: la suma de las 12 mensualidades deberia ser exactamente 1200000, es %', installment_sum;
  end if;

  -- El detalle debe explicar cada mensualidad sin crear eventos sinteticos.
  row_data := (public.get_budget_movements('technology', 'MXN', '2026-08-01'::date))->0;
  if row_data->>'row_kind' <> 'installment' or (row_data->>'personal_amount_minor')::bigint <> 100000
    or (row_data->>'installment_number')::int <> 1 or (row_data->>'installment_count')::int <> 12 then
    raise exception 'CASO M: el detalle de agosto deberia mostrar la mensualidad 1 de 12 por 100000, vino %', row_data;
  end if;
end;
$$;

-- INVARIANTE ANTI DOBLE CONTEO: para NINGUN mes puede aparecer a la vez el
-- personal_amount completo del card_charge original Y sus mensualidades. Si
-- budget_period_spend sumara ambas fuentes, agosto excederia por mucho la
-- mensualidad esperada de 100000 (llegaria a 1,300,000: principal + cuota 1).
do $$
begin
  if exists (
    select 1 from public.budget_period_spend spend
    where spend.user_id = '90100000-0000-4000-8000-000000000003'
      and spend.category_id = 'technology' and spend.currency = 'MXN'
      and spend.period_month = '2026-08-01'::date
      and spend.spent_minor > 100000
  ) then
    raise exception 'INVARIANTE ANTI DOBLE CONTEO ROTO: agosto de technology excede la mensualidad esperada';
  end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO N: MSI compartido. Total $12,000, personal $4,000, Carlos $8,000, 12 MSI.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000004', 'budgets-msi-shared@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000004', true);

do $$
declare
  card_id uuid; carlos_id uuid; personal_sum bigint; first_month jsonb; second_month jsonb;
begin
  card_id := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-06-01', 0, null, null, 'bud-msi-shared-card-01');
  carlos_id := public.create_contact('Carlos', null, null, null, 'bud-msi-shared-carlos-01');
  perform public.create_shared_installment_purchase(card_id, 1200000, 400000,
    jsonb_build_array(jsonb_build_object('contact_id', carlos_id, 'amount_minor', '800000')),
    12, 100000, 'TV compartida', 'technology', '2026-08-05', null, null, 'bud-msi-shared-001');

  perform public.create_budget('technology', 'MXN', 100000, '2026-08-01'::date, null, 'bud-msi-shared-budget-01');

  select coalesce(sum((value->>'spent_minor')::bigint), 0) into personal_sum
  from (
    select public.get_budgets_for_period((date_trunc('month', '2026-08-01'::date) + make_interval(months => offset_month))::date, 'MXN') as period
    from generate_series(0, 11) as offset_month
  ) periods,
  lateral (select value from jsonb_array_elements(periods.period) value where value->>'category_id' = 'technology') spend;

  if personal_sum <> 400000 then
    raise exception 'CASO N: la suma personal de las 12 mensualidades deberia ser exactamente 400000, es %', personal_sum;
  end if;

  first_month := public.get_budgets_for_period('2026-08-01'::date, 'MXN');
  second_month := public.get_budgets_for_period('2026-09-01'::date, 'MXN');
  -- Nunca $1,000 completos (la mensualidad total de tarjeta) ni $12,000/$4,000
  -- de golpe: cada mes debe rondar 333.33-333.34.
  if not exists (
    select 1 from jsonb_array_elements(first_month) value
    where value->>'category_id' = 'technology'
      and (value->>'spent_minor')::bigint in (33333, 33334)
  ) then raise exception 'CASO N: agosto deberia mostrar ~333.33/333.34 de parte personal, no la mensualidad completa'; end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO O: MSI historico. 12 cuotas, 4 ya pagadas antes de Nexo (paid_before_nexo),
-- Nexo controla desde la cuota 5. Las primeras 4 nunca deben aparecer en
-- presupuestos; 5-12 si, segun su due_statement_date.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000005', 'budgets-msi-historical@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000005', true);

do $$
declare
  card_id_var uuid; total_scheduled_sum bigint;
begin
  card_id_var := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-01-01', 0, null, null, 'bud-msi-hist-card-01');
  perform public.import_shared_historical_installment_plan(
    card_id_var, 'Refrigerador', 1200000, 800000, '[]'::jsonb,
    12, 100000, '2026-04-15', 5, 4, 400000, 400000, '2026-09-09', 'home', null, false,
    'bud-msi-hist-001'
  );

  perform public.create_budget('home', 'MXN', 100000, '2026-01-01'::date, null, 'bud-msi-hist-budget-01');

  -- Ninguna de las 4 cuotas paid_before_nexo debe aparecer jamas: revisamos
  -- todos los meses desde bastante antes del control hasta bien despues.
  select coalesce(sum((value->>'spent_minor')::bigint), 0) into total_scheduled_sum
  from (
    select public.get_budgets_for_period((date_trunc('month', '2026-01-01'::date) + make_interval(months => offset_month))::date, 'MXN') as period
    from generate_series(0, 17) as offset_month
  ) periods,
  lateral (select value from jsonb_array_elements(periods.period) value where value->>'category_id' = 'home') spend;

  -- 8 cuotas scheduled (5 a 12, de sep 2026 a abr 2027) de 100000 cada una =
  -- 800000 exactos; las 4 paid_before_nexo (1-4, 400000) nunca deben sumarse.
  if total_scheduled_sum <> 800000 then
    raise exception 'CASO O: solo las 8 mensualidades scheduled (5-12) deben contar, total esperado 800000, vino %',
      total_scheduled_sum;
  end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO R: refund directo sobre una compra MSI activa debe rechazarse.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000006', 'budgets-msi-refund@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000006', true);

do $$
declare card_id uuid; plan_id uuid; purchase_event uuid;
begin
  card_id := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-06-01', 0, null, null, 'bud-msi-refund-card-01');
  plan_id := public.create_shared_installment_purchase(card_id, 1200000, 1200000, '[]'::jsonb,
    12, 100000, 'Laptop', 'technology', '2026-08-05', null, null, 'bud-msi-refund-purchase-01');
  select purchase_event_id into purchase_event from public.installment_plans where id = plan_id;

  begin
    perform public.create_card_refund(card_id, 50000, 'Intento de reembolso MSI', 'technology', '2026-08-06',
      purchase_event, null, 'bud-msi-refund-attempt-01');
    raise exception 'CASO R: el reembolso directo sobre una compra MSI activa debio ser rechazado';
  exception when others then
    if sqlerrm not like '%NEXO_REFUND_NOT_ALLOWED_FOR_ACTIVE_MSI%' then raise; end if;
    raise notice 'CASO R: reembolso correctamente rechazado: %', sqlerrm;
  end;

  -- Un reembolso normal (no ligado a MSI) sigue funcionando: cubre CASO G
  -- tambien en aislamiento.
  perform public.create_card_refund(card_id, 10000, 'Reembolso normal', 'food', '2026-08-07', null, null,
    'bud-msi-refund-normal-01');
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO P/Q: recurrentes con vigencia historica y excepcion mensual.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000007', 'budgets-recurring@example.test', '{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000007', true);

do $$
declare
  budget_id uuid; aug jsonb; sep jsonb; oct jsonb; nov jsonb; dic jsonb; ene jsonb; dic_exception jsonb; ene_after jsonb;
begin
  budget_id := public.create_budget('food', 'MXN', 600000, '2026-08-01'::date, null, 'bud-recurring-aug-001');

  -- Duplicado del mismo mes de inicio debe fallar.
  begin
    perform public.create_budget('food', 'MXN', 700000, '2026-08-01'::date, null, 'bud-recurring-dup-001');
    raise exception 'CASO P: no debio permitir dos versiones recurrentes iniciando en agosto';
  exception when others then
    if sqlerrm not like '%budgets_recurring_start_unique%' and sqlerrm not like '%duplicate key%' then raise; end if;
  end;

  -- Nueva version desde diciembre: NUEVA fila, no UPDATE.
  perform public.update_recurring_budget_from_month('food', 'MXN', 800000, '2026-12-01'::date, 'bud-recurring-dec-001');

  aug := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-08-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  sep := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-09-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  oct := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-10-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  nov := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-11-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  dic := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-12-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  ene := (select value from jsonb_array_elements(public.get_budgets_for_period('2027-01-01'::date, 'MXN')) value where value->>'category_id' = 'food');

  if (aug->>'limit_minor')::bigint <> 600000 or (sep->>'limit_minor')::bigint <> 600000
    or (oct->>'limit_minor')::bigint <> 600000 or (nov->>'limit_minor')::bigint <> 600000 then
    raise exception 'CASO P: agosto-noviembre deberian seguir en 600000 (ago=%, sep=%, oct=%, nov=%)',
      aug->>'limit_minor', sep->>'limit_minor', oct->>'limit_minor', nov->>'limit_minor';
  end if;
  if (dic->>'limit_minor')::bigint <> 800000 or (ene->>'limit_minor')::bigint <> 800000 then
    raise exception 'CASO P: diciembre y enero deberian ser 800000 (dic=%, ene=%)', dic->>'limit_minor', ene->>'limit_minor';
  end if;

  -- CASO Q: excepcion de diciembre a 10,000.
  perform public.create_budget('food', 'MXN', 1000000, null, '2026-12-01'::date, 'bud-exception-dec-001');
  dic_exception := (select value from jsonb_array_elements(public.get_budgets_for_period('2026-12-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  ene_after := (select value from jsonb_array_elements(public.get_budgets_for_period('2027-01-01'::date, 'MXN')) value where value->>'category_id' = 'food');
  if (dic_exception->>'limit_minor')::bigint <> 1000000 or (dic_exception->>'is_recurring')::boolean <> false then
    raise exception 'CASO Q: diciembre deberia mostrar la excepcion de 1000000, vino %', dic_exception;
  end if;
  if (ene_after->>'limit_minor')::bigint <> 800000 then
    raise exception 'CASO Q: enero debe volver al recurrente de 800000 tras la excepcion de diciembre, vino %',
      ene_after->>'limit_minor';
  end if;
end;
$$;

-- update_budget_exception_limit solo debe funcionar sobre la excepcion, nunca
-- sobre una version recurrente (mutar historia).
do $$
declare recurring_id uuid; exception_id uuid;
begin
  select id into recurring_id from public.budgets
  where user_id = '90100000-0000-4000-8000-000000000007' and category_id = 'food' and currency = 'MXN'
    and effective_from_month = '2026-08-01'::date;
  select id into exception_id from public.budgets
  where user_id = '90100000-0000-4000-8000-000000000007' and category_id = 'food' and currency = 'MXN'
    and period_month = '2026-12-01'::date;

  begin
    perform public.update_budget_exception_limit(recurring_id, 900000, 'bud-edit-recurring-blocked-001');
    raise exception 'no debio permitir editar una version recurrente como si fuera excepcion';
  exception when others then
    if sqlerrm not like '%NEXO_USE_RECURRING_VERSION_INSTEAD%' then raise; end if;
  end;

  perform public.update_budget_exception_limit(exception_id, 1100000, 'bud-edit-exception-001');
  if (select limit_minor from public.budgets where id = exception_id) <> 1100000 then
    raise exception 'la excepcion deberia haberse actualizado a 1100000';
  end if;

  -- archive_budget tampoco debe aceptar una version recurrente.
  begin
    perform public.archive_budget(recurring_id, 'bud-archive-recurring-blocked-001');
    raise exception 'no debio permitir archivar una version recurrente directamente';
  exception when others then
    if sqlerrm not like '%NEXO_USE_STOP_RECURRING_BUDGET_INSTEAD%' then raise; end if;
  end;

  -- stop_recurring_budget si debe funcionar, y no debe tocar agosto-noviembre.
  perform public.stop_recurring_budget('food', 'MXN', '2026-08-01'::date, 'bud-stop-recurring-001');
  if exists (
    select 1 from jsonb_array_elements(public.get_budgets_for_period('2026-09-01'::date, 'MXN')) value
    where value->>'category_id' = 'food'
  ) then
    raise exception 'CASO 7: septiembre no deberia tener presupuesto de food tras detener la version de agosto en agosto';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_budgets_for_period('2026-08-01'::date, 'MXN')) value
    where value->>'category_id' = 'food' and (value->>'limit_minor')::bigint = 600000
  ) then
    raise exception 'CASO 7: agosto debe seguir mostrando 600000 despues de detener la serie en agosto';
  end if;
end;
$$;

reset role;
rollback;

-- ===========================================================================
-- CASO L: RLS -- usuario A no puede leer ni escribir presupuestos de usuario B.
-- ===========================================================================
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('90100000-0000-4000-8000-000000000008', 'budgets-rls-a@example.test', '{}'),
  ('90100000-0000-4000-8000-000000000009', 'budgets-rls-b@example.test', '{}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000008', true);
do $$
begin
  perform public.create_budget('food', 'MXN', 500000, '2026-08-01'::date, null, 'bud-rls-a-001');
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90100000-0000-4000-8000-000000000009', true);
do $$
declare visible_count integer; other_budget_id uuid;
begin
  select count(*) into visible_count from public.budgets where category_id = 'food';
  if visible_count <> 0 then
    raise exception 'CASO L: el usuario B no deberia ver ningun presupuesto del usuario A, vio %', visible_count;
  end if;

  select id into other_budget_id from public.budgets where user_id = '90100000-0000-4000-8000-000000000008' limit 1;
  -- Sin RLS de select directa sobre otro usuario, other_budget_id sera null;
  -- de todas formas intentamos escribir contra un id inventado del otro
  -- usuario para confirmar que ningun RPC permite tocarlo.
  begin
    perform public.update_budget_exception_limit(
      coalesce(other_budget_id, gen_random_uuid()), 100, 'bud-rls-b-attack-001'
    );
    raise exception 'CASO L: el usuario B no deberia poder mutar un presupuesto del usuario A';
  exception when others then
    if sqlerrm not like '%NEXO_BUDGET_NOT_FOUND%' then raise; end if;
  end;
end;
$$;
reset role;
rollback;

select 'budgets: A-S cases and anti-double-count invariant passed' as result;
