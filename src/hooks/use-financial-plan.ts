import { useQuery } from "@tanstack/react-query";
import { financialPlanService } from "@/services/financial-plan-service";
import type { CurrencyCode } from "@/types/database";

export function useFinancialPlan(currency: CurrencyCode, horizonMonths: 3 | 6 | 12, asOfDate?: string) {
  return useQuery({
    queryKey: ["financial-plan", currency, horizonMonths, asOfDate ?? "today"],
    queryFn: () => financialPlanService.get(currency, horizonMonths, asOfDate),
  });
}
