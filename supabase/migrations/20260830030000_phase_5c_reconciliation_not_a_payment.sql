-- Nexo Phase 5C correction: the previous migration's reconciliation
-- (20260830020000) fixed the *numbers* (outstanding_minor correctly
-- reaches 0 for a settled pre-5B purchase) but tagged its corrective rows
-- as application_kind = 'payment' -- identical to a real bank payment.
-- get_person_statement groups "payments" by financial_event_id and shows
-- event.amount_minor as what was received; since the reconciliation
-- attached its correction to whatever real payment event happened to be
-- "most recent" for that receivable, that event's own total (e.g. a real
-- $6,500 transfer) stayed correct, but the *coverage* implied for the
-- period (paid_minor, which sums every application regardless of kind)
-- could legitimately exceed that one event's value once several
-- receivables' corrections all landed on the same representative event --
-- exactly the "Pagado $9,000 vs. Pagos recibidos $6,500" gap reported.
--
-- Fix: give reconciliation its own application_kind, excluded by
-- construction from "Pagos recibidos" (which only ever reads
-- application_kind = 'payment'), while still counting normally toward
-- paid_minor / outstanding_minor (those sums are kind-agnostic). This is a
-- labeling correction, not a balance change -- no amount anywhere is
-- recomputed differently.

alter table public.receivable_due_applications
  drop constraint due_application_direction_valid;
alter table public.receivable_due_applications
  drop constraint receivable_due_applications_application_kind_check;
alter table public.receivable_due_applications
  add constraint receivable_due_applications_application_kind_check
    check (application_kind in ('payment', 'credit', 'reconciliation', 'reversal')),
  add constraint due_application_direction_valid check (
    (application_kind in ('payment', 'credit', 'reconciliation') and amount_minor > 0 and reverses_application_id is null)
    or (application_kind = 'reversal' and amount_minor < 0 and reverses_application_id is not null)
  );

create or replace function private.reconcile_simple_receivable_due_item_history()
returns integer language plpgsql set search_path = '' as $$
declare
  target record; representative_event uuid; gap bigint; fixed_count integer := 0;
begin
  for target in
    select item.id as due_item_id, item.user_id, item.receivable_id,
      (item.amount_minor - coalesce((
        select sum(application.amount_minor) from public.receivable_due_applications application
        where application.due_item_id = item.id
      ), 0))::bigint as due_item_outstanding,
      coalesce((
        select sum(entry.amount_minor) from public.receivable_entries entry
        where entry.receivable_id = item.receivable_id
      ), 0)::bigint as true_outstanding
    from public.receivable_due_items item
    where item.installment_id is null
  loop
    gap := target.due_item_outstanding - target.true_outstanding;
    if gap > 0 then
      select entry.financial_event_id into representative_event
      from public.receivable_entries entry
      where entry.receivable_id = target.receivable_id and entry.entry_kind = 'payment'
      order by entry.created_at desc
      limit 1;
      if representative_event is not null then
        insert into public.receivable_due_applications (
          user_id, due_item_id, receivable_id, financial_event_id, amount_minor, application_kind
        ) values (
          target.user_id, target.due_item_id, target.receivable_id, representative_event, gap, 'reconciliation'
        );
        fixed_count := fixed_count + 1;
      end if;
    end if;
  end loop;
  return fixed_count;
end;
$$;

-- Re-running is safe (idempotent): any due item this already fixed now has
-- gap = 0 and is skipped. This only reaches receivables nobody has
-- reconciled yet.
select private.reconcile_simple_receivable_due_item_history();

-- One-time relabel of whatever the *previous* (mis-tagged) run inserted.
-- A row created by that run is identifiable safely and generally, without
-- guessing from amounts or descriptions: create_person_payment/
-- apply_person_credit always insert receivable_due_applications and their
-- matching receivable_entries row in the very same transaction, so a
-- genuine application's created_at is (to the microsecond) the same as its
-- own financial_event's created_at. The previous migration's reconciliation
-- ran separately, at deploy time, days/weeks after the historical event it
-- attached itself to -- its created_at is provably later. Nothing is
-- reclassified unless that gap is unambiguous (over a full day), so a
-- genuine payment recorded any time after its own event (which never
-- happens on the live path, but costs nothing to guard) is left untouched.
do $$
declare relabeled_count integer;
begin
  create temporary table legacy_reconciliation_candidates on commit drop as
  select application.id
  from public.receivable_due_applications application
  join public.receivable_due_items item on item.id = application.due_item_id
  join public.financial_events event on event.id = application.financial_event_id
  where application.application_kind = 'payment'
    and item.installment_id is null
    and application.created_at > event.created_at + interval '1 day';

  select count(*) into relabeled_count from legacy_reconciliation_candidates;
  if relabeled_count > 0 then
    alter table public.receivable_due_applications disable trigger due_applications_are_immutable;
    update public.receivable_due_applications
      set application_kind = 'reconciliation'
      where id in (select id from legacy_reconciliation_candidates);
    alter table public.receivable_due_applications enable trigger due_applications_are_immutable;
    raise notice 'Relabeled % pre-existing application(s) from payment to reconciliation', relabeled_count;
  end if;
end;
$$;

-- Additive: how much of a period's "covered" figure came from reconciling
-- old history rather than a payment the person actually made just now, so
-- the UI can explain the gap instead of leaving it silently unaccounted
-- for.
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
        as credit_applied_minor,
      coalesce(sum(application.amount_minor) filter (where application.application_kind = 'reconciliation'), 0)::bigint
        as reconciled_minor
    from public.receivable_due_item_balances balance
    left join public.receivable_due_applications application on application.due_item_id = balance.id
    where balance.user_id = command_user_id and balance.contact_id = p_contact_id
    group by balance.id, balance.user_id, balance.receivable_id, balance.contact_id,
      balance.installment_id, balance.card_id, balance.statement_date,
      balance.payment_due_date, balance.amount_minor, balance.paid_minor,
      balance.outstanding_minor, balance.sequence_number, balance.description,
      balance.purchase_amount_minor, balance.currency, balance.created_at
  ), eligible as (
    -- Reverted to the original, unconditional `card_id is null` branch: a
    -- simple (non-card) concept stays listed for the period it was assigned
    -- to even once fully covered, showing paid/pendiente = 0 instead of
    -- disappearing -- matching how a card/MSI concept already behaves in
    -- the third branch, and what the product asked for explicitly. The
    -- invariant (remaining_minor never exceeds total_outstanding_minor) is
    -- protected by outstanding_minor always being accurate now
    -- (reconciliation fixes historical drift once; the live payment path
    -- never lets it drift again), not by hiding items.
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
      'reconciled_minor', coalesce(period.reconciled_minor, 0)::text,
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
      sum(item.reconciled_minor)::bigint as reconciled_minor,
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
        'reconciled_minor', item.reconciled_minor::text,
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
