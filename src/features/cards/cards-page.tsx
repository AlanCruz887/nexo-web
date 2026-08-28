import { Plus } from "lucide-react";
import { useState } from "react";

import { EmptyState, ErrorState } from "@/components/feedback";
import { FilterBar, FilterPill } from "@/components/filter-bar";
import { MoneyValue } from "@/components/money-value";
import { PageHeader, SectionHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { CardsSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/app/auth-provider";
import { useCards } from "@/hooks/use-cards";
import { useProfile } from "@/hooks/use-profile";
import { toUserMessage } from "@/lib/errors";
import type { CurrencyCode } from "@/types/database";
import { CardFormSheet } from "@/features/cards/card-form-sheet";
import { CreditCardVisual } from "@/features/cards/credit-card-visual";

export function CardsPage() {
  const { user } = useAuth(); const cards = useCards(); const profile = useProfile(user?.id); const [view, setView] = useState<"active" | "archived">("active"); const [formOpen, setFormOpen] = useState(false);
  if ((cards.isLoading && !cards.data) || (profile.isLoading && !profile.data)) return <CardsSkeleton />;
  if (cards.isError) return <ErrorState message={toUserMessage(cards.error)} onRetry={() => void cards.refetch()} />;
  const all = cards.data ?? []; const visible = all.filter((card) => card.is_active === (view === "active"));
  const totals = all.filter((card) => card.is_active).reduce<Record<string, bigint>>((result, card) => { result[card.currency] = (result[card.currency] ?? 0n) + BigInt(card.used_balance_minor); return result; }, {});
  return <PageTransition><div className="space-y-12"><PageHeader actions={<Button onClick={() => setFormOpen(true)}><Plus className="size-4" />Nueva tarjeta</Button>} eyebrow="Crédito" subtitle="Saldo utilizado, pago actual y ciclo abierto permanecen separados." title="Tarjetas" />
    {all.length === 0 ? <EmptyState action={<Button onClick={() => setFormOpen(true)}>Agregar tarjeta</Button>} description="Configura tu primera tarjeta y elige un baseline explícito." title="Todavía no tienes tarjetas" /> : <><section className="border-b border-border/70 pb-9"><p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">Crédito utilizado</p><div className="mt-3 flex flex-wrap gap-x-8 gap-y-3">{Object.entries(totals).map(([currency, amount]) => <MoneyValue amount={amount} className="text-[clamp(2.5rem,6vw,4.5rem)]" currency={currency as CurrencyCode} key={currency} />)}</div>{Object.keys(totals).length > 1 ? <p className="mt-3 text-xs text-muted-foreground">Cada moneda se presenta por separado. No se aplica FX.</p> : null}</section><section className="space-y-5"><SectionHeader action={<FilterBar><FilterPill active={view === "active"} onClick={() => setView("active")}>Activas</FilterPill><FilterPill active={view === "archived"} onClick={() => setView("archived")}>Archivadas</FilterPill></FilterBar>} title="Tu wallet" />{visible.length ? <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{visible.map((card) => <CreditCardVisual card={card} key={card.id} />)}</div> : <EmptyState description={view === "archived" ? "Las tarjetas archivadas conservarán aquí sus estados e historia." : "No hay tarjetas activas."} title={view === "archived" ? "Sin tarjetas archivadas" : "Sin tarjetas activas"} />}</section></>}
  </div><CardFormSheet baseCurrency={profile.data?.base_currency ?? "MXN"} onOpenChange={setFormOpen} open={formOpen} /></PageTransition>;
}
