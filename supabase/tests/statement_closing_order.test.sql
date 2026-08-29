begin;

insert into auth.users (id, email, raw_user_meta_data)
values ('abababab-abab-abab-abab-abababababab', 'statement-order@example.test', '{"full_name":"Statement Order"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'abababab-abab-abab-abab-abababababab', true);

do $$
declare
  test_card uuid;
  july_statement uuid;
  august_statement uuid;
  future_statement_date date;
begin
  test_card := public.create_credit_card(
    'Tarjeta corte 9', 'Nexo Bank', null, 'MXN', 10000000,
    9, 20, null, 'generic', 'current_bank_balance', '2026-06-09',
    0, null, null, 'statement-order-card'
  );

  perform public.create_card_purchase(
    test_card, 100000, 'Oxxo', 'food', '2026-07-08', null, null, 'statement-order-oxxo'
  );
  perform public.create_card_purchase(
    test_card, 200000, 'Teléfono', 'technology', '2026-07-09', null, null, 'statement-order-phone'
  );
  perform public.create_card_purchase(
    test_card, 30000, 'KFC', 'food', '2026-07-10', null, null, 'statement-order-kfc'
  );

  if public.card_statement_preview_balance(test_card, '2026-07-09') <> 100000 then
    raise exception 'July statement preview was not exactly Oxxo 1000';
  end if;
  if public.card_statement_preview_balance(test_card, '2026-08-09') <> 230000 then
    raise exception 'August statement preview was not exactly phone 2000 plus KFC 300';
  end if;
  if public.card_statement_preview_balance(test_card, '2026-09-09') <> 0 then
    raise exception 'September open-cycle preview was not zero';
  end if;
  if public.card_next_pending_statement_date(test_card, '2026-08-27') <> date '2026-07-09' then
    raise exception 'oldest pending statement was not July 9';
  end if;

  july_statement := public.close_card_statement(
    test_card, '2026-07-09', null, null, 'statement-order-close-july'
  );
  if (select statement_balance_minor from public.card_statements where id = july_statement) <> 100000 then
    raise exception 'closed July statement balance was not 1000';
  end if;
  if public.card_next_pending_statement_date(test_card, '2026-08-27') <> date '2026-08-09' then
    raise exception 'August did not become the next pending statement after July';
  end if;

  august_statement := public.close_card_statement(
    test_card, '2026-08-09', null, null, 'statement-order-close-august'
  );
  if (select statement_balance_minor from public.card_statements where id = august_statement) <> 230000 then
    raise exception 'closed August statement balance was not 2300';
  end if;
  if public.card_next_pending_statement_date(test_card, '2026-08-27') is not null then
    raise exception 'September was considered due on August 27';
  end if;

  future_statement_date := public.card_statement_for_date(current_date, 9);
  begin
    perform public.close_card_statement(
      test_card, future_statement_date, null, null, 'statement-order-close-future'
    );
    raise exception 'normal close accepted a statement whose cut has not arrived';
  exception when invalid_parameter_value then null;
  end;

  if current_date = date '2026-08-27' and not exists (
    select 1
    from public.card_current_cycles
    where card_id = test_card
      and cycle_start = date '2026-08-09'
      and statement_date = date '2026-09-09'
      and open_cycle_accumulated_minor = 0
  ) then
    raise exception 'exact August 27 open cycle was not August 9 through September 9 at zero';
  end if;
end;
$$;

reset role;
rollback;

select 'chronological statement closing scenario passed' as result;
