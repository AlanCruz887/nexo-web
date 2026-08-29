import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { CardPaymentInput, CardPurchaseInput, CardRefundInput } from "@/schemas/card-transaction";
import { cardTransactionService } from "@/services/card-transaction-service";

export const cardTransactionsQueryKey = (cardId: string | undefined, kind: string = "all") => ["card-transactions", cardId, kind] as const;
export const cardStatementActivityQueryKey = (cardId: string | undefined, kind: string = "all", statementDates: string[] = []) => ["card-statement-activity", cardId, kind, [...statementDates].sort().join(",")] as const;

export function useCardTransactions(cardId: string | undefined, kind: "all" | "card_charge" | "installments" | "card_payment" | "card_refund" = "all") {
  return useQuery({ queryKey: cardTransactionsQueryKey(cardId, kind), queryFn: () => cardTransactionService.list(cardId as string, kind), enabled: Boolean(cardId), placeholderData: keepPreviousData });
}

export function useCardStatementActivity(cardId: string | undefined, statementDates: string[], kind: "all" | "card_charge" | "installments" | "card_payment" | "card_refund" = "all") {
  return useQuery({ queryKey: cardStatementActivityQueryKey(cardId, kind, statementDates), queryFn: () => cardTransactionService.statementActivity(cardId as string, statementDates, kind), enabled: Boolean(cardId) && statementDates.length > 0, placeholderData: keepPreviousData });
}

function useInvalidateCardOperations() {
  const client = useQueryClient();
  return () => Promise.all([
    client.invalidateQueries({ queryKey: ["cards"] }), client.invalidateQueries({ queryKey: ["card"] }),
    client.invalidateQueries({ queryKey: ["card-statements"] }), client.invalidateQueries({ queryKey: ["card-current-cycle"] }),
    client.invalidateQueries({ queryKey: ["card-transactions"] }), client.invalidateQueries({ queryKey: ["transactions"] }),
    client.invalidateQueries({ queryKey: ["card-statement-activity"] }),
    client.invalidateQueries({ queryKey: ["installment-plans"] }), client.invalidateQueries({ queryKey: ["installment-plan"] }),
    client.invalidateQueries({ queryKey: ["installment-schedule"] }),
    client.invalidateQueries({ queryKey: ["account-transactions"] }), client.invalidateQueries({ queryKey: ["accounts"] }),
    client.invalidateQueries({ queryKey: ["account"] }), client.invalidateQueries({ queryKey: ["transaction"] }),
    client.invalidateQueries({ queryKey: ["contacts"] }), client.invalidateQueries({ queryKey: ["contact"] }),
    client.invalidateQueries({ queryKey: ["contact-receivables"] }), client.invalidateQueries({ queryKey: ["contact-activity"] }),
  ]);
}

export function useCreateCardPurchase() { const invalidate = useInvalidateCardOperations(); return useMutation({ mutationFn: (input: CardPurchaseInput) => cardTransactionService.createPurchase(input, serializeMoneyMinor(parseMoneyInput(input.amount)), createIdempotencyKey("card:purchase:create")), onSuccess: invalidate }); }
export function useUpdateCardPurchase(eventId: string) { const invalidate = useInvalidateCardOperations(); return useMutation({ mutationFn: (input: CardPurchaseInput) => cardTransactionService.updatePurchase(eventId, input, serializeMoneyMinor(parseMoneyInput(input.amount)), createIdempotencyKey("card:purchase:update")), onSuccess: invalidate }); }
export function useCreateCardPayment() { const invalidate = useInvalidateCardOperations(); return useMutation({ mutationFn: (input: CardPaymentInput) => cardTransactionService.createPayment(input, serializeMoneyMinor(parseMoneyInput(input.amount)), createIdempotencyKey("card:payment:create")), onSuccess: invalidate }); }
export function useCreateCardRefund() { const invalidate = useInvalidateCardOperations(); return useMutation({ mutationFn: (input: CardRefundInput) => cardTransactionService.createRefund(input, serializeMoneyMinor(parseMoneyInput(input.amount)), createIdempotencyKey("card:refund:create")), onSuccess: invalidate }); }
export function useReverseCardTransaction() { const invalidate = useInvalidateCardOperations(); return useMutation({ mutationFn: ({ eventId, kind }: { eventId: string; kind: "card_charge" | "card_payment" | "card_refund" }) => cardTransactionService.reverse(eventId, kind, createIdempotencyKey(`card:${kind}:reverse`)), onSuccess: invalidate }); }
