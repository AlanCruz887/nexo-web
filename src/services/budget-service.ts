import { supabase } from "@/lib/supabase";
import type { BudgetMovement, BudgetPeriodSummary, CurrencyCode } from "@/types/database";

export const budgetService = {
  async forPeriod(month: string, currency?: CurrencyCode): Promise<BudgetPeriodSummary[]> {
    const { data, error } = await supabase.rpc("get_budgets_for_period", { p_month: month, p_currency: currency ?? null });
    if (error) throw error;
    return data;
  },
  async movements(categoryId: string, currency: CurrencyCode, month: string): Promise<BudgetMovement[]> {
    const { data, error } = await supabase.rpc("get_budget_movements", { p_category_id: categoryId, p_currency: currency, p_month: month });
    if (error) throw error;
    return data;
  },
  async create(input: { categoryId: string; currency: CurrencyCode; limitMinor: string; effectiveFromMonth: string | null; periodMonth: string | null }, key: string) {
    const { data, error } = await supabase.rpc("create_budget", {
      p_category_id: input.categoryId, p_currency: input.currency, p_limit_minor: input.limitMinor,
      p_effective_from_month: input.effectiveFromMonth, p_period_month: input.periodMonth, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async changeRecurringFromMonth(input: { categoryId: string; currency: CurrencyCode; limitMinor: string; effectiveFromMonth: string }, key: string) {
    const { data, error } = await supabase.rpc("update_recurring_budget_from_month", {
      p_category_id: input.categoryId, p_currency: input.currency, p_limit_minor: input.limitMinor,
      p_effective_from_month: input.effectiveFromMonth, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async updateExceptionLimit(budgetId: string, limitMinor: string, key: string) {
    const { data, error } = await supabase.rpc("update_budget_exception_limit", { p_budget_id: budgetId, p_limit_minor: limitMinor, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async stopRecurring(input: { categoryId: string; currency: CurrencyCode; lastActiveMonth: string }, key: string) {
    const { data, error } = await supabase.rpc("stop_recurring_budget", {
      p_category_id: input.categoryId, p_currency: input.currency, p_last_active_month: input.lastActiveMonth, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async archive(budgetId: string, key: string) {
    const { data, error } = await supabase.rpc("archive_budget", { p_budget_id: budgetId, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async restore(budgetId: string, key: string) {
    const { data, error } = await supabase.rpc("restore_budget", { p_budget_id: budgetId, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
};
