import { supabase } from "@/lib/supabase";
import type { CurrencyCode, FinancialPlan } from "@/types/database";

export const financialPlanService = {
  async get(currency: CurrencyCode, horizonMonths: 3 | 6 | 12, asOfDate?: string): Promise<FinancialPlan> {
    const { data, error } = await supabase.rpc("get_financial_plan", {
      p_currency: currency,
      p_horizon_months: horizonMonths,
      ...(asOfDate ? { p_as_of_date: asOfDate } : {}),
    });
    if (error) throw error;
    return data;
  },
};
