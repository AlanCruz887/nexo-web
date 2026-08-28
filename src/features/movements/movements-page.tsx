import { ArrowLeftRight, ListFilter, Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { EmptyState, ErrorState } from "@/components/feedback";
import { FilterBar, FilterPill } from "@/components/filter-bar";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { TransactionsSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useAccounts } from "@/hooks/use-accounts";
import { useCategories, useMovements } from "@/hooks/use-movements";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import type { MovementFilters } from "@/services/movement-service";
import { MovementDetailSheet } from "@/features/movements/movement-detail-sheet";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { MovementList } from "@/features/movements/movement-list";
import { TransferFormSheet } from "@/features/movements/transfer-form-sheet";

export function MovementsPage() {
  const [searchParams] = useSearchParams();
  const initialAccount = searchParams.get("cuenta") ?? undefined;
  const [kind, setKind] = useState<MovementFilters["kind"]>("all");
  const [accountId, setAccountId] = useState(initialAccount ?? "");
  const [categoryId, setCategoryId] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [minimum, setMinimum] = useState("");
  const [maximum, setMaximum] = useState("");
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [movementOpen, setMovementOpen] = useState(false);
  const [movementKind, setMovementKind] = useState<"income" | "expense">("expense");
  const [transferOpen, setTransferOpen] = useState(false);
  const [selectedEventId, setSelectedEventId] = useState<string>();
  const accounts = useAccounts();
  const categories = useCategories();
  const filters = useMemo<MovementFilters>(() => {
    const next: MovementFilters = {};
    if (kind && kind !== "all") next.kind = kind;
    if (accountId) next.accountId = accountId;
    if (categoryId) next.categoryId = categoryId;
    if (dateFrom) next.dateFrom = dateFrom;
    if (dateTo) next.dateTo = dateTo;
    try { if (minimum) next.minimumMinor = serializeMoneyMinor(parseMoneyInput(minimum)); } catch { /* wait for valid input */ }
    try { if (maximum) next.maximumMinor = serializeMoneyMinor(parseMoneyInput(maximum)); } catch { /* wait for valid input */ }
    return next;
  }, [accountId, categoryId, dateFrom, dateTo, kind, maximum, minimum]);
  const movements = useMovements(filters);
  const activeAccounts = accounts.data?.filter((account) => account.is_active) ?? [];

  if ((accounts.isLoading && !accounts.data) || (movements.isLoading && !movements.data)) return <TransactionsSkeleton />;

  function openMovement(nextKind: "income" | "expense") { setMovementKind(nextKind); setMovementOpen(true); }

  return (
    <PageTransition>
      <div className="space-y-10">
        <PageHeader actions={<div className="flex gap-2"><Button onClick={() => openMovement("expense")}><Plus className="size-4" />Movimiento</Button><Button aria-label="Transferir" onClick={() => setTransferOpen(true)} size="icon" variant="secondary"><ArrowLeftRight className="size-4" /></Button></div>} eyebrow="Actividad" subtitle="Una cronología clara de cada entrada y salida de tus cuentas." title="Movimientos" />
        <section className="space-y-4 border-b border-border/60 pb-6">
          <div className="flex items-center justify-between gap-3">
            <FilterBar>{(["all", "income", "expense", "transfer"] as const).map((value) => <FilterPill key={value} active={kind === value} onClick={() => setKind(value)}>{value === "all" ? "Todos" : value === "income" ? "Ingresos" : value === "expense" ? "Gastos" : "Transferencias"}</FilterPill>)}</FilterBar>
            <Button aria-expanded={advancedOpen} aria-label="Más filtros" onClick={() => setAdvancedOpen((current) => !current)} size="icon" variant={advancedOpen ? "secondary" : "ghost"}><ListFilter className="size-4" /></Button>
          </div>
          {advancedOpen ? <div className="grid gap-3 rounded-2xl border border-border/70 bg-surface-secondary p-4 sm:grid-cols-2 lg:grid-cols-3">
            <Select aria-label="Filtrar por cuenta" onChange={(event) => setAccountId(event.target.value)} value={accountId}><option value="">Todas las cuentas</option>{accounts.data?.map((account) => <option key={account.id} value={account.id}>{account.name}{!account.is_active ? " · Archivada" : ""}</option>)}</Select>
            <Select aria-label="Filtrar por categoría" onChange={(event) => setCategoryId(event.target.value)} value={categoryId}><option value="">Todas las categorías</option>{categories.data?.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</Select>
            <Input aria-label="Fecha inicial" onChange={(event) => setDateFrom(event.target.value)} type="date" value={dateFrom} />
            <Input aria-label="Fecha final" onChange={(event) => setDateTo(event.target.value)} type="date" value={dateTo} />
            <Input aria-label="Importe mínimo" inputMode="decimal" onChange={(event) => setMinimum(event.target.value)} placeholder="Importe mínimo" value={minimum} />
            <Input aria-label="Importe máximo" inputMode="decimal" onChange={(event) => setMaximum(event.target.value)} placeholder="Importe máximo" value={maximum} />
          </div> : null}
        </section>
        {accounts.isError || movements.isError ? <ErrorState message={toUserMessage(accounts.error ?? movements.error)} onRetry={() => void movements.refetch()} /> : movements.data?.length ? <div className={movements.isFetching ? "opacity-70 transition-opacity" : "opacity-100 transition-opacity"}><MovementList movements={movements.data} onSelect={setSelectedEventId} /></div> : <EmptyState action={activeAccounts.length ? <Button onClick={() => openMovement("expense")}>Registrar movimiento</Button> : undefined} description={activeAccounts.length ? "Prueba otro filtro o registra tu primera entrada o salida." : "Agrega una cuenta antes de registrar actividad."} title="No hay movimientos en este periodo" />}
      </div>
      <MovementFormSheet accounts={accounts.data ?? []} defaultAccountId={initialAccount} defaultKind={movementKind} onOpenChange={setMovementOpen} open={movementOpen} />
      <TransferFormSheet accounts={accounts.data ?? []} defaultFromAccountId={initialAccount} onOpenChange={setTransferOpen} open={transferOpen} />
      <MovementDetailSheet accounts={accounts.data ?? []} eventId={selectedEventId} onEventIdChange={setSelectedEventId} onOpenChange={(open) => { if (!open) setSelectedEventId(undefined); }} open={Boolean(selectedEventId)} />
    </PageTransition>
  );
}
