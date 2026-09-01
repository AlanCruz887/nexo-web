import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { FormField } from "@/components/form-field";
import { MoneyValue } from "@/components/money-value";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useAccounts } from "@/hooks/use-accounts";
import { useCards } from "@/hooks/use-cards";
import { useConfirmRecurringOccurrence } from "@/hooks/use-recurring-rules";
import { formatFinancialDate } from "@/lib/dates";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import { confirmOccurrenceSchema, type ConfirmOccurrenceInput } from "@/schemas/recurring-rule";
import type { RecurringOccurrenceCandidate } from "@/types/database";

export function ConfirmOccurrenceDialog({
  candidate, onOpenChange, open,
}: {
  candidate: RecurringOccurrenceCandidate | null; onOpenChange: (open: boolean) => void; open: boolean;
}) {
  const accounts = useAccounts();
  const cards = useCards();
  const confirm = useConfirmRecurringOccurrence();
  const toast = useToast();
  const form = useForm<ConfirmOccurrenceInput>({
    resolver: zodResolver(confirmOccurrenceSchema),
    defaultValues: { actualAmount: "", actualDate: "", sourceType: "default", accountId: null, cardId: null, notes: null },
  });
  const sourceType = form.watch("sourceType");
  const hasDefaultSource = Boolean(candidate?.account_id || candidate?.card_id);

  useEffect(() => {
    if (!open || !candidate) return;
    form.reset({
      actualAmount: (Number(candidate.amount_minor) / 100).toFixed(2),
      actualDate: candidate.occurred_on,
      sourceType: hasDefaultSource ? "default" : "account",
      accountId: null, cardId: null, notes: null,
    });
  }, [candidate, open, hasDefaultSource, form]);

  if (!candidate) return null;

  async function submit(input: ConfirmOccurrenceInput) {
    if (!candidate) return;
    try {
      const actualAmountMinor = serializeMoneyMinor(parseMoneyInput(input.actualAmount));
      await confirm.mutateAsync({
        ruleId: candidate.rule_id, expectedDate: candidate.occurred_on, actualAmountMinor,
        actualDate: input.actualDate,
        sourceAccountId: input.sourceType === "account" ? input.accountId : null,
        sourceCardId: input.sourceType === "card" ? input.cardId : null,
        notes: input.notes,
      });
      toast.success("Movimiento registrado");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  return <ResponsiveDialog
    description={`Esperado: ${candidate.name} · $${(Number(candidate.amount_minor) / 100).toFixed(2)} · ${formatFinancialDate(candidate.occurred_on)}. Puedes cambiar el importe, la fecha o la fuente sin afectar los próximos pagos.`}
    footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={confirm.isPending} form="confirm-occurrence-form" type="submit">{confirm.isPending ? "Registrando…" : "Registrar"}</Button></>}
    onOpenChange={onOpenChange} open={open} size="small" title={candidate.name}
  >
    <form className="space-y-5" id="confirm-occurrence-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.actualAmount?.message} id="confirm-amount" label="Importe real">
        <Input id="confirm-amount" inputMode="decimal" {...form.register("actualAmount")} />
      </FormField>
      <FormField error={form.formState.errors.actualDate?.message} id="confirm-date" label="Fecha real">
        <Input id="confirm-date" type="date" {...form.register("actualDate")} />
      </FormField>

      <FormField id="confirm-source-type" label="¿Dónde ocurrió?">
        <Select id="confirm-source-type" {...form.register("sourceType")}>
          {hasDefaultSource ? <option value="default">La fuente habitual</option> : null}
          <option value="account">Otra cuenta</option>
          {candidate.direction === "expense" ? <option value="card">Otra tarjeta</option> : null}
        </Select>
      </FormField>

      {sourceType === "account" ? <FormField id="confirm-account" label="Cuenta">
        <Select id="confirm-account" {...form.register("accountId")}>
          <option value="">Elige una cuenta</option>
          {(accounts.data ?? []).map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </Select>
      </FormField> : null}

      {sourceType === "card" ? <FormField id="confirm-card" label="Tarjeta">
        <Select id="confirm-card" {...form.register("cardId")}>
          <option value="">Elige una tarjeta</option>
          {(cards.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </Select>
      </FormField> : null}

      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}

export function occurrenceAmountPreview(candidate: RecurringOccurrenceCandidate) {
  return <MoneyValue amount={candidate.amount_minor} currency={candidate.currency} sign="always" size="sm" />;
}
