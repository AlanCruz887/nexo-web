import { format } from "date-fns";
import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight, SlidersHorizontal } from "lucide-react";
import { motion, useReducedMotion } from "framer-motion";

import { MoneyValue } from "@/components/money-value";
import { motionTokens } from "@/design-system/motion";
import { cn } from "@/lib/cn";
import type { AccountActivity } from "@/types/database";

function dayLabel(date: string) {
  const today = format(new Date(), "yyyy-MM-dd");
  const yesterday = format(new Date(Date.now() - 86_400_000), "yyyy-MM-dd");
  if (date === today) return "Hoy";
  if (date === yesterday) return "Ayer";
  return new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${date}T12:00:00Z`));
}

export function MovementList({ movements, onSelect }: { movements: AccountActivity[]; onSelect: (eventId: string) => void }) {
  const groups = movements.reduce<Map<string, AccountActivity[]>>((result, movement) => {
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
          <div className="divide-y divide-border/70">
            {items.map((movement, index) => <MovementRow key={`${movement.event_id}-${movement.account_id}`} index={index} movement={movement} onClick={() => onSelect(movement.event_id)} />)}
          </div>
        </section>
      ))}
    </div>
  );
}

function MovementRow({ index, movement, onClick }: { index: number; movement: AccountActivity; onClick: () => void }) {
  const reduceMotion = useReducedMotion();
  const isPositive = BigInt(movement.account_delta_minor) > 0n;
  const Icon = movement.kind === "transfer" ? ArrowLeftRight : movement.kind === "income" ? ArrowDownLeft : movement.kind === "expense" ? ArrowUpRight : SlidersHorizontal;
  return (
    <motion.button
      animate={{ opacity: 1, y: 0 }}
      className="group grid w-full grid-cols-[auto_1fr_auto] items-center gap-3 rounded-2xl px-1 py-3.5 text-left transition-colors hover:bg-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 sm:px-3"
      initial={reduceMotion ? false : { opacity: 0, y: 5 }}
      onClick={onClick}
      transition={{ delay: reduceMotion ? 0 : Math.min(index * 0.025, 0.15), duration: motionTokens.duration.normal, ease: motionTokens.ease }}
      type="button"
    >
      <span className={cn("grid size-10 place-items-center rounded-2xl", movement.kind === "transfer" ? "bg-primary/10 text-primary" : isPositive ? "bg-success/10 text-success" : "bg-muted text-muted-foreground")}><Icon className="size-4.5" /></span>
      <span className="min-w-0">
        <span className="block truncate text-sm font-semibold text-foreground">{movement.description}</span>
        <span className="mt-0.5 block truncate text-xs text-muted-foreground">{movement.account_name}{!movement.account_is_active ? " · Archivada" : ""} · {movement.kind === "transfer" ? "Transferencia" : movement.category_name ?? "Sin categoría"}</span>
      </span>
      <MoneyValue amount={movement.account_delta_minor} className={cn("text-sm", isPositive && "text-success")} currency={movement.currency} sign="always" />
    </motion.button>
  );
}
