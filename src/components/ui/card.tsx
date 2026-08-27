import type { HTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("rounded-2xl border border-border/80 bg-surface p-5 shadow-card sm:p-6", className)}
      {...props}
    />
  );
}
