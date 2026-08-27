import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { MovementFormInput, TransferFormInput } from "@/schemas/movement";
import { categoryService } from "@/services/category-service";
import { movementService, type MovementFilters } from "@/services/movement-service";

export const transactionsQueryKey = (filters: MovementFilters) => ["transactions", filters] as const;
export const accountTransactionsQueryKey = (accountId: string, filters: MovementFilters) => ["account-transactions", accountId, filters] as const;

export function useCategories() {
  return useQuery({ queryKey: ["categories"], queryFn: categoryService.list, staleTime: Number.POSITIVE_INFINITY });
}

export function useMovements(filters: MovementFilters = {}) {
  return useQuery({ queryKey: transactionsQueryKey(filters), queryFn: () => movementService.list(filters) });
}

export function useAccountMovements(accountId: string | undefined, filters: MovementFilters = {}) {
  const scopedFilters: MovementFilters = accountId ? { ...filters, accountId } : filters;
  return useQuery({
    queryKey: accountTransactionsQueryKey(accountId ?? "missing", filters),
    queryFn: () => movementService.list(scopedFilters),
    enabled: Boolean(accountId),
  });
}

export function useMovement(eventId: string | undefined) {
  return useQuery({
    queryKey: ["transaction", eventId ?? "missing"],
    queryFn: () => movementService.get(eventId as string),
    enabled: Boolean(eventId),
  });
}

function useInvalidateFinancialData() {
  const queryClient = useQueryClient();
  return () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ["accounts"] }),
    queryClient.invalidateQueries({ queryKey: ["account"] }),
    queryClient.invalidateQueries({ queryKey: ["transactions"] }),
    queryClient.invalidateQueries({ queryKey: ["account-transactions"] }),
    queryClient.invalidateQueries({ queryKey: ["transaction"] }),
  ]);
}

export function useCreateMovement() {
  const invalidate = useInvalidateFinancialData();
  return useMutation({
    mutationFn: (input: MovementFormInput) => movementService.create(
      input,
      serializeMoneyMinor(parseMoneyInput(input.amount)),
      createIdempotencyKey("transaction:create"),
    ),
    onSuccess: invalidate,
  });
}

export function useUpdateMovement(eventId: string) {
  const invalidate = useInvalidateFinancialData();
  return useMutation({
    mutationFn: (input: MovementFormInput) => movementService.update(
      eventId,
      input,
      serializeMoneyMinor(parseMoneyInput(input.amount)),
      createIdempotencyKey("transaction:update"),
    ),
    onSuccess: invalidate,
  });
}

export function useCreateTransfer() {
  const invalidate = useInvalidateFinancialData();
  return useMutation({
    mutationFn: (input: TransferFormInput) => movementService.transfer(
      input,
      serializeMoneyMinor(parseMoneyInput(input.amount)),
      createIdempotencyKey("transfer:create"),
    ),
    onSuccess: invalidate,
  });
}

export function useReverseMovement() {
  const invalidate = useInvalidateFinancialData();
  return useMutation({
    mutationFn: ({ eventId, isTransfer }: { eventId: string; isTransfer: boolean }) => movementService.reverse(
      eventId,
      isTransfer,
      createIdempotencyKey(isTransfer ? "transfer:reverse" : "transaction:reverse"),
    ),
    onSuccess: invalidate,
  });
}

export function useUpdateTransferNotes(eventId: string) {
  const invalidate = useInvalidateFinancialData();
  return useMutation({
    mutationFn: (notes: string) => movementService.updateTransferNotes(
      eventId,
      notes,
      createIdempotencyKey("transfer:update-notes"),
    ),
    onSuccess: invalidate,
  });
}
