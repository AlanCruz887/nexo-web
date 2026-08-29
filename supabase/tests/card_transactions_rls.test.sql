begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'card-ops-a@example.test', '{"full_name":"Card Ops A"}'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'card-ops-b@example.test', '{"full_name":"Card Ops B"}');

create temporary table phase3b_ids (
  account_a uuid,
  account_b uuid,
  card_a uuid,
  card_b uuid,
  purchase_a uuid,
  second_purchase_a uuid,
  statement_a uuid,
  payment_a uuid,
  refund_a uuid
);
insert into phase3b_ids default values;
grant select, update on phase3b_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

do $$
declare
  v_account_a uuid;
  v_card_a uuid;
  v_purchase_a uuid;
  repeated_purchase uuid;
  second_purchase uuid;
  edited_purchase uuid;
  failed boolean;
begin
  v_account_a := public.create_account(
    'Santander', 'checking', 'MXN', 5000000, 'Santander', '1234', 'phase3b-account-a'
  );
  v_card_a := public.create_credit_card(
    'BBVA Oro', 'BBVA', 'Oro', 'MXN', 10000000, 9, 20, '4821', 'bbva_oro',
    'current_bank_balance', '2026-07-01', 2000000, null, null, 'phase3b-card-a'
  );
  failed := false;
  begin
    perform public.create_card_purchase(
      v_card_a, 100000, 'Compra anterior', 'food', '2026-06-30', null, null, 'phase3b-before-start'
    );
  exception when invalid_parameter_value then failed := true;
  end;
  if not failed then raise exception 'impacting purchase before card start was accepted'; end if;
  v_purchase_a := public.create_card_purchase(
    v_card_a, 500000, 'MacBook stand', 'technology', '2026-07-08', 'apple_pay', 'Compra principal', 'phase3b-purchase-a'
  );
  repeated_purchase := public.create_card_purchase(
    v_card_a, 500000, 'MacBook stand', 'technology', '2026-07-08', 'apple_pay', 'Compra principal', 'phase3b-purchase-a'
  );
  if repeated_purchase <> v_purchase_a then raise exception 'purchase idempotency failed'; end if;
  if (select statement_date from public.card_transaction_details where financial_event_id = v_purchase_a) <> date '2026-07-09' then
    raise exception 'purchase before cut was not assigned to July statement';
  end if;
  if (select personal_amount_minor from public.financial_events where id = v_purchase_a) <> 500000 then
    raise exception 'card purchase did not count as personal expense';
  end if;
  if (select used_balance_minor from public.card_summaries where id = v_card_a) <> 2500000
    or (select available_credit_minor from public.card_summaries where id = v_card_a) <> 7500000 then
    raise exception 'purchase did not update used and available credit';
  end if;

  second_purchase := public.create_card_purchase(
    v_card_a, 200000, 'Compra en corte', 'food', '2026-07-09', 'physical_card', null, 'phase3b-purchase-cut'
  );
  if (select statement_date from public.card_transaction_details where financial_event_id = second_purchase) <> date '2026-08-09' then
    raise exception 'purchase on cut day was not assigned to next statement';
  end if;
  edited_purchase := public.update_card_purchase(
    second_purchase, v_card_a, 200000, 'Compra antes del corte', 'food', '2026-07-08',
    'physical_card', 'Fecha corregida', 'phase3b-purchase-edit-date'
  );
  if (select statement_date from public.card_transaction_details where financial_event_id = edited_purchase) <> date '2026-07-09' then
    raise exception 'edited purchase did not move cycle through central engine';
  end if;
  if exists (select 1 from public.financial_activity where event_id = second_purchase) then
    raise exception 'replaced purchase remained visible in unified activity';
  end if;
  if (select count(*) from public.financial_activity where event_id = edited_purchase) <> 1 then
    raise exception 'unified activity did not expose edited purchase exactly once';
  end if;
  update phase3b_ids set account_a = v_account_a, card_a = v_card_a, purchase_a = v_purchase_a, second_purchase_a = edited_purchase;
end;
$$;

do $$
declare
  ids phase3b_ids%rowtype;
  v_statement_a uuid;
  v_payment_a uuid;
  repeated_payment uuid;
  v_refund_a uuid;
  account_before bigint;
begin
  select * into ids from phase3b_ids;
  v_statement_a := public.close_card_statement(ids.card_a, '2026-07-09', null, null, 'phase3b-close-july');
  if (select statement_balance_minor from public.card_statements where id = v_statement_a) <> 2700000 then
    raise exception 'closed statement did not capture baseline and both July-cycle purchases';
  end if;
  select balance_minor into account_before from public.account_balances where id = ids.account_a;
  v_payment_a := public.create_card_payment(
    ids.card_a, ids.account_a, 1000000, '2026-07-10', 'Pago de prueba', 'phase3b-payment-a'
  );
  repeated_payment := public.create_card_payment(
    ids.card_a, ids.account_a, 1000000, '2026-07-10', 'Pago de prueba', 'phase3b-payment-a'
  );
  if repeated_payment <> v_payment_a then raise exception 'payment idempotency failed'; end if;
  if (select balance_minor from public.account_balances where id = ids.account_a) <> account_before - 1000000 then
    raise exception 'card payment did not reduce source account exactly once';
  end if;
  if (select used_balance_minor from public.card_summaries where id = ids.card_a) <> 1700000 then
    raise exception 'card payment did not reduce used balance';
  end if;
  if (select remaining_due_minor from public.card_statements where id = v_statement_a) <> 1700000
    or (select current_payment_minor from public.card_summaries where id = ids.card_a) <> 1700000 then
    raise exception 'payment was not allocated to current closed statement';
  end if;
  if (select personal_amount_minor from public.financial_events where id = v_payment_a) <> 0 then
    raise exception 'card payment counted as personal expense';
  end if;

  v_refund_a := public.create_card_refund(
    ids.card_a, 100000, 'Reembolso parcial', 'technology', '2026-07-10', ids.purchase_a,
    'Devolución parcial', 'phase3b-refund-a'
  );
  if (select used_balance_minor from public.card_summaries where id = ids.card_a) <> 1600000 then
    raise exception 'refund did not reduce used balance';
  end if;
  if (select coalesce(sum(case when kind = 'card_charge' then personal_amount_minor when kind = 'card_refund' then -personal_amount_minor else 0 end), 0)
      from public.financial_activity where card_id = ids.card_a) <> 600000 then
    raise exception 'net card personal expense is not purchases minus refunds';
  end if;
  if (select signed_amount_minor from public.financial_activity where event_id = v_refund_a) <> 100000 then
    raise exception 'refund was not presented as positive card credit';
  end if;
  update phase3b_ids set statement_a = v_statement_a, payment_a = v_payment_a, refund_a = v_refund_a;
end;
$$;

do $$
declare
  ids phase3b_ids%rowtype;
  reversal_id uuid;
  failed boolean;
begin
  select * into ids from phase3b_ids;
  failed := false;
  begin
    perform public.reverse_card_purchase(ids.purchase_a, 'phase3b-closed-purchase-reverse');
  exception when check_violation then failed := true;
  end;
  if not failed then raise exception 'purchase in closed statement could be silently reversed'; end if;

  reversal_id := public.reverse_card_payment(ids.payment_a, 'phase3b-payment-reverse');
  if (select balance_minor from public.account_balances where id = ids.account_a) <> 5000000 then
    raise exception 'payment reversal did not restore source account';
  end if;
  if (select remaining_due_minor from public.card_statements where id = ids.statement_a) <> 2700000
    or (select status from public.card_statements where id = ids.statement_a) <> 'closed' then
    raise exception 'payment reversal did not restore statement debt';
  end if;
  if (select used_balance_minor from public.card_summaries where id = ids.card_a) <> 2600000 then
    raise exception 'payment reversal did not restore card debt while preserving refund';
  end if;
  if not exists (select 1 from public.audit_events where action = 'card_payment_reversed' and entity_id = ids.payment_a) then
    raise exception 'payment reversal audit event missing';
  end if;
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ffffffff-ffff-ffff-ffff-ffffffffffff', true);

do $$
declare
  v_account_b uuid;
  v_card_b uuid;
begin
  v_account_b := public.create_account('Cuenta B', 'checking', 'MXN', 100000, null, null, 'phase3b-account-b');
  v_card_b := public.create_credit_card(
    'Tarjeta B', 'Nexo Bank', null, 'MXN', 1000000, 13, 15, null, 'generic',
    'current_bank_balance', '2026-07-01', 0, null, null, 'phase3b-card-b'
  );
  update phase3b_ids set account_b = v_account_b, card_b = v_card_b;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

do $$
declare
  ids phase3b_ids%rowtype;
  failed boolean;
begin
  select * into ids from phase3b_ids;
  if exists (select 1 from public.financial_activity where card_id = ids.card_b)
    or exists (select 1 from public.card_transaction_details where card_id = ids.card_b) then
    raise exception 'RLS exposed user B card operations';
  end if;

  failed := false;
  begin
    perform public.create_card_purchase(ids.card_b, 1000, 'Ataque', 'food', '2026-07-10', null, null, 'phase3b-attack-purchase');
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A created purchase on card B'; end if;

  failed := false;
  begin
    perform public.create_card_payment(ids.card_a, ids.account_b, 1000, '2026-07-10', null, 'phase3b-attack-account');
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A used account B to pay card A'; end if;

  failed := false;
  begin
    perform public.create_card_refund(ids.card_b, 1000, 'Ataque', null, '2026-07-10', null, null, 'phase3b-attack-refund');
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A created refund on card B'; end if;
end;
$$;

reset role;
rollback;

select 'card transactions, payments, refunds, unified activity, and RLS tests passed' as result;
