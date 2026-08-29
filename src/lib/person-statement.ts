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
  amountMinor: string;
  purchaseAmountMinor: string;
  outstandingMinor: string;
};

export type StatementPayment = PersonStatementPayment;

export type StatementBlock = {
  currency: CurrencyCode;
  periodLabel: string;
  periodStart: string | null;
  paymentDueDate: string | null;
  toPayThisPeriodMinor: string;
  paidThisPeriodMinor: string;
  missingMinor: string;
  overdueMinor: string;
  overdueSince: string | null;
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
    toPayThisPeriodMinor: period.subtotal_minor,
    paidThisPeriodMinor: period.paid_minor,
    missingMinor: period.remaining_minor,
    overdueMinor: period.overdue_minor,
    overdueSince: period.overdue_since,
    totalOwedMinor: period.total_outstanding_minor,
    creditBalanceMinor: period.credit_balance_minor,
    concepts: period.concepts.map((concept) => ({
      id: concept.id,
      description: concept.description,
      typeLabel: conceptTypeLabel(concept),
      amountMinor: concept.amount_minor,
      purchaseAmountMinor: concept.purchase_amount_minor,
      outstandingMinor: concept.outstanding_minor,
    })),
    payments: statement.payments.filter((payment) => payment.currency === period.currency),
  }));
  return { personName, asOfDate: statement.as_of_date, blocks };
}
