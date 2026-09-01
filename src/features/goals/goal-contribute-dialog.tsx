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
import { useContributeToGoal } from "@/hooks/use-goals";
import { cn } from "@/lib/cn";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { goalContributionSchema, type GoalContributionInput } from "@/schemas/goal";
import type { GoalBalance } from "@/types/database";

export function GoalContributeDialog({ goal, onOpenChange, open }: { goal: GoalBalance; onOpenChange: (open: boolean) => void; open: boolean }) {
  const accounts = useAccounts();
  const contribute = useContributeToGoal();
  const toast = useToast();
  const form = useForm<GoalContributionInput>({
    resolver: zodResolver(goalContributionSchema),
    defaultValues: { amount: "", account_id: "", move_real_money: false, occurred_on: new Date().toISOString().slice(0, 10), notes: "" },
  });
  useEffect(() => { if (open) form.reset({ amount: "", account_id: "", move_real_money: false, occurred_on: new Date().toISOString().slice(0, 10), notes: "" }); }, [open, form]);

  const moveRealMoney = form.watch("move_real_money");
  const matchingAccounts = (accounts.data ?? []).filter((account) => account.currency === goal.currency && account.is_active);

  async function submit(input: GoalContributionInput) {
    try {
      await contribute.mutateAsync({
        goalId: goal.id, amountMinor: serializeMoneyMinor(parseMoneyInput(input.amount)),
        sourceAccountId: input.account_id, moveRealMoney: input.move_real_money,
        occurredOn: input.occurred_on, notes: input.notes || null,
      });
      toast.success("Dinero apartado");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  return <ResponsiveDialog description={`Aparta dinero para "${goal.name}".`} footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={contribute.isPending} form="goal-contribute-form" type="submit">{contribute.isPending ? "Guardando…" : "Apartar dinero"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title="Apartar dinero">
    <form className="space-y-5" id="goal-contribute-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.amount?.message} id="contribute-amount" label="Monto"><Input autoFocus id="contribute-amount" inputMode="decimal" placeholder="5,000.00" {...form.register("amount")} /></FormField>
      <FormField error={form.formState.errors.account_id?.message} id="contribute-account" label="Cuenta">
        <Select id="contribute-account" {...form.register("account_id")}>
          <option value="">Elige una cuenta</option>
          {matchingAccounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
        </Select>
      </FormField>
      {goal.linked_account_id ? (
        <div className="grid grid-cols-2 gap-2">
          <button className={cn("rounded-xl border px-3 py-3 text-left text-sm transition", !moveRealMoney ? "border-primary bg-primary-soft text-primary-strong" : "border-border text-muted-foreground")} onClick={() => form.setValue("move_real_money", false)} type="button">
            <p className="font-semibold">Solo apartar</p><p className="mt-0.5 text-xs">El dinero se queda donde está, solo se etiqueta.</p>
          </button>
          <button className={cn("rounded-xl border px-3 py-3 text-left text-sm transition", moveRealMoney ? "border-primary bg-primary-soft text-primary-strong" : "border-border text-muted-foreground")} onClick={() => form.setValue("move_real_money", true)} type="button">
            <p className="font-semibold">Mover dinero</p><p className="mt-0.5 text-xs">Transfiere de verdad a la cuenta vinculada.</p>
          </button>
        </div>
      ) : null}
      <FormField error={form.formState.errors.occurred_on?.message} id="contribute-date" label="Fecha"><Input id="contribute-date" type="date" {...form.register("occurred_on")} /></FormField>
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
