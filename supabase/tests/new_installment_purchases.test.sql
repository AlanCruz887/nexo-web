begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('41414141-4141-4141-4141-414141414141', 'msi-a@example.test', '{"full_name":"MSI A"}'),
  ('42424242-4242-4242-4242-424242424242', 'msi-b@example.test', '{"full_name":"MSI B"}');

create temporary table phase4a_ids (
  account_a uuid,
  card_a uuid,
  card_b uuid,
  plan_a uuid,
  plan_b uuid,
  purchase_a uuid
);
insert into phase4a_ids default values;
grant select, update on phase4a_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '41414141-4141-4141-4141-414141414141', true);

do $$
declare
  v_account_a uuid;
  v_card_a uuid;
  v_plan_a uuid;
  repeated_plan uuid;
  v_purchase_a uuid;
  july_statement uuid;
begin
  v_account_a := public.create_account(
    'Cuenta MSI', 'checking', 'MXN', 2000000, null, null, 'phase4a-account-a'
  );
  v_card_a := public.create_credit_card(
    'Tarjeta MSI', 'Nexo Bank', null, 'MXN', 4000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-01', 500000, null, null, 'phase4a-card-a'
  );

  v_plan_a := public.create_installment_purchase(
    v_card_a, 1200000, 12, null, 'Laptop', 'technology', '2026-07-08',
    'online', 'Compra a 12 MSI', 'phase4a-plan-a'
  );
  repeated_plan := public.create_installment_purchase(
    v_card_a, 1200000, 12, null, 'Laptop', 'technology', '2026-07-08',
    'online', 'Compra a 12 MSI', 'phase4a-plan-a'
  );
  if repeated_plan <> v_plan_a then raise exception 'MSI idempotency failed'; end if;

  select purchase_event_id into v_purchase_a from public.installment_plans where id = v_plan_a;
  if (select used_balance_minor from public.card_summaries where id = v_card_a) <> 1700000
    or (select available_credit_minor from public.card_summaries where id = v_card_a) <> 2300000 then
    raise exception 'MSI purchase did not impact used balance exactly once';
  end if;
  if (select personal_amount_minor from public.financial_events where id = v_purchase_a) <> 1200000 then
    raise exception 'MSI purchase did not recognize full personal expense once';
  end if;
  if (select count(*) from public.card_entries where financial_event_id = v_purchase_a) <> 1
    or (select sum(amount_minor) from public.card_entries where financial_event_id = v_purchase_a) <> 1200000 then
    raise exception 'MSI purchase created duplicate card principal entries';
  end if;
  if (select count(*) from public.installments where plan_id = v_plan_a) <> 12
    or (select sum(principal_minor) from public.installments where plan_id = v_plan_a) <> 1200000 then
    raise exception 'MSI schedule does not close exact principal';
  end if;
  if (select first_statement_date from public.installment_plans where id = v_plan_a) <> date '2026-07-09'
    or (select due_statement_date from public.installments where plan_id = v_plan_a and installment_number = 1) <> date '2026-07-09' then
    raise exception 'purchase before cut was not assigned to first containing statement';
  end if;
  if (select card_statement_preview_balance(v_card_a, '2026-07-09')) <> 600000 then
    raise exception 'statement preview used full MSI principal instead of first installment';
  end if;
  if (select count(*) from public.card_statement_activity_segments where card_id = v_card_a and segment_kind = 'purchase') <> 0
    or (select sum(amount_minor) from public.card_statement_activity_segments
        where card_id = v_card_a and segment_kind = 'installment' and group_statement_date = '2026-07-09') <> 100000 then
    raise exception 'statement activity duplicated MSI principal or omitted installment';
  end if;

  july_statement := public.close_card_statement(v_card_a, '2026-07-09', null, null, 'phase4a-close-july');
  if (select statement_balance_minor from public.card_statements where id = july_statement) <> 600000 then
    raise exception 'closed statement did not contain baseline plus one installment';
  end if;
  if (select paid_count from public.installment_plan_summaries where id = v_plan_a) <> 0 then
    raise exception 'installment progress advanced from date instead of actual statement payment';
  end if;
  perform public.create_card_payment(v_card_a, v_account_a, 500000, '2026-07-10', null, 'phase4a-pay-july-partial');
  if (select remaining_due_minor from public.card_statements where id = july_statement) <> 100000
    or (select paid_count from public.installment_plan_summaries where id = v_plan_a) <> 0
    or (select effective_status from public.installment_schedule where plan_id = v_plan_a and installment_number = 1) <> 'pending' then
    raise exception 'partial statement payment incorrectly marked MSI installment as paid';
  end if;
  perform public.create_card_payment(v_card_a, v_account_a, 100000, '2026-07-11', null, 'phase4a-pay-july-rest');
  if (select paid_count from public.installment_plan_summaries where id = v_plan_a) <> 1
    or (select remaining_principal_minor from public.installment_plan_summaries where id = v_plan_a) <> 1100000 then
    raise exception 'paid statement did not advance MSI progress and remaining principal';
  end if;

  perform public.update_installment_plan_metadata(
    v_plan_a, 'Laptop trabajo', 'technology', 'Descripción corregida', 'phase4a-edit-meta'
  );
  if (select description from public.installment_plan_summaries where id = v_plan_a) <> 'Laptop trabajo' then
    raise exception 'metadata revision was not projected';
  end if;

  update phase4a_ids
  set account_a = v_account_a, card_a = v_card_a, plan_a = v_plan_a, purchase_a = v_purchase_a;
end;
$$;

-- Acceptance regression: closing and paying the first MacBook installment advances
-- the plan without charging the second installment to the card again.
do $$
declare
  macbook_account uuid;
  macbook_card uuid;
  macbook_plan uuid;
  september_statement uuid;
begin
  macbook_account := public.create_account(
    'Cuenta MacBook', 'checking', 'MXN', 200000, null, null, 'phase4a-macbook-account'
  );
  macbook_card := public.create_credit_card(
    'Tarjeta MacBook', 'Nexo Bank', null, 'MXN', 2000000, 9, 20, null, 'generic',
    'current_bank_balance', '2025-09-01', 0, null, null, 'phase4a-macbook-card'
  );
  macbook_plan := public.create_installment_purchase(
    macbook_card, 1200000, 12, 100000, 'MacBook', 'technology', '2025-09-08',
    'online', 'Aceptación primera mensualidad', 'phase4a-macbook-plan'
  );

  if public.card_statement_preview_balance(macbook_card, '2025-09-09') <> 100000 then
    raise exception 'MacBook Sep 09 statement was not exactly the first 1000 installment';
  end if;
  if (select used_balance_minor from public.card_summaries where id = macbook_card) <> 1200000
    or (select paid_count from public.installment_plan_summaries where id = macbook_plan) <> 0 then
    raise exception 'MacBook initial principal or 0/12 progress is incorrect';
  end if;

  september_statement := public.close_card_statement(
    macbook_card, '2025-09-09', null, null, 'phase4a-macbook-close-september'
  );
  if (select statement_balance_minor from public.card_statements where id = september_statement) <> 100000
    or (select count(*) from public.card_entries where card_id = macbook_card) <> 1 then
    raise exception 'closing the Sep 09 statement changed principal or statement amount';
  end if;

  perform public.create_card_payment(
    macbook_card, macbook_account, 100000, '2025-09-10', null, 'phase4a-macbook-pay-september'
  );
  if (select remaining_due_minor from public.card_statements where id = september_statement) <> 0
    or (select paid_count from public.installment_plan_summaries where id = macbook_plan) <> 1
    or (select remaining_principal_minor from public.installment_plan_summaries where id = macbook_plan) <> 1100000
    or (select current_installment_number from public.installment_plan_summaries where id = macbook_plan) <> 2
    or (select next_statement_date from public.installment_plan_summaries where id = macbook_plan) <> date '2025-10-09' then
    raise exception 'paying Sep 09 did not advance MacBook from 0/12 to 1/12 correctly';
  end if;
  if (select used_balance_minor from public.card_summaries where id = macbook_card) <> 1100000
    or (select available_credit_minor from public.card_summaries where id = macbook_card) <> 900000
    or (select sum(amount_minor) from public.card_entries where card_id = macbook_card) <> 1100000
    or (select count(*) from public.card_entries where card_id = macbook_card) <> 2 then
    raise exception 'second MacBook installment duplicated card principal after first payment';
  end if;
end;
$$;

do $$
declare
  rounding_card uuid;
  rounding_plan uuid;
  cut_plan uuid;
  reversal_plan uuid;
  reversal_event uuid;
  failed boolean;
begin
  rounding_card := public.create_credit_card(
    'Redondeo MSI', 'Nexo Bank', null, 'MXN', 2000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-01', 0, null, null, 'phase4a-round-card'
  );
  rounding_plan := public.create_installment_purchase(
    rounding_card, 1000000, 3, null, 'Compra dividida', 'other_expense', '2026-07-08',
    null, null, 'phase4a-round-plan'
  );
  if (select principal_minor from public.installments where plan_id = rounding_plan and installment_number = 1) <> 333333
    or (select principal_minor from public.installments where plan_id = rounding_plan and installment_number = 2) <> 333333
    or (select principal_minor from public.installments where plan_id = rounding_plan and installment_number = 3) <> 333334 then
    raise exception 'last installment did not absorb rounding remainder';
  end if;

  cut_plan := public.create_installment_purchase(
    rounding_card, 600000, 6, 100000, 'Compra en corte', 'other_expense', '2026-07-09',
    null, null, 'phase4a-cut-plan'
  );
  if (select first_statement_date from public.installment_plans where id = cut_plan) <> date '2026-08-09' then
    raise exception 'MSI purchase on cut day did not move to next statement';
  end if;

  reversal_plan := public.create_installment_purchase(
    rounding_card, 120000, 12, 10000, 'Plan reversible', 'other_expense', '2026-08-10',
    null, null, 'phase4a-reverse-plan'
  );
  failed := false;
  begin
    perform public.reverse_card_purchase(
      (select purchase_event_id from public.installment_plans where id = reversal_plan),
      'phase4a-generic-reverse'
    );
  exception when check_violation then failed := true;
  end;
  if not failed then raise exception 'generic purchase reversal bypassed MSI reversal'; end if;

  failed := false;
  begin
    perform public.create_card_refund(
      rounding_card, 1000, 'Refund MSI', null, '2026-08-11',
      (select purchase_event_id from public.installment_plans where id = reversal_plan),
      null, 'phase4a-msi-refund'
    );
  exception when check_violation then failed := true;
  end;
  if not failed then raise exception 'linked MSI refund was accepted'; end if;

  reversal_event := public.reverse_installment_purchase(reversal_plan, 'phase4a-reverse');
  if (select status from public.installment_plans where id = reversal_plan) <> 'reversed'
    or exists (select 1 from public.installments where plan_id = reversal_plan and status <> 'cancelled') then
    raise exception 'dedicated MSI reversal did not cancel the plan atomically';
  end if;
  if not exists (select 1 from public.financial_events where id = reversal_event and reverses_event_id =
    (select purchase_event_id from public.installment_plans where id = reversal_plan)) then
    raise exception 'dedicated MSI reversal did not preserve audit trail';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '42424242-4242-4242-4242-424242424242', true);

do $$
declare
  v_card_b uuid;
  v_plan_b uuid;
begin
  v_card_b := public.create_credit_card(
    'Tarjeta B MSI', 'Nexo Bank', null, 'MXN', 1000000, 13, 15, null, 'generic',
    'current_bank_balance', '2026-08-01', 0, null, null, 'phase4a-card-b'
  );
  v_plan_b := public.create_installment_purchase(
    v_card_b, 300000, 3, 100000, 'MSI B', 'other_expense', '2026-08-10',
    null, null, 'phase4a-plan-b'
  );
  update phase4a_ids set card_b = v_card_b, plan_b = v_plan_b;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '41414141-4141-4141-4141-414141414141', true);

do $$
declare
  ids phase4a_ids%rowtype;
  failed boolean;
begin
  select * into ids from phase4a_ids;
  if exists (select 1 from public.installment_plans where id = ids.plan_b)
    or exists (select 1 from public.installments where plan_id = ids.plan_b) then
    raise exception 'RLS exposed user B installment plan';
  end if;

  failed := false;
  begin
    perform public.create_installment_purchase(
      ids.card_b, 3000, 3, 1000, 'Ataque', 'other_expense', '2026-08-10',
      null, null, 'phase4a-attack-create'
    );
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A created MSI on user B card'; end if;

  failed := false;
  begin
    perform public.reverse_installment_purchase(ids.plan_b, 'phase4a-attack-reverse');
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A reversed user B MSI'; end if;

  failed := false;
  begin
    update public.installment_plans set installment_amount_minor = 1 where id = ids.plan_a;
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'authenticated user directly mutated financial MSI terms'; end if;
end;
$$;

reset role;
rollback;

select 'new MSI purchase, scheduling, rounding, reversal, and RLS tests passed' as result;
