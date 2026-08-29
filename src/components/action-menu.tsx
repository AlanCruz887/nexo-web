import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { MoreHorizontal } from "lucide-react";
import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";

export interface ActionMenuItem {
  icon?: ReactNode;
  label: string;
  onSelect: () => void;
  tone?: "default" | "danger";
}

export function ActionMenu({ items, label = "Más acciones", trigger }: { items: ActionMenuItem[]; label?: string; trigger?: ReactNode }) {
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        {trigger ?? <Button aria-label={label} size="icon" variant="ghost"><MoreHorizontal className="size-5" /></Button>}
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content align="end" className="z-50 min-w-48 rounded-xl border border-border bg-surface-elevated p-1.5 shadow-float">
          {items.map((item) => (
            <DropdownMenu.Item
              key={item.label}
              className={cn("flex min-h-10 cursor-default items-center gap-2 rounded-lg px-3 text-sm font-medium outline-none transition-colors focus:bg-muted", item.tone === "danger" && "text-danger focus:bg-danger/10")}
              onSelect={item.onSelect}
            >
              {item.icon}{item.label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
