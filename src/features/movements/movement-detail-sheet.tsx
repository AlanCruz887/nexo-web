import { Copy, FilePenLine, Trash2, Undo2 } from "lucide-react";
import { useState } from "react";

import { ActionMenu } from "@/components/action-menu";
import { ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { ConfirmDialog, Sheet } from "@/components/sheet";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/toast";
import { useMovement, useReverseMovement, useUpdateTransferNotes } from "@/hooks/use-movements";
import { formatAuditTimestamp, formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import { formatMoney } from "@/lib/money";
import type { AccountActivity, AccountBalance } from "@/types/database";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";

export function MovementDetailSheet({ accounts, eventId, onOpenChange, open }: { accounts: AccountBalance[]; eventId?: string | undefined; onOpenChange: (open: boolean) => void; open: boolean }) {
  const movement = useMovement(eventId);
  const reverse = useReverseMovement();
  const toast = useToast();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [duplicateOpen, setDuplicateOpen] = useState(false);

  const primary = movement.data?.[0];
  const isTransfer = primary?.kind === "transfer";
  const isOpening = primary?.kind === "opening";

  async function handleReverse() {
    if (!eventId || !primary) return;
    try {
      await reverse.mutateAsync({ eventId, isTransfer });
      toast.success(isTransfer ? "Transferencia revertida" : "Movimiento eliminado");
      setConfirmOpen(false);
      onOpenChange(false);
    } catch (error) {
      toast.error(toUserMessage(error));
    }
  }

  return (
    <>
      <Sheet description="Detalle y evidencia del movimiento." onOpenChange={onOpenChange} open={open} title="Movimiento">
        {movement.isLoading ? <LoadingState label="Cargando movimiento" /> : movement.isError ? <ErrorState message={toUserMessage(movement.error)} /> : primary ? (
          <div>
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm text-muted-foreground">{primary.kind === "income" ? "Ingreso" : primary.kind === "expense" ? "Gasto" : primary.kind === "transfer" ? "Transferencia" : primary.kind === "opening" ? "Saldo inicial" : "Ajuste"}</p>
                <MoneyValue amount={primary.amount_minor} className="mt-1 block" currency={primary.currency} size="xl" />
              </div>
              {!isOpening ? <ActionMenu items={isTransfer ? [
                { icon: <FilePenLine className="size-4" />, label: "Editar notas", onSelect: () => setEditOpen(true) },
                { icon: <Undo2 className="size-4" />, label: "Revertir transferencia", onSelect: () => setConfirmOpen(true), tone: "danger" },
              ] : [
                { icon: <FilePenLine className="size-4" />, label: "Editar", onSelect: () => setEditOpen(true) },
                { icon: <Copy className="size-4" />, label: "Duplicar", onSelect: () => setDuplicateOpen(true) },
                { icon: <Trash2 className="size-4" />, label: "Eliminar", onSelect: () => setConfirmOpen(true), tone: "danger" },
              ]} /> : null}
            </div>
            <div className="mt-8 rounded-2xl border border-border/70 bg-surface-secondary p-5">
              <Detail label="Descripción" value={primary.description} />
              {isTransfer ? <TransferAccounts legs={movement.data ?? []} /> : <Detail label="Cuenta" value={`${primary.account_name}${!primary.account_is_active ? " · Archivada" : ""}`} />}
              <Detail label="Categoría" value={primary.category_name ?? (isTransfer ? "Transferencia" : "Sin categoría")} />
              <Detail label="Fecha" value={formatFinancialDate(primary.occurred_on, "dd MMM yyyy")} />
              <Detail label="Creado" value={formatAuditTimestamp(primary.created_at, "dd MMM yyyy, HH:mm")} />
              <Detail label="Notas" value={primary.notes || "Sin notas"} last />
            </div>
            {!isOpening ? <div className="mt-5 grid grid-cols-3 gap-2">
              <Button className="flex-1" onClick={() => setEditOpen(true)} variant="secondary">{isTransfer ? "Editar notas" : "Editar"}</Button>
              {!isTransfer ? <Button onClick={() => setDuplicateOpen(true)} variant="ghost">Duplicar</Button> : null}
              <Button onClick={() => setConfirmOpen(true)} variant="danger">{isTransfer ? "Revertir" : "Eliminar"}</Button>
            </div> : null}
          </div>
        ) : <ErrorState message="No encontramos este movimiento." />}
      </Sheet>
      {primary && !isTransfer && !isOpening ? <MovementFormSheet accounts={accounts} existing={primary} onOpenChange={setEditOpen} open={editOpen} /> : null}
      {primary && !isTransfer && !isOpening ? <MovementFormSheet accounts={accounts} onOpenChange={setDuplicateOpen} open={duplicateOpen} prefill={primary} /> : null}
      {primary && isTransfer ? <TransferNotesSheet event={primary} onOpenChange={setEditOpen} open={editOpen} /> : null}
      <ConfirmDialog
        confirmLabel={isTransfer ? "Revertir transferencia" : "Eliminar movimiento"}
        description={isTransfer ? `Se crearán entradas opuestas para revertir ${primary?.description ?? "la transferencia"} por ${primary ? formatMoney(primary.amount_minor, primary.currency) : "su importe"}. La evidencia original se conserva.` : `Nexo revertirá ${primary?.description ?? "el movimiento"} por ${primary ? formatMoney(primary.amount_minor, primary.currency) : "su importe"}. El registro original y su auditoría se conservan.`}
        isPending={reverse.isPending}
        onConfirm={() => void handleReverse()}
        onOpenChange={setConfirmOpen}
        open={confirmOpen}
        title={isTransfer ? "¿Revertir transferencia?" : "¿Eliminar movimiento?"}
      />
    </>
  );
}

function Detail({ label, last = false, value }: { label: string; last?: boolean; value: string }) {
  return <div className={`flex items-start justify-between gap-5 py-3 ${last ? "" : "border-b border-border/70"}`}><span className="text-xs font-medium text-muted-foreground">{label}</span><span className="max-w-[65%] text-right text-sm font-medium">{value}</span></div>;
}

function TransferAccounts({ legs }: { legs: AccountActivity[] }) {
  const source = legs.find((leg) => BigInt(leg.account_delta_minor) < 0n);
  const destination = legs.find((leg) => BigInt(leg.account_delta_minor) > 0n);
  return <><Detail label="Desde" value={source?.account_name ?? "Cuenta origen"} /><Detail label="Hacia" value={destination?.account_name ?? "Cuenta destino"} /></>;
}

function TransferNotesSheet({ event, onOpenChange, open }: { event: AccountActivity; onOpenChange: (open: boolean) => void; open: boolean }) {
  const [notes, setNotes] = useState(event.notes ?? "");
  const update = useUpdateTransferNotes(event.event_id);
  const toast = useToast();
  async function save() {
    try {
      await update.mutateAsync(notes);
      toast.success("Notas actualizadas");
      onOpenChange(false);
    } catch (error) {
      toast.error(toUserMessage(error));
    }
  }
  return <Sheet description="El importe y las cuentas no cambian; la actualización queda auditada." onOpenChange={onOpenChange} open={open} title="Notas de transferencia"><label className="text-sm font-medium" htmlFor="transfer-detail-notes">Notas</label><textarea className="mt-2 min-h-36 w-full resize-none rounded-xl border border-border bg-surface p-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/20" id="transfer-detail-notes" onChange={(e) => setNotes(e.target.value)} value={notes} /><Button className="mt-5 w-full" disabled={update.isPending} onClick={() => void save()}>{update.isPending ? "Guardando…" : "Guardar notas"}</Button></Sheet>;
}
