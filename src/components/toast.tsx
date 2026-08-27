import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { AlertCircle, CheckCircle2, X } from "lucide-react";
import { createContext, type PropsWithChildren, useCallback, useContext, useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import { motionTokens } from "@/design-system/motion";

interface ToastItem { id: string; message: string; tone: "success" | "error" }
interface ToastContextValue { error: (message: string) => void; success: (message: string) => void }
const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: PropsWithChildren) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const reduceMotion = useReducedMotion();
  const remove = useCallback((id: string) => setItems((current) => current.filter((item) => item.id !== id)), []);
  const add = useCallback((message: string, tone: ToastItem["tone"]) => {
    const id = crypto.randomUUID();
    setItems((current) => [...current, { id, message, tone }]);
    window.setTimeout(() => remove(id), 3200);
  }, [remove]);
  const success = useCallback((message: string) => add(message, "success"), [add]);
  const error = useCallback((message: string) => add(message, "error"), [add]);
  const value = useMemo(() => ({ error, success }), [error, success]);
  return (
    <ToastContext.Provider value={value}>
      {children}
      <div aria-live="polite" className="pointer-events-none fixed inset-x-4 bottom-24 z-[70] flex flex-col items-center gap-2 lg:bottom-6">
        <AnimatePresence>
          {items.map((item) => (
            <motion.div
              key={item.id}
              animate={{ opacity: 1, y: 0 }}
              className="pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-xl border border-border bg-surface-elevated px-4 py-3 text-sm text-foreground shadow-float"
              exit={{ opacity: 0, y: 8 }}
              initial={reduceMotion ? false : { opacity: 0, y: 12 }}
              transition={{ duration: reduceMotion ? 0 : motionTokens.duration.normal, ease: motionTokens.ease.enter }}
            >
              {item.tone === "success" ? <CheckCircle2 className="size-5 text-success" /> : <AlertCircle className="size-5 text-danger" />}
              <span className="flex-1 font-medium">{item.message}</span>
              <Button aria-label="Cerrar aviso" onClick={() => remove(item.id)} size="icon" variant="ghost"><X className="size-4" /></Button>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast debe usarse dentro de ToastProvider.");
  return context;
}
