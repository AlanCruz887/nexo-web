import { supabase } from "@/lib/supabase";
import type { CurrencyCode, PlannedCashFlow, PlannedCashFlowRecurrence } from "@/types/database";

export const plannedCashFlowService = {
  async list(): Promise<PlannedCashFlow[]> {
    const { data, error } = await supabase.from("planned_cash_flows").select("*").order("start_date", { ascending: true });
    if (error) throw error;
    return data;
  },
  async create(
    input: {
      name: string; currency: CurrencyCode; amountMinor: string; categoryId: string | null;
      recurrence: PlannedCashFlowRecurrence; startDate: string; endDate: string | null;
    },
    key: string,
  ) {
    const { data, error } = await supabase.rpc("create_planned_cash_flow", {
      p_name: input.name, p_currency: input.currency, p_amount_minor: input.amountMinor,
      p_category_id: input.categoryId, p_recurrence: input.recurrence,
      p_start_date: input.startDate, p_end_date: input.endDate, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async update(
    id: string,
    input: {
      name: string; amountMinor: string; categoryId: string | null;
      recurrence: PlannedCashFlowRecurrence; startDate: string; endDate: string | null;
    },
    key: string,
  ) {
    const { data, error } = await supabase.rpc("update_planned_cash_flow", {
      p_flow_id: id, p_name: input.name, p_amount_minor: input.amountMinor,
      p_category_id: input.categoryId, p_recurrence: input.recurrence,
      p_start_date: input.startDate, p_end_date: input.endDate, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async archive(id: string, key: string) {
    const { data, error } = await supabase.rpc("archive_planned_cash_flow", { p_flow_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async restore(id: string, key: string) {
    const { data, error } = await supabase.rpc("restore_planned_cash_flow", { p_flow_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
};
