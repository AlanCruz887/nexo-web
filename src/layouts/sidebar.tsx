import { Home, Landmark, ReceiptText, Settings } from "lucide-react";
import { motion } from "framer-motion";
import { NavLink } from "react-router-dom";

import { cn } from "@/lib/cn";
import { prefetchRoute } from "@/routes/prefetch";

export const primaryNavigation = [
  { href: "/inicio", label: "Inicio", icon: Home },
  { href: "/movimientos", label: "Movimientos", icon: ReceiptText },
  { href: "/cuentas", label: "Cuentas", icon: Landmark },
  { href: "/configuracion", label: "Configuración", icon: Settings },
] as const;

export function BrandMark({ compact = false }: { compact?: boolean }) {
  return <div className="flex items-center gap-3"><span className="relative grid size-9 place-items-center overflow-hidden rounded-xl bg-primary text-sm font-bold text-primary-foreground shadow-sm"><span className="absolute -right-2 -top-2 size-6 rounded-full bg-white/20" />N</span>{compact ? null : <span className="text-lg font-semibold tracking-[-0.04em]">Nexo</span>}</div>;
}

export function Sidebar() {
  return <aside className="fixed inset-y-0 left-0 z-30 hidden w-[232px] border-r border-border/70 bg-surface px-4 py-5 lg:flex lg:flex-col">
    <div className="px-2"><BrandMark /></div>
    <nav aria-label="Navegación principal" className="mt-9 space-y-6">
      <NavGroup label="General" items={primaryNavigation.slice(0, 2)} />
      <NavGroup label="Dinero" items={primaryNavigation.slice(2, 3)} />
    </nav>
    <div className="mt-auto"><NavGroup label="Más" items={primaryNavigation.slice(3)} /></div>
  </aside>;
}

function NavGroup({ items, label }: { items: readonly (typeof primaryNavigation)[number][]; label: string }) {
  return <div><p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground/75">{label}</p><div className="space-y-1">{items.map(({ href, icon: Icon, label: itemLabel }) => <NavLink key={href} className={({ isActive }) => cn("relative flex min-h-10 items-center gap-3 rounded-xl px-3 text-sm font-medium text-muted-foreground transition duration-fast ease-nexo hover:bg-surface-secondary hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 active:scale-[.985]", isActive && "bg-primary-soft text-primary-strong")} onFocus={() => prefetchRoute(href)} onPointerEnter={() => prefetchRoute(href)} to={href}>{({ isActive }) => <>{isActive ? <motion.span className="absolute inset-y-2.5 left-0 w-0.5 rounded-full bg-primary" layoutId="desktop-nav-indicator" transition={{ type: "spring", stiffness: 420, damping: 34 }} /> : null}<Icon aria-hidden="true" className={cn("size-[18px] transition-transform duration-fast", isActive && "scale-105")} />{itemLabel}</>}</NavLink>)}</div></div>;
}
