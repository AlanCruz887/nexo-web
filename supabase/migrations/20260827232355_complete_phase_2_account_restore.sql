-- Complete Phase 2 without changing the immutable financial-event model.
-- Restoring an account only changes whether it can receive new activity; its
-- balance and history continue to come from the existing immutable entries.

create function public.restore_account(p_account_id uuid, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_command_result_id uuid := gen_random_uuid();
  resolved_command_result_id uuid;
  command_payload jsonb := jsonb_build_object('account_id', p_account_id);
begin
  resolved_command_result_id := private.resolve_financial_command(
    command_user_id,
    p_idempotency_key,
    'restore_account',
    command_payload,
    proposed_command_result_id
  );
  if resolved_command_result_id <> proposed_command_result_id then
    return p_account_id;
  end if;

  update public.accounts
  set is_active = true
  where id = p_account_id
    and user_id = command_user_id
    and not is_active;

  if found then
    insert into public.audit_events (id, user_id, action, entity_type, entity_id)
    values (
      proposed_command_result_id,
      command_user_id,
      'account_restored',
      'account',
      p_account_id
    );
  elsif not exists (
    select 1
    from public.accounts
    where id = p_account_id and user_id = command_user_id
  ) then
    raise exception 'NEXO_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  return p_account_id;
end;
$$;

revoke all on function public.restore_account(uuid, text) from public, anon;
grant execute on function public.restore_account(uuid, text) to authenticated;

-- The product action is "delete", while the financial implementation remains
-- an immutable reversal. Keep that distinction explicit in the audit trail.
create or replace function public.reverse_transaction(
  p_event_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  command_user_id uuid := private.require_user();
  proposed_reversal_id uuid := gen_random_uuid();
  resolved_reversal_id uuid;
  original_kind text;
  command_payload jsonb := jsonb_build_object('event_id', p_event_id);
begin
  resolved_reversal_id := private.resolve_financial_command(
    command_user_id, p_idempotency_key, 'reverse_transaction', command_payload, proposed_reversal_id
  );
  if resolved_reversal_id <> proposed_reversal_id then return resolved_reversal_id; end if;

  select kind into original_kind from public.financial_events
  where id = p_event_id and user_id = command_user_id;
  if original_kind is null then raise exception 'NEXO_TRANSACTION_NOT_FOUND' using errcode = 'P0002'; end if;
  if original_kind = 'transfer' then raise exception 'NEXO_USE_TRANSFER_REVERSAL' using errcode = '23514'; end if;

  perform private.reverse_event(command_user_id, p_event_id, proposed_reversal_id, 'Reversión de movimiento');
  insert into public.audit_events (user_id, action, entity_type, entity_id, metadata)
  values (
    command_user_id, 'transaction_deleted', 'financial_event', p_event_id,
    jsonb_build_object('reversal_event_id', proposed_reversal_id)
  );
  return proposed_reversal_id;
end;
$$;

revoke all on function public.reverse_transaction(uuid, text) from public, anon;
grant execute on function public.reverse_transaction(uuid, text) to authenticated;
