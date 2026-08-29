import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { MoneyValue } from "@/components/money-value";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { useToast } from "@/components/toast";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useImportHistoricalInstallmentPlan } from "@/hooks/use-installments";
import { useCategories } from "@/hooks/use-movements";
import { toUserMessage } from "@/lib/errors";
import { minorToDisplay, parseMoneyInput } from "@/lib/money";
import { historicalInstallmentSchema, historicalPaidBeforeCount, resolveHistoricalInstallmentCount, standardInstallmentTerms, type HistoricalInstallmentInput } from "@/schemas/historical-installment";
import type { CardSummary } from "@/types/database";
import { PurchaseSplitFields } from "@/features/people/purchase-split-fields";
import { resolvePurchaseSplit } from "@/lib/purchase-split";

export function HistoricalInstallmentForm({ cards, defaultCardId, onOpenChange, open }: { cards: CardSummary[]; defaultCardId?: string; onOpenChange: (open: boolean) => void; open: boolean }) {
  const mutation = useImportHistoricalInstallmentPlan(); const categories = useCategories(); const toast = useToast();
  const form = useForm<HistoricalInstallmentInput>({ resolver: zodResolver(historicalInstallmentSchema), defaultValues: defaults(cards, defaultCardId) });
  const cardId = form.watch("card_id"); const installmentOption = form.watch("installment_count"); const customCount = form.watch("custom_installment_count"); const original = form.watch("original_amount"); const monthly = form.watch("installment_amount"); const current = form.watch("current_installment_number"); const principalPaid = form.watch("principal_paid");
  const count = resolveHistoricalInstallmentCount({ installment_count: installmentOption, custom_installment_count: customCount }); const paidBefore = historicalPaidBeforeCount(current); const selectedCard = cards.find((card) => card.id === cardId);
  let remaining = 0n; try { remaining = parseMoneyInput(original) - parseMoneyInput(principalPaid); } catch { remaining = 0n; }
  useEffect(() => { form.reset(defaults(cards, defaultCardId)); }, [cards, defaultCardId, form, open]);
  useEffect(() => {
    if (!Number.isInteger(count) || count < 2 || paidBefore < 0) return;
    try {
      const originalMinor = parseMoneyInput(original); const monthlyMinor = parseMoneyInput(monthly);
      if (!form.formState.dirtyFields.principal_paid) form.setValue("principal_paid", minorToDisplay((originalMinor / BigInt(count)) * BigInt(paidBefore)));
      if (!form.formState.dirtyFields.reported_paid_amount) form.setValue("reported_paid_amount", minorToDisplay(monthlyMinor * BigInt(paidBefore)));
    } catch { /* wait for complete money inputs */ }
  }, [count, form, monthly, original, paidBefore]);
  useEffect(() => { if (selectedCard && !form.formState.dirtyFields.next_statement_date) form.setValue("next_statement_date", selectedCard.next_statement_date); }, [form, selectedCard]);

  async function submit(input: HistoricalInstallmentInput) {
    try {
      const originalMinor = parseMoneyInput(input.original_amount); const monthlyMinor = parseMoneyInput(input.installment_amount); const principalMinor = parseMoneyInput(input.principal_paid); const reportedMinor = parseMoneyInput(input.reported_paid_amount);
      if (originalMinor <= 0n || monthlyMinor <= 0n) { form.setError("root", { message: "El importe original y la mensualidad deben ser mayores que cero." }); return; }
      if (principalMinor < 0n || principalMinor >= originalMinor) { form.setError("principal_paid", { message: "El importe original ya pagado debe ser menor que el importe total." }); return; }
      if (reportedMinor < 0n) { form.setError("reported_paid_amount", { message: "El dinero reportado no puede ser negativo." }); return; }
      if (historicalPaidBeforeCount(input.current_installment_number) === 0 && principalMinor !== 0n) { form.setError("principal_paid", { message: "Si vas en la primera mensualidad, el importe ya pagado debe ser cero." }); return; }
      resolvePurchaseSplit({ ...input, amount: minorToDisplay(originalMinor - principalMinor) });
      await mutation.mutateAsync(input); toast.success("MSI existente agregado"); onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  return <ResponsiveDialog description="Agrega un plan que comenzó antes de usar Nexo. No crearemos compras ni pagos anteriores." footer={<><Button onClick={() => onOpenChange(false)} variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="historical-installment-form" type="submit">{mutation.isPending ? "Agregando…" : "Agregar MSI"}</Button></>} onOpenChange={onOpenChange} open={open} size="large" title="Agregar MSI existente">
    <form className="space-y-7" id="historical-installment-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <div className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.description?.message} id="historical-description" label="Nombre / descripción"><Input autoFocus id="historical-description" placeholder="iPhone" {...form.register("description")} /></FormField><FormField error={form.formState.errors.card_id?.message} id="historical-card" label="Tarjeta"><Select id="historical-card" {...form.register("card_id")}>{cards.filter((card) => card.is_active).map((card) => <option key={card.id} value={card.id}>{card.name} · {card.currency}</option>)}</Select></FormField></div>
      <div className="grid gap-5 sm:grid-cols-3"><FormField error={form.formState.errors.original_amount?.message} id="historical-original" label="Importe original"><Input id="historical-original" inputMode="decimal" placeholder="12000.00" {...form.register("original_amount")} /></FormField><FormField error={form.formState.errors.installment_count?.message} id="historical-term" label="Mensualidades totales"><Select id="historical-term" {...form.register("installment_count")}>{standardInstallmentTerms.map((term) => <option key={term} value={term}>{term} meses</option>)}<option value="custom">Personalizado</option></Select></FormField>{installmentOption === "custom" ? <FormField error={form.formState.errors.custom_installment_count?.message} hint="Entre 2 y 60." id="historical-custom-term" label="Número de meses"><Input id="historical-custom-term" inputMode="numeric" min={2} max={60} type="number" {...form.register("custom_installment_count")} /></FormField> : <FormField error={form.formState.errors.installment_amount?.message} id="historical-monthly" label="Mensualidad real del banco"><Input id="historical-monthly" inputMode="decimal" placeholder="1000.00" {...form.register("installment_amount")} /></FormField>}</div>
      {installmentOption === "custom" ? <FormField error={form.formState.errors.installment_amount?.message} id="historical-monthly-custom" label="Mensualidad real del banco"><Input id="historical-monthly-custom" inputMode="decimal" placeholder="1000.00" {...form.register("installment_amount")} /></FormField> : null}
      <div className="grid gap-5 sm:grid-cols-3"><FormField error={form.formState.errors.original_purchase_date?.message} id="historical-purchase-date" label="Fecha original de compra"><Input id="historical-purchase-date" type="date" {...form.register("original_purchase_date")} /></FormField><FormField error={form.formState.errors.current_installment_number?.message} hint={`Se marcarán ${paidBefore} como pagadas antes de Nexo.`} id="historical-current" label="Voy en la mensualidad"><Input id="historical-current" inputMode="numeric" min={1} max={Number.isFinite(count) ? count : 60} type="number" {...form.register("current_installment_number")} /></FormField><FormField error={form.formState.errors.next_statement_date?.message} hint="Fecha del estado que contendrá la mensualidad actual." id="historical-next-statement" label="Próximo estado"><Input id="historical-next-statement" type="date" {...form.register("next_statement_date")} /></FormField></div>
      <div className="rounded-2xl bg-surface-secondary p-5"><p className="text-sm font-semibold">Lo que ya pagaste</p><div className="mt-4 grid gap-5 sm:grid-cols-3"><FormField hint="Se calcula a partir de la mensualidad actual." id="historical-paid-count" label="Mensualidades pagadas"><Input disabled id="historical-paid-count" value={paidBefore} /></FormField><FormField error={form.formState.errors.reported_paid_amount?.message} hint="Usa el total real que muestra tu banco." id="historical-reported-paid" label="Total pagado"><Input id="historical-reported-paid" inputMode="decimal" {...form.register("reported_paid_amount")} /></FormField><FormField error={form.formState.errors.principal_paid?.message} hint="Parte del importe original que ya quedó cubierta." id="historical-principal-paid" label="Importe original ya pagado"><Input id="historical-principal-paid" inputMode="decimal" {...form.register("principal_paid")} /></FormField></div>{remaining >= 0n && selectedCard ? <p className="mt-4 text-sm text-muted-foreground">Todavía debes <MoneyValue amount={remaining} className="font-semibold text-foreground" currency={selectedCard.currency} size="sm" /></p> : null}</div>
      <PurchaseSplitFields amount={minorToDisplay(remaining > 0n ? remaining : 0n)} allocations={form.watch("allocations")} onAllocations={(value) => form.setValue("allocations", value, { shouldValidate: true })} onPersonalAmount={(value) => form.setValue("personal_amount", value, { shouldValidate: true })} onScope={(value) => form.setValue("purchase_scope", value, { shouldValidate: true })} personalAmount={form.watch("personal_amount")} scope={form.watch("purchase_scope")} />
      <div><p className="text-sm font-semibold">¿Lo que todavía debes de este MSI ya está incluido en el saldo de tu tarjeta?</p><div className="mt-3 grid gap-3 sm:grid-cols-2"><InclusionOption checked={form.watch("opening_balance_inclusion") === "included"} description="Nexo no lo sumará otra vez." onClick={() => form.setValue("opening_balance_inclusion", "included", { shouldDirty: true })} title="Sí, ya está incluido" /><InclusionOption checked={form.watch("opening_balance_inclusion") === "excluded"} description="Nexo agregará únicamente lo que todavía debes." onClick={() => form.setValue("opening_balance_inclusion", "excluded", { shouldDirty: true })} title="No, falta agregarlo" /></div></div>
      <div className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.category_id?.message} id="historical-category" label="Categoría"><Select id="historical-category" {...form.register("category_id")}>{categories.data?.filter((item) => item.kind !== "income").map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select></FormField><FormField error={form.formState.errors.notes?.message} id="historical-notes" label="Notas (opcional)"><textarea className="min-h-24 w-full rounded-xl border border-border bg-surface p-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary/20" id="historical-notes" {...form.register("notes")} /></FormField></div>
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}

function InclusionOption({ checked, description, onClick, title }: { checked: boolean; description: string; onClick: () => void; title: string }) { return <button aria-pressed={checked} className={`min-h-24 rounded-2xl border p-4 text-left transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 ${checked ? "border-primary bg-primary-soft" : "border-border bg-surface hover:border-primary/30"}`} onClick={onClick} type="button"><span className="text-sm font-semibold">{title}</span><span className="mt-1 block text-xs leading-relaxed text-muted-foreground">{description}</span></button>; }

function defaults(cards: CardSummary[], cardId?: string): HistoricalInstallmentInput {
  const card = cards.find((item) => item.id === cardId) ?? cards.find((item) => item.is_active);
  return { description: "", card_id: card?.id ?? "", original_amount: "", installment_count: "12", custom_installment_count: "", installment_amount: "", original_purchase_date: card?.baseline_date ?? "", current_installment_number: "1", reported_paid_amount: "0", principal_paid: "0", next_statement_date: card?.next_statement_date ?? "", category_id: "other_expense", notes: "", opening_balance_inclusion: "included", purchase_scope: "self", personal_amount: "", allocations: [] };
}
