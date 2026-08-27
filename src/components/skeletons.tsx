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

export function SettingsSkeleton() {
  return <div className="max-w-4xl space-y-10" role="status"><span className="sr-only">Cargando configuración</span><HeaderSkeleton /><div className="divide-y divide-border/60 border-y border-border/60">{[0, 1, 2].map((index) => <div className="grid gap-6 py-8 md:grid-cols-[220px_1fr]" key={index}><div><Skeleton className="h-4 w-28" /><Skeleton className="mt-2 h-3 w-44" /></div><Skeleton className="h-24 w-full" delay={index * 40} /></div>)}</div></div>;
}

export function StartupSplash() {
  return <main className="grid min-h-screen place-items-center bg-background"><div className="flex flex-col items-center"><span className="relative grid size-11 place-items-center overflow-hidden rounded-2xl bg-primary text-sm font-bold text-primary-foreground shadow-sm"><span className="absolute -right-2 -top-2 size-7 rounded-full bg-white/20" />N</span><div className="mt-5 h-1 w-20 overflow-hidden rounded-full bg-border"><span className="block h-full w-1/2 animate-[startup_1s_ease-in-out_infinite] rounded-full bg-primary motion-reduce:animate-none" /></div><span className="sr-only">Preparando Nexo</span></div></main>;
}
