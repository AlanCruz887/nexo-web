import { describe, expect, it } from "vitest";

import { cardPaymentSchema, cardPurchaseSchema, cardRefundSchema, resolveInstallmentCount, standardInstallmentTerms } from "@/schemas/card-transaction";

describe("card transaction schemas", () => {
  const common = { amount: "100.00", card_id: "11111111-1111-4111-8111-111111111111", occurred_on: "2026-08-27", notes: "" };
  const purchase = { ...common, custom_installment_count: "", installment_amount: "", category_id: "food", description: "Café", payment_method: "apple_pay", purchase_scope: "self", personal_amount: "100.00", allocations: [] };
  it("accepts a purchase with an optional wallet method", () => expect(cardPurchaseSchema.safeParse({ ...purchase, purchase_type: "single", installment_count: "12" }).success).toBe(true));
  it("offers only the approved standard MSI terms", () => expect(standardInstallmentTerms).toEqual([3, 6, 9, 12, 18, 24]));
  it("resolves a valid custom MSI term", () => {
    const input = { ...purchase, purchase_type: "installments" as const, installment_count: "custom", custom_installment_count: "15" };
    expect(cardPurchaseSchema.safeParse(input).success).toBe(true);
    expect(resolveInstallmentCount(input)).toBe(15);
  });
  it("rejects an unreasonable custom MSI term", () => expect(cardPurchaseSchema.safeParse({ ...purchase, purchase_type: "installments", installment_count: "custom", custom_installment_count: "61" }).success).toBe(false));
  it("requires a valid source account for a payment", () => expect(cardPaymentSchema.safeParse({ ...common, source_account_id: "bad" }).success).toBe(false));
  it("allows a partial refund without an original reference", () => expect(cardRefundSchema.safeParse({ ...common, description: "Reembolso", category_id: "", original_event_id: "" }).success).toBe(true));
});
