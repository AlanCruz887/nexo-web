begin;

insert into auth.users (id, email, raw_user_meta_data)
values ('acacacac-acac-acac-acac-acacacacacac', 'advance-payments@example.test', '{"full_name":"Advance Payments"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'acacacac-acac-acac-acac-acacacacacac', true);

do $$
declare
  source_account uuid;
  exact_card uuid;
  close_card uuid;
  prior_statement uuid;
  closing_statement uuid;
  purchase_one uuid;
  purchase_two uuid;
  used_before_close bigint;
  entries_before_close integer;
begin
  source_account := public.create_account(
    'Cuenta origen', 'checking', 'MXN', 10000000, null, null, 'advance-account'
  );

  -- Exact open-cycle scenario: a prior statement is fully paid, then all new
  -- payments are advances associated temporally with the September 9 cycle.
  exact_card := public.create_credit_card(
    'Joy', 'Banamex', 'Joy', 'MXN', 10000000, 9, 20, null, 'banamex_joy',
    'current_bank_balance', '2026-07-09', 0, null, null, 'advance-exact-card'
  );
  perform public.create_card_purchase(
    exact_card, 30000, 'Compra estado anterior', 'food', '2026-07-10', null, null, 'advance-prior-purchase'
  );
  prior_statement := public.close_card_statement(
    exact_card, '2026-08-09', null, null, 'advance-close-prior'
  );
  perform public.create_card_payment(
    exact_card, source_account, 30000, '2026-08-10', null, 'advance-pay-prior'
  );
  if (select status from public.card_statements where id = prior_statement) <> 'paid' then
    raise exception 'prior statement was not completely paid';
  end if;

  purchase_one := public.create_card_purchase(
    exact_card, 200000, 'PS5 Alan', 'technology', '2026-08-20', null, null, 'advance-purchase-one'
  );
  purchase_two := public.create_card_purchase(
    exact_card, 100000, 'Audífonos prueba', 'technology', '2026-08-21', null, null, 'advance-purchase-two'
  );
  perform public.create_card_refund(
    exact_card, 40000, 'Reembolso', 'technology', '2026-08-22', purchase_one, null, 'advance-refund'
  );
  perform public.create_card_payment(
    exact_card, source_account, 50000, '2026-08-23', null, 'advance-payment-500'
  );
  perform public.create_card_payment(
    exact_card, source_account, 60000, '2026-08-24', null, 'advance-payment-600'
  );

  if (select used_balance_minor from public.card_summaries where id = exact_card) <> 150000 then
    raise exception 'used balance was not purchases minus refunds and advance payments';
  end if;
  if (select sum(advance_amount_minor) from public.card_payment_classifications where card_id = exact_card) <> 110000 then
    raise exception 'advance payment classification was not exactly 1100';
  end if;
  if (select coalesce(sum(amount_minor), 0) from public.card_statement_activity_segments
      where card_id = exact_card and group_statement_date = date '2026-09-09' and segment_kind = 'purchase') <> 300000 then
    raise exception 'September purchases were not exactly 3000';
  end if;
  if (select coalesce(sum(amount_minor), 0) from public.card_statement_activity_segments
      where card_id = exact_card and group_statement_date = date '2026-09-09' and segment_kind = 'refund') <> 40000 then
    raise exception 'September refunds were not exactly 400';
  end if;
  if (select coalesce(sum(amount_minor), 0) from public.card_statement_activity_segments
      where card_id = exact_card and group_statement_date = date '2026-09-09' and segment_kind = 'payment_advance') <> 110000 then
    raise exception 'September advance payments were not exactly 1100';
  end if;
  if public.card_statement_preview_balance(exact_card, '2026-09-09') <> 260000 then
    raise exception 'net purchases preview was not exactly 2600';
  end if;

  -- Same financial shape in an already-due cycle: closing creates allocations,
  -- but never another account/card entry or a second balance impact.
  close_card := public.create_credit_card(
    'Cierre con anticipos', 'Nexo Bank', null, 'MXN', 10000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-09', 0, null, null, 'advance-close-card'
  );
  perform public.create_card_purchase(
    close_card, 200000, 'Compra A', 'technology', '2026-07-20', null, null, 'advance-close-purchase-a'
  );
  perform public.create_card_purchase(
    close_card, 100000, 'Compra B', 'technology', '2026-07-21', null, null, 'advance-close-purchase-b'
  );
  perform public.create_card_refund(
    close_card, 40000, 'Reembolso', 'technology', '2026-07-22', null, null, 'advance-close-refund'
  );
  perform public.create_card_payment(
    close_card, source_account, 50000, '2026-07-23', null, 'advance-close-payment-500'
  );
  perform public.create_card_payment(
    close_card, source_account, 60000, '2026-07-24', null, 'advance-close-payment-600'
  );
  select used_balance_minor into used_before_close from public.card_summaries where id = close_card;
  select count(*) into entries_before_close from public.card_entries where card_id = close_card;

  closing_statement := public.close_card_statement(
    close_card, '2026-08-09', null, null, 'advance-close-statement'
  );
  if not exists (
    select 1 from public.card_statements
    where id = closing_statement
      and statement_balance_minor = 260000
      and amount_paid_minor = 110000
      and remaining_due_minor = 150000
      and minimum_payment_minor is null
  ) then raise exception 'closed statement did not preserve net purchases, advances, remaining due, or null minimum'; end if;
  if (select used_balance_minor from public.card_summaries where id = close_card) <> used_before_close then
    raise exception 'statement close changed used balance a second time';
  end if;
  if (select count(*) from public.card_entries where card_id = close_card) <> entries_before_close then
    raise exception 'statement close created duplicate financial entries';
  end if;
  if (select coalesce(sum(amount_minor), 0) from public.card_statement_payment_allocations
      where statement_id = closing_statement) <> 110000 then
    raise exception 'advance payments were not traceably allocated at close';
  end if;
end;
$$;

reset role;
rollback;

select 'advance card payment projection and close regression passed' as result;
