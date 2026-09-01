-- Nexo Phase 5C correction #2: reconcile_simple_receivable_due_item_history
-- (both the original 20260830020000 version and the relabeled-only
-- 20260830030000 version) attributed a due item's *entire* historical gap
-- to a single "representative event" -- the most recent 'payment'-kind row
-- in receivable_entries for that receivable -- with no check on whether
-- that event's own amount_minor had any capacity left. Confirmed by
-- reproduction: a receivable already fully settled via one event, plus a
-- later, unrelated, smaller real payment that (because the schedule was
-- still stale) also touched the same due item, causes the *entire* old
-- gap to be dumped onto the newer, smaller event -- inflating "Cubierto"
-- past "Total del periodo" and driving "Pendiente"/"Te debe en total"
-- negative. This is a capacity/attribution bug, not the labeling bug
-- 20260830030000 already fixed.
--
-- Fix: reconcile per (due_item, financial_event) pair instead of per
-- receivable. receivable_entries already carries, for every event that
-- ever touched a receivable, the *exact* real amount that event
-- contributed (unique on (financial_event_id, receivable_id), populated
-- solely by apply_person_amount_to_due_items's own capacity-safe FIFO).
-- Reading that per-pair truth directly -- instead of collapsing it into
-- "whichever event is most recent" -- means an event can never be
-- credited with more than it ever actually contributed to that specific
-- receivable, regardless of how many due items or receivables it touches.
--
-- Also fixes the precondition that let this manifest at payment time:
-- apply_person_amount_to_due_items decides "is this due item still owed"
-- from the schedule (receivable_due_item_balances), not from the ledger.
-- If the schedule is stale (the exact case reconciliation exists to fix),
-- a brand new payment can land on a due item the ledger already says is
-- settled. create_person_payment and apply_person_credit now reconcile
-- this contact's own due items (scoped, not global) immediately before
-- applying, so the schedule is never stale at the moment a payment needs
-- to read it.

drop function if exists private.reconcile_simple_receivable_due_item_history();

create function private.reconcile_simple_receivable_due_item_history(
  p_user_id uuid default null,
  p_contact_id uuid default null,
  p_currency text default null
)
returns integer language plpgsql set search_path = '' as $$
declare
  target record; fixed_count integer := 0;
begin
  -- One row per (due item, financial event) that ever contributed to its
  -- receivable, per the ledger -- capped, by construction, at exactly what
  -- that event contributed to that specific receivable (receivable_entries
  -- is unique on (financial_event_id, receivable_id), and every 'payment'
  -- entry there was itself written by apply_person_amount_to_due_items's
  -- own least()-bounded FIFO, so it can never overstate an event's real
  -- contribution).
  for target in
    select item.id as due_item_id, item.user_id, item.receivable_id,
      entry.financial_event_id,
      (-entry.amount_minor)::bigint as event_contribution,
      coalesce((
        select sum(application.amount_minor) from public.receivable_due_applications application
        where application.due_item_id = item.id
          and application.financial_event_id = entry.financial_event_id
      ), 0)::bigint as already_tracked
    from public.receivable_due_items item
    join public.receivables receivable on receivable.id = item.receivable_id
    join public.receivable_entries entry on entry.receivable_id = item.receivable_id
      and entry.entry_kind = 'payment'
    where item.installment_id is null
      and (p_user_id is null or item.user_id = p_user_id)
      and (p_contact_id is null or receivable.contact_id = p_contact_id)
      and (p_currency is null or receivable.currency = p_currency)
      -- Never attribute reconciliation to a payment event that was itself
      -- later reversed -- its true remaining contribution is netted
      -- elsewhere in receivable_entries via the reversal's own entry, not
      -- collapsible into this per-event view.
      and not exists (
        select 1 from public.financial_events reversal
        where reversal.reverses_event_id = entry.financial_event_id
      )
  loop
    if target.event_contribution > target.already_tracked then
      insert into public.receivable_due_applications (
        user_id, due_item_id, receivable_id, financial_event_id, amount_minor, application_kind
      ) values (
        target.user_id, target.due_item_id, target.receivable_id, target.financial_event_id,
        target.event_contribution - target.already_tracked, 'reconciliation'
      );
      fixed_count := fixed_count + 1;
    end if;
  end loop;
  return fixed_count;
end;
$$;

-- Reconcile this contact's own due items right before deciding what's
-- still owed, so a payment or credit application never reads a stale
-- schedule. Scoped to (user, contact, currency) -- cheap, and never
-- touches another user's or another currency's data.
create or replace function private.apply_person_amount_to_due_items(
  command_user_id uuid, target_contact_id uuid, target_currency text,
  source_event_id uuid, available_amount bigint, source_kind text, application_date date
)
returns bigint language plpgsql set search_path = '' as $$
declare
  target_item record; applied_amount bigint; remaining_amount bigint := available_amount;
begin
  if source_kind not in ('payment', 'credit') then
    raise exception 'NEXO_INVALID_PERSON_APPLICATION_KIND' using errcode = '22023'; end if;
  perform private.reconcile_simple_receivable_due_item_history(command_user_id, target_contact_id, target_currency);
  for target_item in
    select balance.* from public.receivable_due_item_balances balance
    where balance.user_id = command_user_id and balance.contact_id = target_contact_id
      and balance.currency = target_currency and balance.outstanding_minor > 0
    order by
      case when balance.payment_due_date < application_date then 0 else 1 end,
      balance.payment_due_date, balance.statement_date nulls first,
      balance.sequence_number, balance.created_at, balance.id
  loop
    exit when remaining_amount = 0;
    applied_amount := least(remaining_amount, target_item.outstanding_minor);
    insert into public.receivable_due_applications (
      user_id, due_item_id, receivable_id, financial_event_id, amount_minor, application_kind
    ) values (command_user_id, target_item.id, target_item.receivable_id,
      source_event_id, applied_amount, source_kind);
    remaining_amount := remaining_amount - applied_amount;
  end loop;
  insert into public.receivable_entries (
    user_id, receivable_id, financial_event_id, amount_minor, entry_kind
  )
  select command_user_id, application.receivable_id, source_event_id,
    -sum(application.amount_minor), 'payment'
  from public.receivable_due_applications application
  where application.financial_event_id = source_event_id
    and application.user_id = command_user_id
    and application.application_kind = source_kind
  group by application.receivable_id
  on conflict (financial_event_id, receivable_id) do nothing;
  return remaining_amount;
end;
$$;

-- One-time repair of whatever the two prior (attribution-buggy) versions
-- of reconcile_simple_receivable_due_item_history already inserted. Never
-- touches receivable_entries or financial_events -- only reverses
-- (insert-only, per the existing immutability design) the specific
-- receivable_due_applications rows proven, per (due_item, financial_event)
-- pair, to exceed what that event really contributed to that receivable.
do $$
declare
  pair record; excess bigint; row_to_reverse record; reversed_amount bigint;
begin
  for pair in
    select app.due_item_id, app.financial_event_id, item.user_id,
      coalesce(sum(app.amount_minor) filter (where app.application_kind in ('payment', 'reconciliation')), 0)::bigint as applied,
      coalesce((
        select -entry.amount_minor from public.receivable_entries entry
        where entry.receivable_id = item.receivable_id
          and entry.financial_event_id = app.financial_event_id
          and entry.entry_kind = 'payment'
      ), 0)::bigint as true_contribution
    from public.receivable_due_applications app
    join public.receivable_due_items item on item.id = app.due_item_id
    where item.installment_id is null
      and app.application_kind in ('payment', 'reconciliation')
    group by app.due_item_id, app.financial_event_id, item.user_id, item.receivable_id
  loop
    excess := pair.applied - pair.true_contribution;
    continue when excess <= 0;
    -- Reconciliation-tagged rows for this pair are reversed first (100%
    -- certain to be reconstruction, never a real payment); if excess
    -- remains, the most-recently-inserted 'payment'-tagged row for this
    -- pair is next -- the live path always writes its own application in
    -- the same transaction as the event, so a mistagged reconciliation
    -- row (inserted by a later migration run) is reliably the newer one
    -- whenever both exist for the same pair.
    for row_to_reverse in
      select id, amount_minor from public.receivable_due_applications
      where due_item_id = pair.due_item_id and financial_event_id = pair.financial_event_id
        and application_kind in ('payment', 'reconciliation')
        and not exists (
          select 1 from public.receivable_due_applications reversal
          where reversal.reverses_application_id = receivable_due_applications.id
        )
      order by (application_kind = 'reconciliation') desc, created_at desc
    loop
      exit when excess <= 0;
      reversed_amount := least(excess, row_to_reverse.amount_minor);
      insert into public.receivable_due_applications (
        user_id, due_item_id, receivable_id, financial_event_id, amount_minor,
        application_kind, reverses_application_id
      )
      select pair.user_id, pair.due_item_id, app.receivable_id, pair.financial_event_id,
        -reversed_amount, 'reversal', row_to_reverse.id
      from public.receivable_due_applications app where app.id = row_to_reverse.id;
      excess := excess - reversed_amount;
    end loop;
  end loop;
end;
$$;

-- Rebuild whatever genuine gaps remain, now correctly attributed per
-- (due item, financial event) instead of guessed at the receivable level.
select private.reconcile_simple_receivable_due_item_history();
