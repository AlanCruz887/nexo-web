import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight, CreditCard, Landmark, Plus } from "lucide-react";

import { Button } from "@/components/ui/button";

export type QuickAction = "expense" | "income" | "transfer" | "card_purchase" | "account";

const actions = [
  { id: "expense", label: "Gasto desde cuenta", hint: "Registrar una salida bancaria", icon: ArrowUpRight },
  { id: "income", label: "Ingreso", hint: "Registrar una entrada", icon: ArrowDownLeft },
  { id: "transfer", label: "Transferencia", hint: "Mover entre cuentas", icon: ArrowLeftRight },
  { id: "card_purchase", label: "Compra con tarjeta", hint: "Usar una línea de crédito", icon: CreditCard },
  { id: "account", label: "Nueva cuenta", hint: "Agregar dinero disponible", icon: Landmark },
] as const;

export function QuickAddMenu({ onSelect, compact = false, includeAccount = true }: { compact?: boolean; includeAccount?: boolean; onSelect: (action: QuickAction) => void }) {
  const visible = includeAccount ? actions : actions.filter((action) => action.id !== "account");
  return <DropdownMenu.Root><DropdownMenu.Trigger asChild><Button aria-label="Crear nuevo" className={compact ? "rounded-full shadow-[0_8px_24px_-12px_color-mix(in_oklab,var(--primary)_60%,transparent)]" : undefined} size={compact ? "icon" : "sm"}><Plus className="size-4" />{compact ? null : "Nuevo"}</Button></DropdownMenu.Trigger><DropdownMenu.Portal><DropdownMenu.Content align="end" className="z-50 w-64 rounded-2xl border border-border/80 bg-surface-elevated p-2 shadow-float" sideOffset={8}>{visible.map(({ hint, icon: Icon, id, label }) => <DropdownMenu.Item key={id} className="flex cursor-default items-center gap-3 rounded-xl px-3 py-2.5 outline-none transition-colors focus:bg-primary-soft" onSelect={() => onSelect(id)}><span className="grid size-9 place-items-center rounded-xl bg-surface-secondary text-primary"><Icon className="size-4" /></span><span><span className="block text-sm font-semibold">{label}</span><span className="block text-xs text-muted-foreground">{hint}</span></span></DropdownMenu.Item>)}</DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root>;
}
