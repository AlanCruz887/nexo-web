import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useRef, useState, type HTMLAttributes } from "react";

import { usePreferences } from "@/app/preferences-provider";
import { cn } from "@/lib/cn";
import { formatMoney } from "@/lib/money";
import { motionTokens } from "@/design-system/motion";
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
  const reduceMotion = useReducedMotion();
  const target = typeof amount === "bigint" ? amount : BigInt(amount);
  const previous = useRef(target);
  const [displayAmount, setDisplayAmount] = useState(target);

  useEffect(() => {
    const from = previous.current;
    previous.current = target;
    if (reduceMotion || from === target) { setDisplayAmount(target); return; }
    let frame = 0;
    const startedAt = performance.now();
    const duration = 340;
    const tick = (now: number) => {
      const progress = Math.min(1, (now - startedAt) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      const units = BigInt(Math.round(eased * 1000));
      setDisplayAmount(from + ((target - from) * units) / 1000n);
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [reduceMotion, target]);

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
      <motion.span
        animate={{ filter: isHidden && !reduceMotion ? "blur(0.5px)" : "blur(0px)", opacity: 1 }}
        className="tabular-nums"
        initial={false}
        transition={{ duration: reduceMotion ? 0 : motionTokens.duration.fast, ease: motionTokens.ease.standard }}
      >
        {isHidden ? "••••••" : formatMoney(displayAmount, currency, { sign })}
      </motion.span>
    </span>
  );
}
