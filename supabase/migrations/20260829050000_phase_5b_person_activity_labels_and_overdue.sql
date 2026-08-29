-- Nexo Phase 5B correction: two more read-only projection fields, no new
-- balance logic. The person detail screen needs to (a) call out how much of
-- the current period is already overdue, and (b) label each purchase in the
-- activity feed as shared / for-someone-else / an MSI purchase without the
-- frontend re-deriving any of that from raw events.

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
      balance.currency, balance.created_at
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
      jsonb_agg(jsonb_build_object(
        'id', item.id, 'description', item.description,
        'statement_date', item.statement_date, 'payment_due_date', item.payment_due_date,
        'amount_minor', item.amount_minor::text, 'paid_minor', item.paid_minor::text,
        'outstanding_minor', item.outstanding_minor::text,
        'credit_applied_minor', item.credit_applied_minor::text,
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

-- contact_activity: label each purchase without the frontend re-deriving it.
-- personal_amount_minor and installment_count are read straight off the
-- underlying financial_event/installment_plans, same tables
-- get_person_collection_period and installment_plan_summaries already read.
create or replace view public.contact_activity with (security_invoker = true) as
select event.id as event_id, receivable.contact_id, event.user_id, event.kind,
  sum(entry.amount_minor)::bigint as amount_minor, event.description, event.occurred_on,
  event.notes, event.created_at, receivable.currency,
  case when event.kind = 'person_payment' then 'payment' else 'purchase' end as activity_type,
  null::uuid as application_id, event.personal_amount_minor, plan.installment_count
from public.receivable_entries entry
join public.receivables receivable on receivable.id = entry.receivable_id
join public.financial_events event on event.id = entry.financial_event_id
left join public.installment_plans plan on plan.purchase_event_id = event.id
where event.kind not in ('reversal', 'person_credit_application')
  and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id)
group by event.id, receivable.contact_id, receivable.currency, event.personal_amount_minor, plan.installment_count
union all
select event.id as event_id, receivable.contact_id, event.user_id, event.kind,
  -application.amount_minor as amount_minor,
  case when installment.id is not null
    then purchase_event.description || ' · Mensualidad ' || item.sequence_number::text || ' de ' || plan.installment_count::text
    else purchase_event.description end as description,
  event.occurred_on, event.notes, event.created_at, receivable.currency,
  'credit_applied'::text as activity_type,
  application.id as application_id, null::bigint as personal_amount_minor, null::smallint as installment_count
from public.receivable_due_applications application
join public.receivable_due_items item on item.id = application.due_item_id
join public.receivables receivable on receivable.id = item.receivable_id
join public.financial_events purchase_event on purchase_event.id = receivable.source_event_id
join public.financial_events event on event.id = application.financial_event_id
left join public.installments installment on installment.id = item.installment_id
left join public.installment_plans plan on plan.id = installment.plan_id
where application.application_kind = 'credit'
  and not exists (select 1 from public.financial_events reversal where reversal.reverses_event_id = event.id);
