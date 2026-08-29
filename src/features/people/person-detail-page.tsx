import { ArrowLeft, CreditCard, FileText, Landmark, Pencil, PiggyBank, Plus, WalletCards } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageTransition } from "@/components/page-transition";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/toast";
import { CardPurchaseForm } from "@/features/cards/card-purchase-form";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { ContactForm } from "@/features/people/contact-form";
import { PersonPaymentForm } from "@/features/people/person-payment-form";
import { useAccounts } from "@/hooks/use-accounts";
import { useCards } from "@/hooks/use-cards";
import { useApplyPersonCredit, useContact, useContactActivity, useContactInstallments, useContactPeriod, useContactReceivables, useSetContactActive } from "@/hooks/use-contacts";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";
import { previewCreditApplication } from "@/lib/person-payment-preview";
import type { ContactActivity, CurrencyCode, PersonCollectionPeriod, PersonInstallmentSummary } from "@/types/database";

export function PersonDetailPage() {
  const { id } = useParams(); const contact = useContact(id); const receivables = useContactReceivables(id); const activity = useContactActivity(id); const period = useContactPeriod(id); const installments = useContactInstallments(id); const accounts = useAccounts(); const cards = useCards(); const setActive = useSetContactActive();
  const [editOpen, setEditOpen] = useState(false); const [paymentOpen, setPaymentOpen] = useState(false); const [purchaseChoice, setPurchaseChoice] = useState(false); const [accountPurchase, setAccountPurchase] = useState(false); const [cardPurchase, setCardPurchase] = useState(false);
  // contact/receivables/activity are the base data this page can't render
  // without. period/installments are a secondary projection (a pagar este
  // periodo, MSI, saldo a favor): if that fails to load, the rest of the
  // page still renders using the base data below.
  if (contact.isLoading || receivables.isLoading || activity.isLoading) return <LoadingState label="Cargando persona" />;
  if (contact.isError || receivables.isError || activity.isError) return <ErrorState message={toUserMessage(contact.error ?? receivables.error ?? activity.error)} onRetry={() => void contact.refetch()} />;
  const person = contact.data; if (!person) return <EmptyState description="La persona no existe o no tienes acceso." title="No encontramos esta persona" />;
  const personId = person.id; const personIsActive = person.is_active;
  const periods = period.data?.periods ?? [];
  async function toggleActive() { if (personIsActive && !window.confirm("¿Archivar a esta persona? Su historial y saldos se conservarán.")) return; await setActive.mutateAsync({ id: personId, active: !personIsActive }); }
  return <PageTransition><div className="space-y-10">
    <Link className="inline-flex min-h-11 items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground" to="/personas"><ArrowLeft className="size-4" />Personas</Link>
    <header className="border-b border-border pb-8"><div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-xs font-semibold uppercase tracking-[0.16em] text-primary">Dinero compartido</p><h1 className="mt-2 text-4xl font-semibold tracking-tight">{person.name}</h1><p className="mt-2 text-sm text-muted-foreground">{person.email ?? person.phone ?? "Sin datos de contacto"}</p></div><div className="flex flex-wrap gap-2"><Button disabled={!person.is_active} onClick={() => setPurchaseChoice(true)}><Plus className="size-4" />Nueva compra</Button><Button disabled={!person.balances.length} onClick={() => setPaymentOpen(true)} variant="secondary"><WalletCards className="size-4" />Registrar pago</Button><Button asChild variant="secondary"><Link to={`/personas/${person.id}/estado`}><FileText className="size-4" />Ver estado</Link></Button><Button onClick={() => setEditOpen(true)} size="icon" variant="ghost"><Pencil className="size-4" /><span className="sr-only">Editar</span></Button></div></div></header>

    {period.isLoading ? <LoadingState label="Cargando el periodo" /> : period.isError ? <div className="rounded-2xl border border-border bg-surface-secondary p-5"><p className="text-sm font-medium">No pudimos cargar el periodo de cobro</p><p className="mt-1 text-sm text-muted-foreground">{toUserMessage(period.error)}</p><Button className="mt-3" onClick={() => void period.refetch()} size="sm" variant="secondary">Reintentar</Button></div> : periods.length ? periods.map((currencyPeriod) => <PersonPeriodSummary contactId={personId} installments={installments.data?.filter((item) => item.currency === currencyPeriod.currency) ?? []} key={currencyPeriod.currency} period={currencyPeriod} />) : <div><p className="text-xs uppercase tracking-wide text-muted-foreground">Saldo</p><p className="mt-2 text-2xl font-semibold text-success">Sin cobros pendientes</p></div>}

    <section><h2 className="text-lg font-semibold">Compras y saldos</h2><div className="mt-4 divide-y divide-border border-y border-border">{receivables.data?.length ? receivables.data.map((item) => <div className="flex items-center justify-between gap-4 py-4" key={item.id}><div><p className="font-medium">{item.description}</p><p className="mt-1 text-xs text-muted-foreground">{formatFinancialDate(item.occurred_on)} · {item.status === "paid" ? "Pagado" : "Pendiente"}</p></div><div className="text-right"><MoneyValue amount={item.outstanding_minor} currency={item.currency} /><p className="text-xs text-muted-foreground">de <MoneyValue amount={item.original_amount_minor} currency={item.currency} privacy /></p></div></div>) : <p className="py-8 text-sm text-muted-foreground">Aún no hay compras asignadas.</p>}</div></section>
    <section><h2 className="text-lg font-semibold">Actividad</h2><div className="mt-4 divide-y divide-border border-y border-border">{activity.data?.length ? activity.data.map((item) => <ActivityRow item={item} key={`${item.event_id}-${item.application_id ?? ""}`} personName={person.name} />) : <p className="py-8 text-sm text-muted-foreground">Sin actividad.</p>}</div></section>
    <div className="flex justify-end"><Button disabled={setActive.isPending} onClick={() => void toggleActive()} variant="ghost">{person.is_active ? "Archivar persona" : "Restaurar persona"}</Button></div>
  </div>
  <ContactForm contact={person} onOpenChange={setEditOpen} open={editOpen} />
  <PersonPaymentForm accounts={accounts.data ?? []} contact={person} onOpenChange={setPaymentOpen} open={paymentOpen} />
  <ResponsiveDialog description="La fuente financiera seguirá siendo la cuenta o tarjeta que elijas." onOpenChange={setPurchaseChoice} open={purchaseChoice} size="small" title="Nueva compra"><div className="grid gap-3"><Button className="min-h-14" onClick={() => { setPurchaseChoice(false); setAccountPurchase(true); }} variant="secondary"><Landmark className="size-5" />Gasto desde cuenta</Button><Button className="min-h-14" onClick={() => { setPurchaseChoice(false); setCardPurchase(true); }} variant="secondary"><CreditCard className="size-5" />Compra con tarjeta</Button></div></ResponsiveDialog>
  <MovementFormSheet accounts={accounts.data ?? []} defaultContactId={person.id} onOpenChange={setAccountPurchase} open={accountPurchase} />
  <CardPurchaseForm cards={cards.data ?? []} defaultContactId={person.id} onOpenChange={setCardPurchase} open={cardPurchase} />
  </PageTransition>;
}

function PersonPeriodSummary({ contactId, installments, period }: { contactId: string; installments: PersonInstallmentSummary[]; period: PersonCollectionPeriod }) {
  const creditMinor = BigInt(period.credit_balance_minor);
  const overdueMinor = BigInt(period.overdue_minor);
  return <section className="space-y-6">
    <div className="rounded-2xl border border-border bg-surface p-6 shadow-sm"><p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">A pagar este periodo · {period.currency}</p><MoneyValue amount={period.subtotal_minor} className="mt-2" currency={period.currency} size="xl" />
      <div className="mt-6 grid grid-cols-2 gap-5 sm:grid-cols-3"><Metric label="Falta" value={BigInt(period.remaining_minor) === 0n ? <span className="text-success">Periodo pagado</span> : <MoneyValue amount={period.remaining_minor} currency={period.currency} size="sm" />} />{period.payment_due_date ? <Metric label="Fecha límite" value={formatFinancialDate(period.payment_due_date)} /> : null}{overdueMinor > 0n ? <Metric label="Vencido" value={<MoneyValue amount={period.overdue_minor} className="text-danger" currency={period.currency} size="sm" />} /> : null}</div>
      <div className="mt-6 grid grid-cols-2 gap-5 border-t border-border/70 pt-5 sm:grid-cols-3"><Metric label="Te debe en total" value={<MoneyValue amount={period.total_outstanding_minor} currency={period.currency} size="sm" />} /><Metric label="Pagado este periodo" value={<MoneyValue amount={period.paid_minor} currency={period.currency} size="sm" />} /></div>
    </div>
    {period.concepts.length ? <div><h3 className="text-sm font-semibold text-muted-foreground">Este periodo</h3><div className="mt-3 divide-y divide-border border-y border-border">{period.concepts.map((concept) => <div className="flex items-center justify-between gap-4 py-3" key={concept.id}><div><p className="text-sm font-medium">{concept.description}{concept.installment_number && concept.installment_count ? ` · Mensualidad ${concept.installment_number} de ${concept.installment_count}` : ""}</p>{concept.outstanding_minor !== concept.amount_minor ? <p className="mt-0.5 text-xs text-muted-foreground">Falta <MoneyValue amount={concept.outstanding_minor} currency={period.currency} size="sm" /></p> : null}</div><MoneyValue amount={concept.amount_minor} currency={period.currency} size="sm" /></div>)}<div className="flex items-center justify-between gap-4 py-3"><p className="text-sm font-semibold">Total del periodo</p><MoneyValue amount={period.subtotal_minor} currency={period.currency} size="sm" /></div></div></div> : null}
    {installments.length ? <div><h3 className="text-sm font-semibold text-muted-foreground">Compras a meses</h3><div className="mt-3 grid gap-3 md:grid-cols-2">{installments.map((plan) => <InstallmentPlanForPerson key={plan.plan_id} plan={plan} />)}</div></div> : null}
    <CreditBalanceCard contactId={contactId} creditMinor={creditMinor} currency={period.currency} remainingMinor={BigInt(period.remaining_minor)} totalOutstandingMinor={BigInt(period.total_outstanding_minor)} />
  </section>;
}

function InstallmentPlanForPerson({ plan }: { plan: PersonInstallmentSummary }) {
  const paidCount = plan.current_installment_number ? plan.current_installment_number - 1 : plan.installment_count;
  return <div className="rounded-2xl border border-border p-5"><p className="truncate font-semibold">{plan.description}</p>
    <div className="mt-3"><p className="text-xs text-muted-foreground">Te debe</p><MoneyValue amount={plan.outstanding_minor} currency={plan.currency} size="lg" /></div>
    {plan.current_installment_number ? <div className="mt-4 space-y-3 border-t border-border/70 pt-4"><div><p className="text-xs text-muted-foreground">Este periodo</p><p className="mt-1 text-sm font-semibold">Mensualidad {plan.current_installment_number} de {plan.installment_count} · <MoneyValue amount={plan.current_period_minor ?? "0"} currency={plan.currency} size="sm" /></p></div>{plan.current_statement_date ? <Metric label="Próximo corte" value={formatFinancialDate(plan.current_statement_date, "dd MMM")} /> : null}<Metric label="Progreso" value={`${paidCount} de ${plan.installment_count} pagadas`} /></div> : <p className="mt-4 border-t border-border/70 pt-4 text-sm font-semibold text-success">Plan cubierto · {plan.installment_count} de {plan.installment_count} pagadas</p>}
  </div>;
}

function CreditBalanceCard({ contactId, creditMinor, currency, remainingMinor, totalOutstandingMinor }: { contactId: string; creditMinor: bigint; currency: CurrencyCode; remainingMinor: bigint; totalOutstandingMinor: bigint }) {
  const [confirmOpen, setConfirmOpen] = useState(false); const apply = useApplyPersonCredit(contactId); const toast = useToast();
  if (creditMinor <= 0n) return null;
  const preview = previewCreditApplication(creditMinor, totalOutstandingMinor);
  const remainingAfterMinor = remainingMinor > preview.appliedMinor ? remainingMinor - preview.appliedMinor : 0n;
  async function confirm() { try { await apply.mutateAsync({ currency, amountMinor: preview.appliedMinor.toString() }); toast.success("Saldo a favor aplicado"); setConfirmOpen(false); } catch (error) { toast.error(toUserMessage(error)); } }
  return <div className="rounded-2xl border border-primary/20 bg-primary-soft p-5"><div className="flex flex-wrap items-center justify-between gap-4"><div><p className="text-sm font-semibold text-primary-strong">Saldo a favor</p><p className="mt-1 max-w-md text-xs text-muted-foreground">Dinero que ya recibiste y todavía no se ha aplicado a una compra o mensualidad.</p><MoneyValue amount={creditMinor} className="mt-3 text-primary-strong" currency={currency} size="lg" /></div>{totalOutstandingMinor > 0n ? <Button onClick={() => setConfirmOpen(true)} variant="secondary"><PiggyBank className="size-4" />Aplicar saldo a favor</Button> : null}</div>
    <ResponsiveDialog description="No se crea ningún movimiento bancario nuevo: es dinero que ya recibiste." onOpenChange={setConfirmOpen} open={confirmOpen} size="small" title="Aplicar saldo a favor">
      <div className="space-y-4"><div className="grid grid-cols-3 gap-4 rounded-xl bg-surface-secondary p-4"><div><p className="text-xs text-muted-foreground">Saldo disponible</p><MoneyValue amount={creditMinor} currency={currency} size="sm" /></div><div><p className="text-xs text-muted-foreground">Se aplicará</p><MoneyValue amount={preview.appliedMinor} currency={currency} size="sm" /></div><div><p className="text-xs text-muted-foreground">A pagar después</p><MoneyValue amount={remainingAfterMinor} currency={currency} size="sm" /></div></div>
      <div className="flex justify-end gap-2"><Button onClick={() => setConfirmOpen(false)} variant="ghost">Cancelar</Button><Button disabled={apply.isPending} onClick={() => void confirm()}>{apply.isPending ? "Aplicando…" : "Aplicar"}</Button></div></div>
    </ResponsiveDialog>
  </div>;
}

function ActivityRow({ item, personName }: { item: ContactActivity; personName: string }) {
  const label = activityLabel(item, personName);
  return <div className="flex items-center justify-between gap-4 py-4"><div><p className="font-medium">{label}</p><p className="text-xs text-muted-foreground">{formatFinancialDate(item.occurred_on)} · {item.description}</p></div><MoneyValue amount={item.amount_minor} currency={item.currency} sign="always" /></div>;
}

function activityLabel(item: ContactActivity, personName: string) {
  if (item.activity_type === "payment") return "Pago recibido";
  if (item.activity_type === "credit_applied") return "Saldo a favor aplicado";
  if (item.installment_count) return "Compra a meses";
  if (item.personal_amount_minor === "0") return `Compra para ${personName}`;
  return "Compra compartida";
}

function Metric({ label, value }: { label: string; value: React.ReactNode }) { return <div><p className="text-xs text-muted-foreground">{label}</p><div className="mt-1 text-sm font-semibold">{value}</div></div>; }
