import { format, isValid, parseISO } from "date-fns";

export type FinancialDate = string;
export type AuditTimestamp = string;

const financialDatePattern = /^\d{4}-\d{2}-\d{2}$/;

export function parseFinancialDate(value: string): FinancialDate {
  const parsed = parseISO(value);
  if (!financialDatePattern.test(value) || !isValid(parsed)) {
    throw new TypeError("La fecha financiera debe usar el formato YYYY-MM-DD.");
  }
  return value;
}

export function formatFinancialDate(
  value: FinancialDate,
  pattern = "dd/MM/yyyy",
): string {
  return format(parseISO(parseFinancialDate(value)), pattern);
}

export function parseAuditTimestamp(value: string): Date {
  const parsed = parseISO(value);
  if (!isValid(parsed) || financialDatePattern.test(value)) {
    throw new TypeError("El timestamp de auditoría debe incluir fecha y hora.");
  }
  return parsed;
}

export function getBrowserTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

export function isValidTimezone(timezone: string): boolean {
  try {
    new Intl.DateTimeFormat("es-MX", { timeZone: timezone }).format();
    return true;
  } catch {
    return false;
  }
}
