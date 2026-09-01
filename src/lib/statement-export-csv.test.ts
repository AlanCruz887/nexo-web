import { describe, expect, it } from "vitest";

import type { StatementDocument } from "@/lib/person-statement";
import { buildStatementCsv } from "@/lib/statement-export-csv";

const document: StatementDocument = {
  personName: "Carlos",
  asOfDate: "2026-08-28",
  blocks: [
    {
      currency: "MXN", periodLabel: "9 ago — 29 sep", periodStart: "2026-08-09", paymentDueDate: "2026-09-29",
      periodTotalMinor: "176667", coveredMinor: "30000", remainingMinor: "146667", reconciledMinor: "0",
      overdueMinor: "0", overdueSince: null, totalOwedMinor: "770000", creditBalanceMinor: "0",
      concepts: [
        { id: "c1", description: "MacBook Pro", typeLabel: "Mensualidad 5 de 12", amountMinor: "66667", coveredMinor: "0", purchaseAmountMinor: "1200000", outstandingMinor: "66667" },
        { id: "c2", description: 'Cena, "compartida"', typeLabel: "Compra compartida", amountMinor: "40000", coveredMinor: "40000", purchaseAmountMinor: "100000", outstandingMinor: "0" },
      ],
      payments: [],
    },
  ],
};

describe("buildStatementCsv", () => {
  it("opens with a UTF-8 BOM and the expected header row", () => {
    const csv = buildStatementCsv(document);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv.slice(1).split("\r\n")[0]).toBe("Fecha,Concepto,Tipo,Mensualidad,Correspondía,Pagado,Pendiente,Estado,Moneda");
  });

  it("carries the exact per-period amount and marks an MSI concept with its installment progress", () => {
    const csv = buildStatementCsv(document);
    const macbookLine = csv.split("\r\n").find((line) => line.includes("MacBook Pro"));
    expect(macbookLine).toContain("MSI,5 de 12,$666.67,$0.00,$666.67,Pendiente,MXN");
  });

  it("marks a fully covered concept as Pagado, not Pendiente", () => {
    const csv = buildStatementCsv(document);
    const cenaLine = csv.split("\r\n").find((line) => line.includes("Cena"));
    expect(cenaLine).toContain("Pagado,MXN");
  });

  it("quotes a field that itself contains a comma and a quote", () => {
    const csv = buildStatementCsv(document);
    expect(csv).toContain('"Cena, ""compartida"""');
  });
});
