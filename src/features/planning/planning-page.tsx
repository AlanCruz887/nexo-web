import { Archive, Plus, RotateCcw } from "lucide-react";
import { useMemo, useState } from "react";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useAccounts } from "@/hooks/use-accounts";
import { useFinancialPlan } from "@/hooks/use-financial-plan";
import { useArchivePlannedCashFlow, usePlannedCashFlows, useRestorePlannedCashFlow } from "@/hooks/use-planned-cash-flows";
import { cn } from "@/lib/cn";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import { PlannedCashFlowForm } from "@/features/planning/planned-cash-flow-form";
import type {
  CurrencyCode,
  FinancialPlanMonth,
  FinancialPlanScenarioPoint,
  PlannedCashFlow,
} from "@/types/database";

type Scenario = "base" | "planned";
const horizons = [3, 6, 12] as const;

function scenarioPoint(month: FinancialPlanMonth, scenario: Scenario, includeCollections: boolean): FinancialPlanScenarioPoint {
  if (scenario === "base") return month.base;
  return includeCollections ? month.planned_with_collections : month.planned;
}

export function PlanningPage() {
  const accounts = useAccounts();
  const currencies = useMemo(() => [...new Set((accounts.data ?? []).map((account) => account.currency))], [accounts.data]);
  const [currency, setCurrency] = useState<CurrencyCode | "">("");
  const effectiveCurrency = (currency || currencies[0] || "MXN") as CurrencyCode;
  const [horizon, setHorizon] = useState<(typeof horizons)[number]>(6);
  const [scenario, setScenario] = useState<Scenario>("planned");
  const [includeCollections, setIncludeCollections] = useState(false);
  const [selectedMonth, setSelectedMonth] = useState(0);
  const [formOpen, setFormOpen] = useState(false);

  const plan = useFinancialPlan(effectiveCurrency, horizon);
  const flows = usePlannedCashFlows();

  const months = plan.data?.months ?? [];
  const active = months[selectedMonth] ?? months[0];

  return <PageTransition><div className="space-y-8">
    <PageHeader
      actions={<Button onClick={() => setFormOpen(true)}><Plus className="size-4" />Nuevo flujo planeado</Button>}
      eyebrow="Plan" subtitle="Anticipa cómo se verá tu dinero en los próximos meses." title="Planeación"
    />

    <div className="flex flex-wrap items-center gap-3">
      <Select className="w-auto" onChange={(event) => setCurrency(event.target.value as CurrencyCode)} value={effectiveCurrency}>
        {(currencies.length > 0 ? currencies : ["MXN"]).map((code) => <option key={code} value={code}>{code}</option>)}
      </Select>
      <Select className="w-auto" onChange={(event) => setHorizon(Number(event.target.value) as (typeof horizons)[number])} value={horizon}>
        {horizons.map((value) => <option key={value} value={value}>{value} meses</option>)}
      </Select>
      <div className="flex overflow-hidden rounded-xl border border-border">
        <button className={cn("px-4 py-2 text-sm font-medium transition", scenario === "base" ? "bg-primary text-primary-foreground" : "bg-surface text-muted-foreground hover:text-foreground")} onClick={() => setScenario("base")} type="button">Base</button>
        <button className={cn("px-4 py-2 text-sm font-medium transition", scenario === "planned" ? "bg-primary text-primary-foreground" : "bg-surface text-muted-foreground hover:text-foreground")} onClick={() => setScenario("planned")} type="button">Planeado</button>
      </div>
      {scenario === "planned" ? <label className="flex items-center gap-2 text-sm text-muted-foreground">
        <input checked={includeCollections} className="size-4 rounded border-border accent-primary" onChange={(event) => setIncludeCollections(event.target.checked)} type="checkbox" />
        Incluir cobros esperados
      </label> : null}
    </div>

    {plan.isLoading ? <LoadingState label="Calculando tu planeación" /> : null}
    {plan.isError ? <ErrorState message={toUserMessage(plan.error)} onRetry={() => void plan.refetch()} /> : null}

    {plan.data ? <>
      <SaldoInicialCard currency={effectiveCurrency} saldo={plan.data.saldo_inicial} />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        {months.map((month, index) => {
          const point = scenarioPoint(month, scenario, includeCollections);
          const closingMinor = BigInt(point.closing_minor);
          const isNegative = closingMinor < 0n;
          return <button
            className={cn(
              "rounded-2xl border p-4 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30",
              index === selectedMonth ? "border-primary/40 bg-primary-soft" : "border-border bg-surface",
            )}
            key={month.month_start}
            onClick={() => setSelectedMonth(index)}
            type="button"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.12em] text-muted-foreground">{formatFinancialDate(month.month_start, "MMM yyyy")}</p>
            {isNegative ? (
              <p className="mt-2 text-sm font-semibold text-danger">Te faltarían ≈ <MoneyValue amount={(-closingMinor).toString()} currency={effectiveCurrency} size="sm" /></p>
            ) : (
              <p className="mt-2"><MoneyValue amount={point.closing_minor} currency={effectiveCurrency} size="md" /></p>
            )}
          </button>;
        })}
      </div>

      {active ? <MonthDetail currency={effectiveCurrency} includeCollections={includeCollections} month={active} scenario={scenario} /> : null}
    </> : null}

    <PlannedFlowsPanel flows={flows.data ?? []} />

    <PlannedCashFlowForm onOpenChange={setFormOpen} open={formOpen} />
  </div></PageTransition>;
}

function SaldoInicialCard({ currency, saldo }: { currency: CurrencyCode; saldo: NonNullable<ReturnType<typeof useFinancialPlan>["data"]>["saldo_inicial"] }) {
  return <Card>
    <p className="text-xs font-semibold uppercase tracking-[0.12em] text-muted-foreground">Saldo inicial</p>
    <div className="mt-3 grid gap-4 sm:grid-cols-3">
      <div><p className="text-xs text-muted-foreground">En tus cuentas</p><MoneyValue amount={saldo.saldo_en_cuentas_minor} currency={currency} size="lg" /></div>
      <div><p className="text-xs text-muted-foreground">Apartado en metas</p><MoneyValue amount={saldo.apartado_respaldado_minor} currency={currency} size="lg" /></div>
      <div><p className="text-xs text-muted-foreground">Disponible sin comprometer</p><MoneyValue amount={saldo.disponible_sin_comprometer_minor} currency={currency} size="lg" /></div>
    </div>
    {saldo.faltante_de_respaldo_minor !== "0" ? <p className="mt-3 text-xs text-muted-foreground">
      Tienes <MoneyValue amount={saldo.faltante_de_respaldo_minor} currency={currency} size="sm" /> registrado en metas que tus cuentas ya no respaldan por completo (por gastos posteriores). No se resta de nuevo aquí ni genera una aportación automática.
    </p> : null}
  </Card>;
}

function MonthDetail({ currency, includeCollections, month, scenario }: { currency: CurrencyCode; includeCollections: boolean; month: FinancialPlanMonth; scenario: Scenario }) {
  const point = scenarioPoint(month, scenario, includeCollections);
  return <Card className="space-y-6">
    <div className="flex items-center justify-between">
      <h2 className="text-lg font-semibold capitalize tracking-tight">{formatFinancialDate(month.month_start, "MMMM yyyy")}</h2>
      <div className="text-right"><p className="text-xs text-muted-foreground">Saldo proyectado</p><MoneyValue amount={point.closing_minor} currency={currency} size="lg" /></div>
    </div>

    <DetailSection empty="Sin entradas planeadas este mes." title="Entradas planeadas">
      {month.planned_flows.filter((flow) => !flow.amount_minor.startsWith("-")).map((flow) => <Line key={flow.flow_id} label={flow.name} value={<MoneyValue amount={flow.amount_minor} currency={currency} sign="always" size="sm" />} />)}
    </DetailSection>

    <DetailSection empty="Sin obligaciones de tarjeta este mes." title="Obligaciones" total={month.card_obligations_total_minor}>
      {month.card_obligations.map((obligation) => <Line key={`${obligation.card_id}-${obligation.statement_date}`}
        label={`${obligation.name} · vence ${formatFinancialDate(obligation.payment_due_date, "d MMM")}${obligation.is_closed ? "" : " (estimado)"}`}
        value={<MoneyValue amount={obligation.amount_minor} currency={currency} size="sm" />} />)}
    </DetailSection>

    <DetailSection empty="Sin gastos planeados categorizados este mes." title="Gastos planeados">
      {month.planned_flows.filter((flow) => flow.amount_minor.startsWith("-")).map((flow) => <Line key={flow.flow_id} label={flow.name} value={<MoneyValue amount={flow.amount_minor} currency={currency} size="sm" />} />)}
    </DetailSection>

    {scenario === "planned" ? <DetailSection empty="Sin presupuestos este mes." title="Presupuestos (flexible restante)" total={month.flexible_additional_total_minor}>
      {month.budgets.map((budget) => <Line key={budget.category_id} label={budget.category_name} value={<MoneyValue amount={budget.flexible_additional_minor} currency={currency} size="sm" />} />)}
    </DetailSection> : null}

    {scenario === "planned" ? <DetailSection empty="Sin metas con aportación recomendada este mes." title="Metas" total={month.goals_recommended_total_minor}>
      {month.goals.filter((goal) => goal.recommended_minor !== "0").map((goal) => <Line key={goal.goal_id} label={goal.name + (goal.target_date_passed ? " · fecha vencida" : "")} value={<MoneyValue amount={goal.recommended_minor} currency={currency} size="sm" />} />)}
    </DetailSection> : null}

    {scenario === "planned" && includeCollections ? <DetailSection empty="Sin cobros esperados este mes." title="Posibles entradas (cobros de personas)" total={month.expected_collections_total_minor}>
      {month.expected_collections.map((collection) => <Line key={collection.contact_id} label={collection.contact_name + " (no garantizado)"} value={<MoneyValue amount={collection.outstanding_minor} currency={currency} size="sm" />} />)}
    </DetailSection> : null}
  </Card>;
}

function DetailSection({ children, empty, title, total }: { children: React.ReactNode; empty: string; title: string; total?: string }) {
  const items = Array.isArray(children) ? children : children ? [children] : [];
  return <div>
    <div className="flex items-center justify-between"><h3 className="text-sm font-semibold text-foreground">{title}</h3>{total !== undefined ? <span className="text-sm font-semibold text-muted-foreground">{total}</span> : null}</div>
    <div className="mt-2 space-y-1.5">
      {items.length === 0 ? <p className="text-sm text-muted-foreground">{empty}</p> : items}
    </div>
  </div>;
}

function Line({ label, value }: { label: string; value: React.ReactNode }) {
  return <div className="flex items-center justify-between text-sm"><span className="min-w-0 truncate text-muted-foreground">{label}</span><span className="shrink-0 font-medium text-foreground">{value}</span></div>;
}

function PlannedFlowsPanel({ flows }: { flows: PlannedCashFlow[] }) {
  const archive = useArchivePlannedCashFlow();
  const restore = useRestorePlannedCashFlow();
  const toast = useToast();
  const active = flows.filter((flow) => flow.archived_at === null);

  async function toggleArchive(flow: PlannedCashFlow) {
    try {
      if (flow.archived_at) { await restore.mutateAsync(flow.id); toast.success("Flujo restaurado"); }
      else { await archive.mutateAsync(flow.id); toast.success("Flujo archivado"); }
    } catch (error) { toast.error(toUserMessage(error)); }
  }

  return <div className="space-y-4">
    <h2 className="text-lg font-semibold tracking-tight">Tus flujos planeados</h2>
    {active.length === 0 ? (
      <EmptyState description="Declara entradas o salidas que sabes que vienen (renta, aguinaldo, colegiatura) para que la planeación las incluya." title="Sin flujos planeados todavía" />
    ) : (
      <div className="space-y-2">
        {active.map((flow) => <Card className="flex items-center justify-between p-4" key={flow.id}>
          <div>
            <p className="font-medium">{flow.name}</p>
            <p className="text-xs text-muted-foreground">{flow.recurrence === "monthly" ? "Cada mes" : "Una sola vez"} · desde {formatFinancialDate(flow.start_date, "d MMM yyyy")}</p>
          </div>
          <div className="flex items-center gap-3">
            <MoneyValue amount={flow.amount_minor} currency={flow.currency} sign="always" size="sm" />
            <Button aria-label="Archivar" onClick={() => void toggleArchive(flow)} size="icon" variant="ghost"><Archive className="size-4" /></Button>
          </div>
        </Card>)}
      </div>
    )}
    {flows.some((flow) => flow.archived_at !== null) ? <details className="text-sm text-muted-foreground">
      <summary className="cursor-pointer">Flujos archivados</summary>
      <div className="mt-2 space-y-2">
        {flows.filter((flow) => flow.archived_at !== null).map((flow) => <div className="flex items-center justify-between rounded-xl border border-dashed border-border p-3" key={flow.id}>
          <span>{flow.name}</span>
          <Button aria-label="Restaurar" onClick={() => void toggleArchive(flow)} size="icon" variant="ghost"><RotateCcw className="size-4" /></Button>
        </div>)}
      </div>
    </details> : null}
  </div>;
}
