import * as DialogPrimitive from "@radix-ui/react-dialog";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { X } from "lucide-react";
import type { PropsWithChildren } from "react";

import { Button } from "@/components/ui/button";
import { motionTokens } from "@/design-system/motion";
import { useMediaQuery } from "@/hooks/use-media-query";

export function Sheet({
  children,
  description,
  onOpenChange,
  open,
  title,
}: PropsWithChildren<{
  description?: string;
  onOpenChange: (open: boolean) => void;
  open: boolean;
  title: string;
}>) {
  const reduceMotion = useReducedMotion();
  const isDesktop = useMediaQuery("(min-width: 640px)");
  return (
    <DialogPrimitive.Root onOpenChange={onOpenChange} open={open}>
      <AnimatePresence>
        {open ? (
          <DialogPrimitive.Portal forceMount>
            <DialogPrimitive.Overlay asChild forceMount>
              <motion.div
                animate={{ opacity: 1 }}
                className="fixed inset-0 z-40 bg-slate-950/28 backdrop-blur-[2px] dark:bg-black/55"
                exit={{ opacity: 0 }}
                initial={reduceMotion ? false : { opacity: 0 }}
                transition={{ duration: reduceMotion ? 0 : motionTokens.duration.fast }}
              />
            </DialogPrimitive.Overlay>
            <DialogPrimitive.Content asChild forceMount>
              <motion.section
                animate={{ opacity: 1, x: 0, y: 0 }}
                className="fixed inset-x-0 bottom-0 z-50 max-h-[92dvh] overflow-y-auto rounded-t-2xl border border-border bg-surface p-5 shadow-float outline-none sm:inset-y-0 sm:left-auto sm:right-0 sm:max-h-none sm:w-full sm:max-w-[480px] sm:rounded-none sm:border-y-0 sm:border-r-0 sm:p-7"
                exit={reduceMotion ? { opacity: 0 } : { opacity: 0, x: 18, y: 18 }}
                initial={reduceMotion ? false : { opacity: 0, x: 22, y: 22 }}
                transition={reduceMotion ? { duration: 0 } : isDesktop ? { duration: motionTokens.duration.normal, ease: motionTokens.ease.enter } : { type: "spring", ...motionTokens.spring }}
              >
                <div className="mx-auto mb-5 h-1 w-10 rounded-full bg-border sm:hidden" />
                <div className="flex items-start justify-between gap-5">
                  <div>
                    <DialogPrimitive.Title className="text-xl font-semibold tracking-tight">{title}</DialogPrimitive.Title>
                    {description ? <DialogPrimitive.Description className="mt-1 text-sm text-muted-foreground">{description}</DialogPrimitive.Description> : null}
                  </div>
                  <DialogPrimitive.Close asChild>
                    <Button aria-label="Cerrar" className="shrink-0" size="icon" variant="ghost"><X className="size-5" /></Button>
                  </DialogPrimitive.Close>
                </div>
                <div className="mt-6">{children}</div>
              </motion.section>
            </DialogPrimitive.Content>
          </DialogPrimitive.Portal>
        ) : null}
      </AnimatePresence>
    </DialogPrimitive.Root>
  );
}

export function ConfirmDialog({
  confirmLabel,
  description,
  isPending = false,
  onConfirm,
  onOpenChange,
  open,
  title,
  tone = "danger",
}: {
  confirmLabel: string;
  description: string;
  isPending?: boolean;
  onConfirm: () => void;
  onOpenChange: (open: boolean) => void;
  open: boolean;
  title: string;
  tone?: "danger" | "primary";
}) {
  const reduceMotion = useReducedMotion();
  return (
    <DialogPrimitive.Root onOpenChange={onOpenChange} open={open}>
      <AnimatePresence>
        {open ? <DialogPrimitive.Portal forceMount>
          <DialogPrimitive.Overlay asChild forceMount>
            <motion.div animate={{ opacity: 1 }} className="fixed inset-0 z-50 bg-slate-950/28 backdrop-blur-[2px] dark:bg-black/55" exit={{ opacity: 0 }} initial={reduceMotion ? false : { opacity: 0 }} transition={{ duration: reduceMotion ? 0 : motionTokens.duration.fast }} />
          </DialogPrimitive.Overlay>
          <DialogPrimitive.Content asChild forceMount>
            <motion.div
              animate={{ opacity: 1, scale: 1, y: 0 }}
              className="fixed left-1/2 top-1/2 z-50 w-[calc(100%-2rem)] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-border bg-surface p-6 shadow-float outline-none"
              exit={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.985, y: 4 }}
              initial={reduceMotion ? false : { opacity: 0, scale: 0.975, y: 8 }}
              transition={{ duration: reduceMotion ? 0 : motionTokens.duration.normal, ease: motionTokens.ease.enter }}
            >
              <DialogPrimitive.Title className="text-xl font-semibold tracking-tight">{title}</DialogPrimitive.Title>
              <DialogPrimitive.Description className="mt-2 text-sm leading-relaxed text-muted-foreground">{description}</DialogPrimitive.Description>
              <div className="mt-6 flex justify-end gap-2">
                <DialogPrimitive.Close asChild><Button variant="ghost">Cancelar</Button></DialogPrimitive.Close>
                <Button disabled={isPending} onClick={onConfirm} variant={tone}>{isPending ? "Procesando…" : confirmLabel}</Button>
              </div>
            </motion.div>
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal> : null}
      </AnimatePresence>
    </DialogPrimitive.Root>
  );
}

export const Drawer = Sheet;
