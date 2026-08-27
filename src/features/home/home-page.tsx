import { ArrowRight, Landmark, Plus } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageTransition } from "@/components/page-transition";
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
  if (accounts.isLoading || profile.isLoading) return <LoadingState label="Preparando tu resumen" />;
  if (accounts.isError) return <ErrorState message={toUserMessage(accounts.error)} />;
  const activeAccounts = accounts.data?.filter((account) => account.is_active) ?? [];
  const totals = sumBalancesByCurrency(activeAccounts);
  const baseCurrency = profile.data?.base_currency ?? "MXN";

  return (
    <PageTransition>
      <div className="space-y-9">
        <header className="flex items-center justify-between">
          <div><p className="text-sm text-muted-foreground">Buen día</p><h1 className="mt-1 text-3xl font-semibold tracking-[-0.035em]">{profile.data?.full_name?.split(" ")[0] || "Tu Nexo"}</h1></div>
          <Button aria-label="Agregar cuenta" onClick={() => setAccountFormOpen(true)} size="icon" variant="secondary"><Plus className="size-5" /></Button>
        </header>
        <section className="relative overflow-hidden rounded-[32px] bg-foreground p-7 text-background sm:p-10">
          <div className="absolute -right-20 -top-24 size-64 rounded-full bg-primary/30 blur-3xl" />
          <div className="relative">
            <p className="text-sm font-medium text-background/60">Dinero disponible</p>
            <MoneyValue amount={totals[baseCurrency] ?? 0n} className="mt-2 block" currency={baseCurrency} size="xl" />
            {Object.keys(totals).length > 1 ? <div className="mt-4 flex flex-wrap gap-3">{Object.entries(totals).filter(([currency]) => currency !== baseCurrency).map(([currency, amount]) => <span key={currency} className="rounded-full bg-background/10 px-3 py-1.5"><MoneyValue amount={amount ?? 0n} currency={currency as CurrencyCode} size="sm" /></span>)}</div> : null}
            <div className="mt-9 flex items-center justify-between border-t border-background/10 pt-5"><span className="text-sm text-background/60">{activeAccounts.length} {activeAccounts.length === 1 ? "cuenta activa" : "cuentas activas"}</span><Button asChild className="text-background hover:bg-background/10 hover:text-background" size="sm" variant="ghost"><Link to="/cuentas">Ver cuentas <ArrowRight className="size-4" /></Link></Button></div>
          </div>
        </section>
        <section>
          <div className="mb-4 flex items-end justify-between"><div><h2 className="text-lg font-semibold">Actividad reciente</h2><p className="mt-1 text-sm text-muted-foreground">Lo último que pasó con tu dinero.</p></div><Button asChild size="sm" variant="ghost"><Link to="/movimientos">Ver todo</Link></Button></div>
          {movements.isLoading ? <LoadingState /> : movements.data?.length ? <MovementList movements={movements.data.slice(0, 7)} onSelect={setSelectedEventId} /> : <EmptyState action={activeAccounts.length === 0 ? <Button onClick={() => setAccountFormOpen(true)}><Landmark className="size-4" />Agregar cuenta</Button> : undefined} description={activeAccounts.length ? "Abre una cuenta para registrar tu primer ingreso o gasto." : "Agrega una cuenta para empezar a organizar tu dinero."} title="Tu actividad aparecerá aquí" />}
        </section>
      </div>
      <AccountFormSheet baseCurrency={baseCurrency} onOpenChange={setAccountFormOpen} open={accountFormOpen} />
      <MovementDetailSheet accounts={accounts.data ?? []} eventId={selectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
    </PageTransition>
  );
}
