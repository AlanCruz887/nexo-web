import { ArrowLeft, CreditCard, Landmark, Pencil, Plus, WalletCards } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { EmptyState, ErrorState, LoadingState } from "@/components/feedback";
import { MoneyValue } from "@/components/money-value";
import { PageTransition } from "@/components/page-transition";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { CardPurchaseForm } from "@/features/cards/card-purchase-form";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { ContactForm } from "@/features/people/contact-form";
import { PersonPaymentForm } from "@/features/people/person-payment-form";
import { useAccounts } from "@/hooks/use-accounts";
import { useCards } from "@/hooks/use-cards";
import { useContact, useContactActivity, useContactReceivables, useSetContactActive } from "@/hooks/use-contacts";
import { formatFinancialDate } from "@/lib/dates";
import { toUserMessage } from "@/lib/errors";

export function PersonDetailPage() {
  const { id } = useParams(); const contact = useContact(id); const receivables = useContactReceivables(id); const activity = useContactActivity(id); const accounts = useAccounts(); const cards = useCards(); const setActive = useSetContactActive();
  const [editOpen, setEditOpen] = useState(false); const [paymentOpen, setPaymentOpen] = useState(false); const [purchaseChoice, setPurchaseChoice] = useState(false); const [accountPurchase, setAccountPurchase] = useState(false); const [cardPurchase, setCardPurchase] = useState(false);
  if (contact.isLoading || receivables.isLoading || activity.isLoading) return <LoadingState label="Cargando persona" />;
  if (contact.isError || receivables.isError || activity.isError) return <ErrorState message={toUserMessage(contact.error ?? receivables.error ?? activity.error)} onRetry={() => void contact.refetch()} />;
  const person = contact.data; if (!person) return <EmptyState description="La persona no existe o no tienes acceso." title="No encontramos esta persona" />;
  const personId = person.id; const personIsActive = person.is_active;
  async function toggleActive() { if (personIsActive && !window.confirm("¿Archivar a esta persona? Su historial y saldos se conservarán.")) return; await setActive.mutateAsync({ id: personId, active: !personIsActive }); }
  return <PageTransition><div className="space-y-10">
    <Link className="inline-flex min-h-11 items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground" to="/personas"><ArrowLeft className="size-4" />Personas</Link>
    <header className="border-b border-border pb-8"><div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-xs font-semibold uppercase tracking-[0.16em] text-primary">Cuenta por cobrar</p><h1 className="mt-2 text-4xl font-semibold tracking-tight">{person.name}</h1><p className="mt-2 text-sm text-muted-foreground">{person.email ?? person.phone ?? "Sin datos de contacto"}</p></div><div className="flex flex-wrap gap-2"><Button disabled={!person.is_active} onClick={() => setPurchaseChoice(true)}><Plus className="size-4" />Nueva compra</Button><Button disabled={!person.balances.length} onClick={() => setPaymentOpen(true)} variant="secondary"><WalletCards className="size-4" />Registrar pago</Button><Button onClick={() => setEditOpen(true)} size="icon" variant="ghost"><Pencil className="size-4" /><span className="sr-only">Editar</span></Button></div></div>
      <div className="mt-8 flex flex-wrap gap-8">{person.balances.length ? person.balances.map((balance) => <div key={balance.currency}><p className="text-xs uppercase tracking-wide text-muted-foreground">Te debe · {balance.currency}</p><MoneyValue amount={balance.outstanding_minor} currency={balance.currency} size="xl" /></div>) : <div><p className="text-xs uppercase tracking-wide text-muted-foreground">Saldo</p><p className="mt-2 text-2xl font-semibold text-success">Sin saldo pendiente</p></div>}</div>
    </header>
    <section><h2 className="text-lg font-semibold">Compras y saldos</h2><div className="mt-4 divide-y divide-border border-y border-border">{receivables.data?.length ? receivables.data.map((item) => <div className="flex items-center justify-between gap-4 py-4" key={item.id}><div><p className="font-medium">{item.description}</p><p className="mt-1 text-xs text-muted-foreground">{formatFinancialDate(item.occurred_on)} · {item.status === "paid" ? "Pagado" : "Pendiente"}</p></div><div className="text-right"><MoneyValue amount={item.outstanding_minor} currency={item.currency} /><p className="text-xs text-muted-foreground">de <MoneyValue amount={item.original_amount_minor} currency={item.currency} privacy /></p></div></div>) : <p className="py-8 text-sm text-muted-foreground">Aún no hay compras asignadas.</p>}</div></section>
    <section><h2 className="text-lg font-semibold">Actividad</h2><div className="mt-4 divide-y divide-border border-y border-border">{activity.data?.length ? activity.data.map((item) => <div className="flex items-center justify-between gap-4 py-4" key={item.event_id}><div><p className="font-medium">{item.description}</p><p className="text-xs text-muted-foreground">{formatFinancialDate(item.occurred_on)} · {item.activity_type === "payment" ? "Pago recibido" : "Compra"}</p></div><MoneyValue amount={item.amount_minor} currency={item.currency} sign="always" /></div>) : <p className="py-8 text-sm text-muted-foreground">Sin actividad.</p>}</div></section>
    <div className="flex justify-end"><Button disabled={setActive.isPending} onClick={() => void toggleActive()} variant="ghost">{person.is_active ? "Archivar persona" : "Restaurar persona"}</Button></div>
  </div>
  <ContactForm contact={person} onOpenChange={setEditOpen} open={editOpen} />
  <PersonPaymentForm accounts={accounts.data ?? []} contact={person} onOpenChange={setPaymentOpen} open={paymentOpen} />
  <ResponsiveDialog description="La fuente financiera seguirá siendo la cuenta o tarjeta que elijas." onOpenChange={setPurchaseChoice} open={purchaseChoice} size="small" title="Nueva compra"><div className="grid gap-3"><Button className="min-h-14" onClick={() => { setPurchaseChoice(false); setAccountPurchase(true); }} variant="secondary"><Landmark className="size-5" />Gasto desde cuenta</Button><Button className="min-h-14" onClick={() => { setPurchaseChoice(false); setCardPurchase(true); }} variant="secondary"><CreditCard className="size-5" />Compra con tarjeta</Button></div></ResponsiveDialog>
  <MovementFormSheet accounts={accounts.data ?? []} defaultContactId={person.id} onOpenChange={setAccountPurchase} open={accountPurchase} />
  <CardPurchaseForm cards={cards.data ?? []} defaultContactId={person.id} onOpenChange={setCardPurchase} open={cardPurchase} />
  </PageTransition>;
}
