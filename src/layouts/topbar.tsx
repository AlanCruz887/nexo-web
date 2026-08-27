import { Bell, Eye, EyeOff, Menu, Search } from "lucide-react";

import { usePreferences } from "@/app/preferences-provider";
import type { QuickAction } from "@/components/quick-add-menu";
import { QuickAddMenu } from "@/components/quick-add-menu";
import { Button } from "@/components/ui/button";

export function Topbar({ identity, onMenu, onQuickAction, onSearch }: { identity: string; onMenu: () => void; onQuickAction: (action: QuickAction) => void; onSearch: () => void }) {
  const { hideMoney, setHideMoney } = usePreferences();
  return <header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-border/70 bg-surface/90 px-4 backdrop-blur-xl sm:px-6 lg:px-8">
    <div className="flex items-center gap-3"><Button aria-label="Abrir menú" className="lg:hidden" onClick={onMenu} size="icon" variant="ghost"><Menu className="size-5" /></Button><span className="font-semibold tracking-tight lg:hidden">Nexo</span><button className="hidden h-10 w-[min(34vw,380px)] items-center gap-2 rounded-xl bg-surface-secondary px-3 text-left text-sm text-muted-foreground transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 lg:flex" onClick={onSearch} type="button"><Search className="size-4" />Buscar en Nexo<span className="ml-auto rounded-md border border-border bg-surface px-1.5 py-0.5 text-[10px] font-medium">⌘ K</span></button></div>
    <div className="flex items-center gap-1"><div className="hidden sm:block"><QuickAddMenu onSelect={onQuickAction} /></div><Button aria-label={hideMoney ? "Mostrar cantidades" : "Ocultar cantidades"} onClick={() => setHideMoney(!hideMoney)} size="icon" variant="ghost">{hideMoney ? <EyeOff className="size-5" /> : <Eye className="size-5" />}</Button><Button aria-label="Notificaciones" size="icon" variant="ghost"><Bell className="size-5" /></Button><span className="ml-1 grid size-8 place-items-center rounded-full bg-primary-soft text-xs font-bold text-primary-strong">{identity.slice(0, 1).toUpperCase()}</span></div>
  </header>;
}
