import { ArrowUpRight, Landmark, Wallet } from "lucide-react";
import { Link } from "react-router-dom";

import { MoneyValue } from "@/components/money-value";
import { cn } from "@/lib/cn";
import type { AccountBalance } from "@/types/database";
import { accountTypeLabels } from "@/features/accounts/account-utils";

export function AccountCard({ account, featured = false }: { account: AccountBalance; featured?: boolean }) {
  const Icon = account.type === "cash" ? Wallet : Landmark;
  return (
    <Link
      className={cn(
        "group relative flex min-h-40 flex-col overflow-hidden rounded-[24px] bg-surface p-5 shadow-[inset_0_0_0_1px_var(--border)] transition duration-normal ease-nexo hover:-translate-y-0.5 hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/45",
        featured && "bg-primary text-primary-foreground shadow-[0_20px_60px_-34px_color-mix(in_oklab,var(--primary)_70%,transparent)]",
        !account.is_active && "opacity-70",
      )}
      to={`/cuentas/${account.id}`}
    >
      <div className="flex items-start justify-between gap-4">
        <span className={cn("grid size-10 place-items-center rounded-2xl bg-muted text-primary", featured && "bg-primary-foreground/12 text-primary-foreground")}><Icon className="size-5" /></span>
        <ArrowUpRight className={cn("size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5", featured && "text-primary-foreground/65")} />
      </div>
      <div className="mt-auto pt-6">
        <div className="flex items-center gap-2">
          <h3 className="font-semibold tracking-tight">{account.name}</h3>
          {!account.is_active ? <span className="rounded-full bg-warning/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-warning">Archivada</span> : null}
        </div>
        <p className={cn("mt-0.5 text-xs text-muted-foreground", featured && "text-primary-foreground/65")}>{accountTypeLabels[account.type]}{account.last4 ? ` · •••• ${account.last4}` : ""}</p>
        <MoneyValue amount={account.balance_minor} className="mt-3 block text-2xl" currency={account.currency} />
      </div>
    </Link>
  );
}
