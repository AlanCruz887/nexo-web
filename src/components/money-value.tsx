import type { HTMLAttributes } from "react";

import { usePreferences } from "@/app/preferences-provider";
import { cn } from "@/lib/cn";
import { formatMoney } from "@/lib/money";
import type { CurrencyCode } from "@/types/database";
import type { MoneyMinor, MoneyMinorSerialized } from "@/types/money";

interface MoneyValueProps extends Omit<HTMLAttributes<HTMLSpanElement>, "children"> {
  amount: MoneyMinor | MoneyMinorSerialized;
  currency: CurrencyCode;
  privacy?: boolean | undefined;
  sign?: "auto" | "always" | "never";
  size?: "sm" | "md" | "lg" | "xl";
}

export function MoneyValue({
  amount,
  className,
  currency,
  privacy,
  sign = "auto",
  size = "md",
  ...props
}: MoneyValueProps) {
  const { hideMoney } = usePreferences();
  const isHidden = privacy ?? hideMoney;

  return (
    <span
      className={cn(
        "font-semibold tabular-nums tracking-tight",
        size === "sm" && "text-sm",
        size === "md" && "text-base",
        size === "lg" && "text-2xl",
        size === "xl" && "text-4xl font-semibold sm:text-5xl",
        className,
      )}
      aria-label={isHidden ? "Cantidad oculta" : undefined}
      {...props}
    >
      {isHidden ? "••••••" : formatMoney(amount, currency, { sign })}
    </span>
  );
}
