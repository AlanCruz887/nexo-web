import { supabase } from "@/lib/supabase";
import type { CurrencyCode, GoalBalance, GoalEntryActivity } from "@/types/database";

export const goalService = {
  async list(): Promise<GoalBalance[]> {
    const { data, error } = await supabase.from("goal_balances").select("*").order("created_at", { ascending: false });
    if (error) throw error;
    return data;
  },
  async get(id: string): Promise<GoalBalance | null> {
    const { data, error } = await supabase.from("goal_balances").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data;
  },
  async movements(goalId: string): Promise<GoalEntryActivity[]> {
    const { data, error } = await supabase.from("goal_entry_activity").select("*").eq("goal_id", goalId)
      .order("occurred_on", { ascending: false }).order("created_at", { ascending: false });
    if (error) throw error;
    return data;
  },
  async create(input: { name: string; currency: CurrencyCode; targetMinor: string; targetDate: string | null; linkedAccountId: string | null; icon: string | null }, key: string) {
    const { data, error } = await supabase.rpc("create_goal", {
      p_name: input.name, p_currency: input.currency, p_target_minor: input.targetMinor,
      p_target_date: input.targetDate, p_linked_account_id: input.linkedAccountId, p_icon: input.icon,
      p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async update(id: string, input: { name: string; targetMinor: string; targetDate: string | null; linkedAccountId: string | null; icon: string | null }, key: string) {
    const { data, error } = await supabase.rpc("update_goal", {
      p_goal_id: id, p_name: input.name, p_target_minor: input.targetMinor,
      p_target_date: input.targetDate, p_linked_account_id: input.linkedAccountId, p_icon: input.icon,
      p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async setStatus(id: string, status: "active" | "paused", key: string) {
    const { data, error } = await supabase.rpc("set_goal_status", { p_goal_id: id, p_status: status, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async archive(id: string, key: string) {
    const { data, error } = await supabase.rpc("archive_goal", { p_goal_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async restore(id: string, key: string) {
    const { data, error } = await supabase.rpc("restore_goal", { p_goal_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async contribute(input: { goalId: string; amountMinor: string; sourceAccountId: string; moveRealMoney: boolean; occurredOn: string; notes: string | null }, key: string) {
    const { data, error } = await supabase.rpc("contribute_to_goal", {
      p_goal_id: input.goalId, p_amount_minor: input.amountMinor, p_source_account_id: input.sourceAccountId,
      p_move_real_money: input.moveRealMoney, p_occurred_on: input.occurredOn, p_notes: input.notes,
      p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async withdraw(input: { goalId: string; amountMinor: string; accountId: string | null; moveRealMoney: boolean; destinationAccountId: string | null; occurredOn: string; notes: string | null }, key: string) {
    const { data, error } = await supabase.rpc("withdraw_from_goal", {
      p_goal_id: input.goalId, p_amount_minor: input.amountMinor, p_account_id: input.accountId,
      p_move_real_money: input.moveRealMoney, p_destination_account_id: input.destinationAccountId,
      p_occurred_on: input.occurredOn, p_notes: input.notes, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async reverseEntry(entryId: string, key: string) {
    const { data, error } = await supabase.rpc("reverse_goal_entry", { p_entry_id: entryId, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
};
