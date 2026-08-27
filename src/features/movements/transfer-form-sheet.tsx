import { zodResolver } from "@hookform/resolvers/zod";
import { format } from "date-fns";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { Sheet, SheetFooter } from "@/components/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCreateTransfer } from "@/hooks/use-movements";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { transferFormSchema, type TransferFormInput } from "@/schemas/movement";
import type { AccountBalance } from "@/types/database";

export function TransferFormSheet({ accounts, defaultFromAccountId, onOpenChange, open }: { accounts: AccountBalance[]; defaultFromAccountId?: string | undefined; onOpenChange: (open: boolean) => void; open: boolean }) {
  const transfer = useCreateTransfer();
  const toast = useToast();
  const activeAccounts = accounts.filter((account) => account.is_active);
  const form = useForm<TransferFormInput>({
    resolver: zodResolver(transferFormSchema),
    defaultValues: {
      amount: "",
      from_account_id: defaultFromAccountId ?? activeAccounts[0]?.id ?? "",
      to_account_id: activeAccounts.find((account) => account.id !== defaultFromAccountId)?.id ?? "",
      occurred_on: format(new Date(), "yyyy-MM-dd"),
      description: "Transferencia",
      notes: "",
    },
  });
  const fromId = form.watch("from_account_id");
  const source = activeAccounts.find((account) => account.id === fromId);
  const destinations = activeAccounts.filter((account) => account.id !== fromId && account.currency === source?.currency);
  const destinationId = form.watch("to_account_id");

  useEffect(() => {
    if (destinations.length && !destinations.some((account) => account.id === destinationId)) {
      form.setValue("to_account_id", destinations[0]?.id ?? "", { shouldValidate: true });
    }
  }, [destinationId, destinations, form]);

  useEffect(() => {
    const from = defaultFromAccountId ?? activeAccounts[0]?.id ?? "";
    const currency = activeAccounts.find((account) => account.id === from)?.currency;
    form.reset({
      amount: "",
      from_account_id: from,
      to_account_id: activeAccounts.find((account) => account.id !== from && account.currency === currency)?.id ?? "",
      occurred_on: format(new Date(), "yyyy-MM-dd"),
      description: "Transferencia",
      notes: "",
    });
  }, [accounts, defaultFromAccountId, form, open]);

  async function handleSubmit(input: TransferFormInput) {
    try {
      if (parseMoneyInput(input.amount) <= 0n) {
        form.setError("amount", { message: "El importe debe ser mayor que cero." });
        return;
      }
      await transfer.mutateAsync(input);
      toast.success("Transferencia completada");
      onOpenChange(false);
    } catch (error) {
      form.setError("root", { message: toUserMessage(error) });
    }
  }

  return (
    <Sheet description="Mueve dinero entre cuentas de la misma moneda. No se registrará como ingreso ni gasto." onOpenChange={onOpenChange} open={open} title="Transferir">
      <form onSubmit={(event) => void form.handleSubmit(handleSubmit)(event)}>
        <div className="space-y-6">
          <FormField error={form.formState.errors.amount?.message} id="transfer-amount" label="¿Cuánto?">
            <div className="relative"><span className="absolute left-0 top-1/2 -translate-y-1/2 text-3xl text-muted-foreground">$</span><Input autoFocus className="h-20 rounded-none border-x-0 border-t-0 bg-transparent pl-7 text-4xl font-semibold tabular-nums focus-visible:ring-0" id="transfer-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} /></div>
          </FormField>
          <div className="relative space-y-3 before:absolute before:bottom-11 before:left-5 before:top-11 before:w-px before:bg-border">
            <FormField error={form.formState.errors.from_account_id?.message} id="transfer-from" label="Desde">
              <Select id="transfer-from" {...form.register("from_account_id")}>
                {activeAccounts.map((account) => <option key={account.id} value={account.id}>{account.name} · {account.currency}</option>)}
              </Select>
            </FormField>
            <FormField error={form.formState.errors.to_account_id?.message} hint={destinations.length === 0 ? "Necesitas otra cuenta activa en la misma moneda." : undefined} id="transfer-to" label="Hacia">
              <Select id="transfer-to" {...form.register("to_account_id")}>
                <option value="">Selecciona una cuenta</option>{destinations.map((account) => <option key={account.id} value={account.id}>{account.name} · {account.currency}</option>)}
              </Select>
            </FormField>
          </div>
          <FormField error={form.formState.errors.occurred_on?.message} id="transfer-date" label="Fecha"><Input id="transfer-date" type="date" {...form.register("occurred_on")} /></FormField>
          <FormField error={form.formState.errors.description?.message} id="transfer-description" label="Descripción"><Input id="transfer-description" {...form.register("description")} /></FormField>
          <FormField error={form.formState.errors.notes?.message} id="transfer-notes" label="Notas (opcional)"><textarea className="min-h-24 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/20" id="transfer-notes" {...form.register("notes")} /></FormField>
          {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
        </div>
        <SheetFooter><Button className="flex-1" disabled={transfer.isPending || destinations.length === 0} type="submit">{transfer.isPending ? "Transfiriendo…" : "Transferir ahora"}</Button></SheetFooter>
      </form>
    </Sheet>
  );
}
