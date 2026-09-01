import { zipSync } from "fflate";

import { formatFinancialDate } from "@/lib/dates";
import { minorToDisplay } from "@/lib/money";
import type { StatementDocument } from "@/lib/person-statement";

// Hand-built OOXML (.xlsx is a zip of XML parts) using fflate, already a
// project dependency, instead of pulling in a full spreadsheet library.
// Monetary cells are real numbers (minor units / 100), not strings, with a
// currency number format applied via styles.xml.

function escapeXml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

function minorToNumber(minor: string): number {
  return Number(minorToDisplay(BigInt(minor)));
}

type CellValue = { type: "text"; value: string } | { type: "number"; value: number; money?: boolean };

function textCell(value: string): CellValue { return { type: "text", value }; }
function moneyCell(value: number): CellValue { return { type: "number", value, money: true }; }

function cellXml(ref: string, cell: CellValue): string {
  if (cell.type === "text") return `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${escapeXml(cell.value)}</t></is></c>`;
  return `<c r="${ref}"${cell.money ? ' s="1"' : ""}><v>${cell.value}</v></c>`;
}

const columnLetters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"];

export function buildSheetXml(headers: string[], rows: CellValue[][]): string {
  const headerRow = `<row r="1">${headers.map((label, index) => cellXml(`${columnLetters[index]}1`, textCell(label))).join("")}</row>`;
  const dataRows = rows.map((row, rowIndex) => {
    const rowNumber = rowIndex + 2;
    return `<row r="${rowNumber}">${row.map((cell, colIndex) => cellXml(`${columnLetters[colIndex]}${rowNumber}`, cell)).join("")}</row>`;
  }).join("");
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${headerRow}${dataRows}</sheetData></worksheet>`;
}

export function buildResumenRows(document: StatementDocument): { headers: string[]; rows: CellValue[][] } {
  const headers = ["Persona", "Periodo", "Fecha límite", "Total del periodo", "Cubierto", "Pendiente este periodo", "Vencido", "Te debe en total", "Saldo a favor", "Moneda"];
  const rows = document.blocks.map((block) => [
    textCell(document.personName),
    textCell(block.periodLabel),
    textCell(block.paymentDueDate ? formatFinancialDate(block.paymentDueDate) : "—"),
    moneyCell(minorToNumber(block.periodTotalMinor)),
    moneyCell(minorToNumber(block.coveredMinor)),
    moneyCell(minorToNumber(block.remainingMinor)),
    moneyCell(minorToNumber(block.overdueMinor)),
    moneyCell(minorToNumber(block.totalOwedMinor)),
    moneyCell(minorToNumber(block.creditBalanceMinor)),
    textCell(block.currency),
  ]);
  return { headers, rows };
}

export function buildConceptosRows(document: StatementDocument): { headers: string[]; rows: CellValue[][] } {
  const headers = ["Fecha", "Concepto", "Tipo", "Mensualidad", "Correspondía", "Pagado", "Pendiente", "Moneda"];
  const rows = document.blocks.flatMap((block) => block.concepts.map((concept) => [
    textCell(formatFinancialDate(block.paymentDueDate ?? document.asOfDate)),
    textCell(concept.description),
    textCell(concept.typeLabel.startsWith("Mensualidad") ? "MSI" : "Compra"),
    textCell(concept.typeLabel.startsWith("Mensualidad") ? concept.typeLabel.replace("Mensualidad ", "") : "—"),
    moneyCell(minorToNumber(concept.amountMinor)),
    moneyCell(minorToNumber(concept.coveredMinor)),
    moneyCell(minorToNumber(concept.outstandingMinor)),
    textCell(block.currency),
  ]));
  return { headers, rows };
}

export function buildPagosRows(document: StatementDocument): { headers: string[]; rows: CellValue[][] } {
  const headers = ["Fecha", "Importe", "Aplicado al periodo", "Aplicado a futuro", "Saldo a favor generado", "Cuenta receptora", "Moneda"];
  const rows = document.blocks.flatMap((block) => block.payments.map((payment) => [
    textCell(formatFinancialDate(payment.occurred_on)),
    moneyCell(minorToNumber(payment.amount_minor)),
    moneyCell(minorToNumber(payment.applied_to_period_minor)),
    moneyCell(minorToNumber(payment.applied_to_future_minor)),
    moneyCell(minorToNumber(payment.credit_generated_minor)),
    textCell(payment.account_name ?? "—"),
    textCell(block.currency),
  ]));
  return { headers, rows };
}

const CONTENT_TYPES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`;

const ROOT_RELS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`;

const WORKBOOK_RELS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`;

const WORKBOOK_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Resumen" sheetId="1" r:id="rId1"/><sheet name="Conceptos" sheetId="2" r:id="rId2"/><sheet name="Pagos" sheetId="3" r:id="rId3"/></sheets></workbook>`;

const STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0.00"/></numFmts><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>`;

export function buildStatementXlsx(document: StatementDocument): Uint8Array {
  const resumen = buildResumenRows(document);
  const conceptos = buildConceptosRows(document);
  const pagos = buildPagosRows(document);
  const files: Record<string, Uint8Array> = {
    "[Content_Types].xml": strToU8(CONTENT_TYPES),
    "_rels/.rels": strToU8(ROOT_RELS),
    "xl/workbook.xml": strToU8(WORKBOOK_XML),
    "xl/_rels/workbook.xml.rels": strToU8(WORKBOOK_RELS),
    "xl/styles.xml": strToU8(STYLES_XML),
    "xl/worksheets/sheet1.xml": strToU8(buildSheetXml(resumen.headers, resumen.rows)),
    "xl/worksheets/sheet2.xml": strToU8(buildSheetXml(conceptos.headers, conceptos.rows)),
    "xl/worksheets/sheet3.xml": strToU8(buildSheetXml(pagos.headers, pagos.rows)),
  };
  return zipSync(files, { level: 6 });
}

function strToU8(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}
