import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createIdempotencyKey } from "@/lib/idempotency";
import { plannedCashFlowService } from "@/services/planned-cash-flow-service";

function useInvalidatePlannedCashFlows() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: ["planned-cash-flows"] }),
    client.invalidateQueries({ queryKey: ["financial-plan"] }),
  ]);
}

export function usePlannedCashFlows() {
  return useQuery({ queryKey: ["planned-cash-flows"], queryFn: plannedCashFlowService.list });
}

export function useCreatePlannedCashFlow() {
  const invalidate = useInvalidatePlannedCashFlows();
  return useMutation({
    mutationFn: (input: Parameters<typeof plannedCashFlowService.create>[0]) =>
      plannedCashFlowService.create(input, createIdempotencyKey("planned-cash-flow:create")),
    onSuccess: invalidate,
  });
}

export function useUpdatePlannedCashFlow() {
  const invalidate = useInvalidatePlannedCashFlows();
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Parameters<typeof plannedCashFlowService.update>[1] }) =>
      plannedCashFlowService.update(id, input, createIdempotencyKey("planned-cash-flow:update")),
    onSuccess: invalidate,
  });
}

export function useArchivePlannedCashFlow() {
  const invalidate = useInvalidatePlannedCashFlows();
  return useMutation({
    mutationFn: (id: string) => plannedCashFlowService.archive(id, createIdempotencyKey("planned-cash-flow:archive")),
    onSuccess: invalidate,
  });
}

export function useRestorePlannedCashFlow() {
  const invalidate = useInvalidatePlannedCashFlows();
  return useMutation({
    mutationFn: (id: string) => plannedCashFlowService.restore(id, createIdempotencyKey("planned-cash-flow:restore")),
    onSuccess: invalidate,
  });
}
