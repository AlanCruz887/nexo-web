import { formatFinancialDate } from "@/lib/dates";
import { formatMoney } from "@/lib/money";
import type { StatementDocument } from "@/lib/person-statement";

const HEADERS = ["Fecha", "Concepto", "Tipo", "Mensualidad", "Correspondía", "Pagado", "Pendiente", "Estado", "Moneda"];

function escapeCsvField(value: string): string {
  if (/[",\n]/.test(value)) return `"${value.replace(/"/g, '""')}"`;
  return value;
}

function toRow(values: string[]): string {
  return values.map(escapeCsvField).join(",");
}

export function buildStatementCsv(document: StatementDocument): string {
  const lines = [toRow(HEADERS)];
  for (const block of document.blocks) {
    for (const concept of block.concepts) {
      const isInstallment = concept.typeLabel.startsWith("Mensualidad");
      lines.push(toRow([
        formatFinancialDate(block.paymentDueDate ?? document.asOfDate),
        concept.description,
        isInstallment ? "MSI" : "Compra",
        isInstallment ? concept.typeLabel.replace("Mensualidad ", "") : "—",
        formatMoney(concept.amountMinor, block.currency),
        formatMoney(concept.coveredMinor, block.currency),
        formatMoney(concept.outstandingMinor, block.currency),
        concept.outstandingMinor === "0" ? "Pagado" : "Pendiente",
        block.currency,
      ]));
    }
  }
  // UTF-8 BOM so Excel on Windows opens accented characters correctly.
  return `﻿${lines.join("\r\n")}\r\n`;
}
