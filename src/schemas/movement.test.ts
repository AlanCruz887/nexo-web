import { describe, expect, it } from "vitest";

import { movementFormSchema, transferFormSchema } from "@/schemas/movement";

describe("movement schemas", () => {
  it("requires a real income or expense with a financial date", () => {
    const result = movementFormSchema.safeParse({
      amount: "1,450.00",
      account_id: "11111111-1111-4111-8111-111111111111",
      kind: "expense",
      category_id: "food",
      occurred_on: "2026-08-27",
      description: "Supermercado",
      notes: "",
    });
    expect(result.success).toBe(true);
  });

  it("rejects a transfer to the same account", () => {
    const accountId = "11111111-1111-4111-8111-111111111111";
    const result = transferFormSchema.safeParse({
      amount: "5000",
      from_account_id: accountId,
      to_account_id: accountId,
      occurred_on: "2026-08-27",
      description: "Transferencia",
      notes: "",
    });
    expect(result.success).toBe(false);
  });
});
