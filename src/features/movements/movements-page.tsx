import { ListFilter } from "lucide-react";
import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { EmptyState, ErrorState } from "@/components/feedback";
import { FilterBar, FilterPill } from "@/components/filter-bar";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { QuickAddMenu, type QuickAction } from "@/components/quick-add-menu";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { TransactionsSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useAccounts } from "@/hooks/use-accounts";
import { useCards } from "@/hooks/use-cards";
import { useCategories, useMovements } from "@/hooks/use-movements";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import type { MovementFilters } from "@/services/movement-service";
import type { AccountBalance, CardSummary } from "@/types/database";
import { MovementDetailSheet } from "@/features/movements/movement-detail-sheet";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { MovementList } from "@/features/movements/movement-list";
import { instrumentFilterForOrigin, normalizeOriginChange, visibleInstruments } from "@/lib/movement-filters";
import { TransferFormSheet } from "@/features/movements/transfer-form-sheet";
import { CardPurchaseForm } from "@/features/cards/card-purchase-form";

export function MovementsPage() {
  const [searchParams] = useSearchParams();
  const initialAccount = searchParams.get("cuenta") ?? undefined;
  const [kind, setKind] = useState<MovementFilters["kind"]>("all");
  const [origin, setOrigin] = useState<MovementFilters["origin"]>(initialAccount ? "accounts" : "all");
  const [accountId, setAccountId] = useState(initialAccount ?? "");
  const [cardId, setCardId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [minimum, setMinimum] = useState("");
  const [maximum, setMaximum] = useState("");
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [includeArchived, setIncludeArchived] = useState(false);
  const [movementOpen, setMovementOpen] = useState(false);
  const [movementKind, setMovementKind] = useState<"income" | "expense">("expense");
  const [transferOpen, setTransferOpen] = useState(false);
  const [cardPurchaseOpen, setCardPurchaseOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();
  const accounts = useAccounts();
  const cards = useCards();
  const categories = useCategories();
  const filters = useMemo<MovementFilters>(() => {
    const next: MovementFilters = {};
    const instrument = instrumentFilterForOrigin(origin ?? "all", accountId, cardId);
    if (kind && kind !== "all") next.kind = kind;
    if (origin && origin !== "all") next.origin = origin;
    if (instrument.accountId) next.accountId = instrument.accountId;
    if (instrument.cardId) next.cardId = instrument.cardId;
    if (categoryId) next.categoryId = categoryId;
    if (dateFrom) next.dateFrom = dateFrom;
    if (dateTo) next.dateTo = dateTo;
    try { if (minimum) next.minimumMinor = serializeMoneyMinor(parseMoneyInput(minimum)); } catch { /* wait for valid input */ }
    try { if (maximum) next.maximumMinor = serializeMoneyMinor(parseMoneyInput(maximum)); } catch { /* wait for valid input */ }
    return next;
  }, [accountId, cardId, categoryId, dateFrom, dateTo, kind, maximum, minimum, origin]);
  const movements = useMovements(filters);
  const activeAccounts = accounts.data?.filter((account) => account.is_active) ?? [];
  const filterAccounts = visibleInstruments(accounts.data ?? [], includeArchived);
  const filterCards = visibleInstruments(cards.data ?? [], includeArchived);

  if ((accounts.isLoading && !accounts.data) || (cards.isLoading && !cards.data) || (movements.isLoading && !movements.data)) return <TransactionsSkeleton />;

  function openMovement(nextKind: "income" | "expense") { setMovementKind(nextKind); setMovementOpen(true); }
  function openQuickAction(action: QuickAction) { if (action === "expense" || action === "income") openMovement(action); else if (action === "transfer") setTransferOpen(true); else if (action === "card_purchase") setCardPurchaseOpen(true); }
  function changeOrigin(nextOrigin: NonNullable<MovementFilters["origin"]>) { const next = normalizeOriginChange(nextOrigin); setOrigin(next.origin); setAccountId(next.accountId); setCardId(next.cardId); }
  function changeArchived(next: boolean) { setIncludeArchived(next); if (!next) { if (accountId && !accounts.data?.find((item) => item.id === accountId)?.is_active) setAccountId(""); if (cardId && !cards.data?.find((item) => item.id === cardId)?.is_active) setCardId(""); } }

  return (
    <PageTransition>
      <div className="space-y-10">
        <PageHeader actions={<QuickAddMenu includeAccount={false} onSelect={openQuickAction} />} eyebrow="Actividad" subtitle="Todo lo que pasó en tus cuentas y tarjetas, en un solo lugar." title="Movimientos" />
        <section className="space-y-4 border-b border-border/60 pb-6">
          <div><p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">Origen</p><FilterBar>{(["all", "accounts", "cards"] as const).map((value) => <FilterPill active={origin === value} key={value} onClick={() => changeOrigin(value)}>{value === "all" ? "Todos" : value === "accounts" ? "Cuentas" : "Tarjetas"}</FilterPill>)}</FilterBar></div>
          <div className="flex items-center justify-between gap-3">
            <FilterBar>{(["all", "income", "expense", "installments", "transfer", "card_payment", "card_refund"] as const).map((value) => <FilterPill key={value} active={kind === value} onClick={() => setKind(value)}>{value === "all" ? "Todos" : value === "income" ? "Ingresos" : value === "expense" ? "Gastos" : value === "installments" ? "MSI" : value === "transfer" ? "Transferencias" : value === "card_payment" ? "Pagos de tarjeta" : "Reembolsos"}</FilterPill>)}</FilterBar>
            <Button aria-expanded={advancedOpen} aria-label="Más filtros" onClick={() => setAdvancedOpen(true)} size="icon" variant={advancedOpen ? "secondary" : "ghost"}><ListFilter className="size-4" /></Button>
          </div>
          {origin !== "all" ? <div className="hidden max-w-sm sm:block"><InstrumentSelect accountId={accountId} accounts={filterAccounts} cardId={cardId} cards={filterCards} onAccount={setAccountId} onCard={setCardId} origin={origin} /></div> : null}
          <div className="flex flex-wrap gap-2 sm:hidden">{accountId ? <span className="rounded-full bg-primary-soft px-3 py-1 text-xs font-medium text-primary-strong">{accounts.data?.find((item) => item.id === accountId)?.name}</span> : null}{cardId ? <span className="rounded-full bg-primary-soft px-3 py-1 text-xs font-medium text-primary-strong">{cards.data?.find((item) => item.id === cardId)?.name}</span> : null}{categoryId ? <span className="rounded-full bg-surface-secondary px-3 py-1 text-xs font-medium">{categories.data?.find((item) => item.id === categoryId)?.name}</span> : null}</div>
        </section>
        {accounts.isError || cards.isError || movements.isError ? <ErrorState message={toUserMessage(accounts.error ?? cards.error ?? movements.error)} onRetry={() => void movements.refetch()} /> : movements.data?.length ? <div className={movements.isFetching ? "opacity-70 transition-opacity" : "opacity-100 transition-opacity"}><MovementList movements={movements.data} onSelect={setSelectedEventId} /></div> : <EmptyState action={activeAccounts.length ? <Button onClick={() => openMovement("expense")}>Registrar movimiento</Button> : undefined} description="Prueba otro filtro o registra una operación desde Nuevo." title="No hay movimientos en este periodo" />}
      </div>
      <MovementFormSheet accounts={accounts.data ?? []} defaultAccountId={initialAccount} defaultKind={movementKind} onOpenChange={setMovementOpen} open={movementOpen} />
      <TransferFormSheet accounts={accounts.data ?? []} defaultFromAccountId={initialAccount} onOpenChange={setTransferOpen} open={transferOpen} />
      <CardPurchaseForm cards={cards.data ?? []} onOpenChange={setCardPurchaseOpen} open={cardPurchaseOpen} />
      <ResponsiveDialog footer={<Button onClick={() => setAdvancedOpen(false)}>Aplicar filtros</Button>} onOpenChange={setAdvancedOpen} open={advancedOpen} size="medium" title="Filtros"><div className="space-y-5">{origin !== "all" ? <InstrumentSelect accountId={accountId} accounts={filterAccounts} cardId={cardId} cards={filterCards} onAccount={setAccountId} onCard={setCardId} origin={origin} /> : <p className="rounded-xl bg-surface-secondary p-4 text-sm text-muted-foreground">Elige Cuentas o Tarjetas si quieres filtrar por un origen específico.</p>}<label className="flex min-h-11 items-center gap-3 rounded-xl border border-border px-3 text-sm font-medium"><input checked={includeArchived} onChange={(event) => changeArchived(event.target.checked)} type="checkbox" />Incluir cuentas y tarjetas archivadas</label><Select aria-label="Filtrar por categoría" onChange={(event) => setCategoryId(event.target.value)} value={categoryId}><option value="">Todas las categorías</option>{categories.data?.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</Select><div className="grid gap-3 sm:grid-cols-2"><Input aria-label="Fecha inicial" onChange={(event) => setDateFrom(event.target.value)} type="date" value={dateFrom} /><Input aria-label="Fecha final" onChange={(event) => setDateTo(event.target.value)} type="date" value={dateTo} /><Input aria-label="Importe mínimo" inputMode="decimal" onChange={(event) => setMinimum(event.target.value)} placeholder="Importe mínimo" value={minimum} /><Input aria-label="Importe máximo" inputMode="decimal" onChange={(event) => setMaximum(event.target.value)} placeholder="Importe máximo" value={maximum} /></div></div></ResponsiveDialog>
      <MovementDetailSheet accounts={accounts.data ?? []} eventId={selectedEventId} onEventIdChange={setSelectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
    </PageTransition>
  );
}

function InstrumentSelect({ accountId, accounts, cardId, cards, onAccount, onCard, origin }: { accountId: string; accounts: AccountBalance[]; cardId: string; cards: CardSummary[]; onAccount: (id: string) => void; onCard: (id: string) => void; origin: MovementFilters["origin"] }) { if (origin === "accounts") return <Select aria-label="Cuenta" onChange={(event) => onAccount(event.target.value)} value={accountId}><option value="">Todas las cuentas</option><InstrumentGroups items={accounts} /></Select>; return <Select aria-label="Tarjeta" onChange={(event) => onCard(event.target.value)} value={cardId}><option value="">Todas las tarjetas</option><InstrumentGroups items={cards} /></Select>; }
function InstrumentGroups<T extends { id: string; name: string; is_active: boolean }>({ items }: { items: T[] }) { const active = items.filter((item) => item.is_active); const archived = items.filter((item) => !item.is_active); return <>{active.length ? <optgroup label="ACTIVAS">{active.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</optgroup> : null}{archived.length ? <optgroup label="ARCHIVADAS">{archived.map((item) => <option key={item.id} value={item.id}>{item.name} · Archivada</option>)}</optgroup> : null}</>; }
