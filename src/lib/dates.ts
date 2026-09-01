import { format, isValid, parseISO } from "date-fns";
import { es } from "date-fns/locale";

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
  return format(parseISO(parseFinancialDate(value)), pattern, { locale: es });
}

export function parseAuditTimestamp(value: string): Date {
  const parsed = parseISO(value);
  if (!isValid(parsed) || financialDatePattern.test(value)) {
    throw new TypeError("El timestamp de auditoría debe incluir fecha y hora.");
  }
  return parsed;
}

export function formatAuditTimestamp(
  value: AuditTimestamp,
  pattern = "dd/MM/yyyy HH:mm",
): string {
  return format(parseAuditTimestamp(value), pattern, { locale: es });
}

/**
 * Short, human "last used" style formatting: "Hace 3 min", "Hoy, 9:42",
 * "Ayer", or a plain date further back. `now` is injectable for tests --
 * "today"/"yesterday" are deliberately computed by comparing local
 * calendar days against `now` directly (not date-fns's isToday/
 * isYesterday, which always read the real system clock and would
 * silently ignore an injected `now`, making this untestable and, worse,
 * technically wrong the instant a test or a caller ever needed a
 * non-"real right now" reference point).
 */
export function formatRelativeTime(value: AuditTimestamp, now: Date = new Date()): string {
  const date = parseAuditTimestamp(value);
  const diffMinutes = Math.floor((now.getTime() - date.getTime()) / 60_000);
  if (diffMinutes < 1) return "Hace un momento";
  if (diffMinutes < 60) return `Hace ${diffMinutes} min`;
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const startOfYesterday = startOfToday - 86_400_000;
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  if (startOfDate === startOfToday) return `Hoy, ${format(date, "HH:mm", { locale: es })}`;
  if (startOfDate === startOfYesterday) return "Ayer";
  return format(date, "d 'de' MMM, yyyy", { locale: es });
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
