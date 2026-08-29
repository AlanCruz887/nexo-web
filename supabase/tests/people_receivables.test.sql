begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', 'phase5a-a@example.test', '{"full_name":"Phase 5A A"}'),
  ('5b5b5b5b-5b5b-4b5b-8b5b-5b5b5b5b5b5b', 'phase5a-b@example.test', '{"full_name":"Phase 5A B"}');

create temporary table phase5a_ids (account_a uuid, account_b uuid, card_a uuid, contact_a uuid, contact_b uuid,
  account_purchase uuid, card_purchase uuid, purchase_b uuid, payment uuid);
insert into phase5a_ids default values;
grant select, update on phase5a_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', true);

do $$
declare
  account_id uuid; card_id uuid; carlos uuid; ana uuid; purchase_id uuid; card_purchase_id uuid;
  payment_id uuid; repeated_payment uuid; overpayment_id uuid; balance_before bigint;
begin
  account_id := public.create_account('Cuenta A', 'checking', 'MXN', 1000000, null, null, 'phase5a-account');
  card_id := public.create_credit_card('Tarjeta A', 'Banco', null, 'MXN', 5000000, 9, 20, null,
    'generic', 'current_bank_balance', '2026-08-01', 0, null, null, 'phase5a-card');
  carlos := public.create_contact('Carlos', null, null, null, 'phase5a-carlos');
  ana := public.create_contact('Ana', null, null, null, 'phase5a-ana');

  purchase_id := public.create_shared_account_purchase(account_id, 1000000, 300000,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '700000')),
    'Compra compartida', 'food', '2026-08-10', null, '5a-shared-account');
  if (select personal_amount_minor from public.financial_events where id = purchase_id) <> 300000 then
    raise exception 'shared account purchase counted the full amount as personal'; end if;
  if (select outstanding_minor from public.receivable_balances where source_event_id = purchase_id) <> 700000 then
    raise exception 'shared account purchase did not create the receivable'; end if;
  if (select balance_minor from public.account_balances where id = account_id) <> 0 then
    raise exception 'shared account purchase did not reduce cash by its full amount'; end if;

  card_purchase_id := public.create_shared_card_purchase(card_id, 1000000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', carlos, 'amount_minor', '600000'),
      jsonb_build_object('contact_id', ana, 'amount_minor', '400000')),
    'Compra para dos personas', 'food', '2026-08-11', null, null, '5a-shared-card');
  if (select used_balance_minor from public.card_summaries where id = card_id) <> 1000000 then
    raise exception 'shared card purchase did not use the full card amount exactly once'; end if;
  if (select count(*) from public.receivable_balances where source_event_id = card_purchase_id) <> 2 then
    raise exception 'multiple people allocations were not preserved'; end if;

  select balance_minor into balance_before from public.account_balances where id = account_id;
  payment_id := public.create_person_payment(carlos, account_id, 500000, '2026-08-20', null, 'phase5a-payment');
  repeated_payment := public.create_person_payment(carlos, account_id, 500000, '2026-08-20', null, 'phase5a-payment');
  if repeated_payment <> payment_id then raise exception 'person payment idempotency failed'; end if;
  if (select balance_minor from public.account_balances where id = account_id) <> balance_before + 500000 then
    raise exception 'person payment did not increase the receiving account exactly once'; end if;
  if (select personal_amount_minor from public.financial_events where id = payment_id) <> 0 then
    raise exception 'person payment became income or personal expense'; end if;
  if (select outstanding_minor from public.receivable_balances where source_event_id = purchase_id) <> 200000 then
    raise exception 'FIFO did not apply the partial payment to the oldest receivable'; end if;
  if (select outstanding_minor from public.receivable_balances where source_event_id = card_purchase_id and contact_id = carlos) <> 600000 then
    raise exception 'FIFO incorrectly paid a newer receivable first'; end if;

  overpayment_id := public.create_person_payment(carlos, account_id, 1500000, '2026-08-21', null, 'phase5b-overpay');
  if (select credit_balance_minor from public.person_credit_balances
      where contact_id = carlos and currency = 'MXN') <> 700000 then
    raise exception 'overpayment did not preserve the excess as person credit'; end if;
  perform public.reverse_person_payment(overpayment_id, '5b-reverse-overpay');
  if exists (select 1 from public.person_credit_balances where contact_id = carlos and currency = 'MXN') then
    raise exception 'overpayment reversal did not restore person credit'; end if;

  perform public.reverse_person_payment(payment_id, '5a-reverse-payment');
  if (select outstanding_minor from public.receivable_balances where source_event_id = purchase_id) <> 700000 then
    raise exception 'payment reversal did not restore the receivable'; end if;
  if (select balance_minor from public.account_balances where id = account_id) <> balance_before then
    raise exception 'payment reversal did not restore bank cash'; end if;

  perform public.create_person_payment(carlos, account_id, 1300000, '2026-08-22', null, 'phase5a-full-payment');
  if exists (select 1 from public.receivable_balances where contact_id = carlos and outstanding_minor <> 0) then
    raise exception 'full person payment did not close every pending receivable'; end if;
  if (select coalesce(sum(personal_amount_minor), 0) from public.financial_events where kind = 'person_payment'
      and user_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a') <> 0 then
    raise exception 'full person payment was counted as income or expense'; end if;

  update phase5a_ids set account_a = account_id, card_a = card_id, contact_a = carlos,
    account_purchase = purchase_id, card_purchase = card_purchase_id, payment = payment_id;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '5b5b5b5b-5b5b-4b5b-8b5b-5b5b5b5b5b5b', true);
do $$ declare person_id uuid; account_id uuid; purchase_id uuid; begin
  person_id := public.create_contact('Persona B', null, null, null, 'phase5a-person-b');
  account_id := public.create_account('Cuenta B', 'checking', 'MXN', 100000, null, null, 'phase5a-account-b');
  purchase_id := public.create_shared_account_purchase(account_id, 10000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', person_id, 'amount_minor', '10000')),
    'Compra B', 'food', current_date, null, 'phase5a-purchase-b');
  update phase5a_ids set contact_b = person_id, account_b = account_id, purchase_b = purchase_id;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', true);
do $$
declare ids phase5a_ids%rowtype; failed boolean;
begin
  select * into ids from phase5a_ids;
  if exists (select 1 from public.contacts where id = ids.contact_b) then raise exception 'RLS exposed user B contact'; end if;
  failed := false;
  begin perform public.create_shared_account_purchase(ids.account_a, 1000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', ids.contact_b, 'amount_minor', '1000')),
    'Ataque', 'food', current_date, null, '5a-attack-contact');
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A assigned a purchase to user B contact'; end if;
  failed := false;
  begin perform public.create_person_payment(ids.contact_b, ids.account_a, 1000, current_date, null, 'phase5a-attack-payment');
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A registered a payment against user B contact'; end if;
  failed := false;
  begin perform public.create_person_payment(ids.contact_a, ids.account_b, 1000, current_date, null, 'phase5a-attack-account');
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A used user B account as payment destination'; end if;
  failed := false;
  begin perform public.update_shared_account_purchase(ids.purchase_b, 10000, 0,
    jsonb_build_array(jsonb_build_object('contact_id', ids.contact_a, 'amount_minor', '10000')),
    'Ataque edit', 'food', current_date, null, 'phase5a-attack-edit');
  exception when no_data_found then failed := true; end;
  if not failed then raise exception 'user A modified user B purchase'; end if;
end;
$$;

reset role;
rollback;
select 'people, shared purchases, FIFO payments, reversals, idempotency and RLS tests passed' as result;
