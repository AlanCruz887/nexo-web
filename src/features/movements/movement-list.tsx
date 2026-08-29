import { format } from "date-fns";
import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight, CreditCard, RotateCcw, SlidersHorizontal } from "lucide-react";
import { motion, useReducedMotion } from "framer-motion";

import { MoneyValue } from "@/components/money-value";
import { motionTokens } from "@/design-system/motion";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import type { FinancialActivity } from "@/types/database";

function dayLabel(date: string) {
  const today = format(new Date(), "yyyy-MM-dd");
  const yesterday = format(new Date(Date.now() - 86_400_000), "yyyy-MM-dd");
  if (date === today) return "Hoy";
  if (date === yesterday) return "Ayer";
  return new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${date}T12:00:00Z`));
}

export function MovementList({ movements, onSelect }: { movements: FinancialActivity[]; onSelect: (eventId: string) => void }) {
  const groups = movements.reduce<Map<string, FinancialActivity[]>>((result, movement) => {
    const group = result.get(movement.occurred_on) ?? [];
    group.push(movement);
    result.set(movement.occurred_on, group);
    return result;
  }, new Map());
  return (
    <div className="space-y-7">
      {Array.from(groups.entries()).map(([date, items]) => (
        <section key={date}>
          <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">{dayLabel(date)}</h3>
          <div className="divide-y divide-border/60">
            {items.map((movement, index) => <MovementRow key={movement.event_id} index={index} movement={movement} onClick={() => onSelect(movement.event_id)} />)}
          </div>
        </section>
      ))}
    </div>
  );
}

function MovementRow({ index, movement, onClick }: { index: number; movement: FinancialActivity; onClick: () => void }) {
  const reduceMotion = useReducedMotion();
  const isPositive = BigInt(movement.signed_amount_minor) > 0n;
  const isNeutral = movement.kind === "transfer" || movement.kind === "card_payment" || movement.kind === "person_payment";
  const Icon = movement.kind === "transfer" ? ArrowLeftRight : movement.kind === "card_charge" ? CreditCard : movement.kind === "card_refund" ? RotateCcw : movement.kind === "card_payment" ? ArrowLeftRight : movement.kind === "income" ? ArrowDownLeft : movement.kind === "expense" ? ArrowUpRight : SlidersHorizontal;
  const isInstallment = Boolean(movement.installment_plan_id);
  const people = movement.third_party_allocations?.map((item) => item.contact_name).join(", ");
  const kindLabel = movement.kind === "person_payment" ? "Pago recibido · no es ingreso" : movement.kind === "card_charge" ? movement.category_name ?? "Compra" : movement.kind === "card_payment" ? movement.payment_state === "advance" ? "Pago anticipado" : movement.payment_state === "mixed" ? "Pago parcialmente aplicado" : "Pago de tarjeta" : movement.kind === "card_refund" ? "Reembolso" : movement.kind === "transfer" ? "Transferencia" : movement.category_name ?? "Sin categoría";
  return (
    <motion.button
      animate={{ opacity: 1, y: 0 }}
      className="group grid w-full grid-cols-[auto_1fr_auto] items-center gap-3 rounded-xl px-2 py-4 text-left transition-colors hover:bg-surface-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/35 sm:px-3"
      initial={reduceMotion ? false : { opacity: 0, y: 5 }}
      onClick={onClick}
      transition={{ delay: reduceMotion ? 0 : Math.min(index * 0.03, 0.15), duration: motionTokens.duration.normal, ease: motionTokens.ease.enter }}
      type="button"
    >
      <span className={cn("grid size-10 place-items-center rounded-xl", isNeutral || movement.source_type === "card" ? "bg-primary-soft text-primary" : isPositive ? "bg-success/10 text-success" : "bg-surface-secondary text-muted-foreground")}><Icon className="size-4.5" /></span>
      <span className="min-w-0">
        <span className="block truncate text-sm font-semibold text-foreground">{movement.description}</span>
        {isInstallment ? <>
          <span className="mt-1 flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground"><span className="shrink-0 rounded-md bg-primary-soft px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-primary">MSI</span><span className="truncate">{movement.installment_count} meses · <MoneyValue amount={movement.installment_amount_minor ?? "0"} currency={movement.currency} size="sm" />/mes</span></span>
          <span className="mt-1 block truncate text-xs text-muted-foreground">{formatFinancialDate(movement.occurred_on, "dd MMM")} · {movement.source_name}{!movement.source_is_active ? " · Archivada" : ""}</span>
        </> : <span className="mt-0.5 block truncate text-xs text-muted-foreground">{movement.source_name} · {kindLabel}{people ? ` · ${people}` : ""}{!movement.source_is_active ? " · Archivada" : ""}</span>}
      </span>
      <MoneyValue amount={isNeutral ? movement.amount_minor : movement.signed_amount_minor} className={cn("text-sm", isNeutral ? "text-foreground" : isPositive ? "text-success" : "text-danger")} currency={movement.currency} sign={isNeutral ? "never" : "always"} />
    </motion.button>
  );
}
