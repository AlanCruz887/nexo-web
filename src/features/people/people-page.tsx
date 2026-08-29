import { Plus, Users } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { EmptyState, ErrorState } from "@/components/feedback";
import { FilterBar, FilterPill } from "@/components/filter-bar";
import { MoneyValue } from "@/components/money-value";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { Button } from "@/components/ui/button";
import { PeopleSkeleton } from "@/components/skeletons";
import { ContactForm } from "@/features/people/contact-form";
import { useContacts } from "@/hooks/use-contacts";
import { toUserMessage } from "@/lib/errors";

export function PeoplePage() {
  const contacts = useContacts(); const [formOpen, setFormOpen] = useState(false); const [view, setView] = useState<"active" | "archived">("active");
  if (contacts.isLoading) return <PeopleSkeleton />;
  if (contacts.isError) return <ErrorState message={toUserMessage(contacts.error)} onRetry={() => void contacts.refetch()} />;
  const visible = contacts.data?.filter((item) => item.is_active === (view === "active")) ?? [];
  return <PageTransition><div className="space-y-10">
    <PageHeader actions={<Button onClick={() => setFormOpen(true)}><Plus className="size-4" />Nueva persona</Button>} eyebrow="Dinero compartido" subtitle="Consulta cuánto te deben y registra pagos sin confundirlos con ingresos." title="Personas" />
    {(contacts.data?.length ?? 0) === 0 ? <EmptyState action={<Button onClick={() => setFormOpen(true)}>Agregar persona</Button>} description="Agrega a alguien cuando pagues una compra por esa persona." title="Todavía no tienes personas" /> : <section className="space-y-4">
      <FilterBar><FilterPill active={view === "active"} onClick={() => setView("active")}>Activas</FilterPill><FilterPill active={view === "archived"} onClick={() => setView("archived")}>Archivadas</FilterPill></FilterBar>
      {visible.length ? <div className="grid gap-3 md:grid-cols-2">{visible.map((contact) => <Link className="group rounded-2xl border border-border bg-surface p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" key={contact.id} to={`/personas/${contact.id}`}><div className="flex items-start gap-4"><span className="grid size-11 shrink-0 place-items-center rounded-full bg-primary-soft text-primary-strong"><Users className="size-5" /></span><div className="min-w-0 flex-1"><h2 className="truncate font-semibold">{contact.name}</h2><p className="mt-1 text-xs text-muted-foreground">{contact.last_activity_description ?? "Sin actividad"}</p><div className="mt-4 flex flex-wrap gap-x-5 gap-y-1">{contact.balances.length ? contact.balances.map((balance) => <div key={balance.currency}><p className="text-[10px] uppercase tracking-wide text-muted-foreground">Te debe · {balance.currency}</p><MoneyValue amount={balance.outstanding_minor} currency={balance.currency} /></div>) : <p className="text-sm font-medium text-success">Sin saldo pendiente</p>}</div></div></div></Link>)}</div> : <EmptyState description={view === "archived" ? "Las personas archivadas aparecerán aquí." : "No hay personas activas."} title="Sin resultados" />}
    </section>}
  </div><ContactForm onOpenChange={setFormOpen} open={formOpen} /></PageTransition>;
}
