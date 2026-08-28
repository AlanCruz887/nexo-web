import { describe, expect, it } from "vitest";

import { cardFormSchema } from "@/schemas/card";

const validCard = {
  name: "BBVA Oro", issuer: "BBVA", product_name: "Oro", currency: "MXN",
  credit_limit: "100000.00", statement_day: "31", payment_days_after_statement: "20",
  last4: "4821", visual_theme: "bbva_oro", baseline_policy: "current_bank_balance",
  baseline_date: "2026-08-27", bank_balance: "20000.00", excluded_statement_amount: "", baseline_notes: "",
} as const;

describe("credit card form", () => {
  it("accepts day 31 and a current-bank-balance baseline", () => {
    expect(cardFormSchema.safeParse(validCard).success).toBe(true);
  });

  it("requires an excluded statement amount for after-last-statement", () => {
    const result = cardFormSchema.safeParse({ ...validCard, baseline_policy: "after_last_statement" });
    expect(result.success).toBe(false);
  });

  it("rejects invalid cut days", () => {
    expect(cardFormSchema.safeParse({ ...validCard, statement_day: "32" }).success).toBe(false);
  });
});
