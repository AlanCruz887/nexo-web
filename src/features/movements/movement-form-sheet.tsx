import { zodResolver } from "@hookform/resolvers/zod";
import { format } from "date-fns";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCategories, useCreateMovement, useUpdateMovement } from "@/hooks/use-movements";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { movementDraftFromActivity } from "@/lib/movement-draft";
import { movementFormSchema, type MovementFormInput } from "@/schemas/movement";
import type { AccountBalance, FinancialActivity, TransactionKind } from "@/types/database";
import { PurchaseSplitFields } from "@/features/people/purchase-split-fields";
import { resolvePurchaseSplit } from "@/lib/purchase-split";

export function MovementFormSheet({
  accounts,
  defaultAccountId,
  defaultKind = "expense",
  defaultContactId,
  existing,
  prefill,
  onUpdated,
  onOpenChange,
  open,
}: {
  accounts: AccountBalance[];
  defaultAccountId?: string | undefined;
  defaultKind?: Exclude<TransactionKind, "adjustment">;
  defaultContactId?: string | undefined;
  existing?: FinancialActivity | undefined;
  prefill?: FinancialActivity | undefined;
  onUpdated?: ((eventId: string) => void) | undefined;
  onOpenChange: (open: boolean) => void;
  open: boolean;
}) {
  const categories = useCategories();
  const createMovement = useCreateMovement();
  const updateMovement = useUpdateMovement(existing?.event_id ?? "missing");
  const toast = useToast();
  const form = useForm<MovementFormInput>({
    resolver: zodResolver(movementFormSchema),
    defaultValues: {
      amount: "",
      account_id: defaultAccountId ?? accounts[0]?.id ?? "",
      kind: defaultKind,
      category_id: defaultKind === "income" ? "salary" : "other_expense",
      occurred_on: format(new Date(), "yyyy-MM-dd"),
      description: "",
      notes: "",
      purchase_scope: defaultContactId ? "other" : "self",
      personal_amount: defaultContactId ? "0" : "",
      allocations: defaultContactId ? [{ contact_id: defaultContactId, amount: "" }] : [],
    },
  });
  const kind = form.watch("kind");
  const sourceMovement = existing ?? prefill;

  useEffect(() => {
    const today = format(new Date(), "yyyy-MM-dd");
    form.reset(sourceMovement ? movementDraftFromActivity(sourceMovement, existing ? "edit" : "duplicate", today) : {
      amount: "",
      account_id: defaultAccountId ?? accounts[0]?.id ?? "",
      kind: defaultKind,
      category_id: defaultKind === "income" ? "salary" : "other_expense",
      occurred_on: today,
      description: "",
      notes: "",
      purchase_scope: defaultContactId ? "other" : "self",
      personal_amount: defaultContactId ? "0" : "",
      allocations: defaultContactId ? [{ contact_id: defaultContactId, amount: "" }] : [],
    });
  }, [accounts, defaultAccountId, defaultContactId, defaultKind, form, open, sourceMovement]);

  async function handleSubmit(input: MovementFormInput) {
    try {
      if (parseMoneyInput(input.amount) <= 0n) {
        form.setError("amount", { message: "El importe debe ser mayor que cero." });
        return;
      }
      if (input.kind === "expense") resolvePurchaseSplit(input);
      if (existing) {
        const updatedEventId = await updateMovement.mutateAsync(input);
        onUpdated?.(updatedEventId);
        toast.success("Movimiento actualizado");
      } else {
        await createMovement.mutateAsync(input);
        toast.success(input.kind === "income" ? "Ingreso registrado" : "Gasto registrado");
      }
      onOpenChange(false);
    } catch (error) {
      form.setError("root", { message: toUserMessage(error) });
    }
  }

  const availableCategories = categories.data?.filter((category) => category.kind === kind || category.kind === "both") ?? [];
  const activeAccounts = accounts.filter((account) => account.is_active || account.id === existing?.account_id);
  const mutation = existing ? updateMovement : createMovement;

  return (
    <ResponsiveDialog
      description={existing ? "Nexo actualizará el movimiento y conservará el cambio en tu historial." : "Registra el importe y los datos básicos del movimiento."}
      footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="movement-form" type="submit">{mutation.isPending ? "Guardando…" : existing ? "Guardar cambios" : kind === "income" ? "Registrar ingreso" : "Registrar gasto"}</Button></>}
      onOpenChange={onOpenChange}
      open={open}
      size="medium"
      title={existing ? "Editar movimiento" : kind === "income" ? "Nuevo ingreso" : "Nuevo gasto"}
    >
      <form id="movement-form" onSubmit={(event) => void form.handleSubmit(handleSubmit)(event)}>
        <div className="space-y-7">
          <FormField error={form.formState.errors.amount?.message} id="movement-amount" label="¿Cuánto?">
            <div className="relative">
              <span className="pointer-events-none absolute left-0 top-1/2 -translate-y-1/2 text-3xl font-medium text-muted-foreground">$</span>
              <Input autoFocus className="h-24 rounded-none border-x-0 border-t-0 bg-transparent pl-7 text-5xl font-semibold tracking-[-0.04em] tabular-nums shadow-none focus-visible:ring-0" id="movement-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} />
            </div>
          </FormField>
          <div className="grid grid-cols-2 gap-2 rounded-xl bg-surface-secondary p-1.5">
            {(["expense", "income"] as const).map((value) => (
              <button
                key={value}
                className={`min-h-11 rounded-lg text-sm font-semibold transition ${kind === value ? "bg-surface text-primary-strong shadow-sm" : "text-muted-foreground hover:text-foreground"}`}
                onClick={() => {
                  form.setValue("kind", value);
                  form.setValue("category_id", value === "income" ? "salary" : "other_expense");
                }}
                type="button"
              >
                {value === "expense" ? "Gasto" : "Ingreso"}
              </button>
            ))}
          </div>
          {kind === "expense" ? <PurchaseSplitFields amount={form.watch("amount")} allocations={form.watch("allocations")} onAllocations={(value) => form.setValue("allocations", value, { shouldValidate: true })} onPersonalAmount={(value) => form.setValue("personal_amount", value, { shouldValidate: true })} onScope={(value) => form.setValue("purchase_scope", value, { shouldValidate: true })} personalAmount={form.watch("personal_amount")} scope={form.watch("purchase_scope")} /> : null}
          <FormField error={form.formState.errors.account_id?.message} id="movement-account" label="Cuenta">
            <Select disabled={Boolean(existing)} id="movement-account" {...form.register("account_id")}>
              {activeAccounts.map((account) => <option key={account.id} value={account.id}>{account.name} · {account.currency}{!account.is_active ? " · Archivada" : ""}</option>)}
            </Select>
          </FormField>
          <div className="grid gap-5 sm:grid-cols-2">
            <FormField error={form.formState.errors.category_id?.message} id="movement-category" label="Categoría">
              <Select id="movement-category" {...form.register("category_id")}>{availableCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</Select>
            </FormField>
            <FormField error={form.formState.errors.occurred_on?.message} id="movement-date" label="Fecha">
              <Input id="movement-date" type="date" {...form.register("occurred_on")} />
            </FormField>
          </div>
          <FormField error={form.formState.errors.description?.message} id="movement-description" label="Descripción">
            <Input id="movement-description" placeholder={kind === "income" ? "Nómina" : "Supermercado"} {...form.register("description")} />
          </FormField>
          <FormField error={form.formState.errors.notes?.message} id="movement-notes" label="Notas (opcional)">
            <textarea className="min-h-24 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm outline-none transition focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/20" id="movement-notes" {...form.register("notes")} />
          </FormField>
          {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
        </div>
      </form>
    </ResponsiveDialog>
  );
}
