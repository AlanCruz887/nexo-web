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
import { useContactPeriod, useCreatePersonPayment } from "@/hooks/use-contacts";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { previewPersonPayment } from "@/lib/person-payment-preview";
import { personPaymentSchema, type PersonPaymentInput } from "@/schemas/contact";
import type { AccountBalance, ContactSummary, CurrencyCode } from "@/types/database";

export function PersonPaymentForm({ accounts, contact, onOpenChange, open }: { accounts: AccountBalance[]; contact: ContactSummary; onOpenChange: (open: boolean) => void; open: boolean }) {
  const create = useCreatePersonPayment(contact.id); const period = useContactPeriod(contact.id); const toast = useToast();
  const activeAccounts = accounts.filter((item) => item.is_active && contact.balances.some((balance) => balance.currency === item.currency && BigInt(balance.outstanding_minor) > 0n));
  const form = useForm<PersonPaymentInput>({ resolver: zodResolver(personPaymentSchema), defaultValues: { amount: "", account_id: activeAccounts[0]?.id ?? "", occurred_on: format(new Date(), "yyyy-MM-dd"), notes: "" } });
  const account = accounts.find((item) => item.id === form.watch("account_id"));
  const currentPeriod = period.data?.periods.find((item) => item.currency === account?.currency);
  const balance = contact.balances.find((item) => item.currency === account?.currency);
  const dueMinor = BigInt(currentPeriod?.remaining_minor ?? balance?.outstanding_minor ?? "0");
  const totalMinor = BigInt(currentPeriod?.total_outstanding_minor ?? balance?.outstanding_minor ?? "0");
  const amountInput = form.watch("amount");
  let preview: ReturnType<typeof previewPersonPayment> | undefined;
  try { const entered = parseMoneyInput(amountInput || "0"); if (entered > 0n) preview = previewPersonPayment(dueMinor, totalMinor, entered); } catch { preview = undefined; }
  async function submit(input: PersonPaymentInput) { try { if (parseMoneyInput(input.amount) <= 0n) { form.setError("amount", { message: "El importe debe ser mayor que cero." }); return; } await create.mutateAsync(input); toast.success("Pago recibido registrado"); form.reset(); onOpenChange(false); } catch (error) { form.setError("root", { message: toUserMessage(error) }); } }
  return <ResponsiveDialog description="El dinero entrará a la cuenta elegida y reducirá lo que te debe. No se contará como ingreso." footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={create.isPending || activeAccounts.length === 0} form="person-payment-form" type="submit">{create.isPending ? "Guardando…" : "Registrar pago"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title={`Pago de ${contact.name}`}>
    <form className="space-y-5" id="person-payment-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      {account ? <div className="grid grid-cols-2 gap-4 rounded-xl bg-primary-soft p-4"><div><p className="text-xs text-muted-foreground">{contact.name} te debe</p><MoneyValue amount={totalMinor} currency={account.currency} size="lg" /></div><div><p className="text-xs text-muted-foreground">A pagar este periodo</p><MoneyValue amount={dueMinor} currency={account.currency} size="lg" /></div></div> : null}
      <FormField error={form.formState.errors.amount?.message} id="person-payment-amount" label="Pago"><Input autoFocus id="person-payment-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} /></FormField>
      <FormField error={form.formState.errors.account_id?.message} id="person-payment-account" label="Cuenta donde lo recibí"><Select id="person-payment-account" {...form.register("account_id")}><option value="">Elige una cuenta</option>{activeAccounts.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.currency}</option>)}</Select></FormField>
      <FormField error={form.formState.errors.occurred_on?.message} id="person-payment-date" label="Fecha"><Input id="person-payment-date" type="date" {...form.register("occurred_on")} /></FormField>
      <FormField error={form.formState.errors.notes?.message} id="person-payment-notes" label="Notas (opcional)"><textarea className="min-h-20 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm" id="person-payment-notes" {...form.register("notes")} /></FormField>
      {account && preview ? <PaymentPreview currency={account.currency} dueMinor={dueMinor} preview={preview} /> : null}
      {activeAccounts.length === 0 ? <p className="text-sm text-warning">Necesitas una cuenta activa en la misma moneda que la deuda.</p> : null}{form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}

function PaymentPreview({ currency, dueMinor, preview }: { currency: CurrencyCode; dueMinor: bigint; preview: ReturnType<typeof previewPersonPayment> }) {
  if (preview.missingMinor > 0n) return <div className="rounded-xl border border-border bg-surface-secondary p-4"><p className="text-sm font-medium">Pago parcial</p><div className="mt-3 grid grid-cols-2 gap-4"><div><p className="text-xs text-muted-foreground">Aplicado</p><MoneyValue amount={preview.appliedToPeriodMinor} currency={currency} size="sm" /></div><div><p className="text-xs text-muted-foreground">Seguirá faltando</p><MoneyValue amount={preview.missingMinor} className="text-warning" currency={currency} size="sm" /></div></div></div>;
  if (preview.creditMinor > 0n) return <div className="rounded-xl border border-border bg-surface-secondary p-4"><p className="text-sm font-medium">{dueMinor > 0n ? "Periodo pagado" : "Este pago se guardará como saldo a favor"}</p><div className="mt-3 grid grid-cols-2 gap-4"><div><p className="text-xs text-muted-foreground">Aplicado</p><MoneyValue amount={preview.appliedToPeriodMinor} currency={currency} size="sm" /></div><div><p className="text-xs text-muted-foreground">Saldo a favor</p><MoneyValue amount={preview.creditMinor} className="text-primary-strong" currency={currency} size="sm" /></div></div></div>;
  if (preview.advancedMinor > 0n) return <div className="rounded-xl border border-border bg-surface-secondary p-4"><p className="text-sm font-medium">Periodo pagado</p><p className="mt-1 text-xs text-muted-foreground">El resto se aplica a tus próximas compras o mensualidades con esta persona.</p><div className="mt-3 grid grid-cols-2 gap-4"><div><p className="text-xs text-muted-foreground">Este periodo</p><MoneyValue amount={preview.appliedToPeriodMinor} currency={currency} size="sm" /></div><div><p className="text-xs text-muted-foreground">Adelantado</p><MoneyValue amount={preview.advancedMinor} currency={currency} size="sm" /></div></div></div>;
  return <div className="rounded-xl border border-border bg-surface-secondary p-4"><p className="text-sm font-medium">Periodo pagado</p></div>;
}
