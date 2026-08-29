import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { CardPurchaseInput } from "@/schemas/card-transaction";
import type { HistoricalInstallmentInput } from "@/schemas/historical-installment";
import { installmentService } from "@/services/installment-service";

export const installmentPlansQueryKey = (cardId?: string) => ["installment-plans", cardId] as const;
export const installmentPlanQueryKey = (planId?: string) => ["installment-plan", planId] as const;

export function useInstallmentPlans(cardId?: string) {
  return useQuery({ queryKey: installmentPlansQueryKey(cardId), queryFn: () => installmentService.list(cardId as string), enabled: Boolean(cardId) });
}
export function useInstallmentPlan(planId?: string) {
  return useQuery({ queryKey: installmentPlanQueryKey(planId), queryFn: () => installmentService.get(planId as string), enabled: Boolean(planId) });
}
export function useInstallmentSchedule(planId?: string) {
  return useQuery({ queryKey: ["installment-schedule", planId], queryFn: () => installmentService.schedule(planId as string), enabled: Boolean(planId) });
}
function useInvalidateInstallments() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: ["installment-plans"] }),
    client.invalidateQueries({ queryKey: ["installment-plan"] }),
    client.invalidateQueries({ queryKey: ["installment-schedule"] }),
    client.invalidateQueries({ queryKey: ["cards"] }), client.invalidateQueries({ queryKey: ["card"] }),
    client.invalidateQueries({ queryKey: ["card-transactions"] }), client.invalidateQueries({ queryKey: ["transactions"] }),
    client.invalidateQueries({ queryKey: ["card-statement-activity"] }),
  ]);
}
export function useCreateInstallmentPurchase() {
  const invalidate = useInvalidateInstallments();
  return useMutation({ mutationFn: (input: CardPurchaseInput) => installmentService.create(
    input, serializeMoneyMinor(parseMoneyInput(input.amount)),
    input.installment_amount.trim() ? serializeMoneyMinor(parseMoneyInput(input.installment_amount)) : null,
    createIdempotencyKey("installment:purchase:create"),
  ), onSuccess: invalidate });
}
export function useImportHistoricalInstallmentPlan() {
  const invalidate = useInvalidateInstallments();
  return useMutation({ mutationFn: (input: HistoricalInstallmentInput) => installmentService.importHistorical(
    input,
    {
      originalMinor: serializeMoneyMinor(parseMoneyInput(input.original_amount)),
      installmentMinor: serializeMoneyMinor(parseMoneyInput(input.installment_amount)),
      reportedPaidMinor: serializeMoneyMinor(parseMoneyInput(input.reported_paid_amount)),
      principalPaidMinor: serializeMoneyMinor(parseMoneyInput(input.principal_paid)),
    },
    createIdempotencyKey("installment:historical:import"),
  ), onSuccess: invalidate });
}
export function useUpdateInstallmentMetadata(planId: string) {
  const invalidate = useInvalidateInstallments();
  return useMutation({ mutationFn: (input: { description: string; categoryId: string | null; notes: string }) => installmentService.updateMetadata(
    planId, input.description, input.categoryId, input.notes, createIdempotencyKey("installment:metadata:update"),
  ), onSuccess: invalidate });
}
export function useReverseInstallmentPurchase() {
  const invalidate = useInvalidateInstallments();
  return useMutation({ mutationFn: (planId: string) => installmentService.reverse(planId, createIdempotencyKey("installment:purchase:reverse")), onSuccess: invalidate });
}
