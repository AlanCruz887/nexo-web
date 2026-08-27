import * as DialogPrimitive from "@radix-ui/react-dialog";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { X } from "lucide-react";
import type { PropsWithChildren, ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { motionTokens } from "@/design-system/motion";
import { useMediaQuery } from "@/hooks/use-media-query";
import { cn } from "@/lib/cn";

export function ResponsiveDialog({ children, description, footer, onOpenChange, open, size = "medium", title }: PropsWithChildren<{ description?: string; footer?: ReactNode; onOpenChange: (open: boolean) => void; open: boolean; size?: "small" | "medium" | "large"; title: string }>) {
  const reduceMotion = useReducedMotion();
  const isDesktop = useMediaQuery("(min-width: 640px)");
  return <DialogPrimitive.Root onOpenChange={onOpenChange} open={open}><AnimatePresence>{open ? <DialogPrimitive.Portal forceMount>
    <DialogPrimitive.Overlay asChild forceMount><motion.div animate={{ opacity: 1 }} className="fixed inset-0 z-40 bg-slate-950/30 backdrop-blur-[3px] dark:bg-black/60" exit={{ opacity: 0 }} initial={reduceMotion ? false : { opacity: 0 }} transition={{ duration: reduceMotion ? 0 : motionTokens.duration.fast }} /></DialogPrimitive.Overlay>
    <DialogPrimitive.Content asChild forceMount>
      <motion.section
        animate={{ opacity: 1, scale: 1, y: 0 }}
        className={cn("fixed inset-x-0 bottom-0 z-50 flex max-h-[94dvh] flex-col overflow-hidden rounded-t-2xl border border-border bg-surface shadow-float outline-none sm:bottom-auto sm:left-1/2 sm:right-auto sm:top-1/2 sm:w-[calc(100%-3rem)] sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-2xl", size === "small" && "sm:max-w-md", size === "medium" && "sm:max-w-2xl", size === "large" && "sm:max-w-4xl")}
        exit={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.985, y: 8 }}
        initial={reduceMotion ? false : { opacity: 0, scale: 0.98, y: 14 }}
        transition={reduceMotion ? { duration: 0 } : isDesktop ? { duration: motionTokens.duration.normal, ease: motionTokens.ease.enter } : { type: "spring", ...motionTokens.spring }}
      >
        <div className="mx-auto mt-2 h-1 w-10 rounded-full bg-border sm:hidden" />
        <header className="flex items-start justify-between gap-5 border-b border-border/70 px-5 py-5 sm:px-7">
          <div><DialogPrimitive.Title className="text-xl font-semibold tracking-[-0.025em] sm:text-2xl">{title}</DialogPrimitive.Title>{description ? <DialogPrimitive.Description className="mt-1.5 max-w-2xl text-sm leading-relaxed text-muted-foreground">{description}</DialogPrimitive.Description> : null}</div>
          <DialogPrimitive.Close asChild><Button aria-label="Cerrar" className="shrink-0" size="icon" variant="ghost"><X className="size-5" /></Button></DialogPrimitive.Close>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-6 sm:px-7">{children}</div>
        {footer ? <footer className="flex shrink-0 items-center justify-end gap-2 border-t border-border/70 bg-surface px-5 py-4 sm:px-7">{footer}</footer> : null}
      </motion.section>
    </DialogPrimitive.Content>
  </DialogPrimitive.Portal> : null}</AnimatePresence></DialogPrimitive.Root>;
}

export const Modal = ResponsiveDialog;
export const LargeDialog = ResponsiveDialog;
