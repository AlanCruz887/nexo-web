import { skipToken, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { CardEditInput, CardFormInput } from "@/schemas/card";
import { cardService } from "@/services/card-service";

export const cardsQueryKey = ["cards"] as const;
export const cardQueryKey = (cardId: string | undefined) => ["card", cardId] as const;
export const cardStatementsQueryKey = (cardId: string | undefined) => ["card-statements", cardId] as const;
export const cardCurrentCycleQueryKey = (cardId: string | undefined) => ["card-current-cycle", cardId] as const;

export function useCards() { return useQuery({ queryKey: cardsQueryKey, queryFn: cardService.list, staleTime: 45_000 }); }
export function useCard(cardId: string | undefined) { return useQuery({ queryKey: cardQueryKey(cardId), queryFn: cardId ? () => cardService.get(cardId) : skipToken }); }
export function useCardStatements(cardId: string | undefined) { return useQuery({ queryKey: cardStatementsQueryKey(cardId), queryFn: cardId ? () => cardService.statements(cardId) : skipToken }); }
export function useCardCurrentCycle(cardId: string | undefined) { return useQuery({ queryKey: cardCurrentCycleQueryKey(cardId), queryFn: cardId ? () => cardService.cycle(cardId) : skipToken }); }

function useInvalidateCards() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: cardsQueryKey }), client.invalidateQueries({ queryKey: ["card"] }),
    client.invalidateQueries({ queryKey: ["card-statements"] }), client.invalidateQueries({ queryKey: ["card-current-cycle"] }),
  ]);
}

export function useCreateCard() {
  const invalidate = useInvalidateCards();
  return useMutation({ mutationFn: (input: CardFormInput) => cardService.create(input, {
    limit: serializeMoneyMinor(parseMoneyInput(input.credit_limit)),
    bank: serializeMoneyMinor(parseMoneyInput(input.bank_balance)),
    excluded: input.baseline_policy === "after_last_statement" ? serializeMoneyMinor(parseMoneyInput(input.excluded_statement_amount)) : null,
  }, createIdempotencyKey("card:create")), onSuccess: invalidate });
}
export function useUpdateCard(cardId: string) {
  const invalidate = useInvalidateCards();
  return useMutation({ mutationFn: (input: CardEditInput) => cardService.update(cardId, input, serializeMoneyMinor(parseMoneyInput(input.credit_limit)), createIdempotencyKey("card:update")), onSuccess: invalidate });
}
export function useSetCardActive() {
  const invalidate = useInvalidateCards();
  return useMutation({ mutationFn: ({ cardId, active }: { cardId: string; active: boolean }) => cardService.setActive(cardId, active, createIdempotencyKey(active ? "card:restore" : "card:archive")), onSuccess: invalidate });
}
export function useCloseCardStatement(cardId: string) {
  const invalidate = useInvalidateCards();
  return useMutation({ mutationFn: ({ statementDate, minimumPayment }: { statementDate: string; minimumPayment: string }) => cardService.closeStatement(cardId, statementDate, minimumPayment.trim() ? serializeMoneyMinor(parseMoneyInput(minimumPayment)) : null, createIdempotencyKey("card:statement:close")), onSuccess: invalidate });
}
