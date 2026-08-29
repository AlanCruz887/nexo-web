-- Nexo Phase 5C: person statement (view + export). This does not add a new
-- balance engine. get_person_collection_period stays the single source for
-- "a pagar este periodo" vs "te debe en total"; get_person_statement calls
-- it and adds two things read-only from the same ledger already in place:
-- how much of each real payment landed on this period vs advanced future
-- obligations vs became saldo a favor, and the total amount of the purchase
-- behind each concept (so a shared purchase can show "de un total de $X"
-- without a second lookup from the client).

-- Additive: the total purchase amount behind a due item, so the statement
-- can show "Total de la compra" next to the person's own share without a
-- second query. Nothing about paid/outstanding math changes.
create or replace view public.receivable_due_item_balances with (security_invoker = true) as
select item.id, item.user_id, item.receivable_id, receivable.contact_id, item.installment_id,
  item.card_id, item.statement_date, item.payment_due_date, item.amount_minor,
  coalesce(sum(application.amount_minor), 0)::bigint as paid_minor,
  (item.amount_minor - coalesce(sum(application.amount_minor), 0))::bigint as outstanding_minor,
  item.sequence_number, event.description, receivable.currency, item.created_at,
  event.amount_minor as purchase_amount_minor
from public.receivable_due_items item
join public.receivables receivable on receivable.id = item.receivable_id
join public.financial_events event on event.id = receivable.source_event_id
left join public.receivable_due_applications application on application.due_item_id = item.id
where not exists (
  select 1 from public.financial_events reversal
  where reversal.reverses_event_id = receivable.source_event_id
)
group by item.id, receivable.contact_id, event.description, event.amount_minor, receivable.currency;

-- Additive: overdue_since (earliest overdue due date) and purchase_amount_minor
-- per concept. The eligibility/period-selection logic is untouched.
create or replace function public.get_person_collection_period(p_contact_id uuid, p_as_of_date date default current_date)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user(); result jsonb;
begin
  if not exists (select 1 from public.contacts where id = p_contact_id and user_id = command_user_id) then
    raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;
  with currencies as (
    select distinct receivable.currency
    from public.receivables receivable
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    union
    select entry.currency from public.person_credit_entries entry
    where entry.user_id = command_user_id and entry.contact_id = p_contact_id
  ), selected_statements as (
    select currency.currency, card.id as card_id,
      coalesce(
        min(item.statement_date) filter (where item.payment_due_date >= p_as_of_date),
        max(item.statement_date)
      ) as statement_date
    from currencies currency
    join public.receivables receivable on receivable.user_id = command_user_id
      and receivable.contact_id = p_contact_id and receivable.currency = currency.currency
    join public.receivable_due_items item on item.receivable_id = receivable.id and item.card_id is not null
    join public.credit_cards card on card.id = item.card_id
    group by currency.currency, card.id
  ), balances as (
    select balance.*,
      coalesce(sum(application.amount_minor) filter (where application.application_kind = 'credit'), 0)::bigint
        as credit_applied_minor
    from public.receivable_due_item_balances balance
    left join public.receivable_due_applications application on application.due_item_id = balance.id
    where balance.user_id = command_user_id and balance.contact_id = p_contact_id
    group by balance.id, balance.user_id, balance.receivable_id, balance.contact_id,
      balance.installment_id, balance.card_id, balance.statement_date,
      balance.payment_due_date, balance.amount_minor, balance.paid_minor,
      balance.outstanding_minor, balance.sequence_number, balance.description,
      balance.purchase_amount_minor, balance.currency, balance.created_at
  ), eligible as (
    select balance.* from balances balance
    left join selected_statements selected on selected.currency = balance.currency
      and selected.card_id = balance.card_id
    where (balance.card_id is null)
      or (balance.payment_due_date < p_as_of_date and balance.outstanding_minor > 0)
      or (balance.statement_date = selected.statement_date)
  ), totals as (
    select receivable.currency,
      coalesce(sum(entry.amount_minor), 0)::bigint as total_outstanding_minor
    from public.receivables receivable
    join public.receivable_entries entry on entry.receivable_id = receivable.id
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
    group by receivable.currency
  ), credits as (
    select currency, coalesce(sum(amount_minor), 0)::bigint credit_balance_minor
    from public.person_credit_entries
    where user_id = command_user_id and contact_id = p_contact_id group by currency
  )
  select jsonb_build_object(
    'as_of_date', p_as_of_date,
    'periods', coalesce(jsonb_agg(jsonb_build_object(
      'currency', currency.currency,
      'period_start', period.period_start,
      'payment_due_date', period.payment_due_date,
      'subtotal_minor', coalesce(period.subtotal_minor, 0)::text,
      'paid_minor', coalesce(period.paid_minor, 0)::text,
      'credit_applied_minor', coalesce(period.credit_applied_minor, 0)::text,
      'remaining_minor', coalesce(period.remaining_minor, 0)::text,
      'overdue_minor', coalesce(period.overdue_minor, 0)::text,
      'overdue_since', period.overdue_since,
      'total_outstanding_minor', coalesce(total.total_outstanding_minor, 0)::text,
      'credit_balance_minor', coalesce(credit.credit_balance_minor, 0)::text,
      'concepts', coalesce(period.concepts, '[]'::jsonb)
    ) order by currency.currency), '[]'::jsonb)
  ) into result
  from currencies currency
  left join totals total on total.currency = currency.currency
  left join credits credit on credit.currency = currency.currency
  left join lateral (
    select min(coalesce(item.statement_date, item.payment_due_date)) as period_start,
      max(item.payment_due_date) as payment_due_date,
      sum(item.amount_minor)::bigint as subtotal_minor,
      sum(item.paid_minor)::bigint as paid_minor,
      sum(item.credit_applied_minor)::bigint as credit_applied_minor,
      sum(item.outstanding_minor)::bigint as remaining_minor,
      coalesce(sum(item.outstanding_minor) filter (where item.payment_due_date < p_as_of_date), 0)::bigint
        as overdue_minor,
      min(item.payment_due_date) filter (where item.payment_due_date < p_as_of_date and item.outstanding_minor > 0)
        as overdue_since,
      jsonb_agg(jsonb_build_object(
        'id', item.id, 'description', item.description,
        'statement_date', item.statement_date, 'payment_due_date', item.payment_due_date,
        'amount_minor', item.amount_minor::text, 'paid_minor', item.paid_minor::text,
        'outstanding_minor', item.outstanding_minor::text,
        'credit_applied_minor', item.credit_applied_minor::text,
        'purchase_amount_minor', item.purchase_amount_minor::text,
        'installment_id', item.installment_id,
        'installment_number', item.sequence_number,
        'installment_count', concept_plan.installment_count
      ) order by item.payment_due_date, item.sequence_number, item.created_at) as concepts
    from eligible item
    left join public.installments concept_installment on concept_installment.id = item.installment_id
    left join public.installment_plans concept_plan on concept_plan.id = concept_installment.plan_id
    where item.currency = currency.currency
  ) period on true;
  return coalesce(result, jsonb_build_object('as_of_date', p_as_of_date, 'periods', '[]'::jsonb));
end;
$$;

-- New: person statement. Calls get_person_collection_period for the period
-- math (no duplication) and adds a read-only breakdown of each real payment
-- against the exact same due items get_person_collection_period already
-- classifies as "this period" — so a payment above what's due is shown as
-- applied to the period, applied to future obligations, or turned into
-- saldo a favor, matching exactly what create_person_payment did, never a
-- client-side amount - due_amount guess.
create function public.get_person_statement(p_contact_id uuid, p_as_of_date date default current_date)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare
  command_user_id uuid := private.require_user();
  period_result jsonb; payments_result jsonb;
begin
  if not exists (select 1 from public.contacts where id = p_contact_id and user_id = command_user_id) then
    raise exception 'NEXO_CONTACT_NOT_FOUND' using errcode = 'P0002'; end if;

  period_result := public.get_person_collection_period(p_contact_id, p_as_of_date);

  with concept_ids as (
    select distinct (concept->>'id')::uuid as due_item_id
    from jsonb_array_elements(period_result->'periods') currency_period,
      jsonb_array_elements(currency_period->'concepts') concept
  ), applications as (
    select event.id as event_id, event.occurred_on, event.created_at, event.amount_minor,
      receivable.currency, account.name as account_name,
      sum(application.amount_minor) filter (where concept_ids.due_item_id is not null) as period_minor,
      sum(application.amount_minor) filter (where concept_ids.due_item_id is null) as future_minor
    from public.receivable_due_applications application
    join public.receivable_due_items item on item.id = application.due_item_id
    join public.receivables receivable on receivable.id = item.receivable_id
    join public.financial_events event on event.id = application.financial_event_id
    left join public.account_entries entry on entry.financial_event_id = event.id
    left join public.accounts account on account.id = entry.account_id
    left join concept_ids on concept_ids.due_item_id = item.id
    where receivable.user_id = command_user_id and receivable.contact_id = p_contact_id
      and application.application_kind = 'payment'
      and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id)
    group by event.id, event.occurred_on, event.created_at, event.amount_minor, receivable.currency, account.name
  ), credit_generated as (
    select financial_event_id, sum(amount_minor) as credit_minor
    from public.person_credit_entries
    where user_id = command_user_id and contact_id = p_contact_id and entry_kind = 'credit_created'
    group by financial_event_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_id', applications.event_id,
    'occurred_on', applications.occurred_on,
    'currency', applications.currency,
    'account_name', applications.account_name,
    'amount_minor', applications.amount_minor::text,
    'applied_to_period_minor', coalesce(applications.period_minor, 0)::text,
    'applied_to_future_minor', coalesce(applications.future_minor, 0)::text,
    'credit_generated_minor', coalesce(credit_generated.credit_minor, 0)::text
  ) order by applications.occurred_on desc, applications.created_at desc), '[]'::jsonb)
  into payments_result
  from applications
  left join credit_generated on credit_generated.financial_event_id = applications.event_id;

  return period_result || jsonb_build_object('payments', payments_result);
end;
$$;

revoke all on function public.get_person_statement(uuid, date) from public, anon;
grant execute on function public.get_person_statement(uuid, date) to authenticated;
