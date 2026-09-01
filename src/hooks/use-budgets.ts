import { skipToken, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createIdempotencyKey } from "@/lib/idempotency";
import { budgetService } from "@/services/budget-service";
import type { CurrencyCode } from "@/types/database";

function useInvalidateBudgets() {
  const client = useQueryClient();
  return () => Promise.all([client.invalidateQueries({ queryKey: ["budgets"] }), client.invalidateQueries({ queryKey: ["budget-movements"] })]);
}

export function useBudgetsForPeriod(month: string, currency?: CurrencyCode) {
  return useQuery({ queryKey: ["budgets", month, currency ?? "all"], queryFn: () => budgetService.forPeriod(month, currency) });
}

export function useBudgetMovements(categoryId?: string, currency?: CurrencyCode, month?: string) {
  return useQuery({
    queryKey: ["budget-movements", categoryId, currency, month],
    queryFn: categoryId && currency && month ? () => budgetService.movements(categoryId, currency, month) : skipToken,
  });
}

export function useCreateBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: (input: Parameters<typeof budgetService.create>[0]) => budgetService.create(input, createIdempotencyKey("budget:create")),
    onSuccess: invalidate,
  });
}

export function useChangeRecurringBudgetFromMonth() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: (input: Parameters<typeof budgetService.changeRecurringFromMonth>[0]) =>
      budgetService.changeRecurringFromMonth(input, createIdempotencyKey("budget:recurring:change")),
    onSuccess: invalidate,
  });
}

export function useUpdateBudgetExceptionLimit() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: ({ budgetId, limitMinor }: { budgetId: string; limitMinor: string }) =>
      budgetService.updateExceptionLimit(budgetId, limitMinor, createIdempotencyKey("budget:exception:update")),
    onSuccess: invalidate,
  });
}

export function useStopRecurringBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: (input: Parameters<typeof budgetService.stopRecurring>[0]) => budgetService.stopRecurring(input, createIdempotencyKey("budget:recurring:stop")),
    onSuccess: invalidate,
  });
}

export function useArchiveBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({ mutationFn: (budgetId: string) => budgetService.archive(budgetId, createIdempotencyKey("budget:archive")), onSuccess: invalidate });
}
