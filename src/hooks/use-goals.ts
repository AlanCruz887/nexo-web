import { skipToken, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createIdempotencyKey } from "@/lib/idempotency";
import { goalService } from "@/services/goal-service";

function useInvalidateGoals() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: ["goals"] }),
    client.invalidateQueries({ queryKey: ["goal"] }),
    client.invalidateQueries({ queryKey: ["goal-movements"] }),
    client.invalidateQueries({ queryKey: ["accounts"] }),
  ]);
}

export function useGoals() { return useQuery({ queryKey: ["goals"], queryFn: goalService.list }); }
export function useGoal(id?: string) { return useQuery({ queryKey: ["goal", id], queryFn: id ? () => goalService.get(id) : skipToken }); }
export function useGoalMovements(goalId?: string) { return useQuery({ queryKey: ["goal-movements", goalId], queryFn: goalId ? () => goalService.movements(goalId) : skipToken }); }

export function useCreateGoal() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (input: Parameters<typeof goalService.create>[0]) => goalService.create(input, createIdempotencyKey("goal:create")), onSuccess: invalidate });
}
export function useUpdateGoal(id: string) {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (input: Parameters<typeof goalService.update>[1]) => goalService.update(id, input, createIdempotencyKey("goal:update")), onSuccess: invalidate });
}
export function useSetGoalStatus() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: ({ id, status }: { id: string; status: "active" | "paused" }) => goalService.setStatus(id, status, createIdempotencyKey("goal:status")), onSuccess: invalidate });
}
export function useArchiveGoal() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (id: string) => goalService.archive(id, createIdempotencyKey("goal:archive")), onSuccess: invalidate });
}
export function useRestoreGoal() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (id: string) => goalService.restore(id, createIdempotencyKey("goal:restore")), onSuccess: invalidate });
}
export function useContributeToGoal() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (input: Parameters<typeof goalService.contribute>[0]) => goalService.contribute(input, createIdempotencyKey("goal:contribute")), onSuccess: invalidate });
}
export function useWithdrawFromGoal() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (input: Parameters<typeof goalService.withdraw>[0]) => goalService.withdraw(input, createIdempotencyKey("goal:withdraw")), onSuccess: invalidate });
}
export function useReverseGoalEntry() {
  const invalidate = useInvalidateGoals();
  return useMutation({ mutationFn: (entryId: string) => goalService.reverseEntry(entryId, createIdempotencyKey("goal:reverse")), onSuccess: invalidate });
}
