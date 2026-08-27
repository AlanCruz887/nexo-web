import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { AccountEditInput, AccountFormInput } from "@/schemas/account";
import { accountService } from "@/services/account-service";
export { sumBalancesByCurrency } from "@/lib/accounts";

export const accountsQueryKey = ["accounts"] as const;
export const accountQueryKey = (accountId: string) => ["account", accountId] as const;

export function useAccounts() {
  return useQuery({ queryKey: accountsQueryKey, queryFn: accountService.list, staleTime: 45_000 });
}

export function useAccount(accountId: string | undefined) {
  return useQuery({
    queryKey: accountQueryKey(accountId ?? "missing"),
    queryFn: () => accountService.get(accountId as string),
    enabled: Boolean(accountId),
  });
}

function useInvalidateAccounts() {
  const queryClient = useQueryClient();
  return () => Promise.all([
    queryClient.invalidateQueries({ queryKey: accountsQueryKey }),
    queryClient.invalidateQueries({ queryKey: ["account"] }),
    queryClient.invalidateQueries({ queryKey: ["transactions"] }),
    queryClient.invalidateQueries({ queryKey: ["account-transactions"] }),
  ]);
}

export function useCreateAccount() {
  const invalidate = useInvalidateAccounts();
  return useMutation({
    mutationFn: (input: AccountFormInput) => accountService.create(
      input,
      serializeMoneyMinor(parseMoneyInput(input.opening_balance)),
      createIdempotencyKey("account:create"),
    ),
    onSuccess: invalidate,
  });
}

export function useUpdateAccount(accountId: string) {
  const invalidate = useInvalidateAccounts();
  return useMutation({
    mutationFn: (input: AccountEditInput) => accountService.update(
      accountId,
      input,
      createIdempotencyKey("account:update"),
    ),
    onSuccess: invalidate,
  });
}

export function useArchiveAccount() {
  const invalidate = useInvalidateAccounts();
  return useMutation({
    mutationFn: (accountId: string) => accountService.archive(accountId, createIdempotencyKey("account:archive")),
    onSuccess: invalidate,
  });
}

export function useRestoreAccount() {
  const invalidate = useInvalidateAccounts();
  return useMutation({
    mutationFn: (accountId: string) => accountService.restore(accountId, createIdempotencyKey("account:restore")),
    onSuccess: invalidate,
  });
}
