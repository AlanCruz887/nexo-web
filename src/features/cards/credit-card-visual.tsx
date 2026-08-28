import { Link } from "react-router-dom";

import { MoneyValue } from "@/components/money-value";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import type { CardSummary } from "@/types/database";
import { cardThemes, cardUtilization } from "@/features/cards/card-utils";

export function CreditCardVisual({ card }: { card: CardSummary }) {
  const theme = cardThemes[card.visual_theme];
  const utilization = cardUtilization(card.used_balance_minor, card.credit_limit_minor);
  return <Link className="group block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 focus-visible:ring-offset-4" to={`/cards/${card.id}`}>
    <article className={cn("relative min-h-56 overflow-hidden rounded-[1.6rem] bg-gradient-to-br p-6 shadow-card transition duration-normal ease-nexo group-hover:-translate-y-1 group-hover:shadow-float group-active:translate-y-0", theme.className)}>
      <span className="absolute -right-16 -top-16 size-52 rounded-full border border-white/10" /><span className="absolute -bottom-24 -left-12 size-56 rounded-full bg-white/5" />
      <div className="relative flex h-full min-h-44 flex-col justify-between">
        <div className="flex items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-[0.16em] text-white/65">{card.issuer}</p><h2 className="mt-1 text-xl font-semibold">{card.name}</h2></div><span className={cn("size-8 rounded-full opacity-80", theme.accent)} /></div>
        <div><p className="text-xs text-white/65">Saldo utilizado</p><MoneyValue amount={card.used_balance_minor} className="mt-1 block text-2xl text-white" currency={card.currency} /><div className="mt-5 flex items-end justify-between gap-4"><div><p className="text-xs text-white/60">Disponible</p><MoneyValue amount={card.available_credit_minor} className="text-sm text-white" currency={card.currency} /></div><div className="text-right"><p className="font-mono text-sm tracking-[0.18em]">•••• {card.last4 ?? "Nexo"}</p><p className="mt-1 text-[10px] text-white/60">Corte {formatFinancialDate(card.next_statement_date, "dd MMM")} · {utilization.toFixed(0)}%</p></div></div></div>
      </div>
    </article>
  </Link>;
}
