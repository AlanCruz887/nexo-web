import { forwardRef, type SelectHTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  function Select({ className, children, ...props }, ref) {
    return (
      <select
        ref={ref}
        className={cn(
          "h-11 w-full rounded-xl border border-border bg-surface px-3.5 text-base text-foreground shadow-sm outline-none transition duration-normal ease-nexo hover:border-primary/20 focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/15 sm:text-sm",
          className,
        )}
        {...props}
      >
        {children}
      </select>
    );
  },
);
