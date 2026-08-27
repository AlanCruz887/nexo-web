import type { PropsWithChildren } from "react";

export function AuthLayout({ children }: PropsWithChildren) {
  return (
    <main className="relative grid min-h-screen place-items-center overflow-hidden px-4 py-10 sm:px-6">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 top-0 h-72 bg-[radial-gradient(circle_at_top,color-mix(in_oklab,var(--primary)_18%,transparent),transparent_65%)]"
      />
      <div className="relative w-full max-w-md">
        <a className="mb-8 inline-flex items-center gap-2 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary" href="/">
          <span className="grid size-9 place-items-center rounded-xl bg-primary font-bold text-primary-foreground">N</span>
          <span className="text-lg font-semibold tracking-tight">Nexo</span>
        </a>
        {children}
      </div>
    </main>
  );
}
