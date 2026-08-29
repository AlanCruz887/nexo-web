begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('5c5c5c5c-5c5c-4c5c-8c5c-5c5c5c5c5c5c', 'phase5b-a@example.test', '{"full_name":"Phase 5B A"}'),
  ('5d5d5d5d-5d5d-4d5d-8d5d-5d5d5d5d5d5d', 'phase5b-b@example.test', '{"full_name":"Phase 5B B"}');

create temporary table phase5b_ids (account_a uuid, card_a uuid, contact_a uuid, plan_a uuid, contact_b uuid);
insert into phase5b_ids default values;
grant select, update on phase5b_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '5c5c5c5c-5c5c-4c5c-8c5c-5c5c5c5c5c5c', true);

do $$
declare
  account_id uuid; card_id uuid; second_card uuid; carlos uuid; ana uuid;
  iphone_plan uuid; shared_plan uuid; rounding_plan uuid; historical_plan uuid;
  iphone_event uuid; shared_event uuid; payment_id uuid; period jsonb;
  current_period jsonb; repeated uuid; credit_id uuid;
begin
  account_id := public.create_account('Cobros', 'checking', 'MXN', 100000, null, null, '5b-account');
  card_id := public.create_credit_card('Joy', 'Banco', null, 'MXN', 10000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-08-01', 0, null, null, '5b-card-a');
  second_card := public.create_credit_card('Banamex', 'Banco', null, 'MXN', 10000000, 13, 21, null,
    'generic', 'current_bank_balance', '2026-08-01', 0, null, null, '5b-card-two');
  carlos := public.create_contact('Carlos', null, null, null, '5b-carlos');
  ana := public.create_contact('Ana', null, null, null, '5b-ana-a');

  iphone_plan := public.create_shared_installment_purchase(card_id, 2400000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '2400000')),
    12, 200000, 'iPhone', 'other_expense', '2026-08-15', null, null, '5b-iphone');
  select purchase_event_id into iphone_event from public.installment_plans where id = iphone_plan;
  if (select personal_amount_minor from public.financial_events where id = iphone_event) <> 0 then
    raise exception 'third-party MSI became personal expense'; end if;
  if (select used_balance_minor from public.card_summaries where id = card_id) <> 2400000 then
    raise exception 'shared MSI did not impact card principal exactly once'; end if;
  if (select outstanding_minor from public.receivable_balances where source_event_id = iphone_event) <> 2400000 then
    raise exception 'shared MSI total receivable is wrong'; end if;
  if (select sum(amount_minor) from public.receivable_due_items item
      join public.receivables receivable on receivable.id = item.receivable_id
      where receivable.source_event_id = iphone_event) <> 2400000 then
    raise exception 'installment due items duplicated or lost receivable principal'; end if;
  if (select amount_minor from public.receivable_due_items item
      join public.receivables receivable on receivable.id = item.receivable_id
      where receivable.source_event_id = iphone_event order by sequence_number limit 1) <> 200000 then
    raise exception 'first person installment is wrong'; end if;

  shared_plan := public.create_shared_installment_purchase(card_id, 2400000, 600000,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '1200000'),
      jsonb_build_object('contact_id', ana, 'amount_minor', '600000')),
    12, 200000, 'MacBook', 'other_expense', '2026-08-16', null, null, '5b-shared');
  select purchase_event_id into shared_event from public.installment_plans where id = shared_plan;
  if (select personal_amount_minor from public.financial_events where id = shared_event) <> 600000 then
    raise exception 'shared MSI personal amount is wrong'; end if;
  if (select sum(amount_minor) from public.receivable_due_items item
      join public.receivables receivable on receivable.id = item.receivable_id
      where receivable.source_event_id = shared_event and receivable.contact_id = carlos) <> 1200000 then
    raise exception 'Carlos MSI allocation is not exact'; end if;
  if (select amount_minor from public.receivable_due_items item
      join public.receivables receivable on receivable.id = item.receivable_id
      where receivable.source_event_id = shared_event and receivable.contact_id = carlos
      order by sequence_number limit 1) <> 100000 then
    raise exception 'Carlos monthly share is wrong'; end if;

  rounding_plan := public.create_shared_installment_purchase(second_card, 1000000, 300000,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '700000')),
    3, null, 'Redondeo', 'other_expense', '2026-08-15', null, null, '5b-rounding');
  if (select sum(item.amount_minor) from public.receivable_due_items item
      join public.installments installment on installment.id = item.installment_id
      join public.installment_plans plan on plan.id = installment.plan_id
      join public.receivables receivable on receivable.id = item.receivable_id
      where plan.id = rounding_plan and receivable.contact_id = carlos) <> 700000 then
    raise exception 'rounding lost cents in person allocation'; end if;
  if (select sum(principal_minor) from public.installments where plan_id = rounding_plan) <> 1000000 then
    raise exception 'rounding lost cents in MSI principal'; end if;

  period := public.get_person_collection_period(carlos, '2026-08-28');
  select value into current_period from jsonb_array_elements(period->'periods') value
    where value->>'currency' = 'MXN';
  if current_period is null or (current_period->>'remaining_minor')::bigint <= 0 then
    raise exception 'collection period did not expose current obligations'; end if;
  if (current_period->>'payment_due_date')::date <> '2026-10-04' then
    raise exception 'consolidated due date did not use the latest relevant card due date'; end if;
  if not exists (
    select 1 from jsonb_array_elements(current_period->'concepts') concept
    where (concept->>'installment_count')::int = 12
  ) then raise exception 'period concept is missing its installment term'; end if;
  if coalesce((current_period->>'overdue_minor')::bigint, 0) <> 0 then
    raise exception 'nothing should be overdue yet at the as-of date used for the current period'; end if;
  period := public.get_person_collection_period(carlos, '2027-06-01');
  select value into current_period from jsonb_array_elements(period->'periods') value
    where value->>'currency' = 'MXN';
  if (current_period->>'overdue_minor')::bigint <= 0 then
    raise exception 'far-future as-of date did not surface overdue MSI installments'; end if;
  if (current_period->>'overdue_minor')::bigint > (current_period->>'remaining_minor')::bigint then
    raise exception 'overdue amount cannot exceed what remains for the period'; end if;

  payment_id := public.create_person_payment(carlos, account_id, 100000, '2026-08-28', null, '5b-partial');
  repeated := public.create_person_payment(carlos, account_id, 100000, '2026-08-28', null, '5b-partial');
  if repeated <> payment_id then raise exception 'person payment idempotency failed'; end if;
  if (select personal_amount_minor from public.financial_events where id = payment_id) <> 0 then
    raise exception 'person payment became income'; end if;
  if (select used_balance_minor from public.card_summaries where id = card_id) <> 4800000 then
    raise exception 'person payment incorrectly changed card balance'; end if;

  perform public.create_person_payment(carlos, account_id, 5000000, '2026-08-29', null, '5b-overpay');
  if not exists (select 1 from public.person_credit_balances
      where contact_id = carlos and currency = 'MXN' and credit_balance_minor > 0) then
    raise exception 'overpayment did not create credit'; end if;

  perform public.create_shared_account_purchase(account_id, 100000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '100000')),
    'Compra posterior', 'food', '2026-08-30', null, '5b-credit-obligation');
  credit_id := public.apply_person_credit(carlos, 'MXN', 100000, '5b-apply-credit');
  repeated := public.apply_person_credit(carlos, 'MXN', 100000, '5b-apply-credit');
  if repeated <> credit_id then raise exception 'credit application idempotency failed'; end if;
  if exists (select 1 from public.account_entries where financial_event_id = credit_id) then
    raise exception 'credit application created a second bank movement'; end if;
  if not exists (select 1 from public.contact_activity
      where event_id = credit_id and contact_id = carlos and activity_type = 'credit_applied'
        and amount_minor = -100000 and description = 'Compra posterior') then
    raise exception 'credit application is missing from the person activity feed'; end if;
  if exists (select 1 from public.contact_activity where event_id = credit_id and activity_type <> 'credit_applied') then
    raise exception 'credit application leaked into the activity feed as a bank movement'; end if;
  if not exists (select 1 from public.contact_activity
      where event_id = iphone_event and contact_id = carlos
        and personal_amount_minor = 0 and installment_count = 12) then
    raise exception 'the MSI purchase fully assigned to Carlos is missing its activity label data'; end if;
  if not exists (select 1 from public.contact_activity
      where event_id = shared_event and contact_id = carlos
        and personal_amount_minor = 600000 and installment_count = 12) then
    raise exception 'a shared MSI purchase is missing its activity label data'; end if;

  historical_plan := public.import_shared_historical_installment_plan(card_id, 'MSI histórico',
    2400000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '1600000')),
    12, 200000, '2026-04-01', 5, 4, 800000, 800000, '2026-09-09',
    'other_expense', null, true, '5b-historical');
  if (select sum(receivable.original_amount_minor) from public.receivables receivable
      join public.installment_plans plan on plan.purchase_event_id = receivable.source_event_id
      where plan.id = historical_plan and receivable.contact_id = carlos) <> 1600000 then
    raise exception 'historical MSI recreated paid-before-Nexo debt'; end if;
  if (select min(item.sequence_number) from public.receivable_due_items item
      join public.receivables receivable on receivable.id = item.receivable_id
      join public.installment_plans plan on plan.purchase_event_id = receivable.source_event_id
      where plan.id = historical_plan) <> 5 then
    raise exception 'historical MSI scheduled paid installments again'; end if;

  update phase5b_ids set account_a = account_id, card_a = card_id,
    contact_a = carlos, plan_a = iphone_plan;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '5d5d5d5d-5d5d-4d5d-8d5d-5d5d5d5d5d5d', true);
do $$ declare contact_id uuid; begin
  contact_id := public.create_contact('Persona B', null, null, null, '5b-person-b');
  update phase5b_ids set contact_b = contact_id;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '5c5c5c5c-5c5c-4c5c-8c5c-5c5c5c5c5c5c', true);
do $$
declare ids phase5b_ids%rowtype; failed boolean := false;
begin
  select * into ids from phase5b_ids;
  if exists (select 1 from public.receivable_due_items where user_id = '5d5d5d5d-5d5d-4d5d-8d5d-5d5d5d5d5d5d') then
    raise exception 'RLS exposed user B due items'; end if;
  begin perform public.get_person_collection_period(ids.contact_b, current_date);
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A exported/read user B collection period'; end if;
  failed := false;
  begin perform public.apply_person_credit(ids.contact_b, 'MXN', 1, '5b-attack-credit');
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A applied credit to user B'; end if;
  failed := false;
  begin perform public.record_person_statement_export(ids.contact_b, current_date, current_date,
    'pdf', '5b-attack-export'); exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A exported user B statement'; end if;
end;
$$;

reset role;
rollback;
select 'people MSI, periods, partial/advance payments, credit, idempotency and RLS tests passed' as result;
