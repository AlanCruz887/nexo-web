import type { PropsWithChildren } from "react";

export function AuthLayout({ children }: PropsWithChildren) {
  return (
    <main className="grid min-h-screen bg-surface lg:grid-cols-[minmax(360px,.8fr)_1.2fr]">
      <aside className="relative hidden overflow-hidden bg-brand-panel p-12 text-white lg:flex lg:flex-col xl:p-16"><div className="absolute -right-32 top-1/4 size-96 rounded-full bg-primary/20 blur-3xl" /><a className="relative inline-flex items-center gap-3 self-start rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60" href="/"><span className="grid size-10 place-items-center rounded-xl bg-white text-sm font-bold text-primary">N</span><span className="text-xl font-semibold tracking-[-0.04em]">Nexo</span></a><div className="relative my-auto max-w-md"><p className="text-sm font-medium text-white/75">Claridad financiera personal</p><h1 className="mt-4 text-4xl font-semibold leading-tight tracking-[-0.045em] xl:text-5xl">Tu dinero, conectado en un solo lugar.</h1><p className="mt-5 text-base leading-relaxed text-white/70">Organiza cuentas y movimientos con una base financiera diseñada para crecer contigo.</p></div><p className="relative text-xs text-white/60">Privacidad y precisión desde el primer día.</p></aside>
      <div className="relative grid place-items-center bg-background px-4 py-10 sm:px-8"><div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 h-64 bg-[radial-gradient(circle_at_top,color-mix(in_oklab,var(--primary)_10%,transparent),transparent_70%)]" /><div className="relative w-full max-w-md"><a className="mb-8 inline-flex items-center gap-2 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary lg:hidden" href="/"><span className="grid size-9 place-items-center rounded-xl bg-primary font-bold text-primary-foreground shadow-sm">N</span><span className="text-lg font-semibold tracking-tight">Nexo</span></a>{children}</div></div>
    </main>
  );
}
