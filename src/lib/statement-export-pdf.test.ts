import { PDFDocument } from "pdf-lib";
import { describe, expect, it } from "vitest";

import type { StatementDocument } from "@/lib/person-statement";
import { buildStatementPdf, conceptAmountLabel } from "@/lib/statement-export-pdf";

function makeConcept(index: number) {
  return { id: `c${index}`, description: `Compra ${index}`, typeLabel: "Compra compartida", amountMinor: "10000", coveredMinor: "0", purchaseAmountMinor: "20000", outstandingMinor: "10000" };
}

const document: StatementDocument = {
  personName: "Carlos",
  asOfDate: "2026-08-28",
  blocks: [
    {
      currency: "MXN", periodLabel: "9 ago — 29 sep", periodStart: "2026-08-09", paymentDueDate: "2026-09-29",
      periodTotalMinor: "66667", coveredMinor: "0", remainingMinor: "66667", reconciledMinor: "0",
      overdueMinor: "80000", overdueSince: "2026-09-15", totalOwedMinor: "800000", creditBalanceMinor: "0",
      concepts: [{ id: "c1", description: "MacBook Pro", typeLabel: "Mensualidad 5 de 12", amountMinor: "66667", coveredMinor: "0", purchaseAmountMinor: "1200000", outstandingMinor: "66667" }],
      payments: [{ event_id: "p1", occurred_on: "2026-08-18", currency: "MXN", account_name: "BBVA", amount_minor: "50000", applied_to_period_minor: "30000", applied_to_future_minor: "20000", credit_generated_minor: "0" }],
    },
  ],
};

describe("conceptAmountLabel", () => {
  it("shows what is genuinely still owed, not the original nominal amount, for a partially paid concept", () => {
    const kfc = { id: "c9", description: "KFC", typeLabel: "Compra compartida", amountMinor: "70000", coveredMinor: "20000", purchaseAmountMinor: "100000", outstandingMinor: "50000" };
    expect(conceptAmountLabel(kfc, "MXN")).toBe("$500.00 (de $1,000.00)");
  });

  it("shows a single figure with no parenthetical when the concept is 100% the person's own and not the total of a shared purchase", () => {
    const solo = { id: "c10", description: "Solo mío", typeLabel: "Compra compartida", amountMinor: "40000", coveredMinor: "40000", purchaseAmountMinor: "40000", outstandingMinor: "40000" };
    expect(conceptAmountLabel(solo, "MXN")).toBe("$400.00");
  });
});

describe("buildStatementPdf", () => {
  it("produces a structurally valid, single-page PDF for a short statement", async () => {
    const bytes = await buildStatementPdf(document, new Date("2026-08-28T12:00:00Z"));
    const magic = new TextDecoder().decode(bytes.slice(0, 5));
    expect(magic).toBe("%PDF-");
    const loaded = await PDFDocument.load(bytes);
    expect(loaded.getPageCount()).toBe(1);
  });

  it("paginates instead of cutting rows when a person has many concepts", async () => {
    const longDocument: StatementDocument = {
      ...document,
      blocks: [{ ...document.blocks[0]!, concepts: Array.from({ length: 60 }, (_, index) => makeConcept(index)) }],
    };
    const bytes = await buildStatementPdf(longDocument, new Date("2026-08-28T12:00:00Z"));
    const loaded = await PDFDocument.load(bytes);
    expect(loaded.getPageCount()).toBeGreaterThan(1);
  });

  it("does not throw for a person with no debt at all", async () => {
    const empty: StatementDocument = { personName: "Ana", asOfDate: "2026-08-28", blocks: [] };
    const bytes = await buildStatementPdf(empty, new Date("2026-08-28T12:00:00Z"));
    const loaded = await PDFDocument.load(bytes);
    expect(loaded.getPageCount()).toBe(1);
  });
});
