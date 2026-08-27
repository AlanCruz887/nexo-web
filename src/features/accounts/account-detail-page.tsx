import { Archive, ArrowLeft, ArrowLeftRight, ArrowUpRight, Plus, Settings2 } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";

import { ActionMenu } from "@/components/action-menu";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { ConfirmDialog } from "@/components/sheet";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/toast";
import { useAccount, useAccounts, useArchiveAccount } from "@/hooks/use-accounts";
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
  const toast = useToast();
  const [movementKind, setMovementKind] = useState<"income" | "expense">("expense");
  const [movementOpen, setMovementOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();

  if (account.isLoading || accounts.isLoading) return <LoadingState label="Cargando cuenta" />;
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

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <Button asChild size="sm" variant="ghost"><Link to="/cuentas"><ArrowLeft className="size-4" />Cuentas</Link></Button>
        <ActionMenu items={[
          { icon: <Settings2 className="size-4" />, label: "Editar cuenta", onSelect: () => setEditOpen(true) },
          ...(current.is_active ? [{ icon: <Archive className="size-4" />, label: "Archivar cuenta", onSelect: () => setArchiveOpen(true), tone: "danger" as const }] : []),
        ]} />
      </div>
      <section className="relative overflow-hidden rounded-[30px] bg-primary px-6 py-8 text-primary-foreground sm:px-9 sm:py-10">
        <div className="absolute -right-10 -top-16 size-48 rounded-full bg-primary-foreground/10 blur-2xl" />
        <div className="relative">
          <p className="text-sm font-medium text-primary-foreground/65">{accountTypeLabels[current.type]}{!current.is_active ? " · Archivada" : ""}</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">{current.name}</h1>
          <MoneyValue amount={current.balance_minor} className="mt-7 block" currency={current.currency} size="xl" />
          <p className="mt-2 text-sm text-primary-foreground/65">Disponible{current.last4 ? ` · •••• ${current.last4}` : ""}</p>
        </div>
      </section>
      {current.is_active ? (
        <div className="grid grid-cols-3 gap-2">
          <QuickAction icon={<ArrowUpRight className="size-5" />} label="Gasto" onClick={() => openMovement("expense")} />
          <QuickAction icon={<Plus className="size-5" />} label="Ingreso" onClick={() => openMovement("income")} />
          <QuickAction icon={<ArrowLeftRight className="size-5" />} label="Transferir" onClick={() => setTransferOpen(true)} />
        </div>
      ) : <div className="rounded-2xl bg-warning/10 p-4 text-sm text-warning">Esta cuenta está archivada. Su saldo e historial permanecen visibles, pero no acepta movimientos nuevos.</div>}
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
  return <button className="flex min-h-20 flex-col items-center justify-center gap-2 rounded-2xl bg-surface text-sm font-semibold shadow-[inset_0_0_0_1px_var(--border)] transition duration-fast hover:-translate-y-0.5 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 active:translate-y-0" onClick={onClick} type="button"><span className="text-primary">{icon}</span>{label}</button>;
}
