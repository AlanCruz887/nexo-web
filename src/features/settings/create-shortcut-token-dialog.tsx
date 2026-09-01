import { zodResolver } from "@hookform/resolvers/zod";
import { Check, Copy } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useForm } from "react-hook-form";

import { ConfirmDialog } from "@/components/sheet";
import { Modal } from "@/components/responsive-dialog";
import { useToast } from "@/components/toast";
import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useCreateShortcutToken } from "@/hooks/use-shortcut-tokens";
import { reportError } from "@/lib/errors";
import { shortcutTokenFormSchema, type ShortcutTokenFormInput } from "@/schemas/shortcut-token";

/**
 * The plaintext token lives ONLY in this component's local state
 * (`revealedToken`), never in a query cache, never logged, never sent
 * to error reporting. It is cleared on every close path (Listo, X,
 * overlay click, Escape, confirmed close-without-copying) via
 * `resetAll`, which also calls `create.reset()` to drop TanStack
 * Query's own (in-memory-only, never persisted -- this app has no
 * query/mutation cache persister at all) copy of the mutation result.
 */
export function CreateShortcutTokenDialog({ onOpenChange, open }: { onOpenChange: (open: boolean) => void; open: boolean }) {
  const create = useCreateShortcutToken();
  const toast = useToast();
  const form = useForm<ShortcutTokenFormInput>({ resolver: zodResolver(shortcutTokenFormSchema), defaultValues: { name: "" } });
  const [revealedToken, setRevealedToken] = useState<string>();
  const [copied, setCopied] = useState(false);
  const [confirmCloseOpen, setConfirmCloseOpen] = useState(false);
  const revealInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (revealedToken) revealInputRef.current?.focus();
  }, [revealedToken]);

  function resetAll() {
    setRevealedToken(undefined);
    setCopied(false);
    setConfirmCloseOpen(false);
    form.reset({ name: "" });
    create.reset();
  }

  function requestClose() {
    if (revealedToken && !copied) {
      setConfirmCloseOpen(true);
      return;
    }
    resetAll();
    onOpenChange(false);
  }

  async function onSubmit(input: ShortcutTokenFormInput) {
    try {
      const created = await create.mutateAsync(input.name);
      setRevealedToken(created.token_plain);
    } catch (error) {
      reportError("shortcut-tokens:create", error);
      toast.error("No pudimos crear el acceso. Intenta de nuevo.");
    }
  }

  async function handleCopy() {
    if (!revealedToken) return;
    try {
      await navigator.clipboard.writeText(revealedToken);
      setCopied(true);
    } catch {
      toast.error("No pudimos copiar el acceso. Selecciónalo y cópialo manualmente.");
    }
  }

  return (
    <>
      <Modal
        {...(revealedToken ? {} : { description: "Dale un nombre a tu iPhone para reconocerlo después." })}
        onOpenChange={(next) => { if (!next) requestClose(); }}
        open={open}
        size="small"
        title={revealedToken ? "Tu acceso está listo" : "Crear acceso"}
      >
        {revealedToken ? (
          <div className="space-y-5">
            <p className="text-sm leading-relaxed text-foreground">
              Guarda este acceso ahora. Por seguridad, Nexo no podrá volver a mostrarlo.
            </p>
            <div className="space-y-2">
              <label className="block text-sm font-medium text-foreground" htmlFor="shortcut-token-value">Tu acceso</label>
              <div className="flex items-center gap-2">
                <input
                  ref={revealInputRef}
                  className="h-11 w-full select-all truncate rounded-xl border border-border bg-surface-secondary px-3.5 font-mono text-sm text-foreground outline-none focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/15"
                  id="shortcut-token-value"
                  onFocus={(event) => event.currentTarget.select()}
                  readOnly
                  value={revealedToken}
                />
                <Button aria-label="Copiar acceso" onClick={() => void handleCopy()} size="icon" type="button" variant="secondary">
                  {copied ? <Check className="size-4 text-success" /> : <Copy className="size-4" />}
                </Button>
              </div>
              <p aria-live="polite" className="text-sm text-success" role="status">{copied ? "Copiado." : " "}</p>
            </div>
            <div className="flex justify-end">
              <Button onClick={() => { resetAll(); onOpenChange(false); }} type="button">Listo</Button>
            </div>
          </div>
        ) : (
          <form className="space-y-5" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
            <FormField error={form.formState.errors.name?.message} id="shortcut-token-name" label="Nombre del dispositivo">
              <Input autoFocus id="shortcut-token-name" placeholder="Mi iPhone" {...form.register("name")} />
            </FormField>
            <p className="text-sm leading-relaxed text-muted-foreground">
              Este acceso permite que tu iPhone registre compras en Nexo.
            </p>
            <div className="flex justify-end gap-2">
              <Button onClick={requestClose} type="button" variant="ghost">Cancelar</Button>
              <Button disabled={create.isPending} type="submit">{create.isPending ? "Creando…" : "Crear acceso"}</Button>
            </div>
          </form>
        )}
      </Modal>
      <ConfirmDialog
        confirmLabel="Cerrar de todos modos"
        description="Este acceso no podrá volver a mostrarse. ¿Cerrar de todos modos?"
        onConfirm={() => { resetAll(); onOpenChange(false); }}
        onOpenChange={setConfirmCloseOpen}
        open={confirmCloseOpen}
        title="¿Cerrar sin copiar?"
        tone="danger"
      />
    </>
  );
}
