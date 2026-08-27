import { supabase } from "@/lib/supabase";
import type { AccountEditInput, AccountFormInput } from "@/schemas/account";
import type { AccountBalance } from "@/types/database";

export const accountService = {
  async list(): Promise<AccountBalance[]> {
    const { data, error } = await supabase
      .from("account_balances")
      .select("*")
      .order("is_active", { ascending: false })
      .order("created_at", { ascending: true });
    if (error) throw error;
    return data;
  },

  async get(accountId: string): Promise<AccountBalance> {
    const { data, error } = await supabase
      .from("account_balances")
      .select("*")
      .eq("id", accountId)
      .single();
    if (error) throw error;
    return data;
  },

  async create(input: AccountFormInput, openingBalanceMinor: string, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("create_account", {
      p_name: input.name,
      p_type: input.type,
      p_currency: input.currency,
      p_opening_balance_minor: openingBalanceMinor,
      p_institution: input.institution || null,
      p_last4: input.last4 || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async update(accountId: string, input: AccountEditInput, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("update_account", {
      p_account_id: accountId,
      p_name: input.name,
      p_type: input.type,
      p_institution: input.institution || null,
      p_last4: input.last4 || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async archive(accountId: string, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("archive_account", {
      p_account_id: accountId,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async restore(accountId: string, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("restore_account", {
      p_account_id: accountId,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
};
