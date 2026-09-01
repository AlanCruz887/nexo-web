import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { FormField } from "@/components/form-field";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useAccounts } from "@/hooks/use-accounts";
import { useCreateGoal, useUpdateGoal } from "@/hooks/use-goals";
import { useCurrencies } from "@/hooks/use-currencies";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import { goalFormSchema, type GoalFormInput } from "@/schemas/goal";
import type { CurrencyCode, GoalBalance } from "@/types/database";

export function GoalForm({ goal, onOpenChange, open }: { goal?: GoalBalance; onOpenChange: (open: boolean) => void; open: boolean }) {
  const currencies = useCurrencies();
  const accounts = useAccounts();
  const create = useCreateGoal();
  const update = useUpdateGoal(goal?.id ?? "missing");
  const toast = useToast();
  const isEdit = Boolean(goal);
  const form = useForm<GoalFormInput>({
    resolver: zodResolver(goalFormSchema),
    defaultValues: { name: "", currency: "", target_amount: "", target_date: "", linked_account_id: "" },
  });
  const currency = form.watch("currency");

  useEffect(() => {
    if (!open) return;
    form.reset(goal ? {
      name: goal.name, currency: goal.currency, target_amount: (Number(goal.target_minor) / 100).toFixed(2),
      target_date: goal.target_date ?? "", linked_account_id: goal.linked_account_id ?? "",
    } : { name: "", currency: "", target_amount: "", target_date: "", linked_account_id: "" });
  }, [goal, open, form]);

  async function submit(input: GoalFormInput) {
    try {
      const targetMinor = serializeMoneyMinor(parseMoneyInput(input.target_amount));
      const targetDate = input.target_date || null;
      const linkedAccountId = input.linked_account_id || null;
      if (isEdit && goal) {
        await update.mutateAsync({ name: input.name, targetMinor, targetDate, linkedAccountId, icon: null });
      } else {
        await create.mutateAsync({ name: input.name, currency: input.currency as CurrencyCode, targetMinor, targetDate, linkedAccountId, icon: null });
      }
      toast.success(isEdit ? "Meta actualizada" : "Meta creada");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  const mutation = isEdit ? update : create;
  const matchingAccounts = (accounts.data ?? []).filter((account) => account.currency === (isEdit ? goal?.currency : currency));

  return <ResponsiveDialog description="El monto y la fecha se pueden ajustar cuando quieras." footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="goal-form" type="submit">{mutation.isPending ? "Guardando…" : "Guardar"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title={isEdit ? "Editar meta" : "Nueva meta"}>
    <form className="space-y-5" id="goal-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.name?.message} id="goal-name" label="Nombre"><Input autoFocus id="goal-name" placeholder="Viaje a Japón" {...form.register("name")} /></FormField>
      <FormField error={form.formState.errors.target_amount?.message} id="goal-target" label="Monto objetivo"><Input id="goal-target" inputMode="decimal" placeholder="80,000.00" {...form.register("target_amount")} /></FormField>
      <FormField error={form.formState.errors.currency?.message} id="goal-currency" label="Moneda">
        <Select disabled={isEdit} id="goal-currency" {...form.register("currency")}>
          <option value="">Elige una moneda</option>
          {(currencies.data ?? []).map((item) => <option key={item.code} value={item.code}>{item.code}</option>)}
        </Select>
      </FormField>
      <FormField error={form.formState.errors.target_date?.message} id="goal-date" label="Fecha objetivo (opcional)"><Input id="goal-date" type="date" {...form.register("target_date")} /></FormField>
      {isEdit ? <FormField error={form.formState.errors.linked_account_id?.message} id="goal-account" hint="La cuenta a la que van tus aportaciones y retiros reales." label="Cuenta vinculada (opcional)">
        <Select id="goal-account" {...form.register("linked_account_id")}>
          <option value="">Sin cuenta vinculada</option>
          {matchingAccounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
        </Select>
      </FormField> : null}
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
