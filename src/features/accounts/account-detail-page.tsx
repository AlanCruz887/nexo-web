import { Archive, ArchiveRestore, ArrowLeft, ArrowLeftRight, ArrowUpRight, Plus, Settings2 } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";

import { ActionMenu } from "@/components/action-menu";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { ConfirmDialog } from "@/components/sheet";
import { Button } from "@/components/ui/button";
import { AccountsSkeleton } from "@/components/skeletons";
import { useToast } from "@/components/toast";
import { useAccount, useAccounts, useArchiveAccount, useRestoreAccount } from "@/hooks/use-accounts";
import { useAccountMovements } from "@/hooks/use-movements";
import { toUserMessage } from "@/lib/errors";
import { AccountFormSheet } from "@/features/accounts/account-form-sheet";
import { accountTypeLabels } from "@/features/accounts/account-utils";
import { MovementDetailSheet } from "@/features/movements/movement-detail-sheet";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { MovementList } from "@/features/movements/movement-list";
import { TransferFormSheet } from "@/features/movements/transfer-form-sheet";

export function AccountDetailPage() {
  const { id } = useParams();
  const account = useAccount(id);
  const accounts = useAccounts();
  const movements = useAccountMovements(id);
  const archive = useArchiveAccount();
  const restore = useRestoreAccount();
  const toast = useToast();
  const [movementKind, setMovementKind] = useState<"income" | "expense">("expense");
  const [movementOpen, setMovementOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();

  if ((account.isLoading && !account.data) || (accounts.isLoading && !accounts.data)) return <AccountsSkeleton />;
  if (account.isError || !account.data) return <ErrorState message={toUserMessage(account.error)} onRetry={() => void account.refetch()} />;
  const current = account.data;
  const allAccounts = accounts.data ?? [];

  function openMovement(kind: "income" | "expense") { setMovementKind(kind); setMovementOpen(true); }
  async function handleArchive() {
    try {
      await archive.mutateAsync(current.id);
      toast.success("Cuenta archivada");
      setArchiveOpen(false);
    } catch (error) { toast.error(toUserMessage(error)); }
  }
  async function handleRestore() {
    try {
      await restore.mutateAsync(current.id);
      toast.success("Cuenta restaurada");
    } catch (error) { toast.error(toUserMessage(error)); }
  }

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <Button asChild size="sm" variant="ghost"><Link to="/cuentas"><ArrowLeft className="size-4" />Cuentas</Link></Button>
        <ActionMenu items={[
          { icon: <Settings2 className="size-4" />, label: "Editar cuenta", onSelect: () => setEditOpen(true) },
          ...(current.is_active ? [{ icon: <Archive className="size-4" />, label: "Archivar cuenta", onSelect: () => setArchiveOpen(true), tone: "danger" as const }] : [{ icon: <ArchiveRestore className="size-4" />, label: "Restaurar cuenta", onSelect: () => void handleRestore() }]),
        ]} />
      </div>
      <section className="border-b border-border/70 pb-9">
        <div>
          <p className="text-sm font-medium text-primary">{accountTypeLabels[current.type]}{!current.is_active ? " · Archivada" : ""}</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">{current.name}</h1>
          <MoneyValue amount={current.balance_minor} className="mt-7 block text-[clamp(2.8rem,7vw,5rem)] leading-none tracking-[-0.06em]" currency={current.currency} />
          <p className="mt-2 text-sm text-muted-foreground">Disponible{current.last4 ? ` · •••• ${current.last4}` : ""}</p>
        </div>
      </section>
      {current.is_active ? (
        <div className="grid grid-cols-3 gap-3">
          <QuickAction icon={<ArrowUpRight className="size-5" />} label="Gasto" onClick={() => openMovement("expense")} />
          <QuickAction icon={<Plus className="size-5" />} label="Ingreso" onClick={() => openMovement("income")} />
          <QuickAction icon={<ArrowLeftRight className="size-5" />} label="Transferir" onClick={() => setTransferOpen(true)} />
        </div>
      ) : <div className="flex flex-col gap-4 rounded-2xl bg-warning/10 p-4 text-sm text-warning sm:flex-row sm:items-center sm:justify-between"><span>Esta cuenta está archivada. Conserva saldo e historial, pero no acepta movimientos nuevos.</span><Button disabled={restore.isPending} onClick={() => void handleRestore()} size="sm" variant="secondary"><ArchiveRestore className="size-4" />{restore.isPending ? "Restaurando…" : "Restaurar"}</Button></div>}
      <section>
        <div className="mb-4 flex items-end justify-between"><div><h2 className="text-lg font-semibold">Movimientos</h2><p className="mt-1 text-sm text-muted-foreground">Actividad vinculada a esta cuenta.</p></div><Button asChild size="sm" variant="ghost"><Link to={`/movimientos?cuenta=${current.id}`}>Ver todos</Link></Button></div>
        {movements.isLoading ? <LoadingState /> : movements.data?.length ? <MovementList movements={movements.data} onSelect={setSelectedEventId} /> : <EmptyState description="Usa las acciones superiores para registrar la primera actividad." title="Sin movimientos todavía" />}
      </section>
      <MovementFormSheet accounts={allAccounts} defaultAccountId={current.id} defaultKind={movementKind} onOpenChange={setMovementOpen} open={movementOpen} />
      <TransferFormSheet accounts={allAccounts} defaultFromAccountId={current.id} onOpenChange={setTransferOpen} open={transferOpen} />
      <AccountFormSheet account={current} baseCurrency={current.currency} onOpenChange={setEditOpen} open={editOpen} />
      <MovementDetailSheet accounts={allAccounts} eventId={selectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
      <ConfirmDialog confirmLabel="Archivar cuenta" description="Dejará de aparecer en movimientos nuevos, pero conservará su saldo y todo su historial." isPending={archive.isPending} onConfirm={() => void handleArchive()} onOpenChange={setArchiveOpen} open={archiveOpen} title="¿Archivar esta cuenta?" />
    </div>
  );
}

function QuickAction({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick: () => void }) {
  return <button className="flex min-h-20 flex-col items-center justify-center gap-2 rounded-xl border border-border/80 bg-surface text-sm font-semibold shadow-sm transition duration-fast hover:border-primary/20 hover:bg-primary-soft focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/35" onClick={onClick} type="button"><span className="text-primary">{icon}</span>{label}</button>;
}
