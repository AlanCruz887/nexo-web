import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight, CreditCard, Landmark, LogOut, Search } from "lucide-react";
import { useEffect, useState } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { QuickAddMenu, type QuickAction } from "@/components/quick-add-menu";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { AccountFormSheet } from "@/features/accounts/account-form-sheet";
import { CardPurchaseForm } from "@/features/cards/card-purchase-form";
import { MovementFormSheet } from "@/features/movements/movement-form-sheet";
import { TransferFormSheet } from "@/features/movements/transfer-form-sheet";
import { useAccounts } from "@/hooks/use-accounts";
import { useCards } from "@/hooks/use-cards";
import { useProfile } from "@/hooks/use-profile";
import { cn } from "@/lib/cn";
import { reportError } from "@/lib/errors";
import { primaryNavigation, Sidebar } from "@/layouts/sidebar";
import { Topbar } from "@/layouts/topbar";

export function AppShell() {
  const { signOut, user } = useAuth();
  const navigate = useNavigate();
  const accounts = useAccounts();
  const cards = useCards();
  const profile = useProfile(user?.id);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [commandOpen, setCommandOpen] = useState(false);
  const [activeAction, setActiveAction] = useState<QuickAction>();

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); setCommandOpen(true); }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function openAction(action: QuickAction) { setCommandOpen(false); setActiveAction(action); }
  async function handleSignOut() { try { await signOut(); } catch (error) { reportError("sign-out", error); } }
  const identity = user?.email ?? "Tu perfil";

  return <div className="min-h-screen lg:grid lg:grid-cols-[232px_1fr]">
    <Sidebar />
    <div className="min-w-0 lg:col-start-2">
      <Topbar identity={identity} onMenu={() => setMobileMenuOpen((value) => !value)} onQuickAction={openAction} onSearch={() => setCommandOpen(true)} />
      {mobileMenuOpen ? <nav aria-label="Menú móvil" className="border-b border-border bg-surface px-4 py-3 shadow-card lg:hidden">{primaryNavigation.map(({ href, icon: Icon, label }) => <NavLink key={href} className={({ isActive }) => cn("flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm font-medium text-muted-foreground", isActive && "bg-primary-soft text-primary-strong")} onClick={() => setMobileMenuOpen(false)} to={href}><Icon className="size-5" />{label}</NavLink>)}<button className="mt-2 flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-sm font-medium text-muted-foreground" onClick={() => void handleSignOut()} type="button"><LogOut className="size-5" />Cerrar sesión</button></nav> : null}
      <main className="mx-auto w-full max-w-[1180px] px-4 py-8 pb-28 sm:px-6 lg:px-8 lg:py-12 lg:pb-12"><Outlet /></main>
    </div>

    <nav aria-label="Navegación inferior" className="fixed inset-x-0 bottom-0 z-30 grid grid-cols-5 items-end border-t border-border/70 bg-surface/95 px-1 pb-[max(.4rem,env(safe-area-inset-bottom))] pt-1.5 backdrop-blur-xl lg:hidden print:hidden">
      <MobileNav item={primaryNavigation[0]} /><MobileNav item={primaryNavigation[1]} /><div className="flex min-h-12 items-center justify-center"><QuickAddMenu compact onSelect={openAction} /></div><MobileNav item={primaryNavigation[2]} /><MobileNav item={primaryNavigation[3]} />
    </nav>

    <CommandMenu onNavigate={(href) => { setCommandOpen(false); navigate(href); }} onOpenChange={setCommandOpen} onQuickAction={openAction} open={commandOpen} />
    <MovementFormSheet accounts={accounts.data ?? []} defaultKind={activeAction === "income" ? "income" : "expense"} onOpenChange={(open) => { if (!open) setActiveAction(undefined); }} open={activeAction === "expense" || activeAction === "income"} />
    <TransferFormSheet accounts={accounts.data ?? []} onOpenChange={(open) => { if (!open) setActiveAction(undefined); }} open={activeAction === "transfer"} />
    <AccountFormSheet baseCurrency={profile.data?.base_currency ?? "MXN"} onOpenChange={(open) => { if (!open) setActiveAction(undefined); }} open={activeAction === "account"} />
    <CardPurchaseForm cards={cards.data ?? []} onOpenChange={(open) => { if (!open) setActiveAction(undefined); }} open={activeAction === "card_purchase"} />
  </div>;
}

function MobileNav({ item: { href, icon: Icon, label } }: { item: (typeof primaryNavigation)[number] }) {
  return <NavLink className={({ isActive }) => cn("flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-[10px] font-medium text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30", isActive && "text-primary-strong")} to={href}><Icon className="size-5" />{label}</NavLink>;
}

function CommandMenu({ onNavigate, onOpenChange, onQuickAction, open }: { onNavigate: (href: string) => void; onOpenChange: (open: boolean) => void; onQuickAction: (action: QuickAction) => void; open: boolean }) {
  const [query, setQuery] = useState("");
  const actions = [{ id: "expense" as const, label: "Gasto desde cuenta", icon: ArrowUpRight }, { id: "income" as const, label: "Ingreso", icon: ArrowDownLeft }, { id: "transfer" as const, label: "Transferencia", icon: ArrowLeftRight }, { id: "card_purchase" as const, label: "Compra con tarjeta", icon: CreditCard }, { id: "account" as const, label: "Nueva cuenta", icon: Landmark }];
  const normalized = query.trim().toLocaleLowerCase("es");
  const visibleActions = actions.filter(({ label }) => label.toLocaleLowerCase("es").includes(normalized));
  const visibleNavigation = primaryNavigation.filter(({ label }) => label.toLocaleLowerCase("es").includes(normalized));
  return <ResponsiveDialog description="Navega o inicia una acción." onOpenChange={(next) => { if (!next) setQuery(""); onOpenChange(next); }} open={open} size="small" title="Buscar en Nexo"><div className="relative mb-5"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><input autoFocus className="h-11 w-full rounded-xl border border-border bg-surface-secondary pl-9 pr-3 text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/15" onChange={(event) => setQuery(event.target.value)} placeholder="Buscar páginas y acciones" value={query} /></div>{visibleActions.length ? <><p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">Acciones</p><div className="space-y-1">{visibleActions.map(({ icon: Icon, id, label }) => <button key={id} className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-sm font-medium hover:bg-primary-soft focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" onClick={() => onQuickAction(id)} type="button"><Icon className="size-4 text-primary" />{label}</button>)}</div></> : null}{visibleNavigation.length ? <><p className="mb-2 mt-5 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">Ir a</p><div className="space-y-1">{visibleNavigation.map(({ href, icon: Icon, label }) => <button key={href} className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-sm font-medium hover:bg-surface-secondary" onClick={() => onNavigate(href)} type="button"><Icon className="size-4 text-muted-foreground" />{label}</button>)}</div></> : null}{visibleActions.length === 0 && visibleNavigation.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">No encontramos resultados.</p> : null}</ResponsiveDialog>;
}
