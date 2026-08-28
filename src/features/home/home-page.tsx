import { format, subMonths } from "date-fns";
import { AlertCircle, ArrowRight, CheckCircle2, Landmark, TrendingDown } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { FinancialMetric } from "@/components/financial-metric";
import { MoneyValue } from "@/components/money-value";
import { PageSection } from "@/components/page-section";
import { PageTransition } from "@/components/page-transition";
import { DashboardSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { AccountFormSheet } from "@/features/accounts/account-form-sheet";
import { MovementDetailSheet } from "@/features/movements/movement-detail-sheet";
import { MovementList } from "@/features/movements/movement-list";
import { useAccounts, sumBalancesByCurrency } from "@/hooks/use-accounts";
import { useMovements } from "@/hooks/use-movements";
import { useProfile } from "@/hooks/use-profile";
import { toUserMessage } from "@/lib/errors";
import type { CurrencyCode } from "@/types/database";

export function HomePage() {
  const { user } = useAuth();
  const profile = useProfile(user?.id);
  const accounts = useAccounts();
  const movements = useMovements();
  const [accountFormOpen, setAccountFormOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();
  if ((accounts.isLoading && !accounts.data) || (profile.isLoading && !profile.data)) return <DashboardSkeleton />;
  if (accounts.isError) return <ErrorState message={toUserMessage(accounts.error)} />;
  const activeAccounts = accounts.data?.filter((account) => account.is_active) ?? [];
  const totals = sumBalancesByCurrency(activeAccounts);
  const baseCurrency = profile.data?.base_currency ?? "MXN";
  const otherTotals = Object.entries(totals).filter(([currency]) => currency !== baseCurrency);
  const currentMonth = format(new Date(), "yyyy-MM");
  const previousMonth = format(subMonths(new Date(), 1), "yyyy-MM");
  const expenses = movements.data?.filter((movement) => movement.kind === "expense" && movement.currency === baseCurrency) ?? [];
  const currentSpend = expenses.filter((movement) => movement.occurred_on.startsWith(currentMonth)).reduce((sum, movement) => sum + BigInt(movement.personal_amount_minor), 0n);
  const previousSpend = expenses.filter((movement) => movement.occurred_on.startsWith(previousMonth)).reduce((sum, movement) => sum + BigInt(movement.personal_amount_minor), 0n);

  return <PageTransition><div className="space-y-12">
    <header><p className="text-sm text-muted-foreground">Buen día,</p><h1 className="mt-1 text-3xl font-semibold tracking-[-0.045em] sm:text-4xl">{profile.data?.full_name?.split(" ")[0] || "Tu Nexo"}</h1></header>

    <section className="border-b border-border/70 pb-9">
      <p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">Dinero disponible</p>
      <MoneyValue amount={totals[baseCurrency] ?? 0n} className="mt-3 block text-[clamp(2.8rem,7vw,5.5rem)] font-semibold leading-none tracking-[-0.065em]" currency={baseCurrency} />
      <div className="mt-3 flex flex-wrap items-center gap-x-10"><FinancialMetric label="Cuentas activas" value={String(activeAccounts.length)} />{otherTotals.map(([currency, amount]) => <FinancialMetric key={currency} label={`Disponible en ${currency}`} value={<MoneyValue amount={amount ?? 0n} currency={currency as CurrencyCode} />} />)}<Button asChild className="ml-auto" size="sm" variant="ghost"><Link to="/cuentas">Ver cuentas <ArrowRight className="size-4" /></Link></Button></div>
    </section>

    <PageSection title="Necesita tu atención">
      <div className="divide-y divide-border/60 border-y border-border/60">
        {activeAccounts.length === 0 ? <Attention icon={<AlertCircle className="size-5" />} title="Agrega tu primera cuenta" detail="Necesitas un punto de partida antes de registrar actividad." action={<Button onClick={() => setAccountFormOpen(true)} size="sm">Agregar cuenta</Button>} tone="warning" /> : <Attention icon={<CheckCircle2 className="size-5" />} title="Tus cuentas están listas" detail={`${activeAccounts.length} ${activeAccounts.length === 1 ? "cuenta activa" : "cuentas activas"} disponibles para registrar movimientos.`} tone="success" />}
        {otherTotals.length ? <Attention icon={<Landmark className="size-5" />} title="Totales separados por moneda" detail="Nexo no mezcla saldos sin una tasa de cambio explícita." /> : null}
      </div>
    </PageSection>

    <div className="grid gap-12 xl:grid-cols-[minmax(0,1.55fr)_minmax(280px,.75fr)]">
      <PageSection action={<Button asChild size="sm" variant="ghost"><Link to="/movimientos">Ver todo</Link></Button>} description="Lo último que pasó con tu dinero." title="Actividad reciente">
        {movements.isLoading ? <LoadingState /> : movements.data?.length ? <MovementList movements={movements.data.slice(0, 7)} onSelect={setSelectedEventId} /> : <EmptyState action={activeAccounts.length === 0 ? <Button onClick={() => setAccountFormOpen(true)}><Landmark className="size-4" />Agregar cuenta</Button> : undefined} description={activeAccounts.length ? "Registra tu primer ingreso o gasto desde el botón Nuevo." : "Agrega una cuenta para empezar a organizar tu dinero."} title="Tu actividad aparecerá aquí" />}
      </PageSection>
      <PageSection description="Solo gasto personal en tu moneda base." title="Gasto del mes"><div className="rounded-2xl bg-surface-secondary p-6"><span className="grid size-10 place-items-center rounded-xl bg-danger/8 text-danger"><TrendingDown className="size-5" /></span><MoneyValue amount={currentSpend} className="mt-7 block text-3xl" currency={baseCurrency} /><p className="mt-2 text-sm text-muted-foreground">Mes anterior: <MoneyValue amount={previousSpend} currency={baseCurrency} size="sm" /></p><div className="mt-6 h-1.5 overflow-hidden rounded-full bg-border"><div className="h-full rounded-full bg-primary" style={{ width: `${currentSpend === 0n ? 4 : Math.min(100, Number((currentSpend * 100n) / (previousSpend || currentSpend)))}%` }} /></div></div></PageSection>
    </div>
  </div>
  <AccountFormSheet baseCurrency={baseCurrency} onOpenChange={setAccountFormOpen} open={accountFormOpen} />
  <MovementDetailSheet accounts={accounts.data ?? []} eventId={selectedEventId} onEventIdChange={setSelectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
  </PageTransition>;
}

function Attention({ action, detail, icon, title, tone = "default" }: { action?: React.ReactNode; detail: string; icon: React.ReactNode; title: string; tone?: "default" | "success" | "warning" }) {
  return <div className="flex items-center gap-4 py-4"><span className={tone === "success" ? "text-success" : tone === "warning" ? "text-warning" : "text-primary"}>{icon}</span><div className="min-w-0 flex-1"><p className="text-sm font-semibold">{title}</p><p className="mt-0.5 text-sm text-muted-foreground">{detail}</p></div>{action}</div>;
}
