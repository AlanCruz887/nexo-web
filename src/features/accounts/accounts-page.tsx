import { ArrowLeftRight, Plus } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { FilterBar, FilterPill } from "@/components/filter-bar";
import { MoneyValue } from "@/components/money-value";
import { PageHeader, SectionHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { AccountsSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { useAccounts, sumBalancesByCurrency } from "@/hooks/use-accounts";
import { useMovements } from "@/hooks/use-movements";
import { useProfile } from "@/hooks/use-profile";
import { toUserMessage } from "@/lib/errors";
import type { AccountBalance } from "@/types/database";
import { AccountCard } from "@/features/accounts/account-card";
import { AccountFormSheet } from "@/features/accounts/account-form-sheet";
import { MovementDetailSheet } from "@/features/movements/movement-detail-sheet";
import { MovementList } from "@/features/movements/movement-list";
import { TransferFormSheet } from "@/features/movements/transfer-form-sheet";

export function AccountsPage() {
  const { user } = useAuth();
  const profile = useProfile(user?.id);
  const accounts = useAccounts();
  const movements = useMovements();
  const [view, setView] = useState<"active" | "archived">("active");
  const [accountFormOpen, setAccountFormOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();

  if ((accounts.isLoading && !accounts.data) || (profile.isLoading && !profile.data)) return <AccountsSkeleton />;
  if (accounts.isError) return <ErrorState message={toUserMessage(accounts.error)} onRetry={() => void accounts.refetch()} />;
  const allAccounts = accounts.data ?? [];
  const activeAccounts = allAccounts.filter((account) => account.is_active);
  const visibleAccounts = allAccounts.filter((account) => account.is_active === (view === "active"));
  const totals = sumBalancesByCurrency(activeAccounts);
  const totalEntries = Object.entries(totals);

  return (
    <PageTransition>
      <div className="space-y-12">
        <PageHeader actions={<Button onClick={() => setAccountFormOpen(true)}><Plus className="size-4" />Agregar cuenta</Button>} eyebrow="Tu dinero" subtitle="Saldos reconstruidos desde movimientos, sin conversiones automáticas." title="Cuentas" />

        {allAccounts.length === 0 ? (
          <EmptyState action={<Button onClick={() => setAccountFormOpen(true)}>Agregar cuenta</Button>} description="Agrega tu primera cuenta para empezar a registrar movimientos." title="Todavía no tienes cuentas" />
        ) : (
          <>
            <section className="border-b border-border/70 pb-9">
              <div className="flex flex-col gap-7 sm:flex-row sm:items-end sm:justify-between">
                <div>
                  <p className="text-xs font-medium uppercase tracking-[0.16em] text-muted-foreground">Total disponible</p>
                  <div className="mt-2 flex flex-wrap items-baseline gap-x-6 gap-y-2">
                    {totalEntries.map(([currency, amount]) => <MoneyValue key={currency} amount={amount ?? 0n} className="block text-[clamp(2.6rem,6vw,4.8rem)] leading-none tracking-[-0.06em]" currency={currency as AccountBalance["currency"]} />)}
                  </div>
                  {totalEntries.length > 1 ? <p className="mt-3 text-xs text-muted-foreground">Totales separados por moneda. Nexo no inventa tipos de cambio.</p> : null}
                </div>
                <Button disabled={activeAccounts.length < 2} onClick={() => setTransferOpen(true)} variant="secondary"><ArrowLeftRight className="size-4" />Transferir</Button>
              </div>
            </section>

            <section className="space-y-4">
              <SectionHeader action={<FilterBar><FilterPill active={view === "active"} onClick={() => setView("active")}>Activas</FilterPill><FilterPill active={view === "archived"} onClick={() => setView("archived")}>Archivadas</FilterPill></FilterBar>} title="Tus cuentas" />
              {visibleAccounts.length ? <div className="grid gap-4 md:grid-cols-2">{visibleAccounts.map((account, index) => <AccountCard key={account.id} account={account} featured={view === "active" && index === 0} />)}</div> : <EmptyState description={view === "archived" ? "Las cuentas que archives aparecerán aquí con todo su historial." : "No hay cuentas activas."} title={view === "archived" ? "Sin cuentas archivadas" : "Sin cuentas activas"} />}
            </section>

            <section className="space-y-4">
              <SectionHeader action={<Button asChild size="sm" variant="ghost"><Link to="/movimientos">Ver todos</Link></Button>} subtitle="Ingresos, gastos y transferencias recientes." title="Actividad reciente" />
              {movements.isLoading ? <LoadingState label="Cargando actividad" /> : movements.data?.length ? <MovementList movements={movements.data.slice(0, 6)} onSelect={setSelectedEventId} /> : <EmptyState description="Registra un ingreso o gasto desde el detalle de una cuenta." title="Aún no hay movimientos" />}
            </section>
          </>
        )}
      </div>
      <AccountFormSheet baseCurrency={profile.data?.base_currency ?? "MXN"} onOpenChange={setAccountFormOpen} open={accountFormOpen} />
      <TransferFormSheet accounts={activeAccounts} onOpenChange={setTransferOpen} open={transferOpen} />
      <MovementDetailSheet accounts={allAccounts} eventId={selectedEventId} onEventIdChange={setSelectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
    </PageTransition>
  );
}
