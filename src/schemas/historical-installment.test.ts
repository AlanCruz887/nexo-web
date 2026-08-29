import { describe, expect, it } from "vitest";

import { historicalInstallmentSchema, historicalPaidBeforeCount, resolveHistoricalInstallmentCount } from "@/schemas/historical-installment";

const valid = {
  description: "iPhone", card_id: "11111111-1111-4111-8111-111111111111",
  original_amount: "12000", installment_count: "12", custom_installment_count: "",
  installment_amount: "1000", original_purchase_date: "2026-01-10",
  current_installment_number: "5", reported_paid_amount: "4000", principal_paid: "4000",
  next_statement_date: "2026-09-09", category_id: "technology", notes: "",
  opening_balance_inclusion: "included" as const,
};

describe("historical installment schema", () => {
  it("maps 5 of 12 to four payments before Nexo", () => {
    expect(historicalInstallmentSchema.safeParse(valid).success).toBe(true);
    expect(historicalPaidBeforeCount(valid.current_installment_number)).toBe(4);
  });
  it("supports a reasonable custom term", () => {
    const input = { ...valid, installment_count: "custom", custom_installment_count: "15" };
    expect(historicalInstallmentSchema.safeParse(input).success).toBe(true);
    expect(resolveHistoricalInstallmentCount(input)).toBe(15);
  });
  it("rejects current progress beyond the total", () => {
    expect(historicalInstallmentSchema.safeParse({ ...valid, current_installment_number: "13" }).success).toBe(false);
  });
});
