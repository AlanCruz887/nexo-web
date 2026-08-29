begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'cards-a@example.test', '{"full_name":"Cards A"}'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'cards-b@example.test', '{"full_name":"Cards B"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

do $$
begin
  if public.card_statement_for_date('2026-07-08', 9) <> date '2026-07-09'
    or public.card_statement_for_date('2026-07-09', 9) <> date '2026-08-09'
    or public.card_statement_for_date('2026-07-12', 13) <> date '2026-07-13'
    or public.card_statement_for_date('2026-07-13', 13) <> date '2026-08-13' then
    raise exception 'semi-open cycle boundary failed';
  end if;
  if public.card_statement_for_date('2026-02-27', 31) <> date '2026-02-28'
    or public.card_statement_for_date('2026-02-28', 31) <> date '2026-03-31'
    or public.card_statement_for_date('2028-02-28', 31) <> date '2028-02-29'
    or public.card_statement_for_date('2028-02-29', 31) <> date '2028-03-31' then
    raise exception 'effective day 31 or leap-year rule failed';
  end if;
  if public.card_due_date('2026-08-09', 20) <> date '2026-08-29'
    or public.card_due_date('2026-12-20', 20) <> date '2027-01-09' then
    raise exception 'card due date calculation failed';
  end if;
end;
$$;

create temporary table phase3_ids (
  reference_card uuid,
  current_payment_card uuid,
  after_statement_card uuid,
  specific_date_card uuid,
  user_b_card uuid,
  closed_statement uuid
);

do $$
declare
  reference_card uuid;
  repeated_card uuid;
  current_payment_card uuid;
  after_statement_card uuid;
  specific_date_card uuid;
begin
  reference_card := public.create_credit_card(
    'Tarjeta referencia', 'Nexo Bank', 'Reference', 'MXN', 10000000,
    9, 20, '4821', 'generic', 'current_bank_balance', '2026-07-01',
    2000000, null, 'Saldo banco', 'phase3-create-reference'
  );
  repeated_card := public.create_credit_card(
    'Tarjeta referencia', 'Nexo Bank', 'Reference', 'MXN', 10000000,
    9, 20, '4821', 'generic', 'current_bank_balance', '2026-07-01',
    2000000, null, 'Saldo banco', 'phase3-create-reference'
  );
  if repeated_card <> reference_card then raise exception 'card create idempotency failed'; end if;

  current_payment_card := public.create_credit_card(
    'Pago actual', 'Nexo Bank', null, 'MXN', 5000000,
    9, 20, null, 'nu', 'current_bank_balance', '2026-07-09',
    0, null, null, 'phase3-create-current-payment'
  );
  after_statement_card := public.create_credit_card(
    'Después del estado', 'Nexo Bank', null, 'MXN', 10000000,
    13, 20, null, 'banamex_clasica', 'after_last_statement', '2026-07-15',
    5621212, 1287530, null, 'phase3-create-after-statement'
  );
  specific_date_card := public.create_credit_card(
    'Fecha específica', 'Nexo Bank', null, 'USD', 1000000,
    31, 15, null, 'bbva_oro', 'specific_date', '2026-07-15',
    250000, null, null, 'phase3-create-specific'
  );
  if (select baseline_balance_minor from public.card_baselines where card_id = after_statement_card) <> 4333682 then
    raise exception 'after-last-statement comparable baseline failed';
  end if;
  if (select baseline_date from public.card_baselines where card_id = specific_date_card) <> date '2026-07-15' then
    raise exception 'specific-date baseline was not preserved';
  end if;
  insert into phase3_ids(reference_card, current_payment_card, after_statement_card, specific_date_card)
  values (reference_card, current_payment_card, after_statement_card, specific_date_card);
end;
$$;

reset role;

do $$
declare
  reference_card uuid;
  payment_card uuid;
  event_id uuid;
begin
  select phase3_ids.reference_card, phase3_ids.current_payment_card into reference_card, payment_card from phase3_ids;
  event_id := gen_random_uuid();
  insert into public.financial_events(id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on)
  values (event_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'card_charge', 500000, 500000, 'Cargo de referencia', '2026-08-10');
  insert into public.card_entries(user_id, financial_event_id, card_id, amount_minor)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', event_id, reference_card, 500000);

  event_id := gen_random_uuid();
  insert into public.financial_events(id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on)
  values (event_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'card_charge', 1000000, 1000000, 'Estado cerrado', '2026-07-10');
  insert into public.card_entries(user_id, financial_event_id, card_id, amount_minor)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', event_id, payment_card, 1000000);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

do $$
declare
  reference_card uuid;
  payment_card uuid;
  statement_id uuid;
  repeated_statement_id uuid;
  used_balance bigint;
  available bigint;
begin
  select phase3_ids.reference_card, phase3_ids.current_payment_card into reference_card, payment_card from phase3_ids;
  select used_balance_minor, available_credit_minor into used_balance, available
  from public.card_summaries where id = reference_card;
  if used_balance <> 2500000 or available <> 7500000 then
    raise exception 'reference used/available balance failed: used %, available %', used_balance, available;
  end if;
  if (select open_cycle_accumulated_minor from public.card_summaries where id = reference_card) <> 500000 then
    raise exception 'open cycle did not contain the reference charge';
  end if;

  statement_id := public.close_card_statement(payment_card, '2026-08-09', null, null, 'phase3-close-payment-card');
  repeated_statement_id := public.close_card_statement(payment_card, '2026-08-09', null, null, 'phase3-close-payment-card');
  if repeated_statement_id <> statement_id then raise exception 'statement close idempotency failed'; end if;
  if not exists (
    select 1 from public.card_statements
    where id = statement_id and statement_balance_minor = 1000000
      and payment_due_date = date '2026-08-29' and remaining_due_minor = 1000000 and status = 'closed'
  ) then raise exception 'closed statement snapshot failed'; end if;
  perform public.update_card_statement(statement_id, 1000000, 100000, 300000, 'phase3-update-payment-card');
  update phase3_ids set closed_statement = statement_id;
end;
$$;

reset role;

do $$
declare
  payment_card uuid;
  event_id uuid;
begin
  select current_payment_card into payment_card from phase3_ids;
  event_id := gen_random_uuid();
  insert into public.financial_events(id, user_id, kind, amount_minor, description, occurred_on)
  values (event_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'card_payment', 300000, 'Pago', '2026-08-10');
  insert into public.card_entries(user_id, financial_event_id, card_id, amount_minor)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', event_id, payment_card, -300000);
  event_id := gen_random_uuid();
  insert into public.financial_events(id, user_id, kind, amount_minor, personal_amount_minor, description, occurred_on)
  values (event_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'card_charge', 500000, 500000, 'Ciclo abierto', '2026-08-11');
  insert into public.card_entries(user_id, financial_event_id, card_id, amount_minor)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', event_id, payment_card, 500000);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

do $$
declare
  payment_card uuid;
  reference_card uuid;
  future_statement_date date;
begin
  select current_payment_card, phase3_ids.reference_card into payment_card, reference_card from phase3_ids;
  if not exists (
    select 1 from public.card_summaries
    where id = payment_card and used_balance_minor = 1200000
      and current_payment_minor = 700000 and open_cycle_accumulated_minor = 500000
  ) then raise exception 'used balance, current payment, and open cycle were mixed'; end if;
  if public.card_statement_preview_balance(payment_card, '2026-09-09') <> 500000 then
    raise exception 'statement preview mixed prior debt, payments, or used balance with cycle activity';
  end if;
  future_statement_date := public.card_statement_for_date(current_date, 9);
  begin
    perform public.close_card_statement(payment_card, future_statement_date, null, null, 'phase3-close-future-date');
    raise exception 'future statement was closed through the normal flow';
  exception when invalid_parameter_value then null; end;
  perform public.update_credit_card(reference_card, 'Referencia editada', 'Nexo Bank', 'Reference', 11000000, 9, 20, '4821', 'generic', 'phase3-update-card');
  perform public.archive_credit_card(reference_card, 'phase3-archive-card');
  perform public.restore_credit_card(reference_card, 'phase3-restore-card');
  if not exists (select 1 from public.credit_cards where id = reference_card and is_active and credit_limit_minor = 11000000) then
    raise exception 'card update/archive/restore failed';
  end if;
  if (select count(distinct currency) from public.card_summaries) <> 2 then
    raise exception 'multi-currency cards were not preserved separately';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

do $$
declare
  card_b uuid;
begin
  card_b := public.create_credit_card(
    'Tarjeta B', 'Banco B', null, 'MXN', 1000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-09', 0, null, null, 'phase3-create-card-b'
  );
  perform public.close_card_statement(card_b, '2026-08-09', null, null, 'phase3-close-card-b');
  update phase3_ids set user_b_card = card_b;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

do $$
declare
  card_b uuid;
  visible_rows integer;
begin
  select user_b_card into card_b from phase3_ids;
  select count(*) into visible_rows from public.credit_cards where id = card_b;
  if visible_rows <> 0 then raise exception 'user A can read user B card'; end if;
  if exists (select 1 from public.card_statements where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') then
    raise exception 'user A can read user B statements';
  end if;
  if exists (select 1 from public.card_statement_close_candidates where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') then
    raise exception 'user A can read user B statement close candidate';
  end if;
  if public.card_next_pending_statement_date(card_b, current_date) is not null
    or public.card_statement_preview_balance(card_b, '2026-08-09') is not null then
    raise exception 'statement helper functions exposed user B card data';
  end if;
  begin
    perform public.update_credit_card(card_b, 'Ataque', 'Ataque', null, 1, 1, 1, null, 'generic', 'phase3-cross-update');
    raise exception 'user A updated user B card';
  exception when no_data_found then null; end;
  begin
    perform public.archive_credit_card(card_b, 'phase3-cross-archive');
    raise exception 'user A archived user B card';
  exception when no_data_found then null; end;
  begin
    perform public.close_card_statement(card_b, '2026-08-09', null, null, 'phase3-cross-close');
    raise exception 'user A closed user B statement';
  exception when no_data_found then null; end;
  begin
    insert into public.card_baselines(user_id, card_id, policy, baseline_date, reported_bank_balance_minor, baseline_balance_minor)
    values ('cccccccc-cccc-cccc-cccc-cccccccccccc', card_b, 'current_bank_balance', current_date, 0, 0);
    raise exception 'user A inserted baseline for user B';
  exception when insufficient_privilege then null; end;
end;
$$;

reset role;
rollback;

select 'credit cards, cycles, statements, and RLS tests passed' as result;
