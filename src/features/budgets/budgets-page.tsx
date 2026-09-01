import { addMonths, format, startOfMonth } from "date-fns";
import { es } from "date-fns/locale";
import { ChevronLeft, ChevronRight, Plus, Wallet } from "lucide-react";
import { useMemo, useState } from "react";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { Button } from "@/components/ui/button";
import { resolveBudgetAvailability } from "@/features/budgets/budget-availability";
import { BudgetDetailSheet } from "@/features/budgets/budget-detail-sheet";
import { BudgetForm } from "@/features/budgets/budget-form";
import { useBudgetsForPeriod } from "@/hooks/use-budgets";
import { cn } from "@/lib/cn";
import { toUserMessage } from "@/lib/errors";
import type { BudgetPeriodSummary } from "@/types/database";

function monthKey(date: Date): string {
  return format(startOfMonth(date), "yyyy-MM-dd");
}

export function BudgetsPage() {
  const [monthDate, setMonthDate] = useState(() => startOfMonth(new Date()));
  const month = monthKey(monthDate);
  const isFuture = monthDate.getTime() > startOfMonth(new Date()).getTime();
  const budgets = useBudgetsForPeriod(month);
  const [formOpen, setFormOpen] = useState(false);
  const [detail, setDetail] = useState<BudgetPeriodSummary | null>(null);

  const byCurrency = useMemo(() => {
    const groups = new Map<string, BudgetPeriodSummary[]>();
    for (const item of budgets.data ?? []) {
      const list = groups.get(item.currency) ?? [];
      list.push(item);
      groups.set(item.currency, list);
    }
    return [...groups.entries()];
  }, [budgets.data]);

  if (budgets.isLoading) return <LoadingState label="Cargando presupuestos" />;
  if (budgets.isError) return <ErrorState message={toUserMessage(budgets.error)} onRetry={() => void budgets.refetch()} />;

  return <PageTransition><div className="space-y-8">
    <PageHeader actions={<Button onClick={() => setFormOpen(true)}><Plus className="size-4" />Nuevo presupuesto</Button>} eyebrow="Plan" subtitle="Cuánto planeaste gastar por categoría y cuánto llevas." title="Presupuestos" />

    <div className="flex items-center justify-center gap-4 sm:justify-start">
      <Button aria-label="Mes anterior" onClick={() => setMonthDate((current) => addMonths(current, -1))} size="icon" variant="ghost"><ChevronLeft className="size-4" /></Button>
      <p className="min-w-40 text-center text-lg font-semibold capitalize tracking-tight sm:text-left">{format(monthDate, "MMMM yyyy", { locale: es })}</p>
      <Button aria-label="Mes siguiente" onClick={() => setMonthDate((current) => addMonths(current, 1))} size="icon" variant="ghost"><ChevronRight className="size-4" /></Button>
      {monthDate.getTime() !== startOfMonth(new Date()).getTime() ? <Button className="ml-2" onClick={() => setMonthDate(startOfMonth(new Date()))} size="sm" variant="ghost">Hoy</Button> : null}
    </div>

    {(budgets.data?.length ?? 0) === 0 ? (
      <EmptyState action={<Button onClick={() => setFormOpen(true)}>Crear presupuesto</Button>} description="Crea un presupuesto mensual por categoría para ver cuánto llevas gastado." title="Sin presupuestos todavía" />
    ) : (
      <div className="space-y-8">
        {byCurrency.map(([currency, items]) => <section className="space-y-4" key={currency}>
          {byCurrency.length > 1 ? <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{currency}</p> : null}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {items.map((budget) => <BudgetCard budget={budget} isFuture={isFuture} key={budget.id} onClick={() => setDetail(budget)} />)}
          </div>
        </section>)}
      </div>
    )}
  </div>

  <BudgetForm onOpenChange={setFormOpen} open={formOpen} periodMonth={month} />
  <BudgetDetailSheet budget={detail} month={month} onOpenChange={(open) => { if (!open) setDetail(null); }} open={detail !== null} /></PageTransition>;
}

function BudgetCard({ budget, isFuture, onClick }: { budget: BudgetPeriodSummary; isFuture: boolean; onClick: () => void }) {
  const percentage = Math.max(0, budget.percentage);
  const availability = resolveBudgetAvailability(budget.available_minor);
  const status = availability.isExceeded ? "excedido" : percentage >= 85 ? "cerca" : "normal";
  const barColor = status === "excedido" ? "bg-danger" : status === "cerca" ? "bg-warning" : "bg-primary";
  const availableColor = availability.isExceeded ? "text-danger" : "text-foreground";

  return <button className="group rounded-2xl border border-border bg-surface p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" onClick={onClick} type="button">
    <div className="flex items-center gap-3">
      <span className="grid size-10 shrink-0 place-items-center rounded-full bg-primary-soft text-primary-strong"><Wallet className="size-[18px]" /></span>
      <div className="min-w-0"><h2 className="truncate font-semibold">{budget.category_name}</h2>{!budget.is_recurring ? <p className="text-[10px] uppercase tracking-wide text-primary">Excepción de este mes</p> : null}</div>
    </div>

    <div className="mt-4 flex items-baseline gap-1.5">
      <MoneyValue amount={budget.spent_minor} currency={budget.currency} size="lg" />
      <span className="text-sm text-muted-foreground">de <MoneyValue amount={budget.limit_minor} currency={budget.currency} size="sm" /></span>
    </div>

    <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-secondary">
      <div className={cn("h-full rounded-full transition-all duration-normal", barColor)} style={{ width: `${Math.min(100, percentage)}%` }} />
    </div>

    <div className="mt-3 flex items-center justify-between text-xs">
      <span className={cn("font-medium", availableColor)}>{availability.label} <MoneyValue amount={availability.amountMinor} currency={budget.currency} size="sm" /></span>
      <span className="font-semibold text-muted-foreground">{percentage}%</span>
    </div>

    {isFuture && budget.spent_minor === "0" ? <p className="mt-3 text-xs text-muted-foreground">Sin gasto todavía · presupuesto planeado</p> : null}
  </button>;
}
