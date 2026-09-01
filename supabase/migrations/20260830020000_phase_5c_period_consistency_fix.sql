-- Nexo Phase 5C correction: a real financial inconsistency, confirmed by
-- reproduction, not a display bug.
--
-- Root cause (two parts of the same defect):
--
-- 1. get_person_collection_period's `eligible` CTE included every non-card
--    (account) due item unconditionally via `(balance.card_id is null)` --
--    with no `outstanding_minor > 0` check. A fully paid account purchase
--    never left "this period"; it kept contributing its full original
--    amount forever, because subtotal_minor/remaining_minor sum
--    `item.amount_minor`/`item.outstanding_minor` over whatever `eligible`
--    returns, without re-checking whether that item is genuinely still
--    owed.
--
-- 2. The one-time backfill in 20260829031852 (the original 5B migration)
--    seeded receivable_due_items.amount_minor from
--    receivable.original_amount_minor for every receivable that already
--    existed at that point -- with no regard for payments those
--    receivables had already received through create_person_payment
--    before receivable_due_items existed at all. receivable_entries
--    (the real source of truth) correctly reflected those old payments
--    the whole time; the newly-backfilled schedule did not, and had no
--    way to find out, because nothing ties a pre-existing payment event
--    back to a due item that did not exist yet when that payment was
--    made.
--
-- Together: a receivable paid off before 5B shipped kept showing its full
-- original amount as "this period", inflating subtotal_minor/remaining_minor
-- past total_outstanding_minor (which stayed correct, since it only reads
-- receivable_entries). Reproduced deterministically: a fully-paid
-- non-card due item with its receivable_due_applications removed (the
-- exact shape 1's backfill produces) makes remaining_minor exceed
-- total_outstanding_minor every time; this migration is what makes that
-- reproduction pass instead.
--
-- The fix has two parts, both inside the domain/projection layer -- no
-- workaround in React, in get_person_statement, or in any exporter:
--
-- A) eligible now requires outstanding_minor > 0 for the `card_id is null`
--    branch specifically -- the one with no calendar/statement concept
--    anchoring it, so a settled item there has no reason left to appear.
--    The `statement_date = selected.statement_date` branch (the current
--    card/MSI cycle) is deliberately left unconditional: an installment
--    that gets paid off within its own period must keep counting toward
--    subtotal_minor ("a pagar este periodo" stays the fixed original
--    target of that period, per the already-tested Caso B behavior) while
--    remaining_minor correctly nets to zero for it. Adding the same
--    outstanding_minor filter there was tried and reverted: it made the
--    selected statement's own paid-off items vanish from subtotal_minor
--    mid-period, which silently shrinks "a pagar este periodo" instead of
--    showing it paid, and broke the existing overpayment-classification
--    test (person_statement.test.sql) for the reason above.
--
-- B) A one-time reconciliation pass for existing data: for every simple
--    (non-installment) due item whose currently-computed outstanding
--    exceeds what receivable_entries says the receivable actually owes,
--    insert exactly that difference as a receivable_due_applications row,
--    attached to a real payment event that already reduced that
--    receivable (found in receivable_entries itself -- nothing is
--    fabricated). This does not touch receivable_entries (already
--    correct), does not delete any row, and is idempotent: after it runs
--    once, the gap it was closing is zero, so running it again is a
--    no-op. installment due items are excluded on purpose -- they are
--    always created fresh, atomically with the purchase, by
--    create_installment_receivable_due_items; they cannot have
--    pre-existing, un-scheduled payment history and do not need this.

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
    where (balance.card_id is null and balance.outstanding_minor > 0)
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

-- Part B: one-time reconciliation for existing data, re-callable and
-- idempotent (kept as a function, not inline DML, specifically so it stays
-- testable and re-runnable rather than a one-shot statement).
create function private.reconcile_simple_receivable_due_item_history()
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
          target.user_id, target.due_item_id, target.receivable_id, representative_event, gap, 'payment'
        );
        fixed_count := fixed_count + 1;
      end if;
    end if;
  end loop;
  return fixed_count;
end;
$$;

select private.reconcile_simple_receivable_due_item_history();
