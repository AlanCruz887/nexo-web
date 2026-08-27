import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

export function FilterBar({ children }: { children: ReactNode }) {
  return <div className="flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none]">{children}</div>;
}

export function FilterPill({ active, children, onClick }: { active?: boolean; children: ReactNode; onClick: () => void }) {
  return (
    <button
      className={cn("min-h-10 shrink-0 rounded-full border border-border bg-surface px-4 text-sm font-medium text-muted-foreground transition duration-fast ease-nexo hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40", active && "border-primary/20 bg-primary/10 text-primary")}
      onClick={onClick}
      type="button"
    >
      {children}
    </button>
  );
}
