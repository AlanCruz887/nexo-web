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
import { useCardTransactions, useCreateCardRefund } from "@/hooks/use-card-transactions";
import { useCategories } from "@/hooks/use-movements";
import { toUserMessage } from "@/lib/errors";
import { parseMoneyInput } from "@/lib/money";
import { cardRefundSchema, type CardRefundInput } from "@/schemas/card-transaction";
import type { CardSummary } from "@/types/database";

export function CardRefundForm({ cards, defaultCardId, onOpenChange, open }: { cards: CardSummary[]; defaultCardId?: string; onOpenChange: (open: boolean) => void; open: boolean }) {
  const mutation = useCreateCardRefund(); const categories = useCategories(); const toast = useToast(); const form = useForm<CardRefundInput>({ resolver: zodResolver(cardRefundSchema), defaultValues: defaults(cards, defaultCardId) }); const cardId = form.watch("card_id"); const purchases = useCardTransactions(cardId, "card_charge");
  useEffect(() => { form.reset(defaults(cards, defaultCardId)); }, [cards, defaultCardId, form, open]);
  async function submit(input: CardRefundInput) { try { if (parseMoneyInput(input.amount) <= 0n) { form.setError("amount", { message: "El importe debe ser mayor que cero." }); return; } await mutation.mutateAsync(input); toast.success("Reembolso registrado"); onOpenChange(false); } catch (error) { form.setError("root", { message: toUserMessage(error) }); } }
  return <ResponsiveDialog description="El reembolso reducirá el saldo de la tarjeta y el gasto de la compra. No contará como ingreso." footer={<><Button onClick={() => onOpenChange(false)} variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="card-refund-form" type="submit">{mutation.isPending ? "Registrando…" : "Registrar reembolso"}</Button></>} onOpenChange={onOpenChange} open={open} size="medium" title="Registrar reembolso"><form className="space-y-6" id="card-refund-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
    <FormField error={form.formState.errors.amount?.message} id="refund-amount" label="Importe"><Input autoFocus className="h-20 text-4xl font-semibold tabular-nums" id="refund-amount" inputMode="decimal" placeholder="0.00" {...form.register("amount")} /></FormField>
    <div className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.card_id?.message} id="refund-card" label="Tarjeta"><Select id="refund-card" {...form.register("card_id")}>{cards.filter((item) => item.is_active).map((item) => <option key={item.id} value={item.id}>{item.name} · {item.currency}</option>)}</Select></FormField><FormField id="refund-date" label="Fecha"><Input id="refund-date" type="date" {...form.register("occurred_on")} /></FormField></div>
    <FormField hint="Por ahora, las compras a meses se corrigen desde el detalle de su plan." id="refund-original" label="Compra relacionada (opcional)"><Select id="refund-original" {...form.register("original_event_id")}><option value="">Sin relacionar</option>{purchases.data?.filter((purchase) => !purchase.installment_plan_id).map((purchase) => <option key={purchase.event_id} value={purchase.event_id}>{purchase.description} · {purchase.occurred_on}</option>)}</Select></FormField>
    <div className="grid gap-5 sm:grid-cols-2"><FormField error={form.formState.errors.description?.message} id="refund-description" label="Descripción"><Input id="refund-description" placeholder="Devolución parcial" {...form.register("description")} /></FormField><FormField id="refund-category" label="Categoría (opcional)"><Select id="refund-category" {...form.register("category_id")}><option value="">Sin categoría</option>{categories.data?.filter((item) => item.kind !== "income").map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select></FormField></div>
    <FormField error={form.formState.errors.notes?.message} id="refund-notes" label="Notas (opcional)"><textarea className="min-h-24 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary/20" id="refund-notes" {...form.register("notes")} /></FormField>{form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
  </form></ResponsiveDialog>;
}
function defaults(cards: CardSummary[], cardId?: string): CardRefundInput { return { amount: "", card_id: cardId ?? cards.find((item) => item.is_active)?.id ?? "", occurred_on: format(new Date(), "yyyy-MM-dd"), description: "", category_id: "", original_event_id: "", notes: "" }; }
