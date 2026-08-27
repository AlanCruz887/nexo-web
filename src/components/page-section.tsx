import type { PropsWithChildren, ReactNode } from "react";

export function PageSection({ action, children, description, title }: PropsWithChildren<{ action?: ReactNode; description?: string; title: string }>) {
  return <section><header className="mb-5 flex items-end justify-between gap-4"><div><h2 className="text-lg font-semibold tracking-[-0.02em] sm:text-xl">{title}</h2>{description ? <p className="mt-1 text-sm text-muted-foreground">{description}</p> : null}</div>{action}</header>{children}</section>;
}
