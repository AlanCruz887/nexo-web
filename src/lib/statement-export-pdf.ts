import { PDFDocument, StandardFonts, rgb } from "pdf-lib";

import { formatFinancialDate, formatAuditTimestamp } from "@/lib/dates";
import { formatMoney } from "@/lib/money";
import type { StatementBlock, StatementDocument } from "@/lib/person-statement";

// A real structured PDF (selectable text, proper pagination), not a
// screenshot. Every figure comes straight from StatementDocument, which is
// itself a plain reshape of get_person_statement — nothing is recomputed
// here, only laid out on a page.

const PAGE_WIDTH = 612;
const PAGE_HEIGHT = 792;
const MARGIN = 48;
const BLUE = rgb(0.145, 0.388, 0.922);
const INK = rgb(0.06, 0.09, 0.16);
const GRAY = rgb(0.39, 0.45, 0.55);
const LINE = rgb(0.9, 0.92, 0.95);

interface Cursor { page: import("pdf-lib").PDFPage; y: number; pageNumber: number }

export async function buildStatementPdf(document: StatementDocument, generatedAt: Date): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  pdf.setTitle(`Estado de ${document.personName}`);
  pdf.setProducer("Nexo");

  const cursor: Cursor = { page: pdf.addPage([PAGE_WIDTH, PAGE_HEIGHT]), y: PAGE_HEIGHT - MARGIN, pageNumber: 1 };
  drawMainHeader(cursor, document, regular, bold);

  if (document.blocks.length === 0) {
    cursor.y -= 24;
    cursor.page.drawText("Esta persona no tiene compras ni pagos pendientes por el momento.", { x: MARGIN, y: cursor.y, size: 11, font: regular, color: GRAY });
  }

  for (const block of document.blocks) {
    ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 40);
    drawCurrencyHeading(cursor, block, bold);
    drawSummary(pdf, cursor, block, document, regular, bold, generatedAt);
    drawConcepts(pdf, cursor, block, document, regular, bold, generatedAt);
    drawPayments(pdf, cursor, block, document, regular, bold, generatedAt);
    cursor.y -= 16;
  }

  drawFooter(cursor, regular, generatedAt);
  return pdf.save();
}

function drawMainHeader(cursor: Cursor, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont) {
  cursor.page.drawText("NEXO", { x: MARGIN, y: cursor.y, size: 11, font: bold, color: BLUE });
  cursor.y -= 30;
  cursor.page.drawText(`Estado de ${document.personName}`, { x: MARGIN, y: cursor.y, size: 22, font: bold, color: INK });
  cursor.y -= 26;
  const periodText = document.blocks[0] ? `Periodo ${document.blocks[0].periodLabel}` : "Sin periodo activo";
  cursor.page.drawText(periodText, { x: MARGIN, y: cursor.y, size: 11, font: regular, color: GRAY });
  cursor.y -= 26;
  drawLine(cursor);
  cursor.y -= 20;
}

function drawCompactHeader(cursor: Cursor, document: StatementDocument, bold: import("pdf-lib").PDFFont) {
  cursor.page.drawText("NEXO", { x: MARGIN, y: cursor.y, size: 9, font: bold, color: BLUE });
  cursor.page.drawText(`Estado de ${document.personName} (continuación)`, { x: MARGIN + 42, y: cursor.y, size: 9, font: bold, color: GRAY });
  cursor.y -= 18;
  drawLine(cursor);
  cursor.y -= 18;
}

function drawLine(cursor: Cursor) {
  cursor.page.drawLine({ start: { x: MARGIN, y: cursor.y }, end: { x: PAGE_WIDTH - MARGIN, y: cursor.y }, thickness: 0.75, color: LINE });
}

function newPage(pdf: PDFDocument, cursor: Cursor, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont, generatedAt: Date) {
  drawFooter(cursor, regular, generatedAt);
  cursor.page = pdf.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  cursor.pageNumber += 1;
  cursor.y = PAGE_HEIGHT - MARGIN;
  drawCompactHeader(cursor, document, bold);
}

function ensureSpace(pdf: PDFDocument, cursor: Cursor, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont, generatedAt: Date, needed: number) {
  if (cursor.y - needed < MARGIN + 30) newPage(pdf, cursor, document, regular, bold, generatedAt);
}

function drawFooter(cursor: Cursor, regular: import("pdf-lib").PDFFont, generatedAt: Date) {
  const footerY = MARGIN - 12;
  cursor.page.drawLine({ start: { x: MARGIN, y: footerY + 14 }, end: { x: PAGE_WIDTH - MARGIN, y: footerY + 14 }, thickness: 0.5, color: LINE });
  cursor.page.drawText(`Generado el ${formatAuditTimestamp(generatedAt.toISOString())}`, { x: MARGIN, y: footerY, size: 8, font: regular, color: GRAY });
  cursor.page.drawText(`Nexo — documento privado · Página ${cursor.pageNumber}`, { x: PAGE_WIDTH - MARGIN - 170, y: footerY, size: 8, font: regular, color: GRAY });
}

function drawCurrencyHeading(cursor: Cursor, block: StatementBlock, bold: import("pdf-lib").PDFFont) {
  cursor.page.drawText(block.currency, { x: MARGIN, y: cursor.y, size: 13, font: bold, color: BLUE });
  cursor.y -= 22;
}

function summaryRows(block: StatementBlock): Array<[string, string, boolean?]> {
  const rows: Array<[string, string, boolean?]> = [
    ["A pagar este periodo", formatMoney(block.toPayThisPeriodMinor, block.currency)],
    ["Pagado este periodo", formatMoney(block.paidThisPeriodMinor, block.currency)],
    ["Falta", formatMoney(block.missingMinor, block.currency)],
  ];
  if (block.paymentDueDate) rows.push(["Fecha límite", formatFinancialDate(block.paymentDueDate)]);
  if (BigInt(block.overdueMinor) > 0n) {
    rows.push(["Vencido", formatMoney(block.overdueMinor, block.currency), true]);
    if (block.overdueSince) rows.push(["Vencido desde", formatFinancialDate(block.overdueSince), true]);
  }
  rows.push(["Te debe en total", formatMoney(block.totalOwedMinor, block.currency)]);
  if (BigInt(block.creditBalanceMinor) > 0n) rows.push(["Saldo a favor", formatMoney(block.creditBalanceMinor, block.currency), true]);
  return rows;
}

function drawSummary(pdf: PDFDocument, cursor: Cursor, block: StatementBlock, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont, generatedAt: Date) {
  cursor.page.drawText("Resumen", { x: MARGIN, y: cursor.y, size: 11, font: bold, color: INK });
  cursor.y -= 18;
  for (const [label, value, danger] of summaryRows(block)) {
    ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 16);
    cursor.page.drawText(label, { x: MARGIN, y: cursor.y, size: 10, font: regular, color: GRAY });
    cursor.page.drawText(value, { x: MARGIN + 220, y: cursor.y, size: 10, font: bold, color: danger ? rgb(0.78, 0.16, 0.16) : INK });
    cursor.y -= 15;
  }
  cursor.y -= 8;
}

function drawConcepts(pdf: PDFDocument, cursor: Cursor, block: StatementBlock, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont, generatedAt: Date) {
  if (!block.concepts.length) return;
  ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 40);
  cursor.page.drawText("Este periodo", { x: MARGIN, y: cursor.y, size: 11, font: bold, color: INK });
  cursor.y -= 16;
  drawTableHeader(cursor, bold, ["Concepto", "Tipo", "Importe"], [0, 240, 420]);
  for (const concept of block.concepts) {
    ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 16);
    const amountLabel = concept.purchaseAmountMinor !== concept.amountMinor
      ? `${formatMoney(concept.amountMinor, block.currency)} (de ${formatMoney(concept.purchaseAmountMinor, block.currency)})`
      : formatMoney(concept.amountMinor, block.currency);
    cursor.page.drawText(truncate(concept.description, 34), { x: MARGIN, y: cursor.y, size: 9.5, font: regular, color: INK });
    cursor.page.drawText(concept.typeLabel, { x: MARGIN + 240, y: cursor.y, size: 9.5, font: regular, color: GRAY });
    cursor.page.drawText(amountLabel, { x: MARGIN + 420, y: cursor.y, size: 9.5, font: regular, color: INK });
    cursor.y -= 15;
  }
  ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 16);
  drawLine(cursor);
  cursor.y -= 14;
  cursor.page.drawText("Total del periodo", { x: MARGIN, y: cursor.y, size: 10, font: bold, color: INK });
  cursor.page.drawText(formatMoney(block.toPayThisPeriodMinor, block.currency), { x: MARGIN + 420, y: cursor.y, size: 10, font: bold, color: INK });
  cursor.y -= 22;
}

function drawPayments(pdf: PDFDocument, cursor: Cursor, block: StatementBlock, document: StatementDocument, regular: import("pdf-lib").PDFFont, bold: import("pdf-lib").PDFFont, generatedAt: Date) {
  if (!block.payments.length) return;
  ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 40);
  cursor.page.drawText("Pagos recibidos", { x: MARGIN, y: cursor.y, size: 11, font: bold, color: INK });
  cursor.y -= 16;
  drawTableHeader(cursor, bold, ["Fecha", "Cuenta", "Importe", "Detalle"], [0, 90, 190, 280]);
  for (const payment of block.payments) {
    ensureSpace(pdf, cursor, document, regular, bold, generatedAt, 16);
    const detailParts: string[] = [];
    if (BigInt(payment.applied_to_future_minor) > 0n) detailParts.push(`Adelanto ${formatMoney(payment.applied_to_future_minor, block.currency)}`);
    if (BigInt(payment.credit_generated_minor) > 0n) detailParts.push(`Saldo a favor ${formatMoney(payment.credit_generated_minor, block.currency)}`);
    cursor.page.drawText(formatFinancialDate(payment.occurred_on), { x: MARGIN, y: cursor.y, size: 9.5, font: regular, color: INK });
    cursor.page.drawText(truncate(payment.account_name ?? "—", 18), { x: MARGIN + 90, y: cursor.y, size: 9.5, font: regular, color: GRAY });
    cursor.page.drawText(formatMoney(payment.amount_minor, block.currency), { x: MARGIN + 190, y: cursor.y, size: 9.5, font: regular, color: INK });
    cursor.page.drawText(detailParts.join(" · ") || "Aplicado al periodo", { x: MARGIN + 280, y: cursor.y, size: 9, font: regular, color: GRAY });
    cursor.y -= 15;
  }
  cursor.y -= 8;
}

function drawTableHeader(cursor: Cursor, bold: import("pdf-lib").PDFFont, labels: string[], xOffsets: number[]) {
  labels.forEach((label, index) => {
    cursor.page.drawText(label, { x: MARGIN + xOffsets[index]!, y: cursor.y, size: 8.5, font: bold, color: GRAY });
  });
  cursor.y -= 6;
  drawLine(cursor);
  cursor.y -= 12;
}

function truncate(value: string, max: number) {
  return value.length > max ? `${value.slice(0, max - 1)}…` : value;
}
