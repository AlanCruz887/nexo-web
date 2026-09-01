import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createIdempotencyKey } from "@/lib/idempotency";
import { recurringRuleService } from "@/services/recurring-rule-service";

function useInvalidateRecurring() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: ["recurring-rules"] }),
    client.invalidateQueries({ queryKey: ["recurring-occurrences"] }),
    client.invalidateQueries({ queryKey: ["recurring-history"] }),
    client.invalidateQueries({ queryKey: ["financial-plan"] }),
    client.invalidateQueries({ queryKey: ["accounts"] }),
    client.invalidateQueries({ queryKey: ["budgets"] }),
  ]);
}

export function useRecurringRules() {
  return useQuery({ queryKey: ["recurring-rules"], queryFn: recurringRuleService.list });
}

export function useRecurringOccurrences(fromDate: string, toDate: string) {
  return useQuery({
    queryKey: ["recurring-occurrences", fromDate, toDate],
    queryFn: () => recurringRuleService.occurrences(fromDate, toDate),
  });
}

export function useRecurringRuleCurrentVersion(ruleId: string | undefined) {
  return useQuery({
    queryKey: ["recurring-rule-version", ruleId ?? "missing"],
    queryFn: () => recurringRuleService.currentVersion(ruleId as string),
    enabled: Boolean(ruleId),
  });
}

export function useRecurringHistory(ruleId: string | undefined) {
  return useQuery({
    queryKey: ["recurring-history", ruleId ?? "missing"],
    queryFn: () => recurringRuleService.history(ruleId as string),
    enabled: Boolean(ruleId),
  });
}

export function useCreateRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (input: Parameters<typeof recurringRuleService.create>[0]) =>
      recurringRuleService.create(input, createIdempotencyKey("recurring-rule:create")),
    onSuccess: invalidate,
  });
}

export function useUpdateRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Parameters<typeof recurringRuleService.update>[1] }) =>
      recurringRuleService.update(id, input, createIdempotencyKey("recurring-rule:update")),
    onSuccess: invalidate,
  });
}

export function usePauseRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (id: string) => recurringRuleService.pause(id, createIdempotencyKey("recurring-rule:pause")),
    onSuccess: invalidate,
  });
}

export function useResumeRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (id: string) => recurringRuleService.resume(id, createIdempotencyKey("recurring-rule:resume")),
    onSuccess: invalidate,
  });
}

export function useArchiveRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (id: string) => recurringRuleService.archive(id, createIdempotencyKey("recurring-rule:archive")),
    onSuccess: invalidate,
  });
}

export function useRestoreRecurringRule() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (id: string) => recurringRuleService.restore(id, createIdempotencyKey("recurring-rule:restore")),
    onSuccess: invalidate,
  });
}

export function useConfirmRecurringOccurrence() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: (input: Parameters<typeof recurringRuleService.confirm>[0]) =>
      recurringRuleService.confirm(input, createIdempotencyKey("recurring-occurrence:confirm")),
    onSuccess: invalidate,
  });
}

export function useOmitRecurringOccurrence() {
  const invalidate = useInvalidateRecurring();
  return useMutation({
    mutationFn: ({ ruleId, expectedDate, notes }: { ruleId: string; expectedDate: string; notes: string | null }) =>
      recurringRuleService.omit(ruleId, expectedDate, notes, createIdempotencyKey("recurring-occurrence:omit")),
    onSuccess: invalidate,
  });
}
