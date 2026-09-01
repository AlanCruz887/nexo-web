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
import { useCards } from "@/hooks/use-cards";
import { useCategories } from "@/hooks/use-categories";
import { useCreateRecurringRule, useUpdateRecurringRule } from "@/hooks/use-recurring-rules";
import { useCurrencies } from "@/hooks/use-currencies";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import { recurringRuleSchema, type RecurringRuleInput } from "@/schemas/recurring-rule";
import type { CurrencyCode, RecurringDirection, RecurringFrequency, RecurringRule, RecurringRuleVersion } from "@/types/database";

const frequencyLabels: Record<RecurringFrequency, string> = {
  weekly: "Cada semana", biweekly: "Cada 2 semanas", semimonthly: "Dos veces al mes",
  monthly: "Cada mes", bimonthly: "Cada 2 meses", quarterly: "Cada 3 meses",
  semiannual: "Cada 6 meses", annual: "Cada año",
};
const needsDayOfMonth = (f: string) =>
  ["semimonthly", "monthly", "bimonthly", "quarterly", "semiannual", "annual"].includes(f);

const emptyValues: RecurringRuleInput = {
  name: "", direction: "expense", currency: "", amount: "", categoryId: null,
  frequency: "monthly", dayOfMonth: "1", dayOfMonthSecondary: null,
  sourceType: "none", accountId: null, cardId: null, startDate: "", endDate: null,
};

export function RecurringRuleForm({
  onOpenChange, open, rule, ruleVersion,
}: {
  onOpenChange: (open: boolean) => void; open: boolean; rule?: RecurringRule; ruleVersion?: RecurringRuleVersion;
}) {
  const currencies = useCurrencies();
  const categories = useCategories();
  const accounts = useAccounts();
  const cards = useCards();
  const create = useCreateRecurringRule();
  const update = useUpdateRecurringRule();
  const toast = useToast();
  const isEdit = Boolean(rule);
  const form = useForm<RecurringRuleInput>({ resolver: zodResolver(recurringRuleSchema), defaultValues: emptyValues });
  const frequency = form.watch("frequency");
  const sourceType = form.watch("sourceType");
  const direction = form.watch("direction");

  useEffect(() => {
    if (!open) return;
    if (rule && ruleVersion) {
      form.reset({
        name: rule.name, direction: rule.direction, currency: rule.currency,
        amount: (Number(ruleVersion.amount_minor) / 100).toFixed(2), categoryId: ruleVersion.category_id,
        frequency: ruleVersion.frequency, dayOfMonth: ruleVersion.day_of_month?.toString() ?? null,
        dayOfMonthSecondary: ruleVersion.day_of_month_secondary?.toString() ?? null,
        sourceType: ruleVersion.account_id ? "account" : ruleVersion.card_id ? "card" : "none",
        accountId: ruleVersion.account_id, cardId: ruleVersion.card_id,
        startDate: rule.start_date, endDate: rule.end_date,
      });
    } else {
      form.reset(emptyValues);
    }
  }, [rule, ruleVersion, open, form]);

  async function submit(input: RecurringRuleInput) {
    try {
      const amountMinor = serializeMoneyMinor(parseMoneyInput(input.amount));
      const dayOfMonth = needsDayOfMonth(input.frequency) ? Number(input.dayOfMonth) : null;
      const dayOfMonthSecondary = input.frequency === "semimonthly" ? Number(input.dayOfMonthSecondary) : null;
      const accountId = input.sourceType === "account" ? input.accountId : null;
      const cardId = input.sourceType === "card" ? input.cardId : null;

      if (isEdit && rule) {
        await update.mutateAsync({
          id: rule.id,
          input: {
            name: input.name, endDate: input.endDate, effectiveFromDate: input.startDate,
            amountMinor, categoryId: input.categoryId, frequency: input.frequency,
            dayOfMonth, dayOfMonthSecondary, accountId, cardId,
          },
        });
      } else {
        await create.mutateAsync({
          name: input.name, direction: input.direction as RecurringDirection, currency: input.currency as CurrencyCode,
          amountMinor, categoryId: input.categoryId, frequency: input.frequency, dayOfMonth, dayOfMonthSecondary,
          accountId, cardId, startDate: input.startDate, endDate: input.endDate, subtype: null,
        });
      }
      toast.success(isEdit ? "Recurrencia actualizada" : "Recurrencia creada");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  const expenseCategories = (categories.data ?? []).filter((c) => c.kind === "expense" || c.kind === "both");
  const incomeCategories = (categories.data ?? []).filter((c) => c.kind === "income" || c.kind === "both");
  const relevantCategories = direction === "income" ? incomeCategories : expenseCategories;
  const pending = create.isPending || update.isPending;

  return <ResponsiveDialog
    description={isEdit ? "Los cambios aplican desde la fecha de inicio en adelante -- lo ya confirmado u omitido nunca se altera." : "Nada se cobra ni se recibe todavía: solo defines qué esperar."}
    footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={pending} form="recurring-rule-form" type="submit">{pending ? "Guardando…" : isEdit ? "Guardar" : "Crear"}</Button></>}
    onOpenChange={onOpenChange} open={open} size="small" title={isEdit ? "Editar recurrencia" : "Nueva recurrencia"}
  >
    <form className="space-y-5" id="recurring-rule-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.name?.message} id="rec-name" label="Nombre">
        <Input autoFocus id="rec-name" placeholder="Netflix, Renta, Nómina…" {...form.register("name")} />
      </FormField>

      <FormField id="rec-direction" label="¿Es dinero que entra o sale?">
        <Select disabled={isEdit} id="rec-direction" {...form.register("direction")}>
          <option value="expense">Sale (gasto)</option>
          <option value="income">Entra (ingreso)</option>
        </Select>
      </FormField>

      {!isEdit ? <FormField error={form.formState.errors.currency?.message} id="rec-currency" label="Moneda">
        <Select id="rec-currency" {...form.register("currency")}>
          <option value="">Elige una moneda</option>
          {(currencies.data ?? []).map((c) => <option key={c.code} value={c.code}>{c.code}</option>)}
        </Select>
      </FormField> : null}

      <FormField error={form.formState.errors.amount?.message} id="rec-amount" label="Importe">
        <Input id="rec-amount" inputMode="decimal" placeholder="249.00" {...form.register("amount")} />
      </FormField>

      <FormField id="rec-category" label="Categoría (opcional)">
        <Select id="rec-category" {...form.register("categoryId")}>
          <option value="">Sin categoría</option>
          {relevantCategories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </Select>
      </FormField>

      <FormField id="rec-frequency" label="¿Cada cuánto ocurre?">
        <Select id="rec-frequency" {...form.register("frequency")}>
          {Object.entries(frequencyLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </Select>
      </FormField>

      {needsDayOfMonth(frequency) ? <FormField
        error={form.formState.errors.dayOfMonth?.message}
        hint="Si el mes es más corto, se ajusta al último día válido -- nunca se pierde la intención original."
        id="rec-day" label={frequency === "semimonthly" ? "Primer día del mes" : "Día del mes"}
      >
        <Input id="rec-day" inputMode="numeric" max={31} min={1} type="number" {...form.register("dayOfMonth")} />
      </FormField> : null}

      {frequency === "semimonthly" ? <FormField
        hint="Usa 31 para 'el último día del mes'." id="rec-day2" label="Segundo día del mes"
      >
        <Input id="rec-day2" inputMode="numeric" max={31} min={1} type="number" {...form.register("dayOfMonthSecondary")} />
      </FormField> : null}

      <FormField id="rec-source-type" label="Cuenta o tarjeta">
        <Select id="rec-source-type" {...form.register("sourceType")}>
          <option value="none">Todavía no sé</option>
          <option value="account">Cuenta</option>
          {direction === "expense" ? <option value="card">Tarjeta</option> : null}
        </Select>
      </FormField>

      {sourceType === "account" ? <FormField id="rec-account" label="Cuenta">
        <Select id="rec-account" {...form.register("accountId")}>
          <option value="">Elige una cuenta</option>
          {(accounts.data ?? []).map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </Select>
      </FormField> : null}

      {sourceType === "card" ? <FormField id="rec-card" label="Tarjeta">
        <Select id="rec-card" {...form.register("cardId")}>
          <option value="">Elige una tarjeta</option>
          {(cards.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </Select>
      </FormField> : null}

      <FormField error={form.formState.errors.startDate?.message} id="rec-start" label={isEdit ? "A partir de" : "Primera fecha"}>
        <Input id="rec-start" type="date" {...form.register("startDate")} />
      </FormField>

      <FormField hint="Déjalo vacío si no sabes cuándo terminará." id="rec-end" label="Fecha final (opcional)">
        <Input id="rec-end" type="date" {...form.register("endDate")} />
      </FormField>

      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
