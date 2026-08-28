import { keepPreviousData, skipToken, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { MovementFormInput, TransferFormInput } from "@/schemas/movement";
import { categoryService } from "@/services/category-service";
import { movementService, type MovementFilters } from "@/services/movement-service";
import type { AccountActivity, Category } from "@/types/database";

export const transactionsQueryKey = (filters: MovementFilters) => ["transactions", filters] as const;
export const accountTransactionsQueryKey = (accountId: string, filters: MovementFilters) => ["account-transactions", accountId, filters] as const;
export const transactionQueryKey = (eventId: string | undefined) => ["transaction", eventId] as const;

export function useCategories() {
  return useQuery({ queryKey: ["categories"], queryFn: categoryService.list, staleTime: Number.POSITIVE_INFINITY });
}

export function useMovements(filters: MovementFilters = {}) {
  return useQuery({ queryKey: transactionsQueryKey(filters), queryFn: () => movementService.list(filters), placeholderData: keepPreviousData });
}

export function useAccountMovements(accountId: string | undefined, filters: MovementFilters = {}) {
  const scopedFilters: MovementFilters = accountId ? { ...filters, accountId } : filters;
  return useQuery({
    queryKey: accountTransactionsQueryKey(accountId ?? "missing", filters),
    queryFn: () => movementService.list(scopedFilters),
    enabled: Boolean(accountId),
    placeholderData: keepPreviousData,
  });
}

export function useMovement(eventId: string | undefined) {
  return useQuery({
    queryKey: transactionQueryKey(eventId),
    queryFn: eventId ? () => movementService.get(eventId) : skipToken,
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
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: MovementFormInput) => movementService.update(
      eventId,
      input,
      serializeMoneyMinor(parseMoneyInput(input.amount)),
      createIdempotencyKey("transaction:update"),
    ),
    onSuccess: (updatedEventId, input) => {
      const previous = queryClient.getQueryData<AccountActivity[]>(transactionQueryKey(eventId));
      const categories = queryClient.getQueryData<Category[]>(["categories"]);
      if (previous?.length) {
        const amountMinor = serializeMoneyMinor(parseMoneyInput(input.amount));
        const categoryName = categories?.find((category) => category.id === input.category_id)?.name ?? previous[0]?.category_name ?? null;
        queryClient.setQueryData<AccountActivity[]>(transactionQueryKey(updatedEventId), previous.map((activity) => ({
          ...activity,
          event_id: updatedEventId,
          amount_minor: amountMinor,
          personal_amount_minor: activity.kind === "expense" ? amountMinor : "0",
          account_delta_minor: activity.kind === "expense" ? `-${amountMinor}` : amountMinor,
          description: input.description,
          category_id: input.category_id,
          category_name: categoryName,
          occurred_on: input.occurred_on,
          notes: input.notes || null,
          created_at: new Date().toISOString(),
        })));
      }

      void Promise.all([
        queryClient.invalidateQueries({ queryKey: ["accounts"] }),
        queryClient.invalidateQueries({ queryKey: ["account"] }),
        queryClient.invalidateQueries({ queryKey: ["transactions"] }),
        queryClient.invalidateQueries({ queryKey: ["account-transactions"] }),
        queryClient.invalidateQueries({ queryKey: transactionQueryKey(updatedEventId) }),
      ]);
    },
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
