import { Plus, Target } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { Button } from "@/components/ui/button";
import { GoalForm } from "@/features/goals/goal-form";
import { useGoals } from "@/hooks/use-goals";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import type { GoalBalance } from "@/types/database";

export function GoalsPage() {
  const goals = useGoals();
  const [formOpen, setFormOpen] = useState(false);

  if (goals.isLoading) return <LoadingState label="Cargando metas" />;
  if (goals.isError) return <ErrorState message={toUserMessage(goals.error)} onRetry={() => void goals.refetch()} />;

  const active = (goals.data ?? []).filter((goal) => goal.archived_at === null);

  return <PageTransition><div className="space-y-8">
    <PageHeader actions={<Button onClick={() => setFormOpen(true)}><Plus className="size-4" />Nueva meta</Button>} eyebrow="Plan" subtitle="Convierte tus planes en objetivos concretos." title="Metas" />

    {active.length === 0 ? (
      <EmptyState action={<Button onClick={() => setFormOpen(true)}>Crear meta</Button>} description="Crea una meta para saber cuánto llevas ahorrado y cuánto te falta." title="Todavía no tienes metas" />
    ) : (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {active.map((goal) => <GoalCard goal={goal} key={goal.id} />)}
      </div>
    )}

    <GoalForm onOpenChange={setFormOpen} open={formOpen} /></div></PageTransition>;
}

function GoalCard({ goal }: { goal: GoalBalance }) {
  const percentage = Math.max(0, goal.percentage);
  const hasShortfall = BigInt(goal.backed_minor) < BigInt(goal.saved_minor);
  const barColor = goal.is_achieved ? "bg-primary" : hasShortfall ? "bg-warning" : "bg-primary";

  return <Link className="group rounded-2xl border border-border bg-surface p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" to={`/metas/${goal.id}`}>
    <div className="flex items-center gap-3">
      <span className="grid size-10 shrink-0 place-items-center rounded-full bg-primary-soft text-primary-strong"><Target className="size-[18px]" /></span>
      <div className="min-w-0"><h2 className="truncate font-semibold">{goal.name}</h2>{goal.status === "paused" ? <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Pausada</p> : null}</div>
    </div>

    <div className="mt-4 flex items-baseline gap-1.5">
      <MoneyValue amount={goal.saved_minor} currency={goal.currency} size="lg" />
      <span className="text-sm text-muted-foreground">de <MoneyValue amount={goal.target_minor} currency={goal.currency} size="sm" /></span>
    </div>

    <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-secondary">
      <div className={cn("h-full rounded-full transition-all duration-normal", barColor)} style={{ width: `${Math.min(100, percentage)}%` }} />
    </div>

    <div className="mt-3 flex items-center justify-between text-xs">
      <span className="font-medium text-muted-foreground">{goal.is_achieved ? "Meta alcanzada" : <>Faltan <MoneyValue amount={goal.remaining_minor} currency={goal.currency} size="sm" /></>}</span>
      <span className="font-semibold text-muted-foreground">{percentage}%</span>
    </div>

    {goal.target_date ? <p className="mt-2 text-xs text-muted-foreground">Objetivo: {formatFinancialDate(goal.target_date, "MMM yyyy")}</p> : null}
    {hasShortfall ? <p className="mt-2 text-xs text-warning">Respaldo parcial · revisa el detalle</p> : null}
  </Link>;
}
