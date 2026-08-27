import { forwardRef, type InputHTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  function Input({ className, ...props }, ref) {
    return (
      <input
        ref={ref}
        className={cn(
          "h-11 w-full rounded-xl border border-border bg-surface px-3.5 text-base text-foreground shadow-sm outline-none transition duration-normal ease-nexo placeholder:text-muted-foreground/70 hover:border-primary/20 focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/15 disabled:cursor-not-allowed disabled:bg-surface-secondary disabled:opacity-60 sm:text-sm",
          className,
        )}
        {...props}
      />
    );
  },
);
