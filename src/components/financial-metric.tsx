import type { ReactNode } from "react";

export function FinancialMetric({ helper, label, value }: { helper?: ReactNode; label: string; value: ReactNode }) {
  return <div className="min-w-0 py-4"><p className="text-xs font-medium text-muted-foreground">{label}</p><div className="mt-1.5 truncate text-xl font-semibold tracking-[-0.025em] tabular-nums">{value}</div>{helper ? <div className="mt-1 text-xs text-muted-foreground">{helper}</div> : null}</div>;
}
