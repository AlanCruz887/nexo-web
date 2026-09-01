import { Archive, ArchiveRestore, ArrowDownToLine, ArrowLeft, ArrowUpFromLine, Pause, Play, Settings2, Undo2 } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ActionMenu } from "@/components/action-menu";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { ConfirmDialog } from "@/components/sheet";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/toast";
import { GoalContributeDialog } from "@/features/goals/goal-contribute-dialog";
import { GoalForm } from "@/features/goals/goal-form";
import { GoalWithdrawDialog } from "@/features/goals/goal-withdraw-dialog";
import { useArchiveGoal, useGoal, useGoalMovements, useReverseGoalEntry, useRestoreGoal, useSetGoalStatus } from "@/hooks/use-goals";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import type { GoalEntryActivity } from "@/types/database";

export function GoalDetailPage() {
  const { id } = useParams();
  const goal = useGoal(id);
  const movements = useGoalMovements(id);
  const setStatus = useSetGoalStatus();
  const archive = useArchiveGoal();
  const restore = useRestoreGoal();
  const reverse = useReverseGoalEntry();
  const toast = useToast();
  const [editOpen, setEditOpen] = useState(false);
  const [contributeOpen, setContributeOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [reverseTarget, setReverseTarget] = useState<GoalEntryActivity | null>(null);

  if (goal.isLoading) return <LoadingState label="Cargando meta" />;
  if (goal.isError || !goal.data) return <ErrorState message={toUserMessage(goal.error)} onRetry={() => void goal.refetch()} />;
  const current = goal.data;
  const isArchived = current.archived_at !== null;
  const hasShortfall = BigInt(current.backed_minor) < BigInt(current.saved_minor);
  const percentage = Math.max(0, current.percentage);

  async function handleArchive() {
    try { await archive.mutateAsync(current.id); toast.success("Meta archivada"); setArchiveOpen(false); }
    catch (error) { toast.error(toUserMessage(error)); }
  }
  async function handleRestore() {
    try { await restore.mutateAsync(current.id); toast.success("Meta restaurada"); }
    catch (error) { toast.error(toUserMessage(error)); }
  }
  async function handleToggleStatus() {
    try { await setStatus.mutateAsync({ id: current.id, status: current.status === "active" ? "paused" : "active" }); toast.success(current.status === "active" ? "Meta pausada" : "Meta reanudada"); }
    catch (error) { toast.error(toUserMessage(error)); }
  }
  async function handleReverse() {
    if (!reverseTarget) return;
    try { await reverse.mutateAsync(reverseTarget.id); toast.success("Movimiento revertido"); setReverseTarget(null); }
    catch (error) { toast.error(toUserMessage(error)); }
  }

  return <div className="space-y-8">
    <div className="flex items-center justify-between">
      <Button asChild size="sm" variant="ghost"><Link to="/metas"><ArrowLeft className="size-4" />Metas</Link></Button>
      <ActionMenu items={[
        { icon: <Settings2 className="size-4" />, label: "Editar meta", onSelect: () => setEditOpen(true) },
        ...(isArchived ? [] : [{ icon: current.status === "active" ? <Pause className="size-4" /> : <Play className="size-4" />, label: current.status === "active" ? "Pausar meta" : "Reanudar meta", onSelect: () => void handleToggleStatus() }]),
        ...(isArchived
          ? [{ icon: <ArchiveRestore className="size-4" />, label: "Restaurar meta", onSelect: () => void handleRestore() }]
          : [{ icon: <Archive className="size-4" />, label: "Archivar meta", onSelect: () => setArchiveOpen(true), tone: "danger" as const }]),
      ]} />
    </div>

    <section className="border-b border-border/70 pb-9">
      <p className="text-sm font-medium text-primary">{isArchived ? "Archivada" : current.status === "paused" ? "Pausada" : "Activa"}{current.is_achieved ? " · Meta alcanzada" : ""}</p>
      <h1 className="mt-1 text-2xl font-semibold tracking-tight">{current.name}</h1>
      <MoneyValue amount={current.saved_minor} className="mt-7 block text-[clamp(2.8rem,7vw,5rem)] leading-none tracking-[-0.06em]" currency={current.currency} />
      <p className="mt-2 text-sm text-muted-foreground">Ahorrado de <MoneyValue amount={current.target_minor} currency={current.currency} size="sm" /> objetivo</p>

      <div className="mt-5 h-2.5 overflow-hidden rounded-full bg-surface-secondary">
        <div className={cn("h-full rounded-full transition-all duration-normal", hasShortfall ? "bg-warning" : "bg-primary")} style={{ width: `${Math.min(100, percentage)}%` }} />
      </div>

      <div className="mt-5 grid grid-cols-2 gap-5 sm:grid-cols-3">
        <Metric label="Falta"><MoneyValue amount={current.remaining_minor} currency={current.currency} size="sm" /></Metric>
        <Metric label="Porcentaje"><span className="text-sm font-semibold">{percentage}%</span></Metric>
        {current.target_date ? <Metric label="Fecha objetivo"><span className="text-sm font-semibold">{formatFinancialDate(current.target_date, "d MMM yyyy")}</span></Metric> : null}
      </div>

      {hasShortfall ? <div className="mt-5 rounded-2xl border border-warning/30 bg-warning/10 px-5 py-4 text-sm text-warning">
        <p className="font-semibold">Respaldado actualmente <MoneyValue amount={current.backed_minor} className="text-warning" currency={current.currency} size="sm" /></p>
        <p className="mt-1">Una de las cuentas que respalda esta meta tiene menos saldo del que está reservado. Deposita en esa cuenta o ajusta la meta para volver a respaldarla por completo.</p>
      </div> : null}

      {current.recommended_monthly_minor ? <p className="mt-5 text-sm text-muted-foreground">Para llegar a tu objetivo necesitas apartar aproximadamente <MoneyValue amount={current.recommended_monthly_minor} currency={current.currency} size="sm" /> al mes.</p> : null}
    </section>

    {!isArchived ? <div className="grid grid-cols-2 gap-3">
      <QuickAction icon={<ArrowDownToLine className="size-5" />} label="Apartar dinero" onClick={() => setContributeOpen(true)} />
      <QuickAction icon={<ArrowUpFromLine className="size-5" />} label="Retirar dinero" onClick={() => setWithdrawOpen(true)} />
    </div> : null}

    <section>
      <h2 className="text-lg font-semibold">Movimientos</h2>
      <p className="mt-1 text-sm text-muted-foreground">Aportaciones, retiros y reversiones de esta meta.</p>
      {movements.isLoading ? <LoadingState /> : (movements.data?.length ?? 0) === 0 ? (
        <EmptyState description="Usa las acciones de arriba para empezar a apartar dinero." title="Sin movimientos todavía" />
      ) : (
        <div className="mt-4 divide-y divide-border border-y border-border">
          {(movements.data ?? []).map((movement) => <GoalMovementRow currency={current.currency} key={movement.id} movement={movement} onReverse={() => setReverseTarget(movement)} />)}
        </div>
      )}
    </section>

    <GoalForm goal={current} onOpenChange={setEditOpen} open={editOpen} />
    <GoalContributeDialog goal={current} onOpenChange={setContributeOpen} open={contributeOpen} />
    <GoalWithdrawDialog goal={current} onOpenChange={setWithdrawOpen} open={withdrawOpen} />
    <ConfirmDialog confirmLabel="Archivar meta" description="Dejará de aparecer como activa, pero conservará todo su historial de movimientos." isPending={archive.isPending} onConfirm={() => void handleArchive()} onOpenChange={setArchiveOpen} open={archiveOpen} title="¿Archivar esta meta?" />
    <ConfirmDialog confirmLabel="Revertir" description="Deshace este movimiento por completo, incluida la transferencia real si la hubo. No se puede deshacer dos veces." isPending={reverse.isPending} onConfirm={() => void handleReverse()} onOpenChange={(open) => { if (!open) setReverseTarget(null); }} open={reverseTarget !== null} title="¿Revertir este movimiento?" />
  </div>;
}

function Metric({ children, label }: { children: React.ReactNode; label: string }) {
  return <div><p className="text-xs text-muted-foreground">{label}</p><div className="mt-1">{children}</div></div>;
}

function QuickAction({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick: () => void }) {
  return <button className="flex min-h-20 flex-col items-center justify-center gap-2 rounded-xl border border-border/80 bg-surface text-sm font-semibold shadow-sm transition duration-fast hover:border-primary/20 hover:bg-primary-soft focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/35" onClick={onClick} type="button"><span className="text-primary">{icon}</span>{label}</button>;
}

function GoalMovementRow({ currency, movement, onReverse }: { currency: import("@/types/database").CurrencyCode; movement: GoalEntryActivity; onReverse: () => void }) {
  const isPositive = BigInt(movement.amount_minor) > 0n;
  const kindLabel = movement.entry_kind === "reversal" ? "Reversión" : isPositive ? "Aportación" : "Retiro";
  const canReverse = movement.entry_kind !== "reversal" && !movement.is_reversed;
  return <div className="flex items-center justify-between gap-4 py-3">
    <div className="min-w-0">
      <p className="text-sm font-medium">{kindLabel}{movement.is_reversed ? " · Revertida" : ""}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">
        {formatFinancialDate(movement.occurred_on)} · {movement.account_name}{!movement.account_is_active ? " (archivada)" : ""}
        {movement.is_real_movement ? " · Transferencia real" : " · Solo apartado"}
      </p>
    </div>
    <div className="flex items-center gap-3">
      <MoneyValue amount={movement.amount_minor} className={isPositive ? undefined : "text-muted-foreground"} currency={currency} size="sm" />
      {canReverse ? <Button aria-label="Revertir movimiento" onClick={onReverse} size="icon" variant="ghost"><Undo2 className="size-4" /></Button> : null}
    </div>
  </div>;
}
