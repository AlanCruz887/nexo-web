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
import { useCreateCardPayment } from "@/hooks/use-card-transactions";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { cardPaymentSchema, type CardPaymentInput } from "@/schemas/card-transaction";
import type { AccountBalance, CardSummary } from "@/types/database";

export function CardPaymentForm({ accounts, cards, defaultCardId, onOpenChange, open }: { accounts: AccountBalance[]; cards: CardSummary[]; defaultCardId?: string; onOpenChange: (open: boolean) => void; open: boolean }) {
  const mutation = useCreateCardPayment(); const toast = useToast(); const form = useForm<CardPaymentInput>({ resolver: zodResolver(cardPaymentSchema), defaultValues: defaults(accounts, cards, defaultCardId) }); const cardId = form.watch("card_id"); const card = cards.find((item) => item.id === cardId); const matchingAccounts = accounts.filter((account) => account.is_active && (!card || account.currency === card.currency));
  useEffect(() => { form.reset(defaults(accounts, cards, defaultCardId)); }, [accounts, cards, defaultCardId, form, open]);
  useEffect(() => { if (card && !matchingAccounts.some((account) => account.id === form.getValues("source_account_id"))) form.setValue("source_account_id", matchingAccounts[0]?.id ?? ""); }, [card, form, matchingAccounts]);
  async function submit(input: CardPaymentInput) { try { if (parseMoneyInput(input.amount) <= 0n) { form.setError("amount", { message: "El importe debe ser mayor que cero." }); return; } await mutation.mutateAsync(input); toast.success("Pago de tarjeta registrado"); onOpenChange(false); } catch (error) { form.setError("root", { message: toUserMessage(error) }); } }
  return <ResponsiveDialog description="El dinero saldrá de la cuenta que elijas y reducirá lo que debes en la tarjeta. No contará como gasto." footer={<><Button onClick={() => onOpenChange(false)} variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="card-payment-form" type="submit">{mutation.isPending ? "Registrando…" : "Registrar pago"}</Button></>} onOpenChange={onOpenChange} open={open} size="medium" title="Pagar tarjeta"><form className="space-y-6" id="card-payment-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
    <FormField error={form.formState.errors.amount?.message} id="payment-amount" label="Importe"><Input autoFocus className="h-20 text-4xl font-semibold tabular-nums" id="payment-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} /></FormField>
    <div className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.source_account_id?.message} id="payment-account" label="Cuenta origen"><Select id="payment-account" {...form.register("source_account_id")}>{matchingAccounts.map((account) => <option key={account.id} value={account.id}>{account.name} · {account.currency}</option>)}</Select></FormField><FormField error={form.formState.errors.card_id?.message} id="payment-card" label="Tarjeta"><Select id="payment-card" {...form.register("card_id")}>{cards.filter((item) => item.is_active).map((item) => <option key={item.id} value={item.id}>{item.name} · {item.currency}</option>)}</Select></FormField></div>
    <FormField error={form.formState.errors.occurred_on?.message} id="payment-date" label="Fecha"><Input id="payment-date" type="date" {...form.register("occurred_on")} /></FormField>
    <FormField error={form.formState.errors.notes?.message} id="payment-notes" label="Notas (opcional)"><textarea className="min-h-24 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary/20" id="payment-notes" {...form.register("notes")} /></FormField>{form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
  </form></ResponsiveDialog>;
}
function defaults(accounts: AccountBalance[], cards: CardSummary[], cardId?: string): CardPaymentInput { const card = cards.find((item) => item.id === cardId) ?? cards.find((item) => item.is_active); return { amount: "", source_account_id: accounts.find((account) => account.is_active && account.currency === card?.currency)?.id ?? "", card_id: card?.id ?? "", occurred_on: format(new Date(), "yyyy-MM-dd"), notes: "" }; }
