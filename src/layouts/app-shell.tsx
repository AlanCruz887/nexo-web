import { Eye, EyeOff, Home, LogOut, Menu, Settings, WalletCards } from "lucide-react";
import { useState } from "react";
import { NavLink, Outlet } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { usePreferences } from "@/app/preferences-provider";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";
import { reportError } from "@/lib/errors";

const navigation = [
  { href: "/inicio", label: "Inicio", icon: Home },
  { href: "/configuracion", label: "Configuración", icon: Settings },
];

export function AppShell() {
  const { signOut } = useAuth();
  const { hideMoney, setHideMoney } = usePreferences();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  async function handleSignOut() {
    try {
      await signOut();
    } catch (error) {
      reportError("sign-out", error);
    }
  }

  return (
    <div className="min-h-screen lg:grid lg:grid-cols-[248px_1fr]">
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-[248px] border-r border-border bg-surface/90 p-4 backdrop-blur-xl lg:flex lg:flex-col">
        <div className="flex items-center gap-2 px-2 py-3">
          <span className="grid size-9 place-items-center rounded-xl bg-primary font-bold text-primary-foreground">N</span>
          <span className="text-lg font-semibold tracking-tight">Nexo</span>
        </div>
        <nav aria-label="Navegación principal" className="mt-6 space-y-1">
          {navigation.map(({ href, icon: Icon, label }) => (
            <NavLink
              key={href}
              className={({ isActive }) =>
                cn(
                  "flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm font-medium text-muted-foreground transition duration-normal ease-nexo hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                  isActive && "bg-primary/10 text-primary",
                )
              }
              to={href}
            >
              <Icon aria-hidden="true" className="size-5" />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto rounded-2xl bg-muted p-4">
          <div className="flex items-center gap-2 text-sm font-medium">
            <WalletCards aria-hidden="true" className="size-4 text-primary" />
            Fundamento activo
          </div>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">Las funciones financieras llegarán por fases.</p>
        </div>
      </aside>

      <div className="min-w-0 lg:col-start-2">
        <header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-border bg-background/85 px-4 backdrop-blur-xl sm:px-6 lg:px-8">
          <div className="flex items-center gap-3">
            <Button
              aria-expanded={mobileMenuOpen}
              aria-label="Abrir menú"
              className="lg:hidden"
              onClick={() => setMobileMenuOpen((open) => !open)}
              size="icon"
              variant="ghost"
            >
              <Menu aria-hidden="true" className="size-5" />
            </Button>
            <span className="font-semibold tracking-tight lg:hidden">Nexo</span>
          </div>
          <div className="flex items-center gap-1">
            <Button
              aria-label={hideMoney ? "Mostrar cantidades" : "Ocultar cantidades"}
              onClick={() => setHideMoney(!hideMoney)}
              size="icon"
              variant="ghost"
            >
              {hideMoney ? <EyeOff aria-hidden="true" className="size-5" /> : <Eye aria-hidden="true" className="size-5" />}
            </Button>
            <Button aria-label="Cerrar sesión" onClick={() => void handleSignOut()} size="icon" variant="ghost">
              <LogOut aria-hidden="true" className="size-5" />
            </Button>
          </div>
        </header>

        {mobileMenuOpen ? (
          <nav aria-label="Menú móvil" className="border-b border-border bg-surface p-3 lg:hidden">
            {navigation.map(({ href, label }) => (
              <NavLink
                key={href}
                className="block min-h-11 rounded-xl px-3 py-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                onClick={() => setMobileMenuOpen(false)}
                to={href}
              >
                {label}
              </NavLink>
            ))}
          </nav>
        ) : null}

        <main className="mx-auto w-full max-w-6xl px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:py-8 lg:pb-8">
          <Outlet />
        </main>
      </div>

      <nav aria-label="Navegación inferior" className="fixed inset-x-0 bottom-0 z-30 grid grid-cols-2 border-t border-border bg-surface/95 px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 backdrop-blur-xl lg:hidden">
        {navigation.map(({ href, icon: Icon, label }) => (
          <NavLink
            key={href}
            className={({ isActive }) =>
              cn(
                "flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-xs font-medium text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                isActive && "text-primary",
              )
            }
            to={href}
          >
            <Icon aria-hidden="true" className="size-5" />
            {label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
