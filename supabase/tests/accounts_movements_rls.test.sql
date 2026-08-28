begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'phase2-a@example.test', '{"full_name":"Phase 2 A"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'phase2-b@example.test', '{"full_name":"Phase 2 B"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);

do $$
declare
  source_account uuid;
  destination_account uuid;
  repeated_source_account uuid;
  income_event uuid;
  expense_event uuid;
  transfer_event uuid;
  repeated_transfer_event uuid;
  updated_expense_event uuid;
  regression_event uuid;
  regression_updated_event uuid;
  balance_before_edit bigint;
  source_balance bigint;
  destination_balance bigint;
  income_total bigint;
  expense_total bigint;
  visible_accounts integer;
  history_rows integer;
begin
  source_account := public.create_account(
    'Cuenta principal', 'checking', 'MXN', 1000000, 'Banco A', '4201', 'phase2-create-source-a'
  );
  repeated_source_account := public.create_account(
    'Cuenta principal', 'checking', 'MXN', 1000000, 'Banco A', '4201', 'phase2-create-source-a'
  );
  if repeated_source_account <> source_account then
    raise exception 'idempotent account creation returned a different account';
  end if;

  perform public.update_account(
    source_account, 'Cuenta principal editada', 'checking', 'Banco A', '4201', 'phase2-update-account-a'
  );
  perform public.update_account(
    source_account, 'Cuenta principal editada', 'checking', 'Banco A', '4201', 'phase2-update-account-a'
  );
  if (
    select count(*) from public.audit_events
    where action = 'account_updated' and entity_id = source_account
  ) <> 1 then
    raise exception 'idempotent account update duplicated audit evidence';
  end if;

  begin
    perform public.create_account(
      'Different payload', 'cash', 'MXN', 0, null, null, 'phase2-create-source-a'
    );
    raise exception 'idempotency key accepted a different payload';
  exception
    when sqlstate '22023' then null;
  end;

  destination_account := public.create_account(
    'Ahorro', 'savings', 'MXN', 0, 'Banco A', null, 'phase2-create-destination-a'
  );
  income_event := public.create_transaction(
    source_account, 'income', 500000, 'Nómina', 'salary', current_date, null, 'phase2-income-a'
  );
  expense_event := public.create_transaction(
    source_account, 'expense', 200000, 'Supermercado', 'food', current_date, null, 'phase2-expense-a'
  );
  transfer_event := public.create_transfer(
    source_account, destination_account, 100000, 'Ahorro mensual', current_date, null, 'phase2-transfer-a'
  );
  repeated_transfer_event := public.create_transfer(
    source_account, destination_account, 100000, 'Ahorro mensual', current_date, null, 'phase2-transfer-a'
  );
  if repeated_transfer_event <> transfer_event then
    raise exception 'idempotent transfer returned a different event';
  end if;
  perform public.update_transfer_notes(transfer_event, 'Movimiento interno', 'phase2-transfer-note-a');
  perform public.update_transfer_notes(transfer_event, 'Movimiento interno', 'phase2-transfer-note-a');
  if (
    select count(*) from public.financial_event_notes
    where financial_event_id = transfer_event
  ) <> 1 then
    raise exception 'idempotent transfer note update duplicated evidence';
  end if;
  if not exists (
    select 1 from public.account_activity
    where event_id = transfer_event and notes = 'Movimiento interno'
  ) then
    raise exception 'latest transfer note is missing from activity projection';
  end if;

  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  select balance_minor into destination_balance
  from public.account_balances where id = destination_account;
  if source_balance <> 1200000 or destination_balance <> 100000 then
    raise exception 'financial balance invariant failed: source %, destination %', source_balance, destination_balance;
  end if;

  select coalesce(sum(amount_minor), 0) into income_total
  from public.financial_events
  where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and kind = 'income'
    and not exists (
      select 1 from public.financial_events reversal
      where reversal.reverses_event_id = financial_events.id
    );
  select coalesce(sum(personal_amount_minor), 0) into expense_total
  from public.financial_events
  where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and kind = 'expense'
    and not exists (
      select 1 from public.financial_events reversal
      where reversal.reverses_event_id = financial_events.id
    );
  if income_total <> 500000 or expense_total <> 200000 then
    raise exception 'transfer changed income/expense metrics';
  end if;

  updated_expense_event := public.update_transaction(
    expense_event, 150000, 'Supermercado semanal', 'food', current_date, 'Editado', 'phase2-update-expense-a'
  );
  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  if source_balance <> 1250000 then
    raise exception 'editing a transaction did not reverse and replace correctly: %', source_balance;
  end if;

  perform public.reverse_transaction(updated_expense_event, 'phase2-delete-expense-a');
  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  if source_balance <> 1400000 then
    raise exception 'reversing a simple transaction did not restore balance: %', source_balance;
  end if;

  perform public.reverse_transfer(transfer_event, 'phase2-reverse-transfer-a');
  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  select balance_minor into destination_balance
  from public.account_balances where id = destination_account;
  if source_balance <> 1500000 or destination_balance <> 0 then
    raise exception 'transfer reversal did not restore both accounts';
  end if;

  select balance_minor into balance_before_edit
  from public.account_balances where id = source_account;
  regression_event := public.create_transaction(
    source_account, 'expense', 150000, 'Compra original', 'food', current_date, null, 'phase2-regression-create'
  );
  regression_updated_event := public.update_transaction(
    regression_event, 120000, 'Compra editada', 'transport', current_date - 1, 'Metadata editada', 'phase2-regression-update'
  );
  if regression_updated_event = regression_event then
    raise exception 'transaction update did not return the replacement event id';
  end if;
  if exists (select 1 from public.account_activity where event_id = regression_event) then
    raise exception 'replaced event remained in current activity';
  end if;
  if not exists (
    select 1 from public.account_activity
    where event_id = regression_updated_event
      and amount_minor = 120000
      and personal_amount_minor = 120000
      and description = 'Compra editada'
      and category_id = 'transport'
      and occurred_on = current_date - 1
      and notes = 'Metadata editada'
  ) then
    raise exception 'replacement event detail did not resolve with edited amount and metadata';
  end if;
  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  if source_balance <> balance_before_edit - 120000 then
    raise exception '1500 to 1200 edit did not apply exactly once: before %, after %', balance_before_edit, source_balance;
  end if;
  perform public.reverse_transaction(regression_updated_event, 'phase2-regression-cleanup');
  select balance_minor into source_balance
  from public.account_balances where id = source_account;
  if source_balance <> balance_before_edit then
    raise exception 'regression edit cleanup did not restore balance';
  end if;

  perform public.archive_account(source_account, 'phase2-archive-source-a');
  perform public.archive_account(source_account, 'phase2-archive-source-a');
  select count(*) into visible_accounts
  from public.account_balances where is_active;
  if visible_accounts <> 1 then
    raise exception 'archived account remained in active selector projection';
  end if;
  select count(*) into history_rows
  from public.account_activity where account_id = source_account;
  if history_rows = 0 then
    raise exception 'archived account lost its activity history';
  end if;

  if not exists (
    select 1 from public.audit_events
    where action = 'account_archived' and entity_id = source_account
  ) then
    raise exception 'account archive audit event missing';
  end if;
  if (
    select count(*) from public.audit_events
    where action = 'account_archived' and entity_id = source_account
  ) <> 1 then
    raise exception 'idempotent archive duplicated audit evidence';
  end if;

  perform public.restore_account(source_account, 'phase2-restore-source-a');
  perform public.restore_account(source_account, 'phase2-restore-source-a');
  if not exists (
    select 1 from public.accounts where id = source_account and is_active
  ) then
    raise exception 'restored account remained archived';
  end if;
  if (
    select count(*) from public.audit_events
    where action = 'account_restored' and entity_id = source_account
  ) <> 1 then
    raise exception 'idempotent restore did not preserve exactly one audit event';
  end if;
  if not exists (
    select 1 from public.audit_events
    where action = 'transaction_deleted' and entity_id = updated_expense_event
  ) then
    raise exception 'transaction delete audit event missing';
  end if;

  if income_event is null then raise exception 'income event was not created'; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

create temporary table phase2_user_b_ids (account_id uuid, event_id uuid);

do $$
declare
  account_b uuid;
  event_b uuid;
begin
  account_b := public.create_account(
    'Cuenta B', 'cash', 'MXN', 250000, null, null, 'phase2-create-account-b'
  );
  event_b := public.create_transaction(
    account_b, 'expense', 5000, 'Gasto B', 'other_expense', current_date, null, 'phase2-expense-b'
  );
  insert into phase2_user_b_ids values (account_b, event_b);
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);

do $$
declare
  account_b uuid;
  event_b uuid;
  account_a uuid;
  visible_b_rows integer;
begin
  select account_id, event_id into account_b, event_b from phase2_user_b_ids;
  select id into account_a from public.accounts
  where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  order by created_at limit 1;

  select count(*) into visible_b_rows from public.accounts where id = account_b;
  if visible_b_rows <> 0 then raise exception 'user A can read user B account'; end if;

  begin
    perform public.create_transaction(
      account_b, 'income', 1000, 'Ataque', 'other_income', current_date, null, 'phase2-cross-user-movement'
    );
    raise exception 'user A created movement in user B account';
  exception
    when no_data_found then null;
  end;

  begin
    perform public.create_transfer(
      account_a, account_b, 1000, 'Ataque', current_date, null, 'phase2-cross-user-transfer'
    );
    raise exception 'user A transferred to user B account';
  exception
    when no_data_found then null;
  end;

  begin
    perform public.update_transaction(
      event_b, 1000, 'Ataque', 'other_expense', current_date, null, 'phase2-cross-user-update'
    );
    raise exception 'user A edited user B movement';
  exception
    when no_data_found then null;
  end;

  begin
    perform public.archive_account(account_b, 'phase2-cross-user-archive');
    raise exception 'user A archived user B account';
  exception
    when no_data_found then null;
  end;

  begin
    perform public.restore_account(account_b, 'phase2-cross-user-restore');
    raise exception 'user A restored user B account';
  exception
    when no_data_found then null;
  end;
end;
$$;

reset role;
rollback;

select 'accounts and movements RLS tests passed' as result;
