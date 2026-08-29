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
import type { CardStatementCloseCandidate, CardSummary } from "@/types/database";

export function CloseStatementDialog({ candidate, card, onOpenChange, open }: { candidate: CardStatementCloseCandidate; card: CardSummary; onOpenChange: (open: boolean) => void; open: boolean }) {
  const close = useCloseCardStatement(card.id); const toast = useToast(); const [minimum, setMinimum] = useState(""); const [error, setError] = useState<string>();
  async function confirm() { try { await close.mutateAsync({ statementDate: candidate.statement_date, minimumPayment: minimum }); toast.success("Estado de cuenta cerrado"); onOpenChange(false); setMinimum(""); } catch (cause) { setError(toUserMessage(cause)); } }
  return <ResponsiveDialog description="Cerrarás el periodo vencido más antiguo. El periodo actual seguirá abierto." footer={<><Button onClick={() => onOpenChange(false)} variant="ghost">Cancelar</Button><Button disabled={close.isPending} onClick={() => void confirm()}>{close.isPending ? "Cerrando…" : "Cerrar estado"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title="Cerrar estado">
    <div className="space-y-5"><div className="rounded-2xl bg-surface-secondary p-5"><p className="text-xs text-muted-foreground">Periodo</p><p className="mt-1 text-sm font-semibold">{formatFinancialDate(candidate.cycle_start, "dd MMM yyyy")} → {formatFinancialDate(candidate.cycle_end, "dd MMM yyyy")}</p><p className="mt-5 text-xs text-muted-foreground">Total del estado</p><MoneyValue amount={candidate.statement_balance_minor} className="mt-1 block text-3xl" currency={card.currency} /><p className="mt-5 text-xs text-muted-foreground">Fecha límite</p><p className="mt-1 text-sm font-semibold">{formatFinancialDate(candidate.payment_due_date, "dd MMM yyyy")}</p></div><FormField hint="Déjalo vacío si tu banco no lo muestra." id="minimum-payment" label="Pago mínimo (opcional)"><Input id="minimum-payment" inputMode="decimal" onChange={(event) => setMinimum(event.target.value)} placeholder="0.00" value={minimum} /></FormField>{error ? <p className="text-sm text-danger" role="alert">{error}</p> : null}</div>
  </ResponsiveDialog>;
}
