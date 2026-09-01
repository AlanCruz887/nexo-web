-- Phase 6C: financial planning (Planeación). Covers planned_cash_flows CRUD
-- (A-H), RLS (I, AA), every letter of the closing audit (O-AE) and every
-- anti-double-count rule from the design brief (AF-AW) with individually
-- identifiable cases, plus two dedicated audit blocks: a card statement_day
-- of 31 walked across a real February, and a planned_cash_flow that
-- genuinely overshoots its budget's available room. p_as_of_date is always
-- pinned explicitly -- nothing here depends on current_date, so the whole
-- file is deterministic regardless of when it runs. CASO Y is the only
-- test that mutates real financial state (a reversal) and runs last, on
-- purpose, so no other case depends on the state it changes.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90300000-0000-4000-8000-000000000001', 'plan-a@example.test', '{}'),
  ('90300000-0000-4000-8000-000000000002', 'plan-b@example.test', '{}');

create temporary table plan_ids (
  santander uuid, efectivo uuid, usd_account uuid, eur_account uuid, archived_account uuid,
  bbva uuid, amex uuid,
  japon uuid, recursiva uuid, pausada uuid, archivada uuid,
  carlos uuid, temporal_flow uuid, unrelated_expense_event uuid,
  income_flow uuid, outflow_flow uuid
);
insert into plan_ids default values;
grant select, update on plan_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90300000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- CASOS A-H: planned_cash_flows CRUD + validation.
-- ---------------------------------------------------------------------

do $$
declare
  flow_id uuid; repeated uuid; other uuid; temp_id uuid;
begin
  -- CASO A: create one_time, idempotent replay returns the same id.
  flow_id := public.create_planned_cash_flow('Bono', 'MXN', 500000, null, 'one_time', '2020-09-01', null, 'p6c-a-bono');
  repeated := public.create_planned_cash_flow('Bono', 'MXN', 500000, null, 'one_time', '2020-09-01', null, 'p6c-a-bono');
  if repeated <> flow_id then raise exception 'CASO A: idempotency failed'; end if;

  -- CASO B: a second, independent one_time creation succeeds (recurring
  -- intentions moved to recurring_rules in Phase 7A -- planned_cash_flows
  -- accepts one_time exclusively from that phase forward; see 7A's own
  -- CASO AG for the explicit rejection test).
  other := public.create_planned_cash_flow('Gimnasio', 'MXN', -80000, null, 'one_time', '2020-08-25', null, 'p6c-b-gym');
  if other is null then raise exception 'CASO B: one_time creation failed'; end if;

  -- CASO C: one_time cannot carry an end_date.
  begin
    perform public.create_planned_cash_flow('Malo', 'MXN', -1000, null, 'one_time', '2020-09-01', '2020-09-05', 'p6c-c-bad');
    raise exception 'CASO C: one_time with end_date should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_ONE_TIME_CANNOT_HAVE_END_DATE' then raise; end if;
  end;

  -- CASO D: amount_minor = 0 rejected.
  begin
    perform public.create_planned_cash_flow('Cero', 'MXN', 0, null, 'one_time', '2020-09-01', null, 'p6c-d-zero');
    raise exception 'CASO D: zero amount should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_INVALID_AMOUNT' then raise; end if;
  end;

  -- CASO E: any recurrence other than one_time is rejected from Phase 7A
  -- onward (recurring intentions live in recurring_rules now).
  begin
    perform public.create_planned_cash_flow('Malo2', 'MXN', -1000, null, 'weekly', '2020-09-01', null, 'p6c-e-bad');
    raise exception 'CASO E: non-one_time recurrence should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_PLANNED_CASH_FLOW_RECURRENCE_DEPRECATED' then raise; end if;
  end;

  -- CASO F: unknown category rejected.
  begin
    perform public.create_planned_cash_flow('Malo3', 'MXN', -1000, 'not_a_real_category', 'one_time', '2020-09-01', null, 'p6c-f-bad');
    raise exception 'CASO F: unknown category should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_CATEGORY_NOT_FOUND' then raise; end if;
  end;

  -- CASO G: update mutates in place.
  perform public.update_planned_cash_flow(flow_id, 'Bono actualizado', 600000, 'entertainment', 'one_time', '2020-09-02', null, 'p6c-g-update');
  if (select name from public.planned_cash_flows where id = flow_id) <> 'Bono actualizado' then
    raise exception 'CASO G: update did not change name'; end if;
  if (select amount_minor from public.planned_cash_flows where id = flow_id) <> 600000 then
    raise exception 'CASO G: update did not change amount'; end if;

  -- CASO H: archive/restore round trip; archived flow disappears from the plan.
  temp_id := public.create_planned_cash_flow('Temporal', 'MXN', -100000, null, 'one_time', '2020-09-10', null, 'p6c-h-temp');
  perform public.archive_planned_cash_flow(temp_id, 'p6c-h-archive');
  if (select archived_at from public.planned_cash_flows where id = temp_id) is null then
    raise exception 'CASO H: archive did not set archived_at'; end if;
  perform public.restore_planned_cash_flow(temp_id, 'p6c-h-restore');
  if (select archived_at from public.planned_cash_flows where id = temp_id) is not null then
    raise exception 'CASO H: restore did not clear archived_at'; end if;
  perform public.archive_planned_cash_flow(temp_id, 'p6c-h-archive-again');
  update plan_ids set temporal_flow = temp_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Main scenario: accounts, a goal with a later shortfall, two cards (one
-- with an open cycle carrying a normal purchase + MSI, one closed at
-- zero), a recurring budget, planned flows (categorized, uncategorized,
-- past, and a day-31 monthly subscription), and a shared card purchase
-- for Carlos (expected collection).
-- ---------------------------------------------------------------------

do $$
declare
  santander_id uuid; efectivo_id uuid; usd_id uuid; eur_id uuid; archived_id uuid;
  bbva_id uuid; amex_id uuid;
  japon_id uuid; recursiva_id uuid; pausada_id uuid; archivada_id uuid;
  carlos_id uuid; unrelated_expense_id uuid;
  income_flow_id uuid; outflow_flow_id uuid;
begin
  santander_id := public.create_account('Santander', 'checking', 'MXN', 1000000, null, null, 'p6c-account-santander');
  efectivo_id := public.create_account('Efectivo', 'cash', 'MXN', 1000000, null, null, 'p6c-account-efectivo');
  usd_id := public.create_account('Cuenta USD', 'checking', 'USD', 100000, null, null, 'p6c-account-usd');
  eur_id := public.create_account('Cuenta EUR', 'checking', 'EUR', 200000, null, null, 'p6c-account-eur');

  -- CASO V setup: an archived account with real balance must contribute
  -- nothing to saldo inicial.
  archived_id := public.create_account('Cuenta vieja', 'checking', 'MXN', 900000, null, null, 'p6c-account-archived');
  perform public.archive_account(archived_id, 'p6c-archive-old-account');

  -- Japón: virtual contribution fully backed at $8,000, then an UNRELATED
  -- $5,000 expense from the same account drops its real balance to
  -- $5,000 -- saved_minor stays $8,000, backed_minor recomputes to $5,000.
  -- CASO Y setup: this expense's event id is captured so it can be
  -- reversed later at its SOURCE, proving the derived plan follows it.
  japon_id := public.create_goal('Japón', 'MXN', 800000, null, null, null, 'p6c-goal-japon');
  perform public.contribute_to_goal(japon_id, 800000, santander_id, false, '2020-08-05', null, 'p6c-contrib-japon');
  unrelated_expense_id := public.create_transaction(santander_id, 'expense', 500000, 'Gasto no relacionado', 'entertainment', '2020-08-08', null, 'p6c-expense-unrelated');

  -- Recursive-projection goals, isolated from Japón.
  recursiva_id := public.create_goal('Meta recursiva', 'MXN', 400000, '2020-10-20', null, null, 'p6c-goal-recursiva');
  pausada_id := public.create_goal('Meta pausada', 'MXN', 100000, '2020-12-20', null, null, 'p6c-goal-pausada');
  perform public.set_goal_status(pausada_id, 'paused', 'p6c-pause-pausada');
  archivada_id := public.create_goal('Meta archivada', 'MXN', 100000, '2020-12-20', null, null, 'p6c-goal-archivada');
  perform public.archive_goal(archivada_id, 'p6c-archive-archivada');

  -- BBVA: open cycle (no statement closed yet at as_of) with a normal
  -- purchase + a 2-installment MSI purchase, then the Sep cut is closed.
  -- Statements must close chronologically, so the card's own first
  -- (zero-activity) cycle is closed before the one carrying real spend.
  bbva_id := public.create_credit_card('BBVA', 'BBVA', null, 'MXN', 5000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-08-01', 0, null, null, 'p6c-card-bbva');
  perform public.close_card_statement(bbva_id, '2020-08-09', null, 0, 'p6c-close-bbva-aug');
  perform public.create_card_purchase(bbva_id, 500000, 'Supermercado', 'food', '2020-08-15', null, null, 'p6c-purchase-super');
  perform public.create_installment_purchase(bbva_id, 200000, 2, null, 'Laptop chica', 'technology', '2020-08-15', 'online', null, 'p6c-msi-laptop');
  perform public.close_card_statement(bbva_id, '2020-09-09', null, 0, 'p6c-close-sep');

  -- Carlos: a shared purchase in the OPEN Oct cycle. Full card impact,
  -- separate non-guaranteed expected collection.
  carlos_id := public.create_contact('Carlos', null, null, null, 'p6c-carlos');
  perform public.create_shared_card_purchase(bbva_id, 400000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos_id, 'amount_minor', '400000')),
    'Compra para Carlos', 'food', '2020-09-15', null, null, 'p6c-shared-carlos');

  -- Amex: zero-activity statement closed at exactly $0 remaining. Same
  -- chronological requirement: close every prior monthly cut first.
  amex_id := public.create_credit_card('Amex', 'Amex', null, 'MXN', 3000000, 5, 25, null,
    'generic', 'current_bank_balance', '2020-07-01', 0, null, null, 'p6c-card-amex');
  perform public.close_card_statement(amex_id, '2020-07-05', null, 0, 'p6c-close-amex-jul');
  perform public.close_card_statement(amex_id, '2020-08-05', null, 0, 'p6c-close-amex-aug');
  perform public.close_card_statement(amex_id, '2020-09-05', null, 0, 'p6c-close-amex-sep');

  -- Hogar budget: $12,000/month recurring from August. $3,000 real spend
  -- already happened in August (before as_of).
  perform public.create_budget('home', 'MXN', 1200000, '2020-08-01', null, 'p6c-budget-home');
  perform public.create_transaction(efectivo_id, 'expense', 300000, 'Renta parcial ya pagada', 'home', '2020-08-10', null, 'p6c-expense-home-real');

  -- Planned flows.
  perform public.create_planned_cash_flow('Renta chica', 'MXN', -600000, 'home', 'one_time', '2020-08-25', null, 'p6c-flow-renta-chica');
  perform public.create_planned_cash_flow('Renta grande', 'MXN', -1000000, 'home', 'one_time', '2020-11-01', null, 'p6c-flow-renta-grande');
  perform public.create_planned_cash_flow('Suscripción sin categoría', 'MXN', -50000, null, 'one_time', '2020-08-22', null, 'p6c-flow-no-category');
  perform public.create_planned_cash_flow('Ya pagado', 'MXN', -20000, null, 'one_time', '2020-08-05', null, 'p6c-flow-past');
  perform public.create_planned_cash_flow('Ingreso freelance', 'MXN', 300000, null, 'one_time', '2020-09-10', null, 'p6c-flow-income');
  -- Day-31 monthly clamp for a recurring commitment is no longer a
  -- planned_cash_flows concern from Phase 7A onward (recurring_rules owns
  -- it -- see recurring_transactions.test.sql CASO C for the equivalent,
  -- more rigorous test through the real recurring engine).

  -- CASOS R/S setup: a manual +$30,000 income and a manual -$10,000
  -- outflow, dated in December (month_index 4) away from any budget
  -- category, so their only job is to move the projection without ever
  -- touching financial_events.
  income_flow_id := public.create_planned_cash_flow('Ingreso extraordinario', 'MXN', 3000000, null, 'one_time', '2020-12-05', null, 'p6c-flow-r-income');
  outflow_flow_id := public.create_planned_cash_flow('Gasto extraordinario', 'MXN', -1000000, null, 'one_time', '2020-12-06', null, 'p6c-flow-s-outflow');

  -- CASO X setup: an outflow far larger than every available resource
  -- combined, dated in the last month of the horizon, to force a
  -- genuinely negative projected closing.
  perform public.create_planned_cash_flow('Emergencia enorme', 'MXN', -500000000, null, 'one_time', '2021-01-05', null, 'p6c-flow-x-emergency');

  update plan_ids set santander = santander_id, efectivo = efectivo_id, usd_account = usd_id,
    eur_account = eur_id, archived_account = archived_id,
    bbva = bbva_id, amex = amex_id, japon = japon_id, recursiva = recursiva_id,
    pausada = pausada_id, archivada = archivada_id, carlos = carlos_id,
    unrelated_expense_event = unrelated_expense_id,
    income_flow = income_flow_id, outflow_flow = outflow_flow_id;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO I: RLS -- a second user with no data sees nothing.
-- ---------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90300000-0000-4000-8000-000000000002', true);

do $$
declare plan jsonb; flow_count integer;
begin
  select count(*) into flow_count from public.planned_cash_flows;
  if flow_count <> 0 then raise exception 'CASO I: user B can see user A planned_cash_flows'; end if;

  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  if jsonb_array_length(plan->'saldo_inicial'->'accounts') <> 0 then
    raise exception 'CASO I: user B sees user A accounts in get_financial_plan'; end if;
  if (plan->'saldo_inicial'->>'disponible_sin_comprometer_minor')::bigint <> 0 then
    raise exception 'CASO I: user B has nonzero saldo from user A data'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '90300000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- Horizon / currency validation.
-- ---------------------------------------------------------------------

do $$
begin
  begin
    perform public.get_financial_plan('MXN', '2020-08-20'::date, 4);
    raise exception 'Horizon validation: 4 should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_INVALID_HORIZON' then raise; end if;
  end;
  perform public.get_financial_plan('MXN', '2020-08-20'::date, 3);
  perform public.get_financial_plan('MXN', '2020-08-20'::date, 12);

  begin
    perform public.get_financial_plan('XXX', '2020-08-20'::date, 6);
    raise exception 'Currency validation: XXX should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_CURRENCY_NOT_FOUND' then raise; end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AF: shortfall never manufactures negative "disponible".
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; saldo jsonb; santander_line jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  saldo := plan->'saldo_inicial';

  -- Per-account line: Santander itself never shows negative "disponible"
  -- just because Japón's shortfall exists -- backing is capped at its own
  -- real balance ($5,000), never the nominal $8,000 saved.
  select elem into santander_line from jsonb_array_elements(saldo->'accounts') elem
    where (elem->>'account_id')::uuid = (select santander from plan_ids);
  if (santander_line->>'balance_minor')::bigint <> 500000 then
    raise exception 'CASO AF: expected Santander balance=500000, got %', santander_line->>'balance_minor'; end if;
  if (santander_line->>'backed_minor')::bigint <> 500000 then
    raise exception 'CASO AF: expected Santander backed=500000, got %', santander_line->>'backed_minor'; end if;
  if (santander_line->>'available_minor')::bigint <> 0 then
    raise exception 'CASO AF: expected Santander available=0 (not negative), got %', santander_line->>'available_minor';
  end if;

  -- Shortfall is goal-scoped, informative only: $8,000 saved - $5,000
  -- actually backed = $3,000, regardless of what other accounts hold.
  if (saldo->>'faltante_de_respaldo_minor')::bigint <> 300000 then
    raise exception 'CASO AF: expected shortfall=300000, got %', saldo->>'faltante_de_respaldo_minor';
  end if;

  -- Aggregate across every MXN account: Santander ($5,000 free of its own
  -- $5,000 backing) + Efectivo ($7,000, untouched by Japón) = $12,000
  -- saldo, $5,000 backed total, $7,000 disponible -- never negative.
  if (saldo->>'saldo_en_cuentas_minor')::bigint <> 1200000 then
    raise exception 'CASO AF: expected saldo_en_cuentas=1200000, got %', saldo->>'saldo_en_cuentas_minor'; end if;
  if (saldo->>'apartado_respaldado_minor')::bigint <> 500000 then
    raise exception 'CASO AF: expected backed=500000, got %', saldo->>'apartado_respaldado_minor'; end if;
  if (saldo->>'disponible_sin_comprometer_minor')::bigint <> 700000 then
    raise exception 'CASO AF: expected disponible=700000, got %', saldo->>'disponible_sin_comprometer_minor';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AG/AH/AI/AR/AS/AV(card): the September obligation.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; september jsonb; card_obs jsonb; real_remaining bigint; line jsonb; found_bbva boolean := false;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select month from jsonb_array_elements(plan->'months') month
    where (month->>'month_index')::int = 1 into september; -- Aug=0, Sep=1
  if september is null or (september->>'month_start')::date <> '2020-09-01' then
    raise exception 'CASO AG: September month row not found as expected'; end if;

  card_obs := september->'card_obligations';
  -- AI: the closed statement's remaining_due_minor is authoritative --
  -- never the preview, never both summed together.
  select remaining_due_minor into real_remaining
  from public.card_statements
  where user_id = '90300000-0000-4000-8000-000000000001' and statement_date = '2020-09-09';

  for line in select * from jsonb_array_elements(card_obs) loop
    if (line->>'card_id')::uuid = (select bbva from plan_ids) then
      found_bbva := true;
      if (line->>'amount_minor')::bigint <> real_remaining then
        raise exception 'CASO AI: expected closed statement remaining_due % , got %', real_remaining, line->>'amount_minor';
      end if;
      if (line->>'is_closed')::boolean is not true then
        raise exception 'CASO AI: BBVA September obligation should be is_closed=true'; end if;
    end if;
    -- AS: Amex closed at $0 must never appear as a visible obligation.
    if (line->>'card_id')::uuid = (select amex from plan_ids) then
      raise exception 'CASO AS: a $0 closed statement must not appear as a visible obligation';
    end if;
  end loop;
  if not found_bbva then raise exception 'CASO AG/AI: BBVA September obligation missing'; end if;

  -- CASO AR: a genuinely $0 preview (BBVA's December cut has no new
  -- activity at all) never appears as a visible obligation, even though
  -- the underlying preview function is happily called for it.
  if public.card_statement_preview_balance((select bbva from plan_ids), '2020-12-09'::date) <> 0 then
    raise exception 'CASO AR: test setup broken, expected BBVA December preview to be 0'; end if;
  if exists (
    select 1 from jsonb_array_elements(
      (select m.month from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 4)->'card_obligations'
    ) elem where (elem->>'card_id')::uuid = (select bbva from plan_ids)
  ) then raise exception 'CASO AR: a $0 preview must not appear as a visible obligation'; end if;

  -- AG: the underlying real balance genuinely includes the normal
  -- Supermercado purchase (it never vanished waiting for the close).
  if real_remaining < 500000 then
    raise exception 'CASO AG: closed statement should include the normal open-cycle purchase, got %', real_remaining;
  end if;

  -- AV: the visible line items sum exactly to the declared total.
  if (select coalesce(sum((elem->>'amount_minor')::bigint), 0) from jsonb_array_elements(card_obs) elem)
     <> (september->>'card_obligations_total_minor')::bigint then
    raise exception 'CASO AV: card_obligations lines do not sum to the declared total for September';
  end if;
end;
$$;

-- CASO AH: BEFORE the close, the preview for a not-yet-closed statement
-- already folds the cycle's normal spend + that cycle's own MSI
-- installment into one number, never listing them twice. Verified
-- directly against the underlying function using a hypothetical
-- statement_date one cycle further out (October), which is still open.
do $$
declare preview_minor bigint;
begin
  preview_minor := public.card_statement_preview_balance((select bbva from plan_ids), '2020-10-09'::date);
  -- October cycle contains: Carlos shared purchase ($4,000, non-MSI) +
  -- the second MSI installment due exactly then ($1,000) = $5,000, with
  -- no separate MSI line added on top.
  if preview_minor <> 500000 then
    raise exception 'CASO AH: expected October preview 500000 (4000 shared + 1000 MSI), got %', preview_minor;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AJ/AK/AL: planned_cash_flow vs. presupuesto.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; august jsonb; november jsonb; hogar_aug jsonb; hogar_nov jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select month from jsonb_array_elements(plan->'months') month where (month->>'month_index')::int = 0 into august;
  select month from jsonb_array_elements(plan->'months') month where (month->>'month_index')::int = 3 into november;

  select elem into hogar_aug from jsonb_array_elements(august->'budgets') elem where elem->>'category_id' = 'home';
  select elem into hogar_nov from jsonb_array_elements(november->'budgets') elem where elem->>'category_id' = 'home';

  -- CASO AK: August already has $3,000 real spend (available=$9,000) plus
  -- a future $6,000 categorized flow -> flexible adicional = $3,000.
  if (hogar_aug->>'available_minor')::bigint <> 900000 then
    raise exception 'CASO AK: expected available=900000, got %', hogar_aug->>'available_minor'; end if;
  if (hogar_aug->>'planned_categorized_minor')::bigint <> 600000 then
    raise exception 'CASO AK: expected planned_categorized=600000, got %', hogar_aug->>'planned_categorized_minor'; end if;
  if (hogar_aug->>'flexible_additional_minor')::bigint <> 300000 then
    raise exception 'CASO AK: expected flexible_additional=300000, got %', hogar_aug->>'flexible_additional_minor'; end if;

  -- CASO AJ: November has no real spend (available=$12,000) plus a future
  -- $10,000 categorized flow -> flexible adicional=$2,000, total presión
  -- = $12,000, never $22,000.
  if (hogar_nov->>'available_minor')::bigint <> 1200000 then
    raise exception 'CASO AJ: expected available=1200000, got %', hogar_nov->>'available_minor'; end if;
  if (hogar_nov->>'flexible_additional_minor')::bigint <> 200000 then
    raise exception 'CASO AJ: expected flexible_additional=200000, got %', hogar_nov->>'flexible_additional_minor'; end if;
  if ((hogar_nov->>'planned_categorized_minor')::bigint + (hogar_nov->>'flexible_additional_minor')::bigint) <> 1200000 then
    raise exception 'CASO AJ: total pressure must equal the limit (1200000), not 2200000';
  end if;

  -- CASO AL: the uncategorized $500 flow never touches Hogar's numbers.
  if (hogar_aug->>'planned_categorized_minor')::bigint <> 600000 then
    raise exception 'CASO AL: uncategorized flow leaked into Hogar planned_categorized'; end if;
end;
$$;

-- CASO AT: a planned flow whose one_time date already passed (within the
-- current month, relative to as_of_date) never reappears.
do $$
declare plan jsonb; hit_count integer;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select count(*) into hit_count
  from jsonb_array_elements(plan->'months') month, jsonb_array_elements(month->'planned_flows') flow
  where flow->>'name' = 'Ya pagado';
  if hit_count <> 0 then raise exception 'CASO AT: a past-dated flow was reprojected'; end if;
end;
$$;

-- CASO AQ (superseded by Phase 7A): day-31 clamp for a recurring monthly
-- commitment is no longer a planned_cash_flows concern -- recurring_rules
-- owns every recurring commitment now, tested with the same rigor (and
-- through the real calendar engine, not a one-off flow) in
-- recurring_transactions.test.sql CASO C.

-- ---------------------------------------------------------------------
-- CASOS AM/AN: recursive, non-persisted goal simulation.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; month jsonb; goal_line jsonb; idx int; expected bigint;
  expected_recursiva bigint[] := array[200000, 200000, 0, 0, 0, 0];
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  for idx in 0..5 loop
    select m.month into month from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = idx;
    select elem into goal_line from jsonb_array_elements(month->'goals') elem
      where (elem->>'goal_id')::uuid = (select recursiva from plan_ids);
    expected := expected_recursiva[idx + 1];
    if idx < 2 then
      -- CASO AM: months 0-1, still short of the $4,000 target, keep a
      -- coherent $2,000/month recommendation (no runaway growth from
      -- re-reading a static real saved_minor).
      if (goal_line->>'recommended_minor')::bigint <> expected then
        raise exception 'CASO AM: month % expected coherent recommended % got %', idx, expected, goal_line->>'recommended_minor';
      end if;
    else
      -- CASO AN: the simulation reaches the target during month 1
      -- (projected_saved = 4,000 = target), so months 2-5 recommend $0.
      if (goal_line->>'recommended_minor')::bigint <> expected then
        raise exception 'CASO AN: month % expected 0 after reaching target, got %', idx, goal_line->>'recommended_minor';
      end if;
    end if;

    -- Meta pausada: always 0.
    select elem into goal_line from jsonb_array_elements(month->'goals') elem
      where (elem->>'goal_id')::uuid = (select pausada from plan_ids);
    if (goal_line->>'recommended_minor')::bigint <> 0 then
      raise exception 'CASO AM: paused goal must always recommend 0 (month %)', idx; end if;

    -- Meta archivada: excluded entirely.
    if exists (
      select 1 from jsonb_array_elements(month->'goals') elem
      where (elem->>'goal_id')::uuid = (select archivada from plan_ids)
    ) then raise exception 'CASO AM: archived goal must be excluded entirely (month %)', idx; end if;
  end loop;

  -- No goal_entries were touched by the simulation.
  if exists (select 1 from public.goal_entries where goal_id = (select recursiva from plan_ids)) then
    raise exception 'CASO AM: simulation must never write to goal_entries';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AO/AP: independent scenario carry-forward.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; months jsonb; prev jsonb; curr jsonb; idx int;
  collections_month jsonb; collection_total bigint; pwc_delta bigint; planned_delta bigint;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  months := plan->'months';

  -- AO: each scenario's opening this month equals ITS OWN closing last
  -- month -- never crossed with another scenario.
  for idx in 1..5 loop
    select m.month into prev from jsonb_array_elements(months) m(month) where (m.month->>'month_index')::int = idx - 1;
    select m.month into curr from jsonb_array_elements(months) m(month) where (m.month->>'month_index')::int = idx;
    if (curr->'base'->>'opening_minor')::bigint <> (prev->'base'->>'closing_minor')::bigint then
      raise exception 'CASO AO: base carry-forward broken at month %', idx; end if;
    if (curr->'planned'->>'opening_minor')::bigint <> (prev->'planned'->>'closing_minor')::bigint then
      raise exception 'CASO AO: planned carry-forward broken at month %', idx; end if;
    if (curr->'planned_with_collections'->>'opening_minor')::bigint <> (prev->'planned_with_collections'->>'closing_minor')::bigint then
      raise exception 'CASO AO: planned_with_collections carry-forward broken at month %', idx; end if;
  end loop;

  -- AP: collections affect ONLY planned_with_collections, additively, in
  -- exactly the month they are expected -- base and planned never move.
  for idx in 0..5 loop
    select m.month into curr from jsonb_array_elements(months) m(month) where (m.month->>'month_index')::int = idx;
    collection_total := (curr->>'expected_collections_total_minor')::bigint;
    pwc_delta := (curr->'planned_with_collections'->>'closing_minor')::bigint - (curr->'planned_with_collections'->>'opening_minor')::bigint;
    planned_delta := (curr->'planned'->>'closing_minor')::bigint - (curr->'planned'->>'opening_minor')::bigint;
    if pwc_delta - planned_delta <> collection_total then
      raise exception 'CASO AP: month % planned_with_collections must exceed planned by exactly its collections (% vs %)',
        idx, pwc_delta - planned_delta, collection_total;
    end if;
  end loop;

  if not exists (select 1 from jsonb_array_elements(months) m(month) where (m.month->>'expected_collections_total_minor')::bigint > 0) then
    raise exception 'CASO AP: expected at least one month with a nonzero expected collection (Carlos)';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS O/P/Q: Carlos owes $4,000 from a card purchase. The card
-- obligation requires the full amount; the expected collection is a
-- separate, non-guaranteed line; neither cancels the other. Base/Planeado
-- (cobros OFF) keep the full card outflow; only Planeado+cobros reflects
-- the possible recovery, and only in Carlos's own due month.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; october jsonb; collection_month jsonb; card_line jsonb; collection_line jsonb;
  found_bbva boolean := false; collection_month_index int; base_delta bigint; planned_delta bigint; pwc_delta bigint;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into october from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 2;

  -- CASO O: October's BBVA obligation is the full preview (Carlos's
  -- $4,000 purchase + the $1,000 MSI installment due that same cut = 5,000).
  for card_line in select * from jsonb_array_elements(october->'card_obligations') loop
    if (card_line->>'card_id')::uuid = (select bbva from plan_ids) then
      found_bbva := true;
      if (card_line->>'amount_minor')::bigint <> 500000 then
        raise exception 'CASO O: expected October BBVA obligation 500000, got %', card_line->>'amount_minor'; end if;
    end if;
  end loop;
  if not found_bbva then raise exception 'CASO O: BBVA October obligation missing'; end if;
  if (october->>'card_obligations_total_minor')::bigint <> 500000 then
    raise exception 'CASO O: card obligation must not be reduced by the mere existence of an expected collection';
  end if;

  -- Carlos's collection appears somewhere in the horizon as its own line,
  -- for the full $4,000, never netted against the card obligation above.
  select m.month, (m.month->>'month_index')::int into collection_month, collection_month_index
  from jsonb_array_elements(plan->'months') m(month), jsonb_array_elements(m.month->'expected_collections') c(elem)
  where (c.elem->>'contact_id')::uuid = (select carlos from plan_ids)
  limit 1;
  if collection_month is null then raise exception 'CASO O: Carlos collection line not found anywhere in the horizon'; end if;
  select elem into collection_line from jsonb_array_elements(collection_month->'expected_collections') elem
    where (elem->>'contact_id')::uuid = (select carlos from plan_ids);
  if (collection_line->>'outstanding_minor')::bigint <> 400000 then
    raise exception 'CASO O: expected Carlos outstanding 400000, got %', collection_line->>'outstanding_minor'; end if;

  -- CASO P: with cobros esperados OFF (base/planned), the full card outflow
  -- is preserved in whichever month it actually falls -- October always
  -- subtracts the full 500000 from base and planned, collections or not.
  base_delta := (october->'base'->>'closing_minor')::bigint - (october->'base'->>'opening_minor')::bigint;
  planned_delta := (october->'planned'->>'closing_minor')::bigint - (october->'planned'->>'opening_minor')::bigint;
  if (base_delta + (october->>'card_obligations_total_minor')::bigint
      - (october->>'planned_income_total_minor')::bigint + (october->>'planned_outflow_total_minor')::bigint) <> 0 then
    raise exception 'CASO P: base scenario does not reflect the full card outflow for October';
  end if;
  if (planned_delta - base_delta) <> -((october->>'flexible_additional_total_minor')::bigint + (october->>'goals_recommended_total_minor')::bigint) then
    raise exception 'CASO P: planned scenario diverges from base by something other than budgets/goals in October';
  end if;

  -- CASO Q: with cobros esperados ON, ONLY the month that actually holds
  -- Carlos's collection differs between planned and planned_with_collections
  -- -- by exactly that collection amount, additively.
  pwc_delta := (collection_month->'planned_with_collections'->>'closing_minor')::bigint - (collection_month->'planned_with_collections'->>'opening_minor')::bigint;
  planned_delta := (collection_month->'planned'->>'closing_minor')::bigint - (collection_month->'planned'->>'opening_minor')::bigint;
  if (pwc_delta - planned_delta) <> (collection_line->>'outstanding_minor')::bigint then
    raise exception 'CASO Q: planned_with_collections must exceed planned by exactly Carlos''s outstanding amount in his own due month';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS R/S: manual planned income/outflow move the projection without
-- ever creating a financial_event.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; december jsonb; before_fe bigint; after_fe bigint;
begin
  select count(*) into before_fe from public.financial_events;
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO R/S: get_financial_plan created financial_events'; end if;

  select m.month into december from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 4;
  if december is null then raise exception 'CASO R/S: December month not found'; end if;

  -- CASO R: +$30,000 planned income increases the month's income total and
  -- appears as its own line.
  if (december->>'planned_income_total_minor')::bigint < 3000000 then
    raise exception 'CASO R: expected planned income >= 3000000 in December, got %', december->>'planned_income_total_minor';
  end if;
  if not exists (select 1 from jsonb_array_elements(december->'planned_flows') f where (f->>'flow_id')::uuid = (select income_flow from plan_ids)) then
    raise exception 'CASO R: income flow line missing from December'; end if;

  -- CASO S: -$10,000 planned outflow reduces the month's projection and
  -- appears as its own line.
  if (december->>'planned_outflow_total_minor')::bigint < 1000000 then
    raise exception 'CASO S: expected planned outflow >= 1000000 in December, got %', december->>'planned_outflow_total_minor';
  end if;
  if not exists (select 1 from jsonb_array_elements(december->'planned_flows') f where (f->>'flow_id')::uuid = (select outflow_flow from plan_ids)) then
    raise exception 'CASO S: outflow flow line missing from December'; end if;

  -- Neither ever became a real financial_event.
  if exists (select 1 from public.financial_events where description in ('Ingreso extraordinario', 'Gasto extraordinario')) then
    raise exception 'CASO R/S: a planned_cash_flow leaked into financial_events';
  end if;
end;
$$;

-- CASO T (superseded by Phase 7A, see the AQ note above): the day-31
-- cross-February clamp is now tested through recurring_rules.

-- ---------------------------------------------------------------------
-- CASO V: an archived account, even with real money in it, contributes
-- nothing to saldo inicial.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  if exists (
    select 1 from jsonb_array_elements(plan->'saldo_inicial'->'accounts') elem
    where (elem->>'account_id')::uuid = (select archived_account from plan_ids)
  ) then raise exception 'CASO V: an archived account appears in saldo inicial'; end if;
  if (select balance_minor from public.account_balances where id = (select archived_account from plan_ids)) <> 900000 then
    raise exception 'CASO V: test setup broken -- archived account balance changed unexpectedly';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO W: a credit card is never counted as an available asset.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  if exists (
    select 1 from jsonb_array_elements(plan->'saldo_inicial'->'accounts') elem
    where (elem->>'account_id')::uuid in ((select bbva from plan_ids), (select amex from plan_ids))
  ) then raise exception 'CASO W: a credit card appears as an account in saldo inicial'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO X: a projection that goes negative stays negative -- never
-- clamped or auto-corrected.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; january jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into january from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 5;
  if (january->'planned'->>'closing_minor')::bigint >= 0 then
    raise exception 'CASO X: expected a negative January closing after a 5,000,000 planned outflow, got %', january->'planned'->>'closing_minor';
  end if;
  -- Not silently corrected to zero, and not silently dropped from the response.
  if january->'planned'->>'closing_minor' is null then raise exception 'CASO X: negative closing must still be present, not hidden'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO Z: determinism -- the same DB state and the same p_as_of_date
-- always produce exactly the same result.
-- ---------------------------------------------------------------------

do $$
declare plan1 jsonb; plan2 jsonb;
begin
  plan1 := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  plan2 := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  if plan1 <> plan2 then raise exception 'CASO Z: two calls with identical state and p_as_of_date produced different results'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AA: user B cannot write to user A's planned_cash_flows even when
-- it already knows a real id (stronger than CASO I, which only checked
-- read isolation).
-- ---------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90300000-0000-4000-8000-000000000002', true);

do $$
begin
  begin
    perform public.update_planned_cash_flow((select income_flow from plan_ids), 'Hackeado', 100, null, 'one_time', '2020-01-01', null, 'p6c-aa-hack-update');
    raise exception 'CASO AA: user B was able to update user A''s planned_cash_flow';
  exception when others then
    if sqlerrm <> 'NEXO_PLANNED_CASH_FLOW_NOT_FOUND' then raise; end if;
  end;
  begin
    perform public.archive_planned_cash_flow((select income_flow from plan_ids), 'p6c-aa-hack-archive');
    raise exception 'CASO AA: user B was able to archive user A''s planned_cash_flow';
  exception when others then
    if sqlerrm <> 'NEXO_PLANNED_CASH_FLOW_NOT_FOUND' then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '90300000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- CASO AB: archiving/restoring a planned_cash_flow never touches
-- financial_events.
-- ---------------------------------------------------------------------

do $$
declare before_fe int; after_fe int;
begin
  select count(*) into before_fe from public.financial_events;
  perform public.archive_planned_cash_flow((select income_flow from plan_ids), 'p6c-ab-archive');
  perform public.restore_planned_cash_flow((select income_flow from plan_ids), 'p6c-ab-restore');
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO AB: archive/restore of a planned_cash_flow touched financial_events'; end if;
  if (select archived_at from public.planned_cash_flows where id = (select income_flow from plan_ids)) is not null then
    raise exception 'CASO AB: income_flow should be active again after the archive/restore round trip';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AC: no planned_cash_flow write RPC ever touches account_entries.
-- ---------------------------------------------------------------------

do $$
declare before_ae int; after_ae int; scratch_flow uuid;
begin
  select count(*) into before_ae from public.account_entries;
  scratch_flow := public.create_planned_cash_flow('AC test', 'MXN', -12345, null, 'one_time', '2020-09-01', null, 'p6c-ac-create');
  perform public.update_planned_cash_flow(scratch_flow, 'AC test updated', -54321, null, 'one_time', '2020-09-02', null, 'p6c-ac-update');
  perform public.archive_planned_cash_flow(scratch_flow, 'p6c-ac-archive');
  perform public.restore_planned_cash_flow(scratch_flow, 'p6c-ac-restore');
  select count(*) into after_ae from public.account_entries;
  if after_ae <> before_ae then raise exception 'CASO AC: a planned_cash_flow write RPC touched account_entries'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AD: no planned_cash_flow write RPC ever touches card_statements,
-- installments, goals, goal_entries, budgets or receivable_entries.
-- ---------------------------------------------------------------------

do $$
declare before_counts record; after_counts record; scratch_flow uuid;
begin
  select
    (select count(*) from public.card_statements) as cs,
    (select count(*) from public.installments) as inst,
    (select count(*) from public.goals) as g,
    (select count(*) from public.goal_entries) as ge,
    (select count(*) from public.budgets) as bg,
    (select count(*) from public.receivable_entries) as re
  into before_counts;

  scratch_flow := public.create_planned_cash_flow('AD test', 'MXN', 999900, null, 'one_time', '2020-09-01', null, 'p6c-ad-create');
  perform public.update_planned_cash_flow(scratch_flow, 'AD test updated', 999901, null, 'one_time', '2020-09-02', null, 'p6c-ad-update');
  perform public.archive_planned_cash_flow(scratch_flow, 'p6c-ad-archive');
  perform public.restore_planned_cash_flow(scratch_flow, 'p6c-ad-restore');

  select
    (select count(*) from public.card_statements) as cs,
    (select count(*) from public.installments) as inst,
    (select count(*) from public.goals) as g,
    (select count(*) from public.goal_entries) as ge,
    (select count(*) from public.budgets) as bg,
    (select count(*) from public.receivable_entries) as re
  into after_counts;

  if before_counts is distinct from after_counts then
    raise exception 'CASO AD: a planned_cash_flow write RPC touched card_statements/installments/goals/goal_entries/budgets/receivable_entries';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AE: integrated anti-double-count case. Every source is active at
-- once (card statement/preview with an MSI installment inside it, a
-- category budget, a categorized planned_cash_flow, a goal, and a
-- person's expected collection); every figure below is cross-checked
-- against RAW domain tables directly, never against get_financial_plan's
-- own intermediate numbers, so this cannot pass by the RPC being
-- internally consistent with itself alone.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; august jsonb; hogar jsonb;
  raw_limit bigint; raw_spent bigint; raw_categorized bigint; raw_available bigint; raw_flexible bigint;
  raw_goal_target bigint; raw_goal_saved bigint; raw_goal_recommended bigint;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into august from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 0;

  -- 1) Tarjeta: BBVA's first cut is September (verified independently from
  -- credit_cards/card_baselines), so August's card pressure must be zero.
  if (august->>'card_obligations_total_minor')::bigint <> 0 then
    raise exception 'CASO AE: August should have zero card pressure, got %', august->>'card_obligations_total_minor';
  end if;

  -- 2) Presupuesto: recompute available/flexible straight from budgets +
  -- budget_period_spend + planned_cash_flows -- never from the RPC itself.
  select limit_minor into raw_limit from public.budgets
    where user_id = '90300000-0000-4000-8000-000000000001' and category_id = 'home' and currency = 'MXN' and archived_at is null
      and effective_from_month <= '2020-08-01' and (effective_to_month is null or effective_to_month >= '2020-08-01');
  select coalesce(spent_minor, 0) into raw_spent from public.budget_period_spend
    where user_id = '90300000-0000-4000-8000-000000000001' and category_id = 'home' and currency = 'MXN' and period_month = '2020-08-01';
  raw_available := raw_limit - coalesce(raw_spent, 0);
  select coalesce(sum(-amount_minor), 0) into raw_categorized from public.planned_cash_flows
    where user_id = '90300000-0000-4000-8000-000000000001' and category_id = 'home' and currency = 'MXN'
      and archived_at is null and recurrence = 'one_time' and start_date = '2020-08-25';
  raw_flexible := greatest(raw_available - raw_categorized, 0);

  select elem into hogar from jsonb_array_elements(august->'budgets') elem where elem->>'category_id' = 'home';
  if (hogar->>'available_minor')::bigint <> raw_available then
    raise exception 'CASO AE: budget available (%) does not match raw reconstruction (%)', hogar->>'available_minor', raw_available; end if;
  if (hogar->>'planned_categorized_minor')::bigint <> raw_categorized then
    raise exception 'CASO AE: planned_categorized (%) does not match raw reconstruction (%)', hogar->>'planned_categorized_minor', raw_categorized; end if;
  if (hogar->>'flexible_additional_minor')::bigint <> raw_flexible then
    raise exception 'CASO AE: flexible_additional (%) does not match raw reconstruction (%)', hogar->>'flexible_additional_minor', raw_flexible; end if;
  -- Real spend + explicit planned + remaining flexible must account for
  -- the limit exactly (no double count, no invented headroom) whenever
  -- the plan does not itself overshoot the category's available room.
  if raw_categorized <= raw_available and (raw_spent + raw_categorized + raw_flexible) <> raw_limit then
    raise exception 'CASO AE: real spend + planned + flexible (%) should equal the limit (%) exactly, no double count',
      raw_spent + raw_categorized + raw_flexible, raw_limit;
  end if;

  -- 3) Metas: recompute Meta recursiva's month-0 recommendation from raw
  -- goal_balances (target $4,000, $0 saved, 2 months to 2020-10-20).
  select target_minor, saved_minor into raw_goal_target, raw_goal_saved
  from public.goal_balances where id = (select recursiva from plan_ids);
  raw_goal_recommended := ceil((raw_goal_target - raw_goal_saved)::numeric / 2);
  if (
    select (elem->>'recommended_minor')::bigint from jsonb_array_elements(august->'goals') elem
    where (elem->>'goal_id')::uuid = (select recursiva from plan_ids)
  ) <> raw_goal_recommended then
    raise exception 'CASO AE: goal recommendation does not match raw domain reconstruction';
  end if;

  -- 4) Cobros: Carlos's collection, if it ever lands in the same month as
  -- card pressure, must stay strictly additive -- never subtracted from it.
  if exists (
    select 1 from jsonb_array_elements(august->'expected_collections') elem
    where (elem->>'contact_id')::uuid = (select carlos from plan_ids)
  ) and (august->>'card_obligations_total_minor')::bigint <> 0 then
    raise exception 'CASO AE: a collection coexisting with card pressure in the same month must remain additive';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Tarjeta con corte día 31 cruzando febrero (auditoría §5): verifies the
-- raw date functions directly, then confirms the clamp survives end to
-- end through get_financial_plan with real, nonzero activity in both the
-- clamped (February) and reverted (March) cuts.
-- ---------------------------------------------------------------------

do $$
declare
  card31_id uuid; plan jsonb; march jsonb; april jsonb; line jsonb; found boolean;
begin
  -- Raw domain function: the clamp and its reversion, independent of any
  -- card or purchase.
  if public.card_effective_statement_date(2021, 2, 31) <> '2021-02-28'::date then
    raise exception 'Corte 31: expected February 2021 (not a leap year) to clamp to the 28th'; end if;
  if public.card_effective_statement_date(2020, 2, 31) <> '2020-02-29'::date then
    raise exception 'Corte 31: expected February 2020 (a leap year) to clamp to the 29th'; end if;
  if public.card_effective_statement_date(2021, 3, 31) <> '2021-03-31'::date then
    raise exception 'Corte 31: expected March to return to day 31 without permanent drift'; end if;

  -- End to end: a card with statement_day=31, walked from December 2020
  -- through May 2021, with one purchase landing in the clamped February
  -- cut and another in the reverted March cut.
  card31_id := public.create_credit_card('Corte 31', 'Banco', null, 'MXN', 5000000, 31, 10, null,
    'generic', 'current_bank_balance', '2020-11-01', 0, null, null, 'p6c-card31');
  perform public.create_card_purchase(card31_id, 100000, 'Compra de febrero', 'food', '2021-02-10', null, null, 'p6c-card31-feb');
  perform public.create_card_purchase(card31_id, 150000, 'Compra de marzo', 'food', '2021-03-15', null, null, 'p6c-card31-mar');

  plan := public.get_financial_plan('MXN', '2020-12-15'::date, 6);
  select m.month into march from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_start')::date = '2021-03-01';
  select m.month into april from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_start')::date = '2021-04-01';

  -- The February purchase's statement closes 2021-02-28, due 10 days
  -- later (2021-03-10) -- so it lands in MARCH's obligations, clamped.
  found := false;
  for line in select * from jsonb_array_elements(march->'card_obligations') loop
    if (line->>'card_id')::uuid = card31_id then
      found := true;
      if (line->>'statement_date')::date <> '2021-02-28' then
        raise exception 'Corte 31: expected statement_date 2021-02-28, got %', line->>'statement_date'; end if;
      if (line->>'amount_minor')::bigint <> 100000 then
        raise exception 'Corte 31: expected 100000, got %', line->>'amount_minor'; end if;
    end if;
  end loop;
  if not found then raise exception 'Corte 31: February-cut obligation missing from March'; end if;

  -- The March purchase's statement closes 2021-03-31 (back to day 31),
  -- due 2021-04-10 -- lands in APRIL's obligations.
  found := false;
  for line in select * from jsonb_array_elements(april->'card_obligations') loop
    if (line->>'card_id')::uuid = card31_id then
      found := true;
      if (line->>'statement_date')::date <> '2021-03-31' then
        raise exception 'Corte 31: expected statement_date 2021-03-31, got %', line->>'statement_date'; end if;
      if (line->>'amount_minor')::bigint <> 150000 then
        raise exception 'Corte 31: expected 150000, got %', line->>'amount_minor'; end if;
    end if;
  end loop;
  if not found then raise exception 'Corte 31: March-cut obligation missing from April'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Auditoría §6: budget_available < planned_categorized shows the
-- overshoot honestly instead of clamping the plan to fit the limit.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; december jsonb; hogar jsonb;
begin
  -- Step 1: commit $8,000 of December's $12,000 Hogar budget -- still
  -- under the limit, just setup for step 2's overshoot below.
  perform public.create_planned_cash_flow('Remodelación', 'MXN', -800000, 'home', 'one_time', '2020-12-10', null, 'p6c-over-budget-flow');
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into december from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 4;
  select elem into hogar from jsonb_array_elements(december->'budgets') elem where elem->>'category_id' = 'home';
  -- December available is 12,000 (no real spend); categorized is 8,000;
  -- flexible = max(12000-8000,0) = 4,000 -- not yet an overshoot case.
  if (hogar->>'planned_categorized_minor')::bigint <> 800000 then
    raise exception 'Auditoría §6 setup: expected planned_categorized 800000, got %', hogar->>'planned_categorized_minor'; end if;
end;
$$;

do $$
declare over_flow uuid; plan jsonb; december jsonb; hogar jsonb;
begin
  -- Push December's categorized total past its own $12,000 limit: add
  -- another $5,000 in the same category and month (800000 + 500000 =
  -- 1,300,000 > 1,200,000 limit).
  over_flow := public.create_planned_cash_flow('Mueblería', 'MXN', -500000, 'home', 'one_time', '2020-12-11', null, 'p6c-over-budget-flow-2');
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into december from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 4;
  select elem into hogar from jsonb_array_elements(december->'budgets') elem where elem->>'category_id' = 'home';

  if (hogar->>'planned_categorized_minor')::bigint <> 1300000 then
    raise exception 'Auditoría §6: expected planned explícito 1300000, got %', hogar->>'planned_categorized_minor'; end if;
  if (hogar->>'flexible_additional_minor')::bigint <> 0 then
    raise exception 'Auditoría §6: expected flexible adicional 0 (never negative), got %', hogar->>'flexible_additional_minor'; end if;
  -- Never clamp the declared intention down to fit the limit.
  if (hogar->>'planned_categorized_minor')::bigint = (hogar->>'available_minor')::bigint then
    raise exception 'Auditoría §6: planned_categorized must never be silently clamped to available_minor';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AV (generic): every visible line-item array sums exactly to its
-- declared aggregate, across every month.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; month jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  for month in select * from jsonb_array_elements(plan->'months') loop
    if (select coalesce(sum((e->>'amount_minor')::bigint), 0) from jsonb_array_elements(month->'card_obligations') e)
       <> (month->>'card_obligations_total_minor')::bigint then
      raise exception 'CASO AV: card_obligations mismatch at month %', month->>'month_index'; end if;
    if (select coalesce(sum((e->>'flexible_additional_minor')::bigint), 0) from jsonb_array_elements(month->'budgets') e)
       <> (month->>'flexible_additional_total_minor')::bigint then
      raise exception 'CASO AV: budgets flexible mismatch at month %', month->>'month_index'; end if;
    if (select coalesce(sum((e->>'recommended_minor')::bigint), 0) from jsonb_array_elements(month->'goals') e)
       <> (month->>'goals_recommended_total_minor')::bigint then
      raise exception 'CASO AV: goals recommended mismatch at month %', month->>'month_index'; end if;
    if (select coalesce(sum((e->>'outstanding_minor')::bigint), 0) from jsonb_array_elements(month->'expected_collections') e)
       <> (month->>'expected_collections_total_minor')::bigint then
      raise exception 'CASO AV: expected_collections mismatch at month %', month->>'month_index'; end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AW (generic): each scenario's monthly closing-minus-opening
-- reproduces exactly the net of its own declared components.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; month jsonb; base_net bigint; planned_net bigint; pwc_net bigint;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  for month in select * from jsonb_array_elements(plan->'months') loop
    base_net := (month->>'planned_income_total_minor')::bigint - (month->>'planned_outflow_total_minor')::bigint
      - (month->>'card_obligations_total_minor')::bigint;
    planned_net := base_net - (month->>'flexible_additional_total_minor')::bigint - (month->>'goals_recommended_total_minor')::bigint;
    pwc_net := planned_net + (month->>'expected_collections_total_minor')::bigint;

    if (month->'base'->>'closing_minor')::bigint - (month->'base'->>'opening_minor')::bigint <> base_net then
      raise exception 'CASO AW: base net mismatch at month %', month->>'month_index'; end if;
    if (month->'planned'->>'closing_minor')::bigint - (month->'planned'->>'opening_minor')::bigint <> planned_net then
      raise exception 'CASO AW: planned net mismatch at month %', month->>'month_index'; end if;
    if (month->'planned_with_collections'->>'closing_minor')::bigint - (month->'planned_with_collections'->>'opening_minor')::bigint <> pwc_net then
      raise exception 'CASO AW: planned_with_collections net mismatch at month %', month->>'month_index'; end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AU: Planeación never writes to the real financial engine.
-- ---------------------------------------------------------------------

do $$
declare
  before_counts record;
  after_counts record;
begin
  select
    (select count(*) from public.financial_events) as fe,
    (select count(*) from public.account_entries) as ae,
    (select count(*) from public.card_statements) as cs,
    (select count(*) from public.installments) as inst,
    (select count(*) from public.goal_entries) as ge,
    (select count(*) from public.budgets) as bg,
    (select count(*) from public.receivable_entries) as re
  into before_counts;

  perform public.get_financial_plan('MXN', '2020-08-20'::date, 12);
  perform public.get_financial_plan('USD', '2020-08-20'::date, 3);

  select
    (select count(*) from public.financial_events) as fe,
    (select count(*) from public.account_entries) as ae,
    (select count(*) from public.card_statements) as cs,
    (select count(*) from public.installments) as inst,
    (select count(*) from public.goal_entries) as ge,
    (select count(*) from public.budgets) as bg,
    (select count(*) from public.receivable_entries) as re
  into after_counts;

  if before_counts is distinct from after_counts then
    raise exception 'CASO AU: get_financial_plan mutated the real financial engine';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO U: MXN/USD/EUR remain fully separated -- no currency sum, ever.
-- ---------------------------------------------------------------------

do $$
declare mxn_plan jsonb; usd_plan jsonb; eur_plan jsonb;
begin
  mxn_plan := public.get_financial_plan('MXN', '2020-08-20'::date, 3);
  usd_plan := public.get_financial_plan('USD', '2020-08-20'::date, 3);
  eur_plan := public.get_financial_plan('EUR', '2020-08-20'::date, 3);

  if (usd_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint <> 100000 then
    raise exception 'CASO U: expected USD saldo=100000, got %', usd_plan->'saldo_inicial'->>'saldo_en_cuentas_minor';
  end if;
  if jsonb_array_length(usd_plan->'saldo_inicial'->'accounts') <> 1 then
    raise exception 'CASO U: USD plan should show exactly the one USD account'; end if;

  if (eur_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint <> 200000 then
    raise exception 'CASO U: expected EUR saldo=200000, got %', eur_plan->'saldo_inicial'->>'saldo_en_cuentas_minor';
  end if;
  if jsonb_array_length(eur_plan->'saldo_inicial'->'accounts') <> 1 then
    raise exception 'CASO U: EUR plan should show exactly the one EUR account'; end if;

  if (mxn_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint = 100000 then
    raise exception 'CASO U: MXN plan should not equal the USD-only figure'; end if;
  if (mxn_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint
     = (usd_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint + (eur_plan->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint then
    raise exception 'CASO U: MXN total must never coincide with USD+EUR summed -- possible currency mixing';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO Y: reversing a real financial movement at its SOURCE changes the
-- derived plan correctly, without editing any of 6C's own data
-- (planned_cash_flows). Runs last -- it mutates real account state.
-- ---------------------------------------------------------------------

do $$
declare
  plan_before jsonb; plan_after jsonb;
  balance_before bigint; balance_after bigint;
  flows_before int; flows_after int;
begin
  select balance_minor into balance_before from public.account_balances where id = (select santander from plan_ids);
  plan_before := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select count(*) into flows_before from public.planned_cash_flows;

  perform public.reverse_transaction((select unrelated_expense_event from plan_ids), 'p6c-y-reverse');

  select balance_minor into balance_after from public.account_balances where id = (select santander from plan_ids);
  plan_after := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select count(*) into flows_after from public.planned_cash_flows;

  if balance_after <> balance_before + 500000 then
    raise exception 'CASO Y: reversal did not restore 500000 to Santander as expected'; end if;
  if (plan_after->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint
     <> (plan_before->'saldo_inicial'->>'saldo_en_cuentas_minor')::bigint + 500000 then
    raise exception 'CASO Y: the derived plan did not follow the reversal at its source';
  end if;
  if flows_after <> flows_before then
    raise exception 'CASO Y: reversing a real movement must never touch planned_cash_flows rows';
  end if;
end;
$$;

rollback;

select 'financial planning: CRUD, RLS, and A-AW anti-double-count invariants passed' as result;
