import { formatFinancialDate } from "@/lib/dates";
import type { CurrencyCode, PersonPeriodConcept, PersonStatement, PersonStatementPayment } from "@/types/database";

// Shared shape for the person statement screen, PDF, Excel and CSV so all
// four read the exact same already-computed figures from
// get_person_statement — nothing here recomputes a balance or a date, it
// only formats and groups what the RPC already returned.

export type StatementConcept = {
  id: string;
  description: string;
  typeLabel: string;
  /** Correspondía: lo que originalmente correspondía a este concepto en el periodo. */
  amountMinor: string;
  /** Pagado: lo que ya se cubrió de este concepto (amountMinor = coveredMinor + outstandingMinor). */
  coveredMinor: string;
  purchaseAmountMinor: string;
  /** Pendiente: lo que todavía falta de este concepto. */
  outstandingMinor: string;
};

export type StatementPayment = PersonStatementPayment;

export type StatementBlock = {
  currency: CurrencyCode;
  periodLabel: string;
  periodStart: string | null;
  paymentDueDate: string | null;
  /** Total del periodo: lo que originalmente correspondía pagar este periodo (fijo, no baja al pagar). */
  periodTotalMinor: string;
  /** Cubierto: lo ya aplicado a este periodo (pagos reales + reconciliación histórica). */
  coveredMinor: string;
  /** Pendiente este periodo: periodTotalMinor = coveredMinor + remainingMinor. La cifra accionable. */
  remainingMinor: string;
  /** Cuánto de coveredMinor viene de reconciliar cronograma histórico, no de un pago nuevo. */
  reconciledMinor: string;
  overdueMinor: string;
  overdueSince: string | null;
  /** Te debe en total: deuda real total (incluye periodos futuros), distinta de periodTotalMinor. */
  totalOwedMinor: string;
  creditBalanceMinor: string;
  concepts: StatementConcept[];
  payments: StatementPayment[];
};

export type StatementDocument = {
  personName: string;
  asOfDate: string;
  blocks: StatementBlock[];
};

function conceptTypeLabel(concept: PersonPeriodConcept): string {
  if (concept.installment_number && concept.installment_count) {
    return `Mensualidad ${concept.installment_number} de ${concept.installment_count}`;
  }
  return "Compra compartida";
}

function periodLabel(periodStart: string | null, paymentDueDate: string | null): string {
  if (!periodStart && !paymentDueDate) return "Sin periodo activo";
  if (periodStart && paymentDueDate) return `${formatFinancialDate(periodStart, "d MMM")} — ${formatFinancialDate(paymentDueDate, "d MMM")}`;
  return formatFinancialDate((periodStart ?? paymentDueDate) as string, "d MMM");
}

export function buildStatementDocument(personName: string, statement: PersonStatement): StatementDocument {
  const blocks: StatementBlock[] = statement.periods.map((period) => ({
    currency: period.currency,
    periodLabel: periodLabel(period.period_start, period.payment_due_date),
    periodStart: period.period_start,
    paymentDueDate: period.payment_due_date,
    periodTotalMinor: period.subtotal_minor,
    coveredMinor: period.paid_minor,
    remainingMinor: period.remaining_minor,
    reconciledMinor: period.reconciled_minor,
    overdueMinor: period.overdue_minor,
    overdueSince: period.overdue_since,
    totalOwedMinor: period.total_outstanding_minor,
    creditBalanceMinor: period.credit_balance_minor,
    concepts: period.concepts.map((concept) => ({
      id: concept.id,
      description: concept.description,
      typeLabel: conceptTypeLabel(concept),
      amountMinor: concept.amount_minor,
      coveredMinor: concept.paid_minor,
      purchaseAmountMinor: concept.purchase_amount_minor,
      outstandingMinor: concept.outstanding_minor,
    })),
    payments: statement.payments.filter((payment) => payment.currency === period.currency),
  }));
  return { personName, asOfDate: statement.as_of_date, blocks };
}
