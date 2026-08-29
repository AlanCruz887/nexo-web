import { CircleHelp } from "lucide-react";
import { useId } from "react";

import { cn } from "@/lib/cn";

export function ContextHelp({ label, text, className }: { label: string; text: string; className?: string }) {
  const tooltipId = useId();
  return <span className={cn("group relative inline-flex align-middle", className)}>
    <button aria-describedby={tooltipId} aria-label={`Más información sobre ${label}`} className="grid size-6 place-items-center rounded-full text-muted-foreground transition-colors hover:bg-surface-secondary hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30" type="button"><CircleHelp className="size-3.5" /></button>
    <span className="pointer-events-none invisible absolute bottom-full left-1/2 z-30 mb-2 w-64 -translate-x-1/2 rounded-xl border border-border bg-surface-elevated p-3 text-left text-xs font-normal leading-relaxed text-foreground opacity-0 shadow-float transition group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100 motion-reduce:transition-none" id={tooltipId} role="tooltip">{text}</span>
  </span>;
}
