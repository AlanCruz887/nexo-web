import { describe, expect, it } from "vitest";

import type { StatementDocument } from "@/lib/person-statement";
import { buildConceptosRows, buildPagosRows, buildResumenRows, buildSheetXml, buildStatementXlsx } from "@/lib/statement-export-xlsx";

const document: StatementDocument = {
  personName: "Carlos",
  asOfDate: "2026-08-28",
  blocks: [
    {
      currency: "MXN", periodLabel: "9 ago — 29 sep", periodStart: "2026-08-09", paymentDueDate: "2026-09-29",
      toPayThisPeriodMinor: "176667", paidThisPeriodMinor: "30000", missingMinor: "146667",
      overdueMinor: "0", overdueSince: null, totalOwedMinor: "770000", creditBalanceMinor: "0",
      concepts: [
        { id: "c1", description: "MacBook Pro", typeLabel: "Mensualidad 5 de 12", amountMinor: "66667", purchaseAmountMinor: "1200000", outstandingMinor: "66667" },
        { id: "c2", description: "Cena", typeLabel: "Compra compartida", amountMinor: "40000", purchaseAmountMinor: "100000", outstandingMinor: "0" },
      ],
      payments: [
        { event_id: "p1", occurred_on: "2026-08-18", currency: "MXN", account_name: "BBVA", amount_minor: "30000", applied_to_period_minor: "30000", applied_to_future_minor: "0", credit_generated_minor: "0" },
      ],
    },
  ],
};

describe("buildResumenRows", () => {
  it("puts the exact minor-unit figures on the summary sheet as real numbers, not text", () => {
    const { rows } = buildResumenRows(document);
    const row = rows[0]!;
    expect(row[3]).toEqual({ type: "number", value: 1766.67, money: true });
    expect(row[4]).toEqual({ type: "number", value: 300, money: true });
    expect(row[5]).toEqual({ type: "number", value: 1466.67, money: true });
    expect(row[7]).toEqual({ type: "number", value: 7700, money: true });
  });
});

describe("buildConceptosRows", () => {
  it("labels an MSI concept with its installment progress and exact period amount", () => {
    const { rows } = buildConceptosRows(document);
    const macbook = rows.find((row) => row[1]?.type === "text" && row[1].value === "MacBook Pro")!;
    expect(macbook[2]).toEqual({ type: "text", value: "MSI" });
    expect(macbook[3]).toEqual({ type: "text", value: "5 de 12" });
    expect(macbook[4]).toEqual({ type: "number", value: 666.67, money: true });
  });

  it("labels a plain shared purchase without an installment number", () => {
    const { rows } = buildConceptosRows(document);
    const cena = rows.find((row) => row[1]?.type === "text" && row[1].value === "Cena")!;
    expect(cena[2]).toEqual({ type: "text", value: "Compra" });
    expect(cena[3]).toEqual({ type: "text", value: "—" });
  });
});

describe("buildPagosRows", () => {
  it("keeps the exact payment amount and account name", () => {
    const { rows } = buildPagosRows(document);
    expect(rows[0]?.[1]).toEqual({ type: "number", value: 300, money: true });
    expect(rows[0]?.[5]).toEqual({ type: "text", value: "BBVA" });
  });
});

describe("buildSheetXml", () => {
  it("renders a money cell as a numeric <v>, never as inline text", () => {
    const xml = buildSheetXml(["Importe"], [[{ type: "number", value: 1766.67, money: true }]]);
    expect(xml).toContain('<c r="A2" s="1"><v>1766.67</v></c>');
    expect(xml).not.toContain("1766.67</t>");
  });

  it("escapes XML-sensitive characters in text cells", () => {
    const xml = buildSheetXml(["Concepto"], [[{ type: "text", value: 'Compra "grande" & extra' }]]);
    expect(xml).toContain("Compra &quot;grande&quot; &amp; extra");
  });
});

describe("buildStatementXlsx", () => {
  it("produces a valid zip (xlsx) starting with the local file header signature", () => {
    const bytes = buildStatementXlsx(document);
    expect(bytes.length).toBeGreaterThan(0);
    expect(bytes[0]).toBe(0x50); // 'P'
    expect(bytes[1]).toBe(0x4b); // 'K'
  });

  it("does not throw for a person with no debt at all", () => {
    const empty: StatementDocument = { personName: "Ana", asOfDate: "2026-08-28", blocks: [] };
    expect(() => buildStatementXlsx(empty)).not.toThrow();
  });
});
