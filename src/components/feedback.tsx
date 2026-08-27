import { AlertCircle, Inbox } from "lucide-react";
import type { CSSProperties, ReactNode } from "react";

import { Button } from "@/components/ui/button";

export function LoadingState({ label = "Cargando" }: { label?: string }) {
  return (
    <div className="space-y-3 py-2" role="status">
      <span className="sr-only">{label}…</span>
      {["w-full", "w-[92%]", "w-[96%]"].map((width, index) => (
        <Skeleton key={width} className={`h-20 ${width}`} delay={index * 80} />
      ))}
    </div>
  );
}

export function Skeleton({ className, delay = 0, style }: { className?: string; delay?: number; style?: CSSProperties }) {
  return <div aria-hidden="true" className={`skeleton-shimmer rounded-xl bg-surface-secondary ${className ?? ""}`} style={{ ...style, animationDelay: `${delay}ms` }} />;
}

export function EmptyState({
  action,
  description,
  title,
}: {
  action?: ReactNode;
  description: string;
  title: string;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-border bg-surface/60 p-8 text-center">
      <Inbox aria-hidden="true" className="mx-auto mb-3 size-6 text-muted-foreground" />
      <h2 className="font-semibold">{title}</h2>
      <p className="mx-auto mt-1 max-w-md text-sm text-muted-foreground">{description}</p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function ErrorState({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: (() => void) | undefined;
}) {
  return (
    <div className="rounded-2xl border border-danger/25 bg-danger/5 p-5" role="alert">
      <div className="flex gap-3">
        <AlertCircle aria-hidden="true" className="mt-0.5 size-5 shrink-0 text-danger" />
        <div>
          <p className="font-medium">Algo no salió bien</p>
          <p className="mt-1 text-sm text-muted-foreground">{message}</p>
          {onRetry ? (
            <Button className="mt-4" onClick={onRetry} size="sm" variant="secondary">
              Reintentar
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
