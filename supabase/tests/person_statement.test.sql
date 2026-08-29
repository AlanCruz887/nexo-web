begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('6c6c6c6c-6c6c-4c6c-8c6c-6c6c6c6c6c6c', 'phase5c-a@example.test', '{"full_name":"Phase 5C A"}'),
  ('6d6d6d6d-6d6d-4d6d-8d6d-6d6d6d6d6d6d', 'phase5c-b@example.test', '{"full_name":"Phase 5C B"}');

create temporary table phase5c_ids (contact_no_debt uuid);
insert into phase5c_ids default values;
grant select, update on phase5c_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '6c6c6c6c-6c6c-4c6c-8c6c-6c6c6c6c6c6c', true);

do $$
declare
  account_id uuid; usd_account uuid; card_id uuid; carlos uuid; empty_contact uuid;
  plan_id uuid; purchase_event uuid; statement jsonb; mxn_period jsonb;
  payment_a uuid; payment_b uuid; payment_c uuid; payment_d uuid;
  first_concept jsonb; remaining_before_c bigint; total_before_d bigint;
  applied_period bigint; applied_future bigint; credit_generated bigint; payment_row jsonb;
begin
  account_id := public.create_account('Cobros', 'checking', 'MXN', 0, null, null, '5c-account-mxn');
  usd_account := public.create_account('Dolares', 'checking', 'USD', 0, null, null, '5c-account-usd');
  card_id := public.create_credit_card('Tarjeta', 'Banco', null, 'MXN', 20000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-08-01', 0, null, null, '5c-card-001');
  carlos := public.create_contact('Carlos', null, null, null, '5c-carlos');
  empty_contact := public.create_contact('Ana sin deuda', null, null, null, '5c-ana-empty');
  update phase5c_ids set contact_no_debt = empty_contact;

  -- CASO A: MSI compartido $12,000, mi parte $4,000, Carlos $8,000, 12 meses.
  plan_id := public.create_shared_installment_purchase(card_id, 1200000, 400000,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '800000')),
    12, 100000, 'MacBook Pro', 'other_expense', '2026-08-15', null, null, '5c-msi-001');
  select purchase_event_id into purchase_event from public.installment_plans where id = plan_id;
  if (select used_balance_minor from public.card_summaries where id = card_id) <> 1200000 then
    raise exception 'card should be impacted by the full principal exactly once'; end if;
  if (select personal_amount_minor from public.financial_events where id = purchase_event) <> 400000 then
    raise exception 'my personal expense should be exactly my share'; end if;
  if (select outstanding_minor from public.receivable_balances where contact_id = carlos) <> 800000 then
    raise exception 'Carlos should owe exactly his share, not the full purchase'; end if;

  statement := public.get_person_statement(carlos, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if mxn_period is null then raise exception 'statement is missing the MXN period'; end if;
  select value into first_concept from jsonb_array_elements(mxn_period->'concepts') value order by value->>'payment_due_date' limit 1;
  if (first_concept->>'installment_number')::int <> 1 or (first_concept->>'installment_count')::int <> 12 then
    raise exception 'statement concept should show Carlos share as installment 1 of 12'; end if;
  if (first_concept->>'amount_minor')::bigint <> 66667 then
    raise exception 'Carlos monthly share should be his proportional cut, not the full $1,000 installment'; end if;
  if (first_concept->>'purchase_amount_minor')::bigint <> 1200000 then
    raise exception 'statement should also expose the full purchase total alongside Carlos share'; end if;
  if (statement->'payments') <> '[]'::jsonb then raise exception 'no payments should exist yet'; end if;

  -- CASO B: pago parcial de $300.
  payment_a := public.create_person_payment(carlos, account_id, 30000, '2026-08-29', null, '5c-pay-300');
  statement := public.get_person_statement(carlos, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if (mxn_period->>'paid_minor')::bigint <> 30000 then raise exception 'paid this period should be exactly $300'; end if;
  if (mxn_period->>'remaining_minor')::bigint <> 36667 then raise exception 'missing this period should be $366.67'; end if;
  if (mxn_period->>'total_outstanding_minor')::bigint <> 770000 then raise exception 'total debt should drop by exactly $300'; end if;
  if exists (select 1 from public.financial_events where kind = 'income' and id = payment_a) then
    raise exception 'a person payment must never be income'; end if;
  select value into payment_row from jsonb_array_elements(statement->'payments') value where (value->>'event_id')::uuid = payment_a;
  if payment_row is null then raise exception 'the $300 payment is missing from the statement payments list'; end if;
  if (payment_row->>'applied_to_period_minor')::bigint <> 30000 then raise exception 'the $300 payment should be fully applied to this period'; end if;
  if (payment_row->>'applied_to_future_minor')::bigint <> 0 or (payment_row->>'credit_generated_minor')::bigint <> 0 then
    raise exception 'a plain partial payment should not advance the future or create credit'; end if;
  if payment_row->>'account_name' <> 'Cobros' then raise exception 'statement payment should show the receiving account name'; end if;

  -- CASO C: adelanto — paga $1,000 cuando el periodo debia $366.67 y aun hay MSI futuro pendiente.
  remaining_before_c := (mxn_period->>'remaining_minor')::bigint;
  payment_b := public.create_person_payment(carlos, account_id, 100000, '2026-08-30', null, '5c-pay-1000');
  statement := public.get_person_statement(carlos, '2026-08-28');
  select value into payment_row from jsonb_array_elements(statement->'payments') value where (value->>'event_id')::uuid = payment_b;
  applied_period := (payment_row->>'applied_to_period_minor')::bigint;
  applied_future := (payment_row->>'applied_to_future_minor')::bigint;
  credit_generated := (payment_row->>'credit_generated_minor')::bigint;
  if applied_period + applied_future + credit_generated <> 100000 then
    raise exception 'the payment breakdown must add up to exactly what was paid'; end if;
  if applied_period <> remaining_before_c then
    raise exception 'the overpayment should close exactly what was left of the period, no more no less'; end if;
  if credit_generated <> 0 then
    raise exception 'an overpayment must advance future MSI installments before ever becoming credit'; end if;
  if applied_future <= 0 then raise exception 'the excess over the period should be visible as advanced to future obligations'; end if;

  -- CASO D: saldo a favor real — se paga toda la deuda restante mas un excedente exacto.
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  total_before_d := (mxn_period->>'total_outstanding_minor')::bigint;
  payment_c := public.create_person_payment(carlos, account_id, total_before_d + 50000, '2026-08-31', null, '5c-pay-payoff');
  statement := public.get_person_statement(carlos, '2026-08-28');
  select value into mxn_period from jsonb_array_elements(statement->'periods') value where value->>'currency' = 'MXN';
  if (mxn_period->>'total_outstanding_minor')::bigint <> 0 then raise exception 'Carlos should owe exactly $0 after paying everything'; end if;
  if (mxn_period->>'credit_balance_minor')::bigint <> 50000 then raise exception 'the exact excess should become saldo a favor'; end if;
  if (mxn_period->>'total_outstanding_minor')::bigint < 0 then raise exception 'debt must never render negative when there is a credit'; end if;
  select value into payment_row from jsonb_array_elements(statement->'payments') value where (value->>'event_id')::uuid = payment_c;
  if (payment_row->>'credit_generated_minor')::bigint <> 50000 then
    raise exception 'the payoff payment should report the exact credit it generated'; end if;

  -- CASO E: segunda moneda, nunca mezclada.
  perform public.create_shared_account_purchase(usd_account, 10000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '10000')),
    'Suscripción', 'other_expense', '2026-08-29', null, '5c-usd-purchase');
  statement := public.get_person_statement(carlos, '2026-08-28');
  if (select count(*) from jsonb_array_elements(statement->'periods')) <> 2 then
    raise exception 'a person with debt in two currencies should show two separate period blocks'; end if;
  if not exists (select 1 from jsonb_array_elements(statement->'periods') value
      where value->>'currency' = 'USD' and (value->>'total_outstanding_minor')::bigint = 10000) then
    raise exception 'the USD block should show exactly the USD debt, untouched by MXN'; end if;
  if not exists (select 1 from jsonb_array_elements(statement->'periods') value
      where value->>'currency' = 'MXN' and (value->>'total_outstanding_minor')::bigint = 0) then
    raise exception 'the MXN block must not be affected by the new USD purchase'; end if;

  -- CASO F: persona sin deuda debe poder abrirse sin error.
  statement := public.get_person_statement(empty_contact, '2026-08-28');
  if statement->'periods' <> '[]'::jsonb then raise exception 'a contact with no debt should have no periods'; end if;
  if statement->'payments' <> '[]'::jsonb then raise exception 'a contact with no debt should have no payments'; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '6d6d6d6d-6d6d-4d6d-8d6d-6d6d6d6d6d6d', true);
do $$
declare ids phase5c_ids%rowtype; failed boolean := false; contact_id uuid;
begin
  select * into ids from phase5c_ids;
  contact_id := public.create_contact('Persona B', null, null, null, '5c-person-b');
  begin perform public.get_person_statement(ids.contact_no_debt, current_date);
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user B read user A statement through get_person_statement'; end if;
end;
$$;

reset role;
rollback;
select 'person statement consolidation, payments breakdown, credit and RLS tests passed' as result;
