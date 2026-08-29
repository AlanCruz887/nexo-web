import { Skeleton } from "@/components/feedback";

function HeaderSkeleton() { return <div className="border-b border-border/60 pb-7"><Skeleton className="h-3 w-20" /><Skeleton className="mt-4 h-10 w-48" /></div>; }
function TransactionRows({ count = 5 }: { count?: number }) { return <div className="space-y-1">{Array.from({ length: count }, (_, index) => <div className="grid grid-cols-[40px_1fr_90px] items-center gap-3 py-4" key={index}><Skeleton className="size-10" delay={index * 40} /><div><Skeleton className="h-3.5 w-36" delay={index * 40} /><Skeleton className="mt-2 h-3 w-52 max-w-full" delay={index * 40} /></div><Skeleton className="h-4 w-20 justify-self-end" delay={index * 40} /></div>)}</div>; }

export function DashboardSkeleton() {
  return <div className="space-y-12" role="status"><span className="sr-only">Preparando tu resumen</span><div><Skeleton className="h-3 w-20" /><Skeleton className="mt-3 h-10 w-36" /></div><div className="border-b border-border/60 pb-9"><Skeleton className="h-3 w-36" /><Skeleton className="mt-5 h-20 w-[min(560px,90%)]" /><div className="mt-7 flex gap-8"><Skeleton className="h-11 w-28" /><Skeleton className="h-11 w-40" /></div></div><div><Skeleton className="h-6 w-52" /><div className="mt-5 border-y border-border/60 py-5"><Skeleton className="h-4 w-48" /><Skeleton className="mt-2 h-3 w-80 max-w-full" /></div></div><div className="grid gap-12 xl:grid-cols-[1.5fr_.75fr]"><div><Skeleton className="h-6 w-40" /><div className="mt-5"><TransactionRows count={4} /></div></div><div><Skeleton className="h-6 w-32" /><Skeleton className="mt-5 h-40 w-full" /></div></div></div>;
}

export function AccountsSkeleton() {
  return <div className="space-y-12" role="status"><span className="sr-only">Preparando tus cuentas</span><HeaderSkeleton /><div className="border-b border-border/60 pb-9"><Skeleton className="h-3 w-32" /><Skeleton className="mt-5 h-16 w-[min(480px,85%)]" /></div><div><Skeleton className="h-6 w-32" /><div className="mt-5 grid gap-4 md:grid-cols-2">{[0, 1, 2, 3].map((index) => <Skeleton className="h-44 w-full" delay={index * 40} key={index} />)}</div></div></div>;
}

export function TransactionsSkeleton() {
  return <div className="space-y-10" role="status"><span className="sr-only">Cargando movimientos</span><HeaderSkeleton /><div className="flex gap-2 border-b border-border/60 pb-6">{[72, 88, 74, 108].map((width) => <Skeleton className="h-10 rounded-full" key={width} style={{ width }} />)}</div><div><Skeleton className="h-3 w-12" /><TransactionRows /></div></div>;
}

export function CardsSkeleton() {
  return <div className="space-y-12" role="status"><span className="sr-only">Preparando tus tarjetas</span><HeaderSkeleton /><div className="border-b border-border/60 pb-9"><Skeleton className="h-3 w-32" /><Skeleton className="mt-5 h-16 w-[min(480px,85%)]" /></div><div><Skeleton className="h-6 w-32" /><div className="mt-5 grid gap-5 md:grid-cols-2 xl:grid-cols-3">{[0, 1, 2].map((index) => <Skeleton className="h-56 rounded-[1.6rem]" delay={index * 50} key={index} />)}</div></div></div>;
}

export function CardDetailSkeleton() {
  return <div className="space-y-10" role="status"><span className="sr-only">Preparando tarjeta</span><Skeleton className="h-10 w-24" /><div className="grid gap-8 border-b border-border/60 pb-10 lg:grid-cols-2"><div><Skeleton className="h-4 w-28" /><Skeleton className="mt-3 h-10 w-56" /><Skeleton className="mt-12 h-20 w-[min(480px,90%)]" /></div><Skeleton className="h-52 rounded-[1.6rem]" /></div><div className="grid gap-1 sm:grid-cols-2 lg:grid-cols-4">{[0, 1, 2, 3].map((index) => <Skeleton className="h-28" delay={index * 40} key={index} />)}</div><StatementsSkeleton /></div>;
}

export function StatementsSkeleton() {
  return <div className="space-y-1" role="status"><span className="sr-only">Cargando estados de cuenta</span>{[0, 1, 2].map((index) => <div className="flex items-center justify-between border-b border-border py-5" key={index}><div><Skeleton className="h-4 w-36" delay={index * 40} /><Skeleton className="mt-2 h-3 w-52" delay={index * 40} /></div><Skeleton className="h-5 w-24" delay={index * 40} /></div>)}</div>;
}

export function CardMovementListSkeleton() {
  return <div role="status"><span className="sr-only">Cargando movimientos reales</span><Skeleton className="h-3 w-20" /><div className="mt-3 divide-y divide-border/60">{[0, 1, 2].map((index) => <div className="grid grid-cols-[40px_1fr_90px] items-center gap-3 py-4" key={index}><Skeleton className="size-10" delay={index * 40} /><div><Skeleton className="h-3.5 w-36" delay={index * 40} /><Skeleton className="mt-2 h-3 w-48 max-w-full" delay={index * 40} /></div><Skeleton className="h-4 w-20 justify-self-end" delay={index * 40} /></div>)}</div></div>;
}

export function CardStatementActivitySkeleton() {
  return <div className="space-y-4" role="status"><span className="sr-only">Cargando actividad del estado actual</span><Skeleton className="h-3 w-40" /><div className="flex items-start justify-between gap-5"><div><Skeleton className="h-4 w-36" /><Skeleton className="mt-2 h-3 w-20" /></div><div className="grid grid-cols-2 gap-3"><Skeleton className="h-9 w-24" /><Skeleton className="h-9 w-24" /></div></div><div className="border-y border-border/60"><TransactionRows count={2} /></div></div>;
}

export function InstallmentPlansSkeleton() {
  return <div className="grid gap-3 md:grid-cols-2" role="status"><span className="sr-only">Cargando planes MSI</span>{[0, 1].map((index) => <div className="rounded-2xl border border-border p-5" key={index}><Skeleton className="h-4 w-36" delay={index * 40} /><Skeleton className="mt-3 h-7 w-28" delay={index * 40} /><Skeleton className="mt-5 h-2 w-full" delay={index * 40} /><Skeleton className="mt-3 h-3 w-44" delay={index * 40} /></div>)}</div>;
}

export function InstallmentPlanDetailSkeleton() {
  return <div className="space-y-6" role="status"><span className="sr-only">Cargando detalle MSI</span><Skeleton className="h-10 w-48" /><div className="grid grid-cols-2 gap-3">{[0, 1, 2, 3].map((index) => <Skeleton className="h-20" delay={index * 40} key={index} />)}</div><StatementsSkeleton /></div>;
}

export function PeopleSkeleton() {
  return <div className="space-y-10" role="status"><span className="sr-only">Preparando personas</span><HeaderSkeleton /><div className="flex gap-2"><Skeleton className="h-10 w-20 rounded-full" /><Skeleton className="h-10 w-24 rounded-full" /></div><div className="grid gap-3 md:grid-cols-2">{[0, 1, 2, 3].map((index) => <div className="rounded-2xl border border-border p-5" key={index}><Skeleton className="h-5 w-32" delay={index * 40} /><Skeleton className="mt-3 h-3 w-44" delay={index * 40} /><Skeleton className="mt-6 h-8 w-28" delay={index * 40} /></div>)}</div></div>;
}

export function SettingsSkeleton() {
  return <div className="max-w-4xl space-y-10" role="status"><span className="sr-only">Cargando configuración</span><HeaderSkeleton /><div className="divide-y divide-border/60 border-y border-border/60">{[0, 1, 2].map((index) => <div className="grid gap-6 py-8 md:grid-cols-[220px_1fr]" key={index}><div><Skeleton className="h-4 w-28" /><Skeleton className="mt-2 h-3 w-44" /></div><Skeleton className="h-24 w-full" delay={index * 40} /></div>)}</div></div>;
}

export function StartupSplash() {
  return <main className="grid min-h-screen place-items-center bg-background"><div className="flex flex-col items-center"><span className="relative grid size-11 place-items-center overflow-hidden rounded-2xl bg-primary text-sm font-bold text-primary-foreground shadow-sm"><span className="absolute -right-2 -top-2 size-7 rounded-full bg-white/20" />N</span><div className="mt-5 h-1 w-20 overflow-hidden rounded-full bg-border"><span className="block h-full w-1/2 animate-[startup_1s_ease-in-out_infinite] rounded-full bg-primary motion-reduce:animate-none" /></div><span className="sr-only">Preparando Nexo</span></div></main>;
}
