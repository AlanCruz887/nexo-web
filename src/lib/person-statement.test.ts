import { describe, expect, it } from "vitest";

import { buildStatementDocument } from "@/lib/person-statement";
import type { PersonStatement } from "@/types/database";

const baseStatement: PersonStatement = {
  as_of_date: "2026-08-28",
  periods: [
    {
      currency: "MXN", period_start: "2026-08-09", payment_due_date: "2026-09-29",
      subtotal_minor: "176667", paid_minor: "0", credit_applied_minor: "0",
      remaining_minor: "176667", overdue_minor: "0", overdue_since: null,
      total_outstanding_minor: "800000", credit_balance_minor: "0",
      concepts: [
        { id: "c1", description: "MacBook Pro", statement_date: "2026-09-09", payment_due_date: "2026-09-29", amount_minor: "66667", paid_minor: "0", outstanding_minor: "66667", credit_applied_minor: "0", purchase_amount_minor: "1200000", installment_id: "i1", installment_number: 5, installment_count: 12 },
        { id: "c2", description: "Cena", statement_date: null, payment_due_date: "2026-08-30", amount_minor: "40000", paid_minor: "0", outstanding_minor: "40000", credit_applied_minor: "0", purchase_amount_minor: "100000", installment_id: null, installment_number: 1, installment_count: null },
      ],
    },
    {
      currency: "USD", period_start: "2026-08-29", payment_due_date: "2026-08-29",
      subtotal_minor: "10000", paid_minor: "0", credit_applied_minor: "0",
      remaining_minor: "10000", overdue_minor: "0", overdue_since: null,
      total_outstanding_minor: "10000", credit_balance_minor: "0",
      concepts: [],
    },
  ],
  payments: [
    { event_id: "p1", occurred_on: "2026-08-18", currency: "MXN", account_name: "BBVA", amount_minor: "30000", applied_to_period_minor: "30000", applied_to_future_minor: "0", credit_generated_minor: "0" },
    { event_id: "p2", occurred_on: "2026-08-20", currency: "USD", account_name: "Wise", amount_minor: "5000", applied_to_period_minor: "5000", applied_to_future_minor: "0", credit_generated_minor: "0" },
  ],
};

describe("buildStatementDocument", () => {
  it("keeps currencies as separate blocks and never mixes their totals", () => {
    const document = buildStatementDocument("Carlos", baseStatement);
    expect(document.blocks).toHaveLength(2);
    expect(document.blocks[0]?.currency).toBe("MXN");
    expect(document.blocks[0]?.totalOwedMinor).toBe("800000");
    expect(document.blocks[1]?.currency).toBe("USD");
    expect(document.blocks[1]?.totalOwedMinor).toBe("10000");
  });

  it("labels an MSI concept with its installment progress, not a generic purchase label", () => {
    const document = buildStatementDocument("Carlos", baseStatement);
    const macbook = document.blocks[0]?.concepts.find((concept) => concept.id === "c1");
    expect(macbook?.typeLabel).toBe("Mensualidad 5 de 12");
    expect(macbook?.amountMinor).toBe("66667");
    expect(macbook?.purchaseAmountMinor).toBe("1200000");
  });

  it("labels a non-installment concept as a shared purchase and keeps the full purchase total alongside the person's share", () => {
    const document = buildStatementDocument("Carlos", baseStatement);
    const cena = document.blocks[0]?.concepts.find((concept) => concept.id === "c2");
    expect(cena?.typeLabel).toBe("Compra compartida");
    expect(cena?.amountMinor).toBe("40000");
    expect(cena?.purchaseAmountMinor).toBe("100000");
  });

  it("only assigns each payment to the block matching its own currency", () => {
    const document = buildStatementDocument("Carlos", baseStatement);
    expect(document.blocks[0]?.payments).toHaveLength(1);
    expect(document.blocks[0]?.payments[0]?.event_id).toBe("p1");
    expect(document.blocks[1]?.payments).toHaveLength(1);
    expect(document.blocks[1]?.payments[0]?.event_id).toBe("p2");
  });

  it("produces an empty block list for a person with no debt, without throwing", () => {
    const document = buildStatementDocument("Ana", { as_of_date: "2026-08-28", periods: [], payments: [] });
    expect(document.blocks).toEqual([]);
  });
});
