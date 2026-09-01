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
import { useWithdrawFromGoal } from "@/hooks/use-goals";
import { cn } from "@/lib/cn";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { goalWithdrawalSchema, type GoalWithdrawalInput } from "@/schemas/goal";
import type { GoalBalance } from "@/types/database";

export function GoalWithdrawDialog({ goal, onOpenChange, open }: { goal: GoalBalance; onOpenChange: (open: boolean) => void; open: boolean }) {
  const accounts = useAccounts();
  const withdraw = useWithdrawFromGoal();
  const toast = useToast();
  const form = useForm<GoalWithdrawalInput>({
    resolver: zodResolver(goalWithdrawalSchema),
    defaultValues: { amount: "", account_id: "", move_real_money: false, destination_account_id: "", occurred_on: new Date().toISOString().slice(0, 10), notes: "" },
  });
  useEffect(() => { if (open) form.reset({ amount: "", account_id: "", move_real_money: false, destination_account_id: "", occurred_on: new Date().toISOString().slice(0, 10), notes: "" }); }, [open, form]);

  const moveRealMoney = form.watch("move_real_money");
  const matchingAccounts = (accounts.data ?? []).filter((account) => account.currency === goal.currency && account.is_active);

  async function submit(input: GoalWithdrawalInput) {
    try {
      await withdraw.mutateAsync({
        goalId: goal.id, amountMinor: serializeMoneyMinor(parseMoneyInput(input.amount)),
        accountId: input.move_real_money ? null : (input.account_id || null),
        moveRealMoney: input.move_real_money,
        destinationAccountId: input.move_real_money ? (input.destination_account_id || null) : null,
        occurredOn: input.occurred_on, notes: input.notes || null,
      });
      toast.success("Dinero retirado");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  return <ResponsiveDialog description={`Retira dinero de "${goal.name}".`} footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={withdraw.isPending} form="goal-withdraw-form" type="submit">{withdraw.isPending ? "Guardando…" : "Retirar dinero"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title="Retirar dinero">
    <form className="space-y-5" id="goal-withdraw-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.amount?.message} id="withdraw-amount" label="Monto"><Input autoFocus id="withdraw-amount" inputMode="decimal" placeholder="3,000.00" {...form.register("amount")} /></FormField>
      {goal.linked_account_id ? (
        <div className="grid grid-cols-2 gap-2">
          <button className={cn("rounded-xl border px-3 py-3 text-left text-sm transition", !moveRealMoney ? "border-primary bg-primary-soft text-primary-strong" : "border-border text-muted-foreground")} onClick={() => form.setValue("move_real_money", false)} type="button">
            <p className="font-semibold">Solo liberar</p><p className="mt-0.5 text-xs">Deja de apartarse, sin mover dinero.</p>
          </button>
          <button className={cn("rounded-xl border px-3 py-3 text-left text-sm transition", moveRealMoney ? "border-primary bg-primary-soft text-primary-strong" : "border-border text-muted-foreground")} onClick={() => form.setValue("move_real_money", true)} type="button">
            <p className="font-semibold">Mover dinero</p><p className="mt-0.5 text-xs">Transfiere de verdad a otra cuenta.</p>
          </button>
        </div>
      ) : null}
      {moveRealMoney ? (
        <FormField error={form.formState.errors.destination_account_id?.message} id="withdraw-destination" label="Cuenta de destino">
          <Select id="withdraw-destination" {...form.register("destination_account_id")}>
            <option value="">Elige una cuenta</option>
            {matchingAccounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
          </Select>
        </FormField>
      ) : (
        <FormField hint="Si no eliges una, se libera de la cuenta que más tiempo llevaba respaldando esta meta." id="withdraw-account" label="Cuenta (opcional)">
          <Select id="withdraw-account" {...form.register("account_id")}>
            <option value="">Automático</option>
            {matchingAccounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
          </Select>
        </FormField>
      )}
      <FormField error={form.formState.errors.occurred_on?.message} id="withdraw-date" label="Fecha"><Input id="withdraw-date" type="date" {...form.register("occurred_on")} /></FormField>
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
