import { ArrowLeft, ChevronDown, FileSpreadsheet, FileText, Printer, Share2, Table } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ActionMenu } from "@/components/action-menu";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageTransition } from "@/components/page-transition";
import { useToast } from "@/components/toast";
import { Button } from "@/components/ui/button";
import { useContact, useContactInstallments, useContactStatement, useRecordPersonStatementExport } from "@/hooks/use-contacts";
import { formatFinancialDate } from "@/lib/dates";
import { downloadFile, shareOrDownloadFile } from "@/lib/download-file";
import { toUserMessage } from "@/lib/errors";
import { buildStatementDocument, type StatementBlock } from "@/lib/person-statement";
import { buildStatementCsv } from "@/lib/statement-export-csv";
import { buildStatementPdf } from "@/lib/statement-export-pdf";
import { buildStatementXlsx } from "@/lib/statement-export-xlsx";
import type { PersonInstallmentSummary } from "@/types/database";

type ExportFormat = "pdf" | "xlsx" | "csv";

function slugify(value: string) {
  return value.trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "") || "persona";
}

export function PersonStatementPage() {
  const { id } = useParams();
  const contact = useContact(id);
  const statement = useContactStatement(id);
  const installments = useContactInstallments(id);
  const recordExport = useRecordPersonStatementExport(id ?? "missing");
  const toast = useToast();
  const [busy, setBusy] = useState<ExportFormat | "share" | null>(null);

  if (contact.isLoading || statement.isLoading) return <LoadingState label="Cargando estado" />;
  if (contact.isError || statement.isError) return <ErrorState message={toUserMessage(contact.error ?? statement.error)} onRetry={() => { void contact.refetch(); void statement.refetch(); }} />;
  const person = contact.data;
  if (!person) return <EmptyState description="La persona no existe o no tienes acceso." title="No encontramos esta persona" />;

  const personName = person.name;
  const statementDoc = buildStatementDocument(personName, statement.data ?? { as_of_date: new Date().toISOString().slice(0, 10), periods: [], payments: [] });
  const filenameBase = `estado-${slugify(personName)}`;

  async function runExport(format: ExportFormat) {
    setBusy(format);
    try {
      if (format === "pdf") { downloadFile(await buildStatementPdf(statementDoc, new Date()), `${filenameBase}.pdf`, "application/pdf"); }
      else if (format === "xlsx") { downloadFile(buildStatementXlsx(statementDoc), `${filenameBase}.xlsx`, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"); }
      else { downloadFile(buildStatementCsv(statementDoc), `${filenameBase}.csv`, "text/csv;charset=utf-8"); }
      const primary = statementDoc.blocks[0];
      await recordExport.mutateAsync({ start: primary?.periodStart ?? statementDoc.asOfDate, end: primary?.paymentDueDate ?? statementDoc.asOfDate, format });
      toast.success("Exportación lista");
    } catch (error) { toast.error(toUserMessage(error)); } finally { setBusy(null); }
  }

  async function runShare() {
    setBusy("share");
    try {
      const bytes = await buildStatementPdf(statementDoc, new Date());
      const result = await shareOrDownloadFile(bytes, `${filenameBase}.pdf`, "application/pdf", `Estado de ${personName}`);
      if (result === "cancelled") return;
      const primary = statementDoc.blocks[0];
      await recordExport.mutateAsync({ start: primary?.periodStart ?? statementDoc.asOfDate, end: primary?.paymentDueDate ?? statementDoc.asOfDate, format: "pdf" });
      toast.success(result === "shared" ? "Estado compartido" : "PDF descargado");
    } catch (error) { toast.error(toUserMessage(error)); } finally { setBusy(null); }
  }

  return <PageTransition><div className="mx-auto max-w-3xl space-y-10">
    <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
      <Link className="inline-flex min-h-11 items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground" to={`/personas/${person.id}`}><ArrowLeft className="size-4" />{personName}</Link>
      <div className="flex flex-wrap items-center gap-2">
        <Button onClick={() => window.print()} size="sm" variant="ghost"><Printer className="size-4" />Imprimir</Button>
        <Button disabled={busy !== null} onClick={() => void runShare()} size="sm" variant="secondary"><Share2 className="size-4" />{busy === "share" ? "Compartiendo…" : "Compartir"}</Button>
        <ActionMenu
          items={[
            { icon: <FileText className="size-4" />, label: "Exportar PDF", onSelect: () => void runExport("pdf") },
            { icon: <FileSpreadsheet className="size-4" />, label: "Exportar Excel", onSelect: () => void runExport("xlsx") },
            { icon: <Table className="size-4" />, label: "Exportar CSV", onSelect: () => void runExport("csv") },
          ]}
          label="Exportar"
          trigger={<Button disabled={busy !== null && busy !== "share"} size="sm">{busy && busy !== "share" ? "Generando…" : "Exportar"}<ChevronDown className="size-4" /></Button>}
        />
      </div>
    </div>

    <header className="border-b border-border pb-8">
      <p className="text-xs font-semibold uppercase tracking-[0.16em] text-primary">Nexo</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">Estado de {personName}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{statementDoc.blocks[0] ? `Periodo ${statementDoc.blocks[0].periodLabel}` : "Sin periodo activo"} · Generado el {formatFinancialDate(statementDoc.asOfDate)}</p>
    </header>

    {statementDoc.blocks.length === 0 ? <EmptyState description="No tiene compras ni pagos pendientes por el momento. Su historial sigue disponible." title="Sin pagos pendientes" /> : statementDoc.blocks.map((block) => <StatementBlockView block={block} installments={installments.data?.filter((item) => item.currency === block.currency) ?? []} key={block.currency} />)}

    <p className="border-t border-border pt-6 text-xs text-muted-foreground print:mt-16">Este documento solo incluye la relación financiera entre Nexo y {personName}: no incluye saldos de cuentas, límites de tarjeta ni gastos de otras personas.</p>
  </div></PageTransition>;
}

function StatementBlockView({ block, installments }: { block: StatementBlock; installments: PersonInstallmentSummary[] }) {
  const hasOverdue = BigInt(block.overdueMinor) > 0n;
  const hasCredit = BigInt(block.creditBalanceMinor) > 0n;
  return <section className="space-y-8 break-inside-avoid">
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{block.currency}</p>
      <div className="mt-4 grid gap-6 sm:grid-cols-2">
        <div><p className="text-xs uppercase tracking-wide text-muted-foreground">A pagar este periodo</p><MoneyValue amount={block.toPayThisPeriodMinor} className="mt-1" currency={block.currency} size="xl" /></div>
        {block.paymentDueDate ? <div><p className="text-xs uppercase tracking-wide text-muted-foreground">Fecha límite</p><p className="mt-1 text-2xl font-semibold">{formatFinancialDate(block.paymentDueDate)}</p></div> : null}
      </div>
      <div className="mt-6 grid grid-cols-2 gap-5 border-t border-border/70 pt-5 sm:grid-cols-4">
        <Metric label="Te debe en total" value={<MoneyValue amount={block.totalOwedMinor} currency={block.currency} size="sm" />} />
        <Metric label="Pagado este periodo" value={<MoneyValue amount={block.paidThisPeriodMinor} currency={block.currency} size="sm" />} />
        <Metric label="Falta" value={<MoneyValue amount={block.missingMinor} currency={block.currency} size="sm" />} />
        {hasOverdue ? <Metric label={block.overdueSince ? `Vencido desde ${formatFinancialDate(block.overdueSince)}` : "Vencido"} value={<MoneyValue amount={block.overdueMinor} className="text-danger" currency={block.currency} size="sm" />} /> : null}
      </div>
      {hasCredit ? <div className="mt-5 rounded-2xl border border-primary/20 bg-primary-soft px-5 py-4"><p className="text-xs font-semibold text-primary-strong">Saldo a favor</p><MoneyValue amount={block.creditBalanceMinor} className="mt-1 text-primary-strong" currency={block.currency} size="lg" /></div> : null}
    </div>

    {block.concepts.length ? <div><h2 className="text-sm font-semibold text-muted-foreground">Este periodo</h2>
      <div className="mt-3 divide-y divide-border border-y border-border">
        {block.concepts.map((concept) => <div className="flex items-center justify-between gap-4 py-3" key={concept.id}>
          <div><p className="text-sm font-medium">{concept.description}</p><p className="mt-0.5 text-xs text-muted-foreground">{concept.typeLabel}</p></div>
          <div className="text-right"><MoneyValue amount={concept.amountMinor} currency={block.currency} size="sm" />{concept.purchaseAmountMinor !== concept.amountMinor ? <p className="mt-0.5 text-xs text-muted-foreground">de <MoneyValue amount={concept.purchaseAmountMinor} currency={block.currency} privacy size="sm" /></p> : null}</div>
        </div>)}
        <div className="flex items-center justify-between gap-4 py-3"><p className="text-sm font-semibold">Total del periodo</p><MoneyValue amount={block.toPayThisPeriodMinor} currency={block.currency} size="sm" /></div>
      </div>
    </div> : null}

    {installments.length ? <div><h2 className="text-sm font-semibold text-muted-foreground">MSI activos</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">{installments.map((plan) => <div className="rounded-2xl border border-border p-4" key={plan.plan_id}>
        <p className="truncate text-sm font-semibold">{plan.description}</p>
        {plan.current_installment_number ? <p className="mt-1 text-xs text-muted-foreground">Mensualidad {plan.current_installment_number} de {plan.installment_count} · <MoneyValue amount={plan.current_period_minor ?? "0"} currency={plan.currency} size="sm" /></p> : <p className="mt-1 text-xs text-success">Plan cubierto</p>}
        <p className="mt-2 text-xs text-muted-foreground">Restante total <MoneyValue amount={plan.outstanding_minor} currency={plan.currency} size="sm" /></p>
      </div>)}</div>
    </div> : null}

    {block.payments.length ? <div><h2 className="text-sm font-semibold text-muted-foreground">Pagos recibidos</h2>
      <div className="mt-3 divide-y divide-border border-y border-border">{block.payments.map((payment) => <div className="py-3" key={payment.event_id}>
        <div className="flex items-center justify-between gap-4"><div><p className="text-sm font-medium">Pago recibido</p><p className="mt-0.5 text-xs text-muted-foreground">{formatFinancialDate(payment.occurred_on)}{payment.account_name ? ` · ${payment.account_name}` : ""}</p></div><MoneyValue amount={payment.amount_minor} currency={block.currency} size="sm" /></div>
        {BigInt(payment.applied_to_future_minor) > 0n || BigInt(payment.credit_generated_minor) > 0n ? <div className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-xs text-muted-foreground">
          <span>Aplicado a este periodo <MoneyValue amount={payment.applied_to_period_minor} currency={block.currency} size="sm" /></span>
          {BigInt(payment.applied_to_future_minor) > 0n ? <span>Aplicado a próximos pagos <MoneyValue amount={payment.applied_to_future_minor} currency={block.currency} size="sm" /></span> : null}
          {BigInt(payment.credit_generated_minor) > 0n ? <span className="font-medium text-primary-strong">Generó saldo a favor <MoneyValue amount={payment.credit_generated_minor} currency={block.currency} size="sm" /></span> : null}
        </div> : null}
      </div>)}</div>
    </div> : null}
  </section>;
}

function Metric({ label, value }: { label: string; value: React.ReactNode }) { return <div><p className="text-xs text-muted-foreground">{label}</p><div className="mt-1 text-sm font-semibold">{value}</div></div>; }
