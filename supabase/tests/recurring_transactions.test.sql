-- Phase 7A: recurring transactions (Recurrentes). Covers every letter A-BA
-- from the approved design: calendar engine (versions, pauses, all eight
-- frequencies), confirm/omit against the real financial engine, atomic
-- concurrency-safe confirmation, append-only reversal/replacement
-- trazability, the migration from 6C's monthly planned_cash_flows, and
-- integration with Planeación/Presupuestos. Dates are pinned (2020) so the
-- file is deterministic regardless of when it runs.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('90400000-0000-4000-8000-000000000001', 'recur-a@example.test', '{}'),
  ('90400000-0000-4000-8000-000000000002', 'recur-b@example.test', '{}');

create temporary table recur_ids (
  santander uuid, usd_account uuid, bbva uuid,
  renta uuid, netflix uuid, nomina uuid, gimnasio uuid, seguro uuid, semanal uuid, dia31 uuid
);
insert into recur_ids default values;
grant select, update on recur_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90400000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- Main scenario setup.
-- ---------------------------------------------------------------------

do $$
declare
  santander_id uuid; usd_id uuid; bbva_id uuid;
  renta_id uuid; netflix_id uuid; nomina_id uuid; gimnasio_id uuid; seguro_id uuid; semanal_id uuid; dia31_id uuid;
begin
  santander_id := public.create_account('Santander', 'checking', 'MXN', 5000000, null, null, 'p7a-account-santander');
  usd_id := public.create_account('Cuenta USD', 'checking', 'USD', 100000, null, null, 'p7a-account-usd');

  bbva_id := public.create_credit_card('BBVA', 'BBVA', null, 'MXN', 5000000, 9, 20, null,
    'generic', 'current_bank_balance', '2020-08-01', 0, null, null, 'p7a-card-bbva');
  perform public.close_card_statement(bbva_id, '2020-08-09', null, 0, 'p7a-close-bbva-aug');

  perform public.create_budget('subscriptions', 'MXN', 100000, '2020-08-01', null, 'p7a-budget-subs');

  -- CASOS A/I/O/P/Q/S/AZ: Renta, gasto de cuenta mensual.
  renta_id := public.create_recurring_rule('Renta', 'expense', 'MXN', 1200000, 'home',
    'monthly', 1, null, santander_id, null, '2020-08-01', null, null, 'p7a-rule-renta');

  -- CASOS J/T/AH/AI: Netflix, gasto de tarjeta mensual, categorizado.
  netflix_id := public.create_recurring_rule('Netflix', 'expense', 'MXN', 24900, 'subscriptions',
    'monthly', 15, null, null, bbva_id, '2020-08-01', null, null, 'p7a-rule-netflix');

  -- CASOS B/K/E/W: Nómina, ingreso semimensual (15 y último día).
  nomina_id := public.create_recurring_rule('Nómina', 'income', 'MXN', 3000000, 'salary',
    'semimonthly', 15, 31, santander_id, null, '2020-08-01', null, null, 'p7a-rule-nomina');

  -- CASOS D/F/G/AN: Gimnasio, gasto quincenal (cada 2 semanas exactas).
  gimnasio_id := public.create_recurring_rule('Gimnasio', 'expense', 'MXN', 70000, null,
    'biweekly', null, null, santander_id, null, '2020-08-03', null, null, 'p7a-rule-gimnasio');

  -- CASO AO: Seguro, sin fuente predeterminada.
  seguro_id := public.create_recurring_rule('Seguro del auto', 'expense', 'MXN', 800000, null,
    'annual', 15, null, null, null, '2020-08-01', null, null, 'p7a-rule-seguro');

  -- CASO D (semanal puro): comparación directa contra biweekly.
  semanal_id := public.create_recurring_rule('Semanal test', 'expense', 'MXN', 10000, null,
    'weekly', null, null, santander_id, null, '2020-08-03', null, null, 'p7a-rule-semanal');

  -- CASO C: recurrencia mensual día 31 cruzando febrero.
  dia31_id := public.create_recurring_rule('Día 31 test', 'expense', 'MXN', 50000, null,
    'monthly', 31, null, santander_id, null, '2019-12-31', null, null, 'p7a-rule-dia31');

  update recur_ids set santander = santander_id, usd_account = usd_id, bbva = bbva_id,
    renta = renta_id, netflix = netflix_id, nomina = nomina_id, gimnasio = gimnasio_id,
    seguro = seguro_id, semanal = semanal_id, dia31 = dia31_id;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS A/B: defining a rule never creates a financial_event/account_entry.
-- ---------------------------------------------------------------------

do $$
declare before_fe int; after_fe int; before_ae int; after_ae int;
begin
  select count(*) into before_fe from public.financial_events;
  select count(*) into before_ae from public.account_entries;
  perform public.create_recurring_rule('CASO AB temp', 'expense', 'MXN', 10000, null,
    'monthly', 5, null, (select santander from recur_ids), null, '2020-09-01', null, null, 'p7a-caso-ab-setup');
  select count(*) into after_fe from public.financial_events;
  select count(*) into after_ae from public.account_entries;
  if after_fe <> before_fe then raise exception 'CASO A: creating a rule created a financial_event'; end if;
  if after_ae <> before_ae then raise exception 'CASO A: creating a rule created an account_entry'; end if;
end;
$$;

do $$
declare before_fe int; after_fe int;
begin
  select count(*) into before_fe from public.financial_events;
  perform public.create_recurring_rule('CASO B income temp', 'income', 'MXN', 500000, null,
    'monthly', 5, null, (select santander from recur_ids), null, '2020-09-01', null, null, 'p7a-caso-b-setup');
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO B: creating an income rule created a financial_event'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO C: monthly day 31 clamps in February, returns to 31 in March.
-- ---------------------------------------------------------------------

do $$
declare occurrences jsonb; d date;
begin
  occurrences := public.get_recurring_occurrences('2021-01-01'::date, '2021-04-01'::date);
  select (elem->>'occurred_on')::date into strict d from jsonb_array_elements(occurrences) elem
    where (elem->>'rule_id')::uuid = (select dia31 from recur_ids) and (elem->>'occurred_on')::date < '2021-02-01';
  if d <> '2021-01-31' then raise exception 'CASO C: expected January 31, got %', d; end if;

  select (elem->>'occurred_on')::date into strict d from jsonb_array_elements(occurrences) elem
    where (elem->>'rule_id')::uuid = (select dia31 from recur_ids)
      and (elem->>'occurred_on')::date >= '2021-02-01' and (elem->>'occurred_on')::date < '2021-03-01';
  if d <> '2021-02-28' then raise exception 'CASO C: expected February 28 (2021 not leap), got %', d; end if;

  select (elem->>'occurred_on')::date into strict d from jsonb_array_elements(occurrences) elem
    where (elem->>'rule_id')::uuid = (select dia31 from recur_ids)
      and (elem->>'occurred_on')::date >= '2021-03-01' and (elem->>'occurred_on')::date < '2021-04-01';
  if d <> '2021-03-31' then raise exception 'CASO C: expected March to return to 31 (no permanent drift), got %', d; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS D/E: biweekly (14 días exactos) vs weekly vs semimonthly (dos
-- fechas de calendario, nunca 14 días).
-- ---------------------------------------------------------------------

do $$
declare occurrences jsonb; dates date[];
begin
  occurrences := public.get_recurring_occurrences('2020-08-01'::date, '2020-10-01'::date);

  select array_agg((elem->>'occurred_on')::date order by (elem->>'occurred_on')::date) into dates
  from jsonb_array_elements(occurrences) elem where (elem->>'rule_id')::uuid = (select gimnasio from recur_ids);
  if dates[2] - dates[1] <> 14 then raise exception 'CASO D: biweekly gap must be exactly 14 days, got %', dates[2] - dates[1]; end if;
  if dates[3] - dates[2] <> 14 then raise exception 'CASO D: biweekly gap must be exactly 14 days, got %', dates[3] - dates[2]; end if;

  select array_agg((elem->>'occurred_on')::date order by (elem->>'occurred_on')::date) into dates
  from jsonb_array_elements(occurrences) elem where (elem->>'rule_id')::uuid = (select semanal from recur_ids);
  if dates[2] - dates[1] <> 7 then raise exception 'CASO D: weekly gap must be exactly 7 days, got %', dates[2] - dates[1]; end if;

  -- CASO E: Nómina semimensual (15 y último día) -- gaps de 13-16 días,
  -- nunca uniformes de 14, y siempre 24 pagos al año (no 26).
  select array_agg((elem->>'occurred_on')::date order by (elem->>'occurred_on')::date) into dates
  from jsonb_array_elements(occurrences) elem where (elem->>'rule_id')::uuid = (select nomina from recur_ids);
  if dates[1] <> '2020-08-15' then raise exception 'CASO E: expected first Nómina on Aug 15, got %', dates[1]; end if;
  if dates[2] <> '2020-08-31' then raise exception 'CASO E: expected second Nómina on Aug 31 (último día), got %', dates[2]; end if;
  if dates[2] - dates[1] = 14 then raise exception 'CASO E: semimonthly must never behave like biweekly'; end if;
  if dates[3] <> '2020-09-15' then raise exception 'CASO E: expected third Nómina on Sep 15, got %', dates[3]; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS F/G/AN: pause does not create phantom debt, and does not erase
-- an occurrence already pending before the pause began.
-- ---------------------------------------------------------------------

do $$
declare before_occ jsonb; after_occ jsonb; found boolean; baseline_future_occ jsonb;
begin
  -- Renta's September (day 1) occurrence is already "pending" relative to
  -- our reference window before we pause anything.
  before_occ := public.get_recurring_occurrences('2020-09-01'::date, '2020-09-02'::date);
  if jsonb_array_length(before_occ) <> 1 then raise exception 'CASO AN setup: expected exactly one Renta candidate for Sep 1'; end if;
  baseline_future_occ := public.get_recurring_occurrences(current_date, current_date + 90);

  perform public.pause_recurring_rule((select renta from recur_ids), 'p7a-pause-renta');

  -- CASO AN: pausing today (current_date, safely after 2020-09-01 in this
  -- sandbox) must never retroactively erase the Sep 1 occurrence.
  after_occ := public.get_recurring_occurrences('2020-09-01'::date, '2020-09-02'::date);
  if jsonb_array_length(after_occ) <> 1 then
    raise exception 'CASO AN: pausing today erased an occurrence pending since before the pause'; end if;

  -- CASO F: the paused window itself derives nothing at all -- no phantom
  -- debt accumulates for the months while paused. pause_recurring_rule is
  -- always anchored at real current_date (never a caller-supplied date),
  -- so "the paused window" here is [current_date, resumed) -- the first
  -- future day itself must already be excluded.
  found := exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(current_date, current_date + 90)) elem
    where (elem->>'rule_id')::uuid = (select renta from recur_ids)
  );
  if found then raise exception 'CASO F: a paused rule must derive zero occurrences from today onward'; end if;

  perform public.resume_recurring_rule((select renta from recur_ids), 'p7a-resume-renta');

  -- CASO G: reactivating resumes derivation correctly. Because both pause
  -- and resume happened within this same test transaction (both anchored
  -- at the same real current_date), the paused interval is empty by
  -- construction -- the meaningful assertion is that this pause/resume
  -- round trip is a true no-op: the set of occurrences derivable for the
  -- same future window matches the baseline captured before pausing at
  -- all (no ghost gap, no ghost duplicate introduced by the round trip).
  if public.get_recurring_occurrences(current_date, current_date + 90) is distinct from baseline_future_occ then
    raise exception 'CASO G: an instantaneous pause/resume round trip must reproduce the pre-pause baseline exactly';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(current_date, current_date + 90)) elem
    where (elem->>'rule_id')::uuid = (select renta from recur_ids)
  ) then raise exception 'CASO G: resuming should let future occurrences derive again'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS I/J/K/M/N/S/T/AA/AI/AH/AZ: confirming and omitting against the
-- real engine.
-- ---------------------------------------------------------------------

do $$
declare
  before_fe int; after_fe int; new_event uuid;
  santander_id uuid := (select santander from recur_ids);
  before_closing bigint; after_closing bigint;
  plan jsonb; sept jsonb;
begin
  -- CASO AZ (parte 1): saldo proyectado de septiembre ANTES de confirmar Renta.
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into sept from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 1;
  before_closing := (sept->'base'->>'closing_minor')::bigint;
  if not exists (select 1 from jsonb_array_elements(sept->'planned_flows') f where (f->>'flow_id')::uuid = (select renta from recur_ids)) then
    raise exception 'CASO S setup: Renta should appear as an expected flow in September before confirming'; end if;

  -- CASO I: cuenta + gasto -> expense real.
  select count(*) into before_fe from public.financial_events;
  new_event := public.confirm_recurring_occurrence(
    (select renta from recur_ids), '2020-09-01'::date, 1200000, '2020-09-01'::date,
    null, null, null, 'p7a-confirm-renta-sep'
  );
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe + 1 then raise exception 'CASO I: confirming an account expense must create exactly one financial_event'; end if;
  if (select kind from public.financial_events fe
      join public.recurring_occurrence_events roe on roe.financial_event_id = fe.id
      where roe.occurrence_id = new_event) <> 'expense' then
    raise exception 'CASO I: confirmed account occurrence must produce kind=expense'; end if;

  -- CASO S: la occurrence confirmada desaparece de la expectativa.
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into sept from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 1;
  if exists (select 1 from jsonb_array_elements(sept->'planned_flows') f where (f->>'flow_id')::uuid = (select renta from recur_ids)) then
    raise exception 'CASO S: a confirmed occurrence must stop appearing as an expected flow'; end if;

  -- CASO AZ (parte 2): el saldo proyectado de septiembre NO cambia -- el
  -- gasto salió de "planeado futuro" y entró a "saldo inicial ya real" por
  -- el mismo monto exacto, nunca ambos ni ninguno.
  after_closing := (sept->'base'->>'closing_minor')::bigint;
  if after_closing <> before_closing then
    raise exception 'CASO AZ: confirming must not create an artificial jump in projected liquidity (before % after %)',
      before_closing, after_closing;
  end if;
end;
$$;

do $$
declare new_event uuid; found_card boolean := false;
  plan jsonb; october jsonb; september jsonb; line jsonb;
begin
  -- CASO J/T/AI: tarjeta + gasto -> card_charge real, entra al preview de
  -- octubre (corte 9-oct, vencimiento ~29-oct) y NO se resta además como
  -- flujo esperado de septiembre (donde estaba dated) una vez confirmado.
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into september from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 1;
  if not exists (select 1 from jsonb_array_elements(september->'planned_flows') f where (f->>'flow_id')::uuid = (select netflix from recur_ids)) then
    raise exception 'CASO T setup: Netflix should be an expected flow in September before confirming'; end if;

  new_event := public.confirm_recurring_occurrence(
    (select netflix from recur_ids), '2020-09-15'::date, 24900, '2020-09-15'::date,
    null, null, null, 'p7a-confirm-netflix-sep'
  );
  if (select kind from public.financial_events fe
      join public.recurring_occurrence_events roe on roe.financial_event_id = fe.id
      where roe.occurrence_id = new_event) <> 'card_charge' then
    raise exception 'CASO J: confirmed card occurrence must produce kind=card_charge'; end if;

  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into september from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 1;
  select m.month into october from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 2;

  if exists (select 1 from jsonb_array_elements(september->'planned_flows') f where (f->>'flow_id')::uuid = (select netflix from recur_ids)) then
    raise exception 'CASO T: a confirmed card occurrence must stop appearing as an expected flow'; end if;

  for line in select * from jsonb_array_elements(october->'card_obligations') loop
    if (line->>'card_id')::uuid = (select bbva from recur_ids) then found_card := true; end if;
  end loop;
  if not found_card then raise exception 'CASO AI: the confirmed card_charge must appear via October''s statement/preview obligation'; end if;
end;
$$;

do $$
declare new_event uuid;
begin
  -- CASO K: cuenta + ingreso -> income real.
  new_event := public.confirm_recurring_occurrence(
    (select nomina from recur_ids), '2020-08-15'::date, 3000000, '2020-08-15'::date,
    null, null, null, 'p7a-confirm-nomina-aug15'
  );
  if (select kind from public.financial_events fe
      join public.recurring_occurrence_events roe on roe.financial_event_id = fe.id
      where roe.occurrence_id = new_event) <> 'income' then
    raise exception 'CASO K: confirmed income occurrence must produce kind=income'; end if;
end;
$$;

do $$
declare new_event uuid; event_row public.recurring_occurrence_events%rowtype;
begin
  -- CASOS M/N: importe y fecha reales distintos de los esperados, ambos preservados.
  new_event := public.confirm_recurring_occurrence(
    (select gimnasio from recur_ids), '2020-08-03'::date, 75000, '2020-08-04'::date,
    null, null, null, 'p7a-confirm-gimnasio-1'
  );
  select * into event_row from public.recurring_occurrence_events where occurrence_id = new_event;
  if event_row.actual_amount_minor <> 75000 then raise exception 'CASO M: actual_amount_minor not preserved'; end if;
  if (select expected_amount_minor from public.recurring_occurrences where id = new_event) <> 70000 then
    raise exception 'CASO M: expected_amount_minor must stay the rule''s expected value, not the actual one'; end if;
  if event_row.actual_date <> '2020-08-04' then raise exception 'CASO N: actual_date not preserved'; end if;
  if (select expected_date from public.recurring_occurrences where id = new_event) <> '2020-08-03' then
    raise exception 'CASO N: expected_date must stay the calendar slot, not the actual date'; end if;
end;
$$;

-- CASO AA: an omitted occurrence never creates a financial_event.
do $$
declare before_fe int; after_fe int; occ_id uuid;
begin
  select count(*) into before_fe from public.financial_events;
  occ_id := public.omit_recurring_occurrence((select gimnasio from recur_ids), '2020-08-17'::date, 'saltado', 'p7a-omit-gimnasio-1');
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO AA: omitting must never create a financial_event'; end if;
  if (select status from public.recurring_occurrences where id = occ_id) <> 'omitted' then
    raise exception 'CASO AA: occurrence status must be omitted'; end if;
end;
$$;

-- CASO H: omitting one occurrence never affects the next.
do $$
declare occ jsonb;
begin
  occ := public.get_recurring_occurrences('2020-08-31'::date, '2020-09-01'::date);
  if not exists (
    select 1 from jsonb_array_elements(occ) elem where (elem->>'rule_id')::uuid = (select gimnasio from recur_ids)
  ) then raise exception 'CASO H: the occurrence after an omitted one must still derive normally'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO L: confirming the same occurrence twice never duplicates the
-- movement.
-- ---------------------------------------------------------------------

do $$
declare before_fe int; after_fe int;
begin
  select count(*) into before_fe from public.financial_events;
  begin
    perform public.confirm_recurring_occurrence(
      (select renta from recur_ids), '2020-09-01'::date, 1200000, '2020-09-01'::date,
      null, null, null, 'p7a-confirm-renta-sep-again'
    );
    raise exception 'CASO L: a second confirmation with a fresh idempotency key should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_OCCURRENCE_ALREADY_CONFIRMED' then raise; end if;
  end;
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO L: a rejected re-confirmation must never create a financial_event'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS O/P/Q: editing amount/day/source after a confirmation never
-- rewrites that confirmed occurrence's history.
-- ---------------------------------------------------------------------

-- Nota de diseño: update_recurring_rule's "guarda de vigencia" is anchored
-- at real current_date (a write, like close_card_statement's own
-- not-due check -- never p_as_of_date). The rest of this file is pinned to
-- 2020 for card-chronological reasons unrelated to this guard, so every
-- effective_from_date below is deliberately computed from current_date
-- instead of a fixed year, comfortably past whatever this rule's own
-- "last protected" occurrence resolves to on whatever real day this runs.

do $$
declare bbva_id uuid := (select bbva from recur_ids); safely_future_month date := date_trunc('month', current_date)::date + interval '2 months';
begin
  -- CASO O: editar el importe futuro no cambia el snapshot histórico de
  -- la ocurrencia de septiembre ya confirmada (inmune por construcción:
  -- nunca vuelve a leer la regla).
  perform public.update_recurring_rule(
    (select netflix from recur_ids), 'Netflix', null, safely_future_month,
    24900 + 3000, 'subscriptions', 'monthly', 15, null, null, bbva_id, 'p7a-update-netflix-amount'
  );
  if (select expected_amount_minor from public.recurring_occurrences
      where rule_id = (select netflix from recur_ids) and expected_date = '2020-09-15') <> 24900 then
    raise exception 'CASO O: editing amount must not rewrite a confirmed occurrence''s expected_amount_minor';
  end if;

  -- CASO P: editar el día futuro no cambia el historial (septiembre ya
  -- confirmado sigue en 15).
  perform public.update_recurring_rule(
    (select renta from recur_ids), 'Renta', null, safely_future_month,
    1200000, 'home', 'monthly', 5, null, (select santander from recur_ids), null, 'p7a-update-renta-day'
  );
  if (select expected_date from public.recurring_occurrences
      where rule_id = (select renta from recur_ids) and expected_date = '2020-09-01') <> '2020-09-01' then
    raise exception 'CASO P: editing the day must not move a confirmed occurrence''s expected_date'; end if;

  -- CASO Q: cambiar la fuente futura no cambia la fuente histórica ya
  -- confirmada (Netflix de septiembre debe seguir mostrando BBVA aunque
  -- la regla cambie de tarjeta después).
  if (select card_id from public.recurring_occurrence_events e
      join public.recurring_occurrences o on o.id = e.occurrence_id
      where o.rule_id = (select netflix from recur_ids) and o.expected_date = '2020-09-15') <> bbva_id then
    raise exception 'CASO Q: the historical card_id on a confirmed occurrence must remain BBVA';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AL/AM/AX: the "guarda de vigencia" prevents a version change from
-- erasing or duplicating an occurrence already pending (this month, real
-- current_date, unconfirmed), and confirming it later still uses the OLD
-- version's values.
-- ---------------------------------------------------------------------

do $$
declare
  rule_id uuid; this_month date := date_trunc('month', current_date)::date;
  next_month date := (this_month + interval '1 month')::date;
  new_event uuid; amt bigint;
begin
  rule_id := public.create_recurring_rule('CASO vigencia', 'expense', 'MXN', 100000, null,
    'monthly', 1, null, (select santander from recur_ids), null, (this_month - interval '3 months')::date,
    null, null, 'p7a-vigencia-create');

  -- CASO AL setup: this month's day-1 occurrence is derivable and
  -- unconfirmed -- genuinely pending, not immune-because-already-persisted.
  if not exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(this_month, this_month + 1)) elem
    where (elem->>'rule_id')::uuid = rule_id and (elem->>'existing_occurrence_id') is null
  ) then raise exception 'CASO AL setup: expected an unconfirmed pending occurrence this month'; end if;

  -- Edita día 1 -> día 10, vigente desde el mes siguiente (la guarda
  -- exige esto: el mes de la ocurrencia ya vencida queda protegido).
  perform public.update_recurring_rule(rule_id, 'CASO vigencia', null, next_month,
    100000, null, 'monthly', 10, null, (select santander from recur_ids), null, 'p7a-vigencia-update');

  -- CASO AL: la ocurrencia pendiente de este mes no desapareció.
  if not exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(this_month, this_month + 1)) elem
    where (elem->>'rule_id')::uuid = rule_id
  ) then raise exception 'CASO AL: editing day_of_month must not erase the already-pending occurrence of this month';
  end if;

  -- CASO AX: este mes nunca produce dos ocurrencias del mismo compromiso
  -- (ni día 1 duplicado con día 10) durante el mes de transición.
  if (
    select count(*) from jsonb_array_elements(public.get_recurring_occurrences(this_month, next_month)) elem
    where (elem->>'rule_id')::uuid = rule_id
  ) <> 1 then raise exception 'CASO AX: this month must derive exactly one occurrence, never two';
  end if;

  -- El mes siguiente debe usar el nuevo día 10, no el 1.
  if not exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(next_month + 9, next_month + 10)) elem
    where (elem->>'rule_id')::uuid = rule_id
  ) then raise exception 'CASO AT: next month onward must use the new day 10'; end if;
  if exists (
    select 1 from jsonb_array_elements(public.get_recurring_occurrences(next_month, next_month + 1)) elem
    where (elem->>'rule_id')::uuid = rule_id
  ) then raise exception 'CASO AT: next month must not also derive the old day 1'; end if;

  -- CASO AM: confirmar la ocurrencia pendiente de este mes (nacida bajo
  -- la regla vieja) usa $1,000 (la versión vigente en ese momento), nunca
  -- un importe editado después del vencimiento (aquí el importe no
  -- cambió, pero la versión resuelta debe ser explícitamente la vieja,
  -- no la nueva -- se prueba vía category_id, que sí cambiaría si la
  -- resolución usara la versión equivocada... en este caso ambas
  -- versiones comparten category_id=null, así que el importe basta como
  -- testigo porque ninguna edición posterior lo tocó; ver el bloque
  -- aislado siguiente para un cambio de importe real).
  new_event := public.confirm_recurring_occurrence(rule_id, this_month::date, 100000, this_month::date,
    null, null, null, 'p7a-vigencia-confirm');
  select expected_amount_minor into amt from public.recurring_occurrences where id = new_event;
  if amt <> 100000 then
    raise exception 'CASO AM: expected_amount_minor of a pending occurrence born under the old version must stay 100000, got %', amt;
  end if;
end;
$$;

-- CASO AM (aislado, con un cambio de importe real): confirmar una
-- ocurrencia vencida antes de editar usa el importe de la versión
-- vigente en ese momento, nunca el importe editado después del vencimiento.
do $$
declare
  rule_id uuid; this_month date := date_trunc('month', current_date)::date;
  next_month date := (this_month + interval '1 month')::date;
  new_event uuid; amt bigint;
begin
  rule_id := public.create_recurring_rule('CASO AM aislado', 'expense', 'MXN', 100000, null,
    'monthly', 1, null, (select santander from recur_ids), null, (this_month - interval '3 months')::date,
    null, null, 'p7a-caso-am-create');
  perform public.update_recurring_rule(rule_id, 'CASO AM aislado', null, next_month,
    250000, null, 'monthly', 1, null, (select santander from recur_ids), null, 'p7a-caso-am-update');
  new_event := public.confirm_recurring_occurrence(rule_id, this_month::date, 100000, this_month::date,
    null, null, null, 'p7a-caso-am-confirm');
  select expected_amount_minor into amt from public.recurring_occurrences where id = new_event;
  if amt <> 100000 then
    raise exception 'CASO AM: expected_amount_minor of a pending occurrence born under the old version must stay 100000, got %', amt;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO R: archiving a rule preserves every financial_event already
-- created through it.
-- ---------------------------------------------------------------------

do $$
declare before_fe int; after_fe int;
begin
  select count(*) into before_fe from public.financial_events;
  perform public.archive_recurring_rule((select gimnasio from recur_ids), 'p7a-archive-gimnasio');
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO R: archiving a rule must not touch financial_events'; end if;
  if not exists (select 1 from public.recurring_occurrences where rule_id = (select gimnasio from recur_ids)) then
    raise exception 'CASO R: archiving must not delete confirmed/omitted occurrences'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AO/AP: confirming with no default source, via an explicit
-- override, without ever silently touching the rule.
-- ---------------------------------------------------------------------

do $$
declare bbva_id uuid := (select bbva from recur_ids); new_event uuid; card_used uuid;
begin
  begin
    perform public.confirm_recurring_occurrence(
      (select seguro from recur_ids), '2020-08-15'::date, 800000, '2020-08-15'::date,
      null, null, null, 'p7a-confirm-seguro-no-source'
    );
    raise exception 'CASO AO setup: confirming with no source anywhere must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_HAS_NO_SOURCE' then raise; end if;
  end;

  new_event := public.confirm_recurring_occurrence(
    (select seguro from recur_ids), '2020-08-15'::date, 800000, '2020-08-15'::date,
    null, bbva_id, null, 'p7a-confirm-seguro-with-card'
  );
  if (select kind from public.financial_events fe
      join public.recurring_occurrence_events roe on roe.financial_event_id = fe.id
      where roe.occurrence_id = new_event) <> 'card_charge' then
    raise exception 'CASO AO: Seguro confirmed with an explicit card must create a real card_charge'; end if;

  select card_id into card_used from public.recurring_occurrence_events where occurrence_id = new_event;
  if card_used <> bbva_id then raise exception 'CASO AO: the occurrence must snapshot the explicitly chosen card'; end if;

  -- CASO AP: la regla de Seguro sigue sin fuente predeterminada.
  if exists (
    select 1 from public.recurring_rule_versions
    where rule_id = (select seguro from recur_ids) and (account_id is not null or card_id is not null)
  ) then raise exception 'CASO AP: choosing a source at confirm time must never modify the rule''s default source';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AQ/AR/AV/AW: reversal, replacement, and atomic first-confirmation
-- guarantees.
-- ---------------------------------------------------------------------

do $$
declare event_a uuid; event_b uuid; occ_id uuid; active_count int; before_fe int; after_fe int;
begin
  event_a := public.confirm_recurring_occurrence(
    (select nomina from recur_ids), '2020-08-31'::date, 3000000, '2020-08-31'::date,
    null, null, null, 'p7a-confirm-nomina-a'
  );
  occ_id := event_a;

  -- CASO AR: exactamente un evento activo tras la primera confirmación.
  select count(*) into active_count from public.recurring_occurrence_current_event where occurrence_id = occ_id;
  if active_count <> 1 then raise exception 'CASO AR: expected exactly one active event, got %', active_count; end if;

  -- Revertir el movimiento real desde Movimientos (motor existente).
  perform public.reverse_transaction(
    (select financial_event_id from public.recurring_occurrence_events where occurrence_id = occ_id),
    'p7a-reverse-nomina-a'
  );

  -- Con el único evento revertido, ya no hay ninguno activo.
  select count(*) into active_count from public.recurring_occurrence_current_event where occurrence_id = occ_id;
  if active_count <> 0 then raise exception 'CASO AQ: after reversal, zero events should be active, got %', active_count; end if;

  -- CASO AQ: reemplazo -- se permite reconfirmar, crea el evento B.
  event_b := public.confirm_recurring_occurrence(
    (select nomina from recur_ids), '2020-08-31'::date, 3000000, '2020-09-01'::date,
    null, null, null, 'p7a-confirm-nomina-b'
  );
  if event_b <> occ_id then raise exception 'CASO AQ: replacement must reuse the same occurrence id'; end if;
  if (select count(*) from public.recurring_occurrence_events where occurrence_id = occ_id) <> 2 then
    raise exception 'CASO AQ: both events A and B must remain in the append-only table'; end if;

  select count(*) into active_count from public.recurring_occurrence_current_event where occurrence_id = occ_id;
  if active_count <> 1 then raise exception 'CASO AR: exactly one active event after replacement, got %', active_count; end if;
  if (select financial_event_id from public.recurring_occurrence_current_event where occurrence_id = occ_id)
     = (select financial_event_id from public.recurring_occurrence_events where occurrence_id = occ_id order by created_at asc limit 1) then
    raise exception 'CASO AQ: the active event must be B, not the reversed A';
  end if;

  -- Reconfirmar con un evento vivo (B) debe rechazarse -- nunca dos activos.
  begin
    perform public.confirm_recurring_occurrence(
      (select nomina from recur_ids), '2020-08-31'::date, 3000000, '2020-09-02'::date,
      null, null, null, 'p7a-confirm-nomina-c'
    );
    raise exception 'CASO AR: confirming again while an event is still active must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_OCCURRENCE_ALREADY_CONFIRMED' then raise; end if;
  end;

  -- CASO AV: dos intentos de PRIMERA confirmación sobre un slot todavía
  -- sin fila -- el segundo debe fallar por el guard de dominio (bloqueado
  -- serialmente por el advisory lock, nunca por una condición de carrera
  -- resuelta después de crear dinero real).
  perform public.confirm_recurring_occurrence(
    (select nomina from recur_ids), '2020-09-15'::date, 3000000, '2020-09-15'::date,
    null, null, null, 'p7a-confirm-nomina-sep15-first'
  );
  select count(*) into before_fe from public.financial_events;
  begin
    perform public.confirm_recurring_occurrence(
      (select nomina from recur_ids), '2020-09-15'::date, 3000000, '2020-09-15'::date,
      null, null, null, 'p7a-confirm-nomina-sep15-second'
    );
    raise exception 'CASO AV: a second first-confirmation attempt on the same slot must be rejected';
  exception when others then
    if sqlerrm <> 'NEXO_OCCURRENCE_ALREADY_CONFIRMED' then raise; end if;
  end;
  select count(*) into after_fe from public.financial_events;
  if after_fe <> before_fe then raise exception 'CASO AV: the rejected second attempt must never create a financial_event'; end if;

  -- CASO AW: forzar un fallo real dentro de create_transaction (cuenta
  -- archivada) y confirmar que NINGUNA tabla queda con huérfanos --
  -- ninguna escritura de confirm_recurring_occurrence sobrevive cuando el
  -- motor financiero real falla, porque todo corre en una sola transacción.
  declare
    temp_account uuid; temp_rule uuid;
    before_counts record; after_counts record;
  begin
    temp_account := public.create_account('Cuenta para archivar', 'checking', 'MXN', 100000, null, null, 'p7a-aw-account');
    temp_rule := public.create_recurring_rule('CASO AW temp', 'expense', 'MXN', 10000, null,
      'monthly', 1, null, temp_account, null, '2020-09-01', null, null, 'p7a-aw-rule');
    perform public.archive_account(temp_account, 'p7a-aw-archive-account');

    select
      (select count(*) from public.financial_events) as fe,
      (select count(*) from public.account_entries) as ae,
      (select count(*) from public.recurring_occurrences) as ro,
      (select count(*) from public.recurring_occurrence_events) as roe
    into before_counts;

    begin
      perform public.confirm_recurring_occurrence(temp_rule, '2020-09-01'::date, 10000, '2020-09-01'::date,
        null, null, null, 'p7a-aw-confirm-fails');
      raise exception 'CASO AW: confirming against an archived account should have failed';
    exception when others then
      if sqlerrm <> 'NEXO_ACCOUNT_ARCHIVED' then raise; end if;
    end;

    select
      (select count(*) from public.financial_events) as fe,
      (select count(*) from public.account_entries) as ae,
      (select count(*) from public.recurring_occurrences) as ro,
      (select count(*) from public.recurring_occurrence_events) as roe
    into after_counts;

    if before_counts is distinct from after_counts then
      raise exception 'CASO AW: a failed confirmation left orphaned rows behind';
    end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AC/AD/AE: no over-materialization; deterministic derivation.
-- ---------------------------------------------------------------------

do $$
declare occ_count int; derived_count int;
begin
  -- CASO AC: a pesar de derivar 12 meses de varias reglas, solo las que
  -- de verdad se confirmaron/omitieron tienen fila.
  select count(*) into occ_count from public.recurring_occurrences;
  select count(*) into derived_count from jsonb_array_elements(
    public.get_recurring_occurrences(current_date, current_date + 365)
  );
  if occ_count > 40 then raise exception 'CASO AC: too many persisted occurrences for this scenario, got %', occ_count; end if;

  -- CASO AD: el próximo año se deriva de forma determinística sin
  -- depender de nada más que rango + estado de la regla.
  if derived_count < 1 then raise exception 'CASO AD: expected derivable occurrences over the next year'; end if;
end;
$$;

-- CASO AE: mismo estado + mismo p_as_of_date = mismo resultado.
do $$
declare plan1 jsonb; plan2 jsonb;
begin
  plan1 := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  plan2 := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  if plan1 <> plan2 then raise exception 'CASO AE: two calls with identical state and p_as_of_date produced different results'; end if;
end;
$$;

-- CASO AF: archiving never modifies balances.
do $$
declare before_balance bigint; after_balance bigint;
begin
  select balance_minor into before_balance from public.account_balances where id = (select santander from recur_ids);
  perform public.archive_recurring_rule((select semanal from recur_ids), 'p7a-archive-semanal');
  select balance_minor into after_balance from public.account_balances where id = (select santander from recur_ids);
  if before_balance <> after_balance then raise exception 'CASO AF: archiving a rule must never change any account balance'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO AG: planned_cash_flows rejects new recurring intentions --
-- structurally impossible to duplicate a recurring commitment across
-- both sources going forward.
-- ---------------------------------------------------------------------

do $$
begin
  begin
    perform public.create_planned_cash_flow('Intento monthly', 'MXN', -10000, null, 'monthly', '2020-09-01', null, 'p7a-caso-ag-reject');
    raise exception 'CASO AG: planned_cash_flows must reject monthly from Phase 7A onward';
  exception when others then
    if sqlerrm <> 'NEXO_PLANNED_CASH_FLOW_RECURRENCE_DEPRECATED' then raise; end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO U/V/AH: budget flexible before and after confirming a categorized
-- recurring expense -- never double-subtracted.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; sept jsonb; subs jsonb;
begin
  -- CASO U: antes de confirmar, Netflix ya consume el flexible de
  -- Suscripciones (esto se probó ya como parte del setup vía AJ/AK más
  -- abajo indirectamente, pero aquí se afirma explícitamente para
  -- septiembre antes de la confirmación de netflix ya ocurrida arriba --
  -- por eso se valida contra noviembre, un mes donde Netflix TODAVÍA no
  -- se ha confirmado).
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into sept from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 3; -- Nov
  select elem into subs from jsonb_array_elements(sept->'budgets') elem where elem->>'category_id' = 'subscriptions';
  if (subs->>'planned_categorized_minor')::bigint <> 24900 then
    raise exception 'CASO U: expected Netflix to consume 24900 of Suscripciones flexible before confirming, got %', subs->>'planned_categorized_minor';
  end if;
  if (subs->>'flexible_additional_minor')::bigint <> 75100 then
    raise exception 'CASO U: expected flexible_additional 75100 before confirming, got %', subs->>'flexible_additional_minor';
  end if;

  -- CASO V/AH: septiembre, donde Netflix YA se confirmó (bloque J/T
  -- arriba) -- gasto real entra a budget_period_spend, la expectativa
  -- desaparece, y el flexible se mantiene en 751, nunca 502.
  select m.month into sept from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 1;
  select elem into subs from jsonb_array_elements(sept->'budgets') elem where elem->>'category_id' = 'subscriptions';
  if (subs->>'spent_minor')::bigint <> 24900 then
    raise exception 'CASO V: expected real spend 24900 after confirming, got %', subs->>'spent_minor'; end if;
  if (subs->>'planned_categorized_minor')::bigint <> 0 then
    raise exception 'CASO V: expectation must be 0 once confirmed, got %', subs->>'planned_categorized_minor'; end if;
  if (subs->>'flexible_additional_minor')::bigint <> 75100 then
    raise exception 'CASO AH: expected flexible 75100 (never 50200 double-subtracted), got %', subs->>'flexible_additional_minor';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO W: recurring income feeds Planeación as an expected entrada.
-- ---------------------------------------------------------------------

do $$
declare plan jsonb; nov jsonb;
begin
  plan := public.get_financial_plan('MXN', '2020-08-20'::date, 6);
  select m.month into nov from jsonb_array_elements(plan->'months') m(month) where (m.month->>'month_index')::int = 3;
  if not exists (select 1 from jsonb_array_elements(nov->'planned_flows') f where (f->>'flow_id')::uuid = (select nomina from recur_ids)) then
    raise exception 'CASO W: Nómina (still unconfirmed in November) must appear as an expected income flow'; end if;
  if (nov->>'planned_income_total_minor')::bigint < 3000000 then
    raise exception 'CASO W: November planned income should reflect Nómina''s expected amount'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO X/Y: multimoneda.
-- ---------------------------------------------------------------------

do $$
declare mxn_plan jsonb; usd_plan jsonb;
begin
  mxn_plan := public.get_financial_plan('MXN', '2020-08-20'::date, 3);
  usd_plan := public.get_financial_plan('USD', '2020-08-20'::date, 3);
  if not exists (
    select 1 from jsonb_array_elements(mxn_plan->'months') m, jsonb_array_elements(m->'planned_flows') f
    where (f->>'flow_id')::uuid = (select nomina from recur_ids)
  ) then raise exception 'CASO X setup: Nómina should appear under MXN'; end if;
  if exists (
    select 1 from jsonb_array_elements(usd_plan->'months') m, jsonb_array_elements(m->'planned_flows') f
    where (f->>'flow_id')::uuid = (select nomina from recur_ids)
  ) then raise exception 'CASO X: a MXN recurring rule must never leak into the USD projection'; end if;
end;
$$;

do $$
begin
  begin
    perform public.create_recurring_rule('Fuente moneda distinta', 'expense', 'MXN', 10000, null,
      'monthly', 1, null, (select usd_account from recur_ids), null, '2020-09-01', null, null, 'p7a-caso-y-reject');
    raise exception 'CASO Y: a source with a mismatched currency should have been rejected';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_CURRENCY_MISMATCH' then raise; end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO Z: RLS -- user B cannot see/edit/pause/archive/omit/confirm user A's
-- rules or occurrences.
-- ---------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90400000-0000-4000-8000-000000000002', true);

do $$
declare rule_count int;
begin
  select count(*) into rule_count from public.recurring_rules;
  if rule_count <> 0 then raise exception 'CASO Z: user B can see user A recurring_rules'; end if;

  begin
    perform public.update_recurring_rule((select renta from recur_ids), 'Hackeado', null, '2020-12-01'::date,
      1, null, 'monthly', 1, null, null, null, 'p7a-z-update');
    raise exception 'CASO Z: user B was able to update user A''s rule';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_NOT_FOUND' then raise; end if;
  end;

  begin
    perform public.pause_recurring_rule((select renta from recur_ids), 'p7a-z-pause');
    raise exception 'CASO Z: user B was able to pause user A''s rule';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_NOT_FOUND' then raise; end if;
  end;

  begin
    perform public.archive_recurring_rule((select renta from recur_ids), 'p7a-z-archive');
    raise exception 'CASO Z: user B was able to archive user A''s rule';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_NOT_FOUND' then raise; end if;
  end;

  begin
    perform public.omit_recurring_occurrence((select renta from recur_ids), '2020-12-01'::date, null, 'p7a-z-omit');
    raise exception 'CASO Z: user B was able to omit against user A''s rule';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_NOT_FOUND' then raise; end if;
  end;

  begin
    perform public.confirm_recurring_occurrence((select renta from recur_ids), '2020-12-01'::date, 1, '2020-12-01'::date,
      null, null, null, 'p7a-z-confirm');
    raise exception 'CASO Z: user B was able to confirm against user A''s rule';
  exception when others then
    if sqlerrm <> 'NEXO_RECURRING_RULE_NOT_FOUND' then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '90400000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- CASOS AY: a pause and an effective version that cross each other still
-- produce a deterministic, non-duplicated calendar.
-- ---------------------------------------------------------------------

do $$
declare
  rule_id uuid; occ jsonb;
  this_month date := date_trunc('month', current_date)::date;
  next_month date := (this_month + interval '1 month')::date;
  month_after date := (this_month + interval '2 months')::date;
begin
  rule_id := public.create_recurring_rule('CASO AY', 'expense', 'MXN', 50000, null,
    'monthly', 10, null, (select santander from recur_ids), null, (this_month - interval '3 months')::date, null, null, 'p7a-ay-create');
  -- This month's occurrence (day 10) is already past-pending "today";
  -- pausing today cannot erase it (same guarantee as AN), and a later
  -- day-of-month edit (effective two months from now) cannot duplicate it.
  perform public.pause_recurring_rule(rule_id, 'p7a-ay-pause');
  perform public.resume_recurring_rule(rule_id, 'p7a-ay-resume');
  perform public.update_recurring_rule(rule_id, 'CASO AY', null, month_after,
    50000, null, 'monthly', 20, null, (select santander from recur_ids), null, 'p7a-ay-update');

  if (select count(*) from jsonb_array_elements(public.get_recurring_occurrences(this_month, next_month)) elem
      where (elem->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO AY: this month must still derive exactly one occurrence after pause+resume+later edit'; end if;
  if (select count(*) from jsonb_array_elements(public.get_recurring_occurrences(next_month, month_after)) elem
      where (elem->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO AY: next month must derive exactly one occurrence (old day 10, version still governs)'; end if;
  if (select count(*) from jsonb_array_elements(public.get_recurring_occurrences(month_after, (month_after + interval '1 month')::date)) elem
      where (elem->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO AY: the month after must derive exactly one occurrence (new day 20, no duplication)'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASOS AJ/AK/AU/BA/BG/BH: migration from planned_cash_flows monthly
-- rows -- exercised in full, against a genuinely raw 'monthly' row, in
-- supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql, run by
-- scripts/test-db.sh in the one-migration window where the CHECK
-- constraint below does not exist yet. Not repeated here: by the time
-- this file runs, that constraint is already in place, so a raw insert
-- attempt here would only prove CASO BF below, not the migration itself.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- CASO BF: no normal write path can create a new planned_cash_flow
-- monthly row -- the RPC layer already rejects it (CASO AG), and now the
-- schema itself makes it structurally impossible, for every writer,
-- including one bypassing the RPC entirely.
-- ---------------------------------------------------------------------

do $$
declare constraint_def text;
begin
  select pg_get_constraintdef(oid) into constraint_def
  from pg_constraint
  where conrelid = 'public.planned_cash_flows'::regclass and conname = 'planned_cash_flows_recurrence_valid';
  if constraint_def is null then
    raise exception 'CASO BF: the recurrence CHECK constraint is missing entirely'; end if;
  if constraint_def ilike '%monthly%' then
    raise exception 'CASO BF: the recurrence CHECK constraint must no longer mention monthly, got: %', constraint_def; end if;
  if constraint_def not ilike '%one_time%' then
    raise exception 'CASO BF: the recurrence CHECK constraint must still require one_time, got: %', constraint_def; end if;

end;
$$;

-- Prueba positiva, no solo de metadatos: un intento real de escribir
-- 'monthly' directamente en la tabla, con privilegios suficientes para
-- llegar hasta el CHECK (bypass tanto del RPC como del GRANT que ya
-- bloquea a `authenticated`), debe fallar por el CHECK en sí mismo, sin
-- importar qué rol lo intente.
reset role;
do $$
begin
  begin
    insert into public.planned_cash_flows (user_id, name, currency, amount_minor, recurrence, start_date)
    values ('90400000-0000-4000-8000-000000000001', 'CASO BF intento directo', 'MXN', -1000, 'monthly', current_date);
    raise exception 'CASO BF: a direct INSERT of a monthly row must be rejected by the schema itself';
  exception when check_violation then
    null; -- esperado
  end;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', '90400000-0000-4000-8000-000000000001', true);

-- ---------------------------------------------------------------------
-- CASO AU: la migración embebida en esta propia migración (ejecutada
-- automáticamente sobre una base de datos efímera y vacía) fue un no-op
-- seguro y auditable -- no hay filas monthly sin convertir en ningún
-- momento posterior a la migración.
-- ---------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from public.planned_cash_flows
    where recurrence = 'monthly' and archived_at is null
  ) then raise exception 'CASO AU: no unmigrated monthly row should ever remain unarchived after the migration function runs';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO BB: reproduces the exact scenario from the closing audit, letter
-- for letter -- monthly day 1, $12,000, pending; edited on day 5 to day
-- 10; the pending day-1 occurrence must survive unmoved, and day 10 must
-- NOT also appear in the same (transition) month.
-- ---------------------------------------------------------------------

do $$
declare
  rule_id uuid; this_month date := date_trunc('month', current_date)::date;
  next_month date := (this_month + interval '1 month')::date;
  occurrences_this_month jsonb; occurrences_next_month jsonb; only_row jsonb;
begin
  rule_id := public.create_recurring_rule('CASO BB Renta', 'expense', 'MXN', 1200000, 'home',
    'monthly', 1, null, (select santander from recur_ids), null, (this_month - interval '3 months')::date,
    null, null, 'p7a-bb-create');

  -- "1 sep: queda pendiente" (día de hoy relativo al mes actual).
  occurrences_this_month := public.get_recurring_occurrences(this_month, next_month);
  if (select count(*) from jsonb_array_elements(occurrences_this_month) e where (e->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO BB setup: expected exactly one pending occurrence this month before editing'; end if;

  -- "5 sep: usuario cambia futuros a día 10 y $13,000" (BC combina el
  -- cambio de importe; BB en sentido estricto solo cambia el día, pero
  -- probamos ambos a la vez porque el mismo update_recurring_rule los
  -- aplica juntos -- ver la aserción de importe más abajo para BC).
  perform public.update_recurring_rule(rule_id, 'CASO BB Renta', null, next_month,
    1300000, 'home', 'monthly', 10, null, (select santander from recur_ids), null, 'p7a-bb-update');

  -- "1 sep / $12,000 sigue pendiente" -- exactamente una fila, día 1, con
  -- el importe ANTIGUO (CASO BC).
  occurrences_this_month := public.get_recurring_occurrences(this_month, next_month);
  if (select count(*) from jsonb_array_elements(occurrences_this_month) e where (e->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO BB: this month must still derive exactly one occurrence after the edit, never two, never zero';
  end if;
  select e into only_row from jsonb_array_elements(occurrences_this_month) e where (e->>'rule_id')::uuid = rule_id;
  if extract(day from (only_row->>'occurred_on')::date) <> 1 then
    raise exception 'CASO BB: the surviving occurrence must stay on day 1, got day %', extract(day from (only_row->>'occurred_on')::date);
  end if;
  if (only_row->>'amount_minor')::bigint <> 1200000 then
    raise exception 'CASO BC: the pending occurrence must keep the OLD amount (1200000), got %', only_row->>'amount_minor';
  end if;

  -- "10 sep NO debe aparecer una segunda obligación" -- ya cubierto por
  -- el count()=1 de arriba, y explícitamente aquí también.
  if exists (
    select 1 from jsonb_array_elements(occurrences_this_month) e
    where (e->>'rule_id')::uuid = rule_id and extract(day from (e->>'occurred_on')::date) = 10
  ) then raise exception 'CASO BB: day 10 must never appear in the same transition month as the protected day 1'; end if;

  -- "10 oct / $13,000 es la primera bajo la nueva versión."
  occurrences_next_month := public.get_recurring_occurrences(next_month, (next_month + interval '1 month')::date);
  if (select count(*) from jsonb_array_elements(occurrences_next_month) e where (e->>'rule_id')::uuid = rule_id) <> 1 then
    raise exception 'CASO BB: next month must derive exactly one occurrence under the new version'; end if;
  select e into only_row from jsonb_array_elements(occurrences_next_month) e where (e->>'rule_id')::uuid = rule_id;
  if extract(day from (only_row->>'occurred_on')::date) <> 10 then
    raise exception 'CASO BB: next month must use the new day 10, got day %', extract(day from (only_row->>'occurred_on')::date); end if;
  if (only_row->>'amount_minor')::bigint <> 1300000 then
    raise exception 'CASO BC: next month must use the new amount (1300000), got %', only_row->>'amount_minor'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO BD: semimonthly with one of its two monthly dates already due --
-- a calendar edit must neither erase nor duplicate that pending date.
-- ---------------------------------------------------------------------

do $$
declare
  rule_id uuid; this_month date := date_trunc('month', current_date)::date;
  next_month date := (this_month + interval '1 month')::date;
  count_this_month int; count_next_month int;
begin
  -- day_of_month=1 is always already due by the time this runs (day 1 of
  -- the current month is always <= today); day_of_month_secondary=20
  -- may or may not be due yet depending on the real day -- irrelevant,
  -- the invariant under test only concerns the day-1 slot.
  rule_id := public.create_recurring_rule('CASO BD Nómina', 'income', 'MXN', 3000000, null,
    'semimonthly', 1, 20, (select santander from recur_ids), null, (this_month - interval '3 months')::date,
    null, null, 'p7a-bd-create');

  perform public.update_recurring_rule(rule_id, 'CASO BD Nómina', null, next_month,
    3000000, null, 'semimonthly', 5, 25, (select santander from recur_ids), null, 'p7a-bd-update');

  select count(*) into count_this_month from jsonb_array_elements(public.get_recurring_occurrences(this_month, next_month)) e
  where (e->>'rule_id')::uuid = rule_id and extract(day from (e->>'occurred_on')::date) = 1;
  if count_this_month <> 1 then raise exception 'CASO BD: the already-due day-1 occurrence must survive the edit, got % matches', count_this_month; end if;

  select count(*) into count_this_month from jsonb_array_elements(public.get_recurring_occurrences(this_month, next_month)) e
  where (e->>'rule_id')::uuid = rule_id and extract(day from (e->>'occurred_on')::date) = 5;
  if count_this_month <> 0 then raise exception 'CASO BD: the new day 5 must not also appear in the transition month'; end if;

  select count(*) into count_next_month from jsonb_array_elements(public.get_recurring_occurrences(next_month, (next_month + interval '1 month')::date)) e
  where (e->>'rule_id')::uuid = rule_id and extract(day from (e->>'occurred_on')::date) in (5, 25);
  if count_next_month <> 2 then raise exception 'CASO BD: next month must derive both new days (5 and 25), got %', count_next_month; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CASO BE: biweekly with a slot already due -- a new version must never
-- move that specific slot.
-- ---------------------------------------------------------------------

do $$
declare
  rule_id uuid; last_due_before_edit date; last_due_after_edit date;
begin
  rule_id := public.create_recurring_rule('CASO BE Gimnasio', 'expense', 'MXN', 70000, null,
    'biweekly', null, null, (select santander from recur_ids), null, (current_date - interval '60 days')::date,
    null, null, 'p7a-be-create');

  select max((e->>'occurred_on')::date) into last_due_before_edit
  from jsonb_array_elements(public.get_recurring_occurrences(current_date - 60, current_date + 1)) e
  where (e->>'rule_id')::uuid = rule_id;
  if last_due_before_edit is null or last_due_before_edit > current_date then
    raise exception 'CASO BE setup: expected an already-due biweekly slot'; end if;

  -- Editar el importe (sin tocar la cadencia) vigente desde justo después
  -- del slot ya vencido -- la guarda para weekly/biweekly exige una fecha
  -- estrictamente posterior a esa fecha exacta (no un redondeo a mes) Y
  -- nunca anterior a hoy; con cadencia de 14 días el slot ya vencido
  -- puede estar hasta 13 días en el pasado, así que se necesita el mayor
  -- de los dos límites.
  perform public.update_recurring_rule(rule_id, 'CASO BE Gimnasio', null, greatest(last_due_before_edit + 1, current_date),
    90000, null, 'biweekly', null, null, (select santander from recur_ids), null, 'p7a-be-update');

  select max((e->>'occurred_on')::date) into last_due_after_edit
  from jsonb_array_elements(public.get_recurring_occurrences(current_date - 60, current_date + 1)) e
  where (e->>'rule_id')::uuid = rule_id;
  if last_due_after_edit <> last_due_before_edit then
    raise exception 'CASO BE: editing after the fact must never move an already-due biweekly slot (was %, now %)',
      last_due_before_edit, last_due_after_edit;
  end if;
end;
$$;

rollback;

select 'recurring transactions: A-BA design cases and atomicity guarantees passed' as result;
