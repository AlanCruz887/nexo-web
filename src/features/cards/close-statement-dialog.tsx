import { useState } from "react";

import { FormField } from "@/components/form-field";
import { MoneyValue } from "@/components/money-value";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/toast";
import { useCloseCardStatement } from "@/hooks/use-cards";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import type { CardCurrentCycle, CardSummary } from "@/types/database";

export function CloseStatementDialog({ card, cycle, onOpenChange, open }: { card: CardSummary; cycle: CardCurrentCycle; onOpenChange: (open: boolean) => void; open: boolean }) {
  const close = useCloseCardStatement(card.id); const toast = useToast(); const [minimum, setMinimum] = useState(""); const [error, setError] = useState<string>();
  async function confirm() { try { await close.mutateAsync({ statementDate: card.next_statement_date, minimumPayment: minimum }); toast.success("Estado de cuenta cerrado"); onOpenChange(false); setMinimum(""); } catch (cause) { setError(toUserMessage(cause)); } }
  return <ResponsiveDialog description="El cierre crea un snapshot inmutable. No registra pagos ni movimientos nuevos." footer={<><Button onClick={() => onOpenChange(false)} variant="ghost">Cancelar</Button><Button disabled={close.isPending} onClick={() => void confirm()}>{close.isPending ? "Cerrando…" : "Cerrar estado"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title="Cerrar estado">
    <div className="space-y-5"><div className="rounded-2xl bg-surface-secondary p-5"><p className="text-xs text-muted-foreground">Periodo</p><p className="mt-1 text-sm font-semibold">{formatFinancialDate(cycle.cycle_start, "dd MMM yyyy")} → {formatFinancialDate(cycle.cycle_end, "dd MMM yyyy")}</p><p className="mt-5 text-xs text-muted-foreground">Saldo utilizado al preview</p><MoneyValue amount={card.used_balance_minor} className="mt-1 block text-3xl" currency={card.currency} /><p className="mt-5 text-xs text-muted-foreground">Fecha límite</p><p className="mt-1 text-sm font-semibold">{formatFinancialDate(card.next_payment_due_date, "dd MMM yyyy")}</p></div><FormField id="minimum-payment" label="Pago mínimo reportado (opcional)"><Input id="minimum-payment" inputMode="decimal" onChange={(event) => setMinimum(event.target.value)} placeholder="0.00" value={minimum} /></FormField>{error ? <p className="text-sm text-danger" role="alert">{error}</p> : null}</div>
  </ResponsiveDialog>;
}
