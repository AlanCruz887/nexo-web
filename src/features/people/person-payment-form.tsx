import { zodResolver } from "@hookform/resolvers/zod";
import { format } from "date-fns";
import { useForm } from "react-hook-form";
import { FormField } from "@/components/form-field";
import { MoneyValue } from "@/components/money-value";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCreatePersonPayment } from "@/hooks/use-contacts";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { personPaymentSchema, type PersonPaymentInput } from "@/schemas/contact";
import type { AccountBalance, ContactSummary } from "@/types/database";

export function PersonPaymentForm({ accounts, contact, onOpenChange, open }: { accounts: AccountBalance[]; contact: ContactSummary; onOpenChange: (open: boolean) => void; open: boolean }) {
  const create = useCreatePersonPayment(contact.id); const toast = useToast();
  const activeAccounts = accounts.filter((item) => item.is_active && contact.balances.some((balance) => balance.currency === item.currency && BigInt(balance.outstanding_minor) > 0n));
  const form = useForm<PersonPaymentInput>({ resolver: zodResolver(personPaymentSchema), defaultValues: { amount: "", account_id: activeAccounts[0]?.id ?? "", occurred_on: format(new Date(), "yyyy-MM-dd"), notes: "" } });
  const account = accounts.find((item) => item.id === form.watch("account_id")); const balance = contact.balances.find((item) => item.currency === account?.currency);
  async function submit(input: PersonPaymentInput) { try { if (parseMoneyInput(input.amount) <= 0n) { form.setError("amount", { message: "El importe debe ser mayor que cero." }); return; } await create.mutateAsync(input); toast.success("Pago recibido registrado"); form.reset(); onOpenChange(false); } catch (error) { form.setError("root", { message: toUserMessage(error) }); } }
  return <ResponsiveDialog description="El dinero entrará a la cuenta elegida y reducirá lo que te debe. No se contará como ingreso." footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={create.isPending || activeAccounts.length === 0} form="person-payment-form" type="submit">{create.isPending ? "Guardando…" : "Registrar pago"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title={`Pago de ${contact.name}`}>
    <form className="space-y-5" id="person-payment-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      {account && balance ? <div className="rounded-xl bg-primary-soft p-4"><p className="text-xs text-muted-foreground">Pendiente en {account.currency}</p><MoneyValue amount={balance.outstanding_minor} currency={account.currency} size="lg" /></div> : null}
      <FormField error={form.formState.errors.amount?.message} id="person-payment-amount" label="Importe"><Input autoFocus id="person-payment-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} /></FormField>
      <FormField error={form.formState.errors.account_id?.message} id="person-payment-account" label="Cuenta que recibe"><Select id="person-payment-account" {...form.register("account_id")}><option value="">Elige una cuenta</option>{activeAccounts.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.currency}</option>)}</Select></FormField>
      <FormField error={form.formState.errors.occurred_on?.message} id="person-payment-date" label="Fecha"><Input id="person-payment-date" type="date" {...form.register("occurred_on")} /></FormField>
      <FormField error={form.formState.errors.notes?.message} id="person-payment-notes" label="Notas (opcional)"><textarea className="min-h-20 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm" id="person-payment-notes" {...form.register("notes")} /></FormField>
      {activeAccounts.length === 0 ? <p className="text-sm text-warning">Necesitas una cuenta activa en la misma moneda que la deuda.</p> : null}{form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
