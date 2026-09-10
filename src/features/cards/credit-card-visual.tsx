import { Link } from "react-router-dom";

import { MoneyValue } from "@/components/money-value";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import type { CardSummary } from "@/types/database";
import { cardProductThemes, cardUtilization } from "@/features/cards/card-utils";
import { CardArtwork } from "@/features/cards/card-artwork";

export function CreditCardVisual({ card }: { card: CardSummary }) {
  const theme = cardProductThemes[card.visual_theme];
  const utilization = cardUtilization(card.used_balance_minor, card.credit_limit_minor);
  return <Link aria-label={`Abrir tarjeta ${card.name}`} className="group block rounded-[1.65rem] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 focus-visible:ring-offset-4" to={`/cards/${card.id}`}>
    <article className={cn("relative aspect-[1.586/1] min-h-[220px] overflow-hidden rounded-[1.65rem] border p-5 shadow-[0_16px_36px_-24px_rgba(15,23,42,.55),0_2px_8px_rgba(15,23,42,.08)] transition duration-normal ease-nexo group-hover:-translate-y-[3px] group-hover:shadow-[0_22px_44px_-24px_rgba(15,23,42,.62),0_4px_12px_rgba(15,23,42,.10)] group-active:translate-y-0 motion-reduce:transform-none motion-reduce:transition-none sm:p-6", theme.surfaceClass, theme.primaryTextClass, theme.borderClass)}>
      <CardArtwork theme={card.visual_theme} />
      <CardFinancialInfo card={card} utilization={utilization} />
    </article>
  </Link>;
}

function CardFinancialInfo({ card, utilization }: { card: CardSummary; utilization: number }) {
  const theme = cardProductThemes[card.visual_theme];
  return <div className="relative z-10 flex h-full min-h-[178px] flex-col">
    <div className="flex items-start justify-between gap-4">
      <div>
        <p className="text-[1.05rem] font-bold leading-none tracking-[-0.035em]">{theme.brand}</p>
        <h2 className={cn("mt-2 max-w-[15rem] truncate text-[11px] font-medium", theme.secondaryTextClass)}>{card.name}</h2>
      </div>
      <div className="text-right">
        <p className="text-[9px] font-semibold tracking-[0.22em] opacity-75">{theme.product}</p>
        {!card.is_active ? <p className="mt-1 text-[9px] font-medium uppercase tracking-[0.14em] opacity-60">Archivada</p> : null}
      </div>
    </div>

    <div className="mt-auto">
      <p className={cn("text-[10px] font-medium uppercase tracking-[0.14em]", theme.secondaryTextClass)}>Saldo utilizado</p>
      <MoneyValue amount={card.used_balance_minor} className={cn("mt-0.5 block text-[clamp(1.65rem,3vw,2.15rem)] leading-none tracking-[-0.04em]", theme.primaryTextClass)} currency={card.currency} />

      <div className="mt-4 grid grid-cols-[1fr_auto] items-end gap-4">
        <div>
          <p className={cn("text-[9px] uppercase tracking-[0.13em]", theme.secondaryTextClass)}>Disponible</p>
          <MoneyValue amount={card.available_credit_minor} className={cn("mt-0.5 block text-sm", theme.primaryTextClass)} currency={card.currency} size="sm" />
        </div>
        <p className="font-mono text-[12px] font-medium tracking-[0.17em]">•••• {card.last4 ?? "Nexo"}</p>
      </div>

      <div className={cn("mt-3 h-1 overflow-hidden rounded-full", theme.trackClass)}>
        <div className={cn("h-full rounded-full", theme.progressClass)} style={{ width: `${Math.min(100, utilization)}%` }} />
      </div>
      <div className={cn("mt-2 flex items-center justify-between text-[9px] font-medium uppercase tracking-[0.11em]", theme.secondaryTextClass)}>
        <span>Corte {formatFinancialDate(card.next_statement_date, "dd MMM")}</span>
        <span>{utilization.toFixed(0)}% utilizado</span>
      </div>
    </div>
  </div>;
}
