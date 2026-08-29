import { CreditCard, HandCoins, RotateCcw } from "lucide-react";

import { MoneyValue } from "@/components/money-value";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import type { CardStatementActivitySegment, CurrencyCode } from "@/types/database";
import { parseInstallmentSegmentDescription } from "@/features/cards/installment-presentation";

type ActivityGroupKind = "open" | "pending" | "closed";

export function CardStatementActivity({
  closedStatementDates,
  currency,
  openStatementDate,
  onSelect,
  pendingStatementDate,
  segments,
}: {
  closedStatementDates: string[];
  currency: CurrencyCode;
  openStatementDate: string;
  onSelect: (eventId: string) => void;
  pendingStatementDate?: string;
  segments: CardStatementActivitySegment[];
}) {
  const visibleDates = new Set([openStatementDate, pendingStatementDate, ...closedStatementDates].filter(Boolean));
  const closedDates = new Set(closedStatementDates);
  const groups = segments.reduce<Map<string, CardStatementActivitySegment[]>>((map, segment) => {
    if (!visibleDates.has(segment.group_statement_date)) return map;
    map.set(segment.group_statement_date, [...(map.get(segment.group_statement_date) ?? []), segment]);
    return map;
  }, new Map());
  const orderedGroups = Array.from(groups.entries()).sort(([left], [right]) => {
    const leftRank = groupRank(left, openStatementDate, pendingStatementDate);
    const rightRank = groupRank(right, openStatementDate, pendingStatementDate);
    return leftRank === rightRank ? right.localeCompare(left) : leftRank - rightRank;
  });

  let renderedClosedHeading = false;
  return <div className="space-y-9">{orderedGroups.map(([statementDate, items]) => {
    const kind: ActivityGroupKind = statementDate === openStatementDate ? "open" : statementDate === pendingStatementDate ? "pending" : "closed";
    const showClosedHeading = kind === "closed" && !renderedClosedHeading;
    if (showClosedHeading) renderedClosedHeading = true;
    return <div key={statementDate}>
      {kind === "open" ? <Eyebrow>Estado actual / próximo</Eyebrow> : kind === "pending" ? <Eyebrow>Periodo pendiente de cierre</Eyebrow> : showClosedHeading ? <Eyebrow>Estados cerrados</Eyebrow> : null}
      <StatementGroup currency={currency} items={items} kind={closedDates.has(statementDate) ? "closed" : kind} onSelect={onSelect} statementDate={statementDate} />
    </div>;
  })}</div>;
}

function StatementGroup({ currency, items, kind, onSelect, statementDate }: { currency: CurrencyCode; items: CardStatementActivitySegment[]; kind: ActivityGroupKind; onSelect: (eventId: string) => void; statementDate: string }) {
  const purchases = total(items, "purchase");
  const installments = total(items, "installment");
  const refunds = total(items, "refund");
  const advancePayments = total(items, "payment_advance");
  const appliedPayments = total(items, "payment_applied");
  const netPurchases = purchases + installments - refunds;
  const netImpact = netPurchases - advancePayments - appliedPayments;
  return <section className="mt-3">
    <div className="mb-4 flex flex-wrap items-start justify-between gap-4">
      <div><h3 className="font-semibold">Estado {formatFinancialDate(statementDate, "dd MMM yyyy")}</h3><p className={cn("mt-1 text-xs font-medium", kind === "open" ? "text-primary" : "text-muted-foreground")}>{kind === "open" ? "Periodo actual" : kind === "pending" ? "Pendiente de cierre" : "Estado cerrado"}</p></div>
      <div className="grid grid-cols-2 gap-x-5 gap-y-2 text-xs sm:grid-cols-4">
        <Summary amount={purchases.toString()} currency={currency} label="Compras" />
        {installments > 0n ? <Summary amount={installments.toString()} currency={currency} label="MSI del periodo" /> : null}
        <Summary amount={refunds.toString()} currency={currency} label="Reembolsos" />
        {advancePayments > 0n ? <Summary amount={advancePayments.toString()} currency={currency} label="Pagos anticipados" /> : null}
        {appliedPayments > 0n ? <Summary amount={appliedPayments.toString()} currency={currency} label="Pagos aplicados" /> : null}
        <Summary amount={netPurchases.toString()} currency={currency} label="Compras del periodo" />
        <Summary amount={netImpact.toString()} currency={currency} label="Después de pagos" />
      </div>
    </div>
    <div className="divide-y divide-border/60 border-y border-border/60">{items.map((segment) => <SegmentRow currency={currency} key={segment.segment_id} onClick={() => onSelect(segment.event_id)} segment={segment} />)}</div>
  </section>;
}

function Eyebrow({ children }: { children: React.ReactNode }) {
  return <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">{children}</p>;
}

function groupRank(statementDate: string, openStatementDate: string, pendingStatementDate?: string) {
  if (statementDate === openStatementDate) return 0;
  if (statementDate === pendingStatementDate) return 1;
  return 2;
}

function total(items: CardStatementActivitySegment[], kind: CardStatementActivitySegment["segment_kind"]) {
  return items.reduce((sum, item) => sum + (item.segment_kind === kind ? BigInt(item.amount_minor) : 0n), 0n);
}

function Summary({ amount, currency, label }: { amount: string; currency: CurrencyCode; label: string }) {
  return <div><p className="text-muted-foreground">{label}</p><MoneyValue amount={amount} className="mt-0.5 block font-semibold" currency={currency} size="sm" /></div>;
}

function SegmentRow({ currency, onClick, segment }: { currency: CurrencyCode; onClick: () => void; segment: CardStatementActivitySegment }) {
  const isPurchase = segment.segment_kind === "purchase" || segment.segment_kind === "installment";
  const isRefund = segment.segment_kind === "refund";
  const isAdvance = segment.segment_kind === "payment_advance";
  const Icon = isPurchase ? CreditCard : isRefund ? RotateCcw : HandCoins;
  const installment = segment.segment_kind === "installment" ? parseInstallmentSegmentDescription(segment.description) : null;
  const label = isAdvance ? "Pago anticipado" : segment.segment_kind === "payment_applied" ? "Pago aplicado" : installment?.description ?? segment.description;
  const detail = installment?.progress ?? (isAdvance ? `Próximo estado ${formatFinancialDate(segment.group_statement_date, "dd MMM yyyy")}` : segment.segment_kind === "payment_applied" ? "Aplicado a estado cerrado" : formatFinancialDate(segment.occurred_on, "dd MMM yyyy"));
  const displayAmount = isPurchase ? (-BigInt(segment.amount_minor)).toString() : segment.amount_minor;
  return <button className="grid min-h-16 w-full grid-cols-[auto_1fr_auto] items-center gap-3 px-1 py-3 text-left transition-colors hover:bg-surface-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 sm:px-2" onClick={onClick} type="button">
    <span className={cn("grid size-9 place-items-center rounded-xl", isPurchase ? "bg-primary-soft text-primary" : isRefund ? "bg-success/10 text-success" : "bg-primary-soft text-primary")}><Icon className="size-4" /></span>
    <span className="min-w-0"><span className="block truncate text-sm font-semibold">{label}</span><span className="mt-0.5 block truncate text-xs text-muted-foreground">{detail}{segment.source_account_name ? ` · ${segment.source_account_name}` : ""}</span></span>
    <MoneyValue amount={displayAmount} className={cn("text-sm", isPurchase ? "text-danger" : "text-success")} currency={currency} sign="always" />
  </button>;
}
