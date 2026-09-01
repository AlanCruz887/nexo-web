import { describe, expect, it } from "vitest";

import { buildStatementDocument } from "@/lib/person-statement";
import type { PersonStatement } from "@/types/database";

const baseStatement: PersonStatement = {
  as_of_date: "2026-08-28",
  periods: [
    {
      currency: "MXN", period_start: "2026-08-09", payment_due_date: "2026-09-29",
      subtotal_minor: "176667", paid_minor: "0", credit_applied_minor: "0", reconciled_minor: "0",
      remaining_minor: "176667", overdue_minor: "0", overdue_since: null,
      total_outstanding_minor: "800000", credit_balance_minor: "0",
      concepts: [
        { id: "c1", description: "MacBook Pro", statement_date: "2026-09-09", payment_due_date: "2026-09-29", amount_minor: "66667", paid_minor: "0", outstanding_minor: "66667", credit_applied_minor: "0", reconciled_minor: "0", purchase_amount_minor: "1200000", installment_id: "i1", installment_number: 5, installment_count: 12 },
        { id: "c2", description: "Cena", statement_date: null, payment_due_date: "2026-08-30", amount_minor: "40000", paid_minor: "0", outstanding_minor: "40000", credit_applied_minor: "0", reconciled_minor: "0", purchase_amount_minor: "100000", installment_id: null, installment_number: 1, installment_count: null },
      ],
    },
    {
      currency: "USD", period_start: "2026-08-29", payment_due_date: "2026-08-29",
      subtotal_minor: "10000", paid_minor: "0", credit_applied_minor: "0", reconciled_minor: "0",
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

  it("keeps a partially paid concept's original and outstanding amounts distinct, never collapsing one into the other", () => {
    const withPartialPayment: PersonStatement = {
      ...baseStatement,
      periods: [{
        ...baseStatement.periods[0]!,
        concepts: [{
          id: "c3", description: "KFC", statement_date: null, payment_due_date: "2026-08-30",
          amount_minor: "70000", paid_minor: "20000", outstanding_minor: "50000", credit_applied_minor: "0", reconciled_minor: "0",
          purchase_amount_minor: "100000", installment_id: null, installment_number: 1, installment_count: null,
        }],
      }],
    };
    const document = buildStatementDocument("Carlos", withPartialPayment);
    const kfc = document.blocks[0]?.concepts[0];
    // "Correspondía" (what the period originally asked for) stays the nominal amount...
    expect(kfc?.amountMinor).toBe("70000");
    // ...while what is genuinely still owed on this one concept is tracked separately, and "Pagado" is threaded through too.
    expect(kfc?.coveredMinor).toBe("20000");
    expect(kfc?.outstandingMinor).toBe("50000");
    expect(kfc?.purchaseAmountMinor).toBe("100000");
  });

  it("reconciles period_total = covered + remaining, matching the Estado de Princesa figures", () => {
    // 9,666.67 (total del periodo) = 9,000.00 (cubierto) + 666.67 (pendiente).
    const princesa: PersonStatement = {
      as_of_date: "2026-08-28",
      periods: [{
        currency: "MXN", period_start: "2026-08-09", payment_due_date: "2026-09-29",
        subtotal_minor: "966667", paid_minor: "900000", credit_applied_minor: "0", reconciled_minor: "900000",
        remaining_minor: "66667", overdue_minor: "0", overdue_since: null,
        total_outstanding_minor: "800000", credit_balance_minor: "0",
        concepts: [
          { id: "boletos", description: "Boletos prueba", statement_date: null, payment_due_date: "2026-08-30", amount_minor: "200000", paid_minor: "200000", outstanding_minor: "0", credit_applied_minor: "0", reconciled_minor: "200000", purchase_amount_minor: "200000", installment_id: null, installment_number: 1, installment_count: null },
          { id: "kfc", description: "KFC", statement_date: null, payment_due_date: "2026-08-30", amount_minor: "700000", paid_minor: "700000", outstanding_minor: "0", credit_applied_minor: "0", reconciled_minor: "700000", purchase_amount_minor: "1000000", installment_id: null, installment_number: 1, installment_count: null },
          { id: "telefono", description: "Telefono Gael", statement_date: "2026-09-09", payment_due_date: "2026-09-29", amount_minor: "66667", paid_minor: "0", outstanding_minor: "66667", credit_applied_minor: "0", reconciled_minor: "0", purchase_amount_minor: "800000", installment_id: "i1", installment_number: 1, installment_count: 12 },
        ],
      }],
      payments: [
        { event_id: "p1", occurred_on: "2026-08-14", currency: "MXN", account_name: "Santander", amount_minor: "650000", applied_to_period_minor: "650000", applied_to_future_minor: "0", credit_generated_minor: "0" },
      ],
    };
    const document = buildStatementDocument("Princesa", princesa);
    const block = document.blocks[0]!;
    expect(BigInt(block.coveredMinor) + BigInt(block.remainingMinor)).toBe(BigInt(block.periodTotalMinor));
    expect(block.periodTotalMinor).toBe("966667");
    expect(block.coveredMinor).toBe("900000");
    expect(block.remainingMinor).toBe("66667");
    expect(block.reconciledMinor).toBe("900000");
    // "Te debe en total" stays its own, smaller-scope-in-this-example figure — never forced to equal "Total del periodo".
    expect(block.totalOwedMinor).toBe("800000");
    for (const concept of block.concepts) {
      expect(BigInt(concept.coveredMinor) + BigInt(concept.outstandingMinor)).toBe(BigInt(concept.amountMinor));
    }
    // Paid-off concepts (Boletos, KFC) stay listed with Pendiente = 0, not hidden.
    expect(block.concepts.find((concept) => concept.id === "boletos")?.outstandingMinor).toBe("0");
    expect(block.concepts.find((concept) => concept.id === "kfc")?.outstandingMinor).toBe("0");
    // The reconciliation never shows up in Pagos recibidos as if it were a new payment.
    expect(block.payments).toHaveLength(1);
    expect(block.payments[0]?.amount_minor).toBe("650000");
  });
});
