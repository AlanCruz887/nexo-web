import { zodResolver } from "@hookform/resolvers/zod";
import { format } from "date-fns";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { MoneyValue } from "@/components/money-value";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCreateCard, useUpdateCard } from "@/hooks/use-cards";
import { cn } from "@/lib/cn";
import { minorToDisplay, parseMoneyInput } from "@/lib/money";
import { cardFormSchema, type CardFormInput } from "@/schemas/card";
import type { CardBaselinePolicy, CardSummary, CurrencyCode } from "@/types/database";
import { toUserMessage } from "@/lib/errors";
import { cardThemes } from "@/features/cards/card-utils";

const baselineOptions: Array<{ value: CardBaselinePolicy; title: string; description: string }> = [
  { value: "current_bank_balance", title: "Saldo actual del banco", description: "Nexo toma como punto de partida lo que tu banco muestra hoy." },
  { value: "after_last_statement", title: "Después del último estado", description: "Excluye un estado anterior que ya consideras resuelto." },
  { value: "specific_date", title: "Desde una fecha específica", description: "Solo los eventos impactantes desde esa fecha modifican el saldo." },
];

export function CardFormSheet({ card, baseCurrency, onOpenChange, open }: { card?: CardSummary; baseCurrency: CurrencyCode; onOpenChange: (open: boolean) => void; open: boolean }) {
  const createCard = useCreateCard();
  const updateCard = useUpdateCard(card?.id ?? "missing");
  const toast = useToast();
  const form = useForm<CardFormInput>({ resolver: zodResolver(cardFormSchema), defaultValues: defaults(baseCurrency) });
  const policy = form.watch("baseline_policy");
  const bankBalance = safeMoney(form.watch("bank_balance"));
  const excluded = policy === "after_last_statement" ? safeMoney(form.watch("excluded_statement_amount")) : 0n;
  const comparable = bankBalance - excluded;

  useEffect(() => {
    form.reset(card ? { ...defaults(card.currency), name: card.name, issuer: card.issuer, product_name: card.product_name ?? "", credit_limit: minorToDisplay(BigInt(card.credit_limit_minor)), statement_day: String(card.statement_day), payment_days_after_statement: String(card.payment_days_after_statement), last4: card.last4 ?? "", visual_theme: card.visual_theme } : defaults(baseCurrency));
  }, [baseCurrency, card, form, open]);

  async function submit(input: CardFormInput) {
    try {
      if (parseMoneyInput(input.credit_limit) < 0n || parseMoneyInput(input.bank_balance) < 0n || comparable < 0n) {
        form.setError("root", { message: "Los importes de la tarjeta y el baseline deben ser válidos." }); return;
      }
      if (card) { await updateCard.mutateAsync(input); toast.success("Tarjeta actualizada"); }
      else { await createCard.mutateAsync(input); toast.success("Tarjeta agregada"); }
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }
  const mutation = card ? updateCard : createCard;
  return <ResponsiveDialog description={card ? "Actualiza configuración futura sin reescribir el baseline." : "Configura la tarjeta y su punto de partida financiero."} footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="card-form" type="submit">{mutation.isPending ? "Guardando…" : card ? "Guardar cambios" : "Agregar tarjeta"}</Button></>} onOpenChange={onOpenChange} open={open} size="large" title={card ? "Editar tarjeta" : "Nueva tarjeta"}>
    <form id="card-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}><div className="space-y-8">
      <section className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.name?.message} id="card-name" label="Nombre"><Input autoFocus id="card-name" placeholder="BBVA Oro" {...form.register("name")} /></FormField><FormField error={form.formState.errors.issuer?.message} id="card-issuer" label="Emisor"><Input id="card-issuer" placeholder="BBVA" {...form.register("issuer")} /></FormField><FormField error={form.formState.errors.product_name?.message} id="card-product" label="Producto"><Input id="card-product" placeholder="Oro" {...form.register("product_name")} /></FormField><FormField error={form.formState.errors.last4?.message} id="card-last4" label="Últimos 4"><Input id="card-last4" inputMode="numeric" maxLength={4} placeholder="4821" {...form.register("last4")} /></FormField></section>
      <section className="grid gap-5 rounded-2xl bg-surface-secondary p-5 sm:grid-cols-2"><FormField error={form.formState.errors.credit_limit?.message} id="card-limit" label="Límite de crédito"><Input id="card-limit" inputMode="decimal" placeholder="100000.00" {...form.register("credit_limit")} /></FormField>{!card ? <FormField error={form.formState.errors.currency?.message} id="card-currency" label="Moneda"><Select id="card-currency" {...form.register("currency")}><option>MXN</option><option>USD</option><option>EUR</option></Select></FormField> : null}<FormField error={form.formState.errors.statement_day?.message} hint="Si no existe, se usa el último día del mes." id="card-statement-day" label="Día de corte"><Input id="card-statement-day" inputMode="numeric" {...form.register("statement_day")} /></FormField><FormField error={form.formState.errors.payment_days_after_statement?.message} id="card-payment-days" label="Días después del corte"><Input id="card-payment-days" inputMode="numeric" {...form.register("payment_days_after_statement")} /></FormField><FormField error={form.formState.errors.visual_theme?.message} id="card-theme" label="Tema visual"><Select id="card-theme" {...form.register("visual_theme")}>{Object.entries(cardThemes).map(([value, theme]) => <option key={value} value={value}>{theme.label}</option>)}</Select></FormField></section>
      {!card ? <section><h3 className="text-lg font-semibold">¿Desde cuándo quieres llevar esta tarjeta en Nexo?</h3><div className="mt-4 grid gap-3 sm:grid-cols-3">{baselineOptions.map((option) => <button className={cn("rounded-2xl border p-4 text-left transition", policy === option.value ? "border-primary bg-primary-soft" : "border-border hover:border-primary/30")} key={option.value} onClick={() => form.setValue("baseline_policy", option.value, { shouldValidate: true })} type="button"><span className="text-sm font-semibold">{option.title}</span><span className="mt-1 block text-xs leading-relaxed text-muted-foreground">{option.description}</span></button>)}</div><div className="mt-5 grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.baseline_date?.message} id="baseline-date" label={policy === "specific_date" ? "Fecha de inicio" : "Fecha del saldo"}><Input id="baseline-date" type="date" {...form.register("baseline_date")} /></FormField><FormField error={form.formState.errors.bank_balance?.message} id="bank-balance" label="Saldo utilizado actual del banco"><Input id="bank-balance" inputMode="decimal" {...form.register("bank_balance")} /></FormField>{policy === "after_last_statement" ? <FormField error={form.formState.errors.excluded_statement_amount?.message} id="excluded-statement" label="Estado anterior a excluir"><Input id="excluded-statement" inputMode="decimal" {...form.register("excluded_statement_amount")} /></FormField> : null}<FormField error={form.formState.errors.baseline_notes?.message} id="baseline-notes" label="Notas"><Input id="baseline-notes" {...form.register("baseline_notes")} /></FormField></div>{policy === "after_last_statement" ? <div className="mt-5 rounded-2xl border border-border p-5"><p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Resumen del baseline</p><div className="mt-3 flex justify-between text-sm"><span>Saldo banco</span><MoneyValue amount={bankBalance} currency={form.watch("currency")} /></div><div className="mt-2 flex justify-between text-sm"><span>Menos estado anterior</span><MoneyValue amount={-excluded} currency={form.watch("currency")} sign="always" /></div><div className="mt-3 flex justify-between border-t border-border pt-3 font-semibold"><span>Saldo inicial en Nexo</span><MoneyValue amount={comparable} currency={form.watch("currency")} /></div></div> : null}</section> : null}
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </div></form>
  </ResponsiveDialog>;
}

function defaults(currency: CurrencyCode): CardFormInput { return { name: "", issuer: "", product_name: "", currency, credit_limit: "0.00", statement_day: "9", payment_days_after_statement: "20", last4: "", visual_theme: "generic", baseline_policy: "current_bank_balance", baseline_date: format(new Date(), "yyyy-MM-dd"), bank_balance: "0.00", excluded_statement_amount: "", baseline_notes: "" }; }
function safeMoney(value: string): bigint { try { return parseMoneyInput(value || "0"); } catch { return 0n; } }
