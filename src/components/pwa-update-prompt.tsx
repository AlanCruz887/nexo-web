import { RefreshCw, X } from "lucide-react";

import { Button } from "@/components/ui/button";

export function PwaUpdatePrompt({ onDismiss, onUpdate, open }: { onDismiss: () => void; onUpdate: () => void; open: boolean }) {
  if (!open) return null;
  return (
    <aside aria-label="Actualización disponible" aria-live="polite" className="fixed inset-x-4 bottom-[calc(5.75rem+env(safe-area-inset-bottom,0px))] z-[65] mx-auto flex max-w-lg items-center gap-3 rounded-2xl border border-border bg-surface-elevated p-3 shadow-float lg:bottom-6">
      <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-primary-soft text-primary-strong"><RefreshCw className="size-5" /></span>
      <div className="min-w-0 flex-1"><p className="text-sm font-semibold">Hay una nueva versión de Nexo</p><p className="text-xs text-muted-foreground">Actualiza cuando hayas terminado lo que estás haciendo.</p></div>
      <Button onClick={onUpdate} size="sm" type="button">Actualizar</Button>
      <Button aria-label="Actualizar más tarde" onClick={onDismiss} size="icon" type="button" variant="ghost"><X className="size-4" /></Button>
    </aside>
  );
}
