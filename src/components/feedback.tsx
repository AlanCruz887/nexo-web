import { AlertCircle, Inbox, LoaderCircle } from "lucide-react";
import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";

export function LoadingState({ label = "Cargando" }: { label?: string }) {
  return (
    <div className="flex min-h-40 items-center justify-center gap-3 text-sm text-muted-foreground" role="status">
      <LoaderCircle aria-hidden="true" className="size-5 animate-spin motion-reduce:animate-none" />
      <span>{label}…</span>
    </div>
  );
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
    <div className="rounded-2xl border border-dashed border-border p-8 text-center">
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
