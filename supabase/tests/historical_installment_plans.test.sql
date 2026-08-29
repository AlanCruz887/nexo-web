begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('4b4b4b4b-4b4b-4b4b-8b4b-4b4b4b4b4b4b', 'phase4b-a@example.test', '{"full_name":"Phase 4B A"}'),
  ('4c4c4c4c-4c4c-4c4c-8c4c-4c4c4c4c4c4c', 'phase4b-b@example.test', '{"full_name":"Phase 4B B"}');

create temporary table phase4b_ids (
  account_a uuid,
  included_card uuid,
  excluded_card uuid,
  included_plan uuid,
  excluded_plan uuid,
  card_b uuid,
  plan_b uuid
);
insert into phase4b_ids default values;
grant select, update on phase4b_ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '4b4b4b4b-4b4b-4b4b-8b4b-4b4b4b4b4b4b', true);

do $$
declare
  v_account uuid;
  v_included_card uuid;
  v_excluded_card uuid;
  v_included_plan uuid;
  v_excluded_plan uuid;
  repeated_plan uuid;
  included_event uuid;
  excluded_event uuid;
begin
  v_account := public.create_account(
    'Cuenta pagos 4B', 'checking', 'MXN', 5000000, null, null, 'phase4b-account'
  );
  v_included_card := public.create_credit_card(
    'MSI incluido', 'Nexo Bank', null, 'MXN', 10000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-10', 4000000, null, null, 'phase4b-included-card'
  );
  v_excluded_card := public.create_credit_card(
    'MSI no incluido', 'Nexo Bank', null, 'MXN', 10000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-07-10', 4000000, null, null, 'phase4b-excluded-card'
  );

  v_included_plan := public.import_historical_installment_plan(
    v_included_card, 'iPhone histórico', 1200000, 12, 100000, '2026-07-01',
    5, 4, 410000, 400000, '2026-08-09', 'technology', 'Pago real conservado',
    true, 'phase4b-import-included'
  );
  repeated_plan := public.import_historical_installment_plan(
    v_included_card, 'iPhone histórico', 1200000, 12, 100000, '2026-07-01',
    5, 4, 410000, 400000, '2026-08-09', 'technology', 'Pago real conservado',
    true, 'phase4b-import-included'
  );
  if repeated_plan <> v_included_plan then raise exception 'historical MSI idempotency failed'; end if;

  v_excluded_plan := public.import_historical_installment_plan(
    v_excluded_card, 'iPhone fuera del saldo', 1200000, 12, 100000, '2026-07-01',
    5, 4, 400000, 400000, '2026-08-09', 'technology', null,
    false, 'phase4b-import-excluded'
  );

  if (select used_balance_minor from public.card_summaries where id = v_included_card) <> 4000000 then
    raise exception 'included historical MSI inflated opening balance';
  end if;
  if (select used_balance_minor from public.card_summaries where id = v_excluded_card) <> 4800000 then
    raise exception 'excluded historical MSI did not add remaining principal exactly once';
  end if;
  if (select additional_card_impact_minor from public.installment_plan_summaries where id = v_included_plan) <> 0
    or (select additional_card_impact_minor from public.installment_plan_summaries where id = v_excluded_plan) <> 800000 then
    raise exception 'historical MSI additional impact projection is incorrect';
  end if;
  if (select reported_paid_amount_minor from public.installment_plan_summaries where id = v_included_plan) <> 410000
    or (select principal_paid_before_nexo_minor from public.installment_plan_summaries where id = v_included_plan) <> 400000
    or (select remaining_principal_minor from public.installment_plan_summaries where id = v_included_plan) <> 800000 then
    raise exception 'reported payment, amortized principal, or remaining principal was lost';
  end if;
  if (select count(*) from public.installment_schedule where plan_id = v_included_plan and effective_status = 'paid_before_nexo') <> 4
    or (select installment_number from public.installment_schedule where plan_id = v_included_plan and effective_status = 'future' order by installment_number limit 1) <> 5
    or (select count(*) from public.installment_schedule where plan_id = v_included_plan) <> 12 then
    raise exception '5 of 12 historical schedule was not generated correctly';
  end if;
  if (select paid_before_nexo_count from public.installment_plan_summaries where id = v_included_plan) <> 4
    or (select paid_count from public.installment_plan_summaries where id = v_included_plan) <> 4
    or (select pending_count from public.installment_plan_summaries where id = v_included_plan) <> 8
    or (select current_installment_number from public.installment_plan_summaries where id = v_included_plan) <> 5 then
    raise exception 'historical MSI progress summary is incorrect';
  end if;
  if (select card_statement_preview_balance(v_included_card, '2026-08-09')) <> 3300000 then
    raise exception 'included historical principal was duplicated in first statement preview';
  end if;
  if (select card_statement_preview_balance(v_excluded_card, '2026-08-09')) <> 4100000 then
    raise exception 'excluded historical principal was charged in full to statement instead of monthly amount';
  end if;

  select purchase_event_id into included_event from public.installment_plans where id = v_included_plan;
  select purchase_event_id into excluded_event from public.installment_plans where id = v_excluded_plan;
  if (select personal_amount_minor from public.financial_events where id = included_event) <> 0
    or (select personal_amount_minor from public.financial_events where id = excluded_event) <> 0 then
    raise exception 'historical MSI import created current personal expense';
  end if;
  if exists (select 1 from public.account_entries where financial_event_id in (included_event, excluded_event))
    or exists (select 1 from public.financial_activity_enriched where installment_plan_id in (v_included_plan, v_excluded_plan)) then
    raise exception 'historical MSI import created false bank or purchase movements';
  end if;
  if (select effect_scope from public.card_entries where financial_event_id = included_event) <> 'historical_non_impacting'
    or (select effect_scope from public.card_entries where financial_event_id = excluded_event) <> 'impacting' then
    raise exception 'opening-balance inclusion did not control ledger scope';
  end if;
  if not exists (select 1 from public.audit_events where action = 'historical_installment_plan_imported' and entity_id = v_included_plan) then
    raise exception 'historical import audit missing';
  end if;
  perform public.update_installment_plan_metadata(
    v_included_plan, 'iPhone histórico corregido', 'technology', 'Solo metadata',
    'phase4b-metadata-correction'
  );
  if not exists (select 1 from public.audit_events where action = 'historical_installment_plan_corrected' and entity_id = v_included_plan) then
    raise exception 'historical correction audit missing';
  end if;

  update phase4b_ids set account_a = v_account, included_card = v_included_card,
    excluded_card = v_excluded_card, included_plan = v_included_plan, excluded_plan = v_excluded_plan;
end;
$$;

do $$
declare
  ids phase4b_ids%rowtype;
  statement_id uuid;
begin
  select * into ids from phase4b_ids;
  statement_id := public.close_card_statement(ids.included_card, '2026-08-09', null, null, 'phase4b-close');
  if (select statement_balance_minor from public.card_statements where id = statement_id) <> 3300000 then
    raise exception 'historical current installment was not integrated into statement';
  end if;
  perform public.create_card_payment(ids.included_card, ids.account_a, 3200000, '2026-08-10', null, 'phase4b-partial');
  if (select effective_status from public.installment_schedule where plan_id = ids.included_plan and installment_number = 5) <> 'pending'
    or (select paid_count from public.installment_plan_summaries where id = ids.included_plan) <> 4 then
    raise exception 'partial statement payment marked historical installment as paid';
  end if;
  perform public.create_card_payment(ids.included_card, ids.account_a, 100000, '2026-08-11', null, 'phase4b-complete');
  if (select effective_status from public.installment_schedule where plan_id = ids.included_plan and installment_number = 5) <> 'paid'
    or (select paid_count from public.installment_plan_summaries where id = ids.included_plan) <> 5
    or (select remaining_principal_minor from public.installment_plan_summaries where id = ids.included_plan) <> 700000 then
    raise exception 'fully paid statement did not advance historical MSI';
  end if;
end;
$$;

do $$
declare
  rounding_card uuid;
  rounding_plan uuid;
  reversible_card uuid;
  reversible_plan uuid;
  used_before bigint;
begin
  rounding_card := public.create_credit_card(
    'Redondeo histórico', 'Nexo Bank', null, 'MXN', 2000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-08-10', 1000000, null, null, 'phase4b-round-card'
  );
  rounding_plan := public.import_historical_installment_plan(
    rounding_card, 'Redondeo real', 1000000, 3, 333333, '2026-08-01',
    2, 1, 333333, 333333, '2026-09-09', 'other_expense', null,
    true, 'phase4b-round-plan'
  );
  if (select installment_amount_minor from public.installment_plan_summaries where id = rounding_plan) <> 333333
    or (select reported_amount_minor from public.installment_schedule where plan_id = rounding_plan and installment_number = 3) <> 333334
    or (select sum(principal_minor) from public.installment_schedule where plan_id = rounding_plan) <> 1000000 then
    raise exception 'reported monthly amount or exact principal rounding was not preserved';
  end if;

  reversible_card := public.create_credit_card(
    'Reversión histórica', 'Nexo Bank', null, 'MXN', 2000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-08-10', 400000, null, null, 'phase4b-reverse-card'
  );
  reversible_plan := public.import_historical_installment_plan(
    reversible_card, 'Plan a revertir', 300000, 3, 100000, '2026-08-01',
    2, 1, 100000, 100000, '2026-09-09', 'other_expense', null,
    false, 'phase4b-reverse-plan'
  );
  select used_balance_minor into used_before from public.card_summaries where id = reversible_card;
  if used_before <> 600000 then raise exception 'reversal fixture did not add remaining principal'; end if;
  perform public.reverse_installment_purchase(reversible_plan, 'phase4b-reverse');
  if (select used_balance_minor from public.card_summaries where id = reversible_card) <> 400000
    or (select status from public.installment_plans where id = reversible_plan) <> 'reversed'
    or exists (select 1 from public.installments where plan_id = reversible_plan and status <> 'cancelled') then
    raise exception 'historical MSI reversal did not restore ledger and cancel schedule';
  end if;
  if not exists (select 1 from public.audit_events where action = 'historical_installment_plan_reversed' and entity_id = reversible_plan) then
    raise exception 'historical reversal audit missing';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '4c4c4c4c-4c4c-4c4c-8c4c-4c4c4c4c4c4c', true);

do $$
declare
  v_card_b uuid;
  v_plan_b uuid;
begin
  v_card_b := public.create_credit_card(
    'Tarjeta histórica B', 'Nexo Bank', null, 'MXN', 1000000, 9, 20, null, 'generic',
    'current_bank_balance', '2026-08-10', 0, null, null, 'phase4b-card-b'
  );
  v_plan_b := public.import_historical_installment_plan(
    v_card_b, 'Plan B', 300000, 3, 100000, '2026-08-01',
    2, 1, 100000, 100000, '2026-09-09', 'other_expense', null,
    true, 'phase4b-plan-b'
  );
  update phase4b_ids set card_b = v_card_b, plan_b = v_plan_b;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '4b4b4b4b-4b4b-4b4b-8b4b-4b4b4b4b4b4b', true);

do $$
declare
  ids phase4b_ids%rowtype;
  failed boolean;
begin
  select * into ids from phase4b_ids;
  if exists (select 1 from public.installment_plans where id = ids.plan_b)
    or exists (select 1 from public.installments where plan_id = ids.plan_b) then
    raise exception 'RLS exposed user B historical plan';
  end if;
  failed := false;
  begin
    perform public.import_historical_installment_plan(
      ids.card_b, 'Ataque', 300000, 3, 100000, '2026-08-01',
      2, 1, 100000, 100000, '2026-09-09', 'other_expense', null,
      true, 'phase4b-attack-import'
    );
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A imported historical MSI on user B card'; end if;

  failed := false;
  begin
    perform public.reverse_installment_purchase(ids.plan_b, 'phase4b-attack-reverse');
  exception when no_data_found then failed := true;
  end;
  if not failed then raise exception 'user A reversed user B historical MSI'; end if;

  failed := false;
  begin
    update public.installments set principal_minor = 1 where plan_id = ids.included_plan;
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'authenticated user directly edited historical installments'; end if;
end;
$$;

reset role;
rollback;

select 'historical MSI baseline, schedule, payments, reversal, idempotency, and RLS tests passed' as result;
