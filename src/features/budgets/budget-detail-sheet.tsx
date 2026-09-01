import { CreditCard, Receipt } from "lucide-react";
import { Sheet } from "@/components/sheet";
import { LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { resolveBudgetAvailability } from "@/features/budgets/budget-availability";
import { useBudgetMovements } from "@/hooks/use-budgets";
import { formatFinancialDate } from "@/lib/dates";
import { cn } from "@/lib/cn";
import type { BudgetPeriodSummary } from "@/types/database";

export function BudgetDetailSheet({ budget, month, onOpenChange, open }: { budget: BudgetPeriodSummary | null; month: string; onOpenChange: (open: boolean) => void; open: boolean }) {
  const movements = useBudgetMovements(budget?.category_id, budget?.currency, month);
  const availability = budget ? resolveBudgetAvailability(budget.available_minor) : null;

  return <Sheet {...(budget ? { description: `Cómo se compone el gasto de ${budget.category_name.toLowerCase()} este periodo.` } : {})} onOpenChange={onOpenChange} open={open} title={budget?.category_name ?? "Presupuesto"}>
    {budget && availability ? <div className="space-y-6">
      <div className="grid grid-cols-3 gap-4 rounded-2xl border border-border bg-surface-secondary p-4">
        <div><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Gastado</p><MoneyValue amount={budget.spent_minor} currency={budget.currency} size="sm" /></div>
        <div><p className="text-[10px] uppercase tracking-wide text-muted-foreground">{availability.label}</p><MoneyValue amount={availability.amountMinor} className={cn(availability.isExceeded && "text-danger")} currency={budget.currency} size="sm" /></div>
        <div><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Límite</p><MoneyValue amount={budget.limit_minor} currency={budget.currency} size="sm" /></div>
      </div>

      <div>
        <h3 className="text-sm font-semibold text-muted-foreground">Movimientos que componen este gasto</h3>
        {movements.isLoading ? <LoadingState label="Cargando movimientos" /> : null}
        {!movements.isLoading && (movements.data?.length ?? 0) === 0 ? <p className="mt-3 text-sm text-muted-foreground">Sin movimientos en este periodo.</p> : null}
        <div className="mt-3 divide-y divide-border border-y border-border">
          {(movements.data ?? []).map((movement) => <div className="flex items-center justify-between gap-4 py-3" key={`${movement.row_kind}-${movement.event_id}-${movement.occurred_on}`}>
            <div className="flex min-w-0 items-center gap-3">
              <span className="grid size-8 shrink-0 place-items-center rounded-full bg-primary-soft text-primary-strong">{movement.row_kind === "installment" ? <CreditCard className="size-4" /> : <Receipt className="size-4" />}</span>
              <div className="min-w-0"><p className="truncate text-sm font-medium">{movement.description ?? "Sin descripción"}</p><p className="mt-0.5 text-xs text-muted-foreground">
                {formatFinancialDate(movement.occurred_on)}
                {movement.row_kind === "installment" ? ` · Mensualidad ${movement.installment_number} de ${movement.installment_count}` : movement.source_name ? ` · ${movement.source_name}` : ""}
              </p></div>
            </div>
            <MoneyValue amount={movement.personal_amount_minor} currency={budget.currency} size="sm" />
          </div>)}
        </div>
      </div>
    </div> : null}
  </Sheet>;
}
