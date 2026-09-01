import { addDays, format } from "date-fns";
import { Archive, Ban, CalendarClock, Pause, Play, Plus, RotateCcw } from "lucide-react";
import { useMemo, useState } from "react";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/toast";
import { ConfirmOccurrenceDialog } from "@/features/recurring/confirm-occurrence-dialog";
import { RecurringRuleForm } from "@/features/recurring/recurring-rule-form";
import {
  useArchiveRecurringRule, useOmitRecurringOccurrence, usePauseRecurringRule, useRecurringHistory,
  useRecurringOccurrences, useRecurringRuleCurrentVersion, useRecurringRules, useRestoreRecurringRule, useResumeRecurringRule,
} from "@/hooks/use-recurring-rules";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import type { RecurringFrequency, RecurringOccurrenceCandidate, RecurringRule } from "@/types/database";

const frequencyLabels: Record<RecurringFrequency, string> = {
  weekly: "semanal", biweekly: "cada 2 semanas", semimonthly: "dos veces al mes",
  monthly: "mensual", bimonthly: "cada 2 meses", quarterly: "trimestral",
  semiannual: "semestral", annual: "anual",
};

function todayLocal(): string {
  return format(new Date(), "yyyy-MM-dd");
}

export function RecurringPage() {
  const from = todayLocal();
  const to = format(addDays(new Date(), 90), "yyyy-MM-dd");
  const rules = useRecurringRules();
  const occurrences = useRecurringOccurrences(from, to);
  const [formOpen, setFormOpen] = useState(false);
  const [editingRule, setEditingRule] = useState<RecurringRule | null>(null);
  const [confirmCandidate, setConfirmCandidate] = useState<RecurringOccurrenceCandidate | null>(null);
  const [detailRule, setDetailRule] = useState<RecurringRule | null>(null);
  const editingRuleVersion = useRecurringRuleCurrentVersion(editingRule?.id);
  const omit = useOmitRecurringOccurrence();
  const toast = useToast();

  const upcoming = useMemo(() => {
    const pending = (occurrences.data ?? []).filter((o) => !o.existing_occurrence_id);
    const groups = new Map<string, RecurringOccurrenceCandidate[]>();
    for (const item of pending) {
      const list = groups.get(item.occurred_on) ?? [];
      list.push(item);
      groups.set(item.occurred_on, list);
    }
    return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
  }, [occurrences.data]);

  const activeRules = (rules.data ?? []).filter((r) => r.archived_at === null);
  const archivedRules = (rules.data ?? []).filter((r) => r.archived_at !== null);

  async function handleOmit(candidate: RecurringOccurrenceCandidate) {
    try {
      await omit.mutateAsync({ ruleId: candidate.rule_id, expectedDate: candidate.occurred_on, notes: null });
      toast.success("Omitido");
    } catch (error) { toast.error(toUserMessage(error)); }
  }

  if (rules.isLoading || occurrences.isLoading) return <LoadingState label="Cargando recurrentes" />;
  if (rules.isError) return <ErrorState message={toUserMessage(rules.error)} onRetry={() => void rules.refetch()} />;
  if (occurrences.isError) return <ErrorState message={toUserMessage(occurrences.error)} onRetry={() => void occurrences.refetch()} />;

  return <PageTransition><div className="space-y-8">
    <PageHeader
      actions={<Button onClick={() => { setEditingRule(null); setFormOpen(true); }}><Plus className="size-4" />Nueva recurrencia</Button>}
      eyebrow="Plan" subtitle="Lo que esperas recibir o pagar periódicamente -- nada se cobra hasta que lo registras." title="Recurrentes"
    />

    <section className="space-y-4">
      <h2 className="text-lg font-semibold tracking-tight">Próximos</h2>
      {upcoming.length === 0 ? (
        <EmptyState description="No hay pagos ni cobros esperados en los próximos 90 días." title="Nada pendiente" />
      ) : (
        <div className="space-y-5">
          {upcoming.map(([date, items]) => <div key={date}>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.12em] text-muted-foreground">
              {date === from ? "Hoy" : formatFinancialDate(date, "EEEE d 'de' MMMM")}
            </p>
            <div className="space-y-2">
              {items.map((item) => <Card className="flex flex-wrap items-center justify-between gap-3 p-4" key={`${item.rule_id}-${item.occurred_on}`}>
                <div className="min-w-0">
                  <p className="truncate font-medium">{item.name}</p>
                  <MoneyValue amount={item.amount_minor} currency={item.currency} sign={item.direction === "income" ? "always" : "never"} size="sm" />
                </div>
                <div className="flex items-center gap-2">
                  <Button onClick={() => setConfirmCandidate(item)} size="sm">Registrar</Button>
                  <Button onClick={() => void handleOmit(item)} size="sm" variant="ghost">Omitir esta vez</Button>
                </div>
              </Card>)}
            </div>
          </div>)}
        </div>
      )}
    </section>

    <section className="space-y-4">
      <h2 className="text-lg font-semibold tracking-tight">Recurrentes activos</h2>
      {activeRules.length === 0 ? (
        <EmptyState action={<Button onClick={() => { setEditingRule(null); setFormOpen(true); }}>Crear recurrencia</Button>} description="Declara pagos o cobros que se repiten -- Netflix, renta, nómina -- para verlos aquí." title="Sin recurrentes todavía" />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {activeRules.map((rule) => <RuleCard key={rule.id} onOpenDetail={() => setDetailRule(rule)} rule={rule} />)}
        </div>
      )}
    </section>

    {archivedRules.length > 0 ? <details className="text-sm text-muted-foreground">
      <summary className="cursor-pointer">Archivadas</summary>
      <div className="mt-2 space-y-2">
        {archivedRules.map((rule) => <RuleCard key={rule.id} onOpenDetail={() => setDetailRule(rule)} rule={rule} />)}
      </div>
    </details> : null}

    <RecurringRuleForm
      onOpenChange={(open) => { setFormOpen(open); if (!open) setEditingRule(null); }} open={formOpen}
      {...(editingRule ? { rule: editingRule } : {})}
      {...(editingRuleVersion.data ? { ruleVersion: editingRuleVersion.data } : {})}
    />
    <ConfirmOccurrenceDialog candidate={confirmCandidate} onOpenChange={(open) => { if (!open) setConfirmCandidate(null); }} open={confirmCandidate !== null} />
    {detailRule ? <RuleDetailSheet
      onEdit={() => { setEditingRule(detailRule); setDetailRule(null); setFormOpen(true); }}
      onOpenChange={(open) => { if (!open) setDetailRule(null); }} open={detailRule !== null} rule={detailRule}
    /> : null}
  </div></PageTransition>;
}

function RuleCard({ onOpenDetail, rule }: { onOpenDetail: () => void; rule: RecurringRule }) {
  return <button className="group rounded-2xl border border-border bg-surface p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" onClick={onOpenDetail} type="button">
    <div className="flex items-center gap-3">
      <span className="grid size-10 shrink-0 place-items-center rounded-full bg-primary-soft text-primary-strong"><CalendarClock className="size-[18px]" /></span>
      <div className="min-w-0">
        <h3 className="truncate font-semibold">{rule.name}</h3>
        {rule.status === "paused" ? <p className="text-[10px] uppercase tracking-wide text-warning">Pausada</p> : null}
        {rule.archived_at ? <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Archivada</p> : null}
      </div>
    </div>
  </button>;
}

function RuleDetailSheet({
  onEdit, onOpenChange, open, rule,
}: {
  onEdit: () => void; onOpenChange: (open: boolean) => void; open: boolean; rule: RecurringRule;
}) {
  const history = useRecurringHistory(rule.id);
  const pause = usePauseRecurringRule();
  const resume = useResumeRecurringRule();
  const archive = useArchiveRecurringRule();
  const restore = useRestoreRecurringRule();
  const toast = useToast();

  if (!open) return null;

  async function run(action: () => Promise<unknown>, label: string) {
    try { await action(); toast.success(label); } catch (error) { toast.error(toUserMessage(error)); }
  }

  return <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/30 sm:items-center" onClick={() => onOpenChange(false)}>
    <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-surface p-6 shadow-card sm:rounded-2xl" onClick={(e) => e.stopPropagation()}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold tracking-tight">{rule.name}</h2>
          <p className="text-sm text-muted-foreground">{rule.direction === "income" ? "Ingreso" : "Gasto"} recurrente</p>
        </div>
        <Button onClick={() => onOpenChange(false)} size="sm" variant="ghost">Cerrar</Button>
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <Button onClick={onEdit} size="sm" variant="secondary">Editar</Button>
        {rule.archived_at ? (
          <Button onClick={() => void run(() => restore.mutateAsync(rule.id), "Recurrencia restaurada")} size="sm" variant="secondary">
            <RotateCcw className="size-4" />Restaurar
          </Button>
        ) : <>
          {rule.status === "active" ? (
            <Button onClick={() => void run(() => pause.mutateAsync(rule.id), "Pausada")} size="sm" variant="secondary">
              <Pause className="size-4" />Pausar
            </Button>
          ) : (
            <Button onClick={() => void run(() => resume.mutateAsync(rule.id), "Reactivada")} size="sm" variant="secondary">
              <Play className="size-4" />Reactivar
            </Button>
          )}
          <Button onClick={() => void run(() => archive.mutateAsync(rule.id), "Archivada")} size="sm" variant="ghost">
            <Archive className="size-4" />Archivar
          </Button>
        </>}
      </div>

      <div className="mt-6">
        <h3 className="text-sm font-semibold text-foreground">Historial</h3>
        {history.isLoading ? <p className="mt-2 text-sm text-muted-foreground">Cargando…</p> : null}
        {!history.isLoading && (history.data ?? []).length === 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">Sin movimientos registrados todavía.</p>
        ) : (
          <div className="mt-2 space-y-2">
            {(history.data ?? []).map((entry) => <div className="flex items-center justify-between rounded-xl border border-border px-3 py-2 text-sm" key={entry.id}>
              <div className="min-w-0">
                <p className="font-medium">{formatFinancialDate(entry.expected_date)}</p>
                <p className={cn("text-xs", entry.status === "omitted" ? "text-muted-foreground" : "text-foreground")}>
                  {entry.status === "omitted" ? "Omitido" : entry.is_reversed_without_replacement ? "Movimiento revertido" : "Registrado"}
                </p>
              </div>
              {entry.actual_amount_minor ? <MoneyValue amount={entry.actual_amount_minor} currency={entry.currency} size="sm" /> : <Ban className="size-4 text-muted-foreground" />}
            </div>)}
          </div>
        )}
      </div>
    </div>
  </div>;
}

export { frequencyLabels };
