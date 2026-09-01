import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { FormField } from "@/components/form-field";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCategories } from "@/hooks/use-categories";
import { useCreatePlannedCashFlow, useUpdatePlannedCashFlow } from "@/hooks/use-planned-cash-flows";
import { useCurrencies } from "@/hooks/use-currencies";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import { plannedCashFlowSchema, type PlannedCashFlowInput } from "@/schemas/planned-cash-flow";
import type { CurrencyCode, PlannedCashFlow } from "@/types/database";

const emptyValues: PlannedCashFlowInput = {
  name: "", currency: "", amount: "", direction: "outflow", categoryId: null,
  recurrence: "one_time", startDate: "", endDate: null,
};

export function PlannedCashFlowForm({ flow, onOpenChange, open }: { flow?: PlannedCashFlow; onOpenChange: (open: boolean) => void; open: boolean }) {
  const currencies = useCurrencies();
  const categories = useCategories();
  const create = useCreatePlannedCashFlow();
  const update = useUpdatePlannedCashFlow();
  const toast = useToast();
  const isEdit = Boolean(flow);
  const form = useForm<PlannedCashFlowInput>({ resolver: zodResolver(plannedCashFlowSchema), defaultValues: emptyValues });
  const direction = form.watch("direction");
  const recurrence = form.watch("recurrence");

  useEffect(() => {
    if (!open) return;
    form.reset(flow ? {
      name: flow.name, currency: flow.currency, amount: (Number(flow.amount_minor.replace("-", "")) / 100).toFixed(2),
      direction: flow.amount_minor.startsWith("-") ? "outflow" : "income",
      categoryId: flow.category_id, recurrence: flow.recurrence, startDate: flow.start_date, endDate: flow.end_date,
    } : emptyValues);
  }, [flow, open, form]);

  async function submit(input: PlannedCashFlowInput) {
    try {
      const magnitude = parseMoneyInput(input.amount);
      const signed = input.direction === "outflow" ? -magnitude : magnitude;
      const amountMinor = serializeMoneyMinor(signed);
      const categoryId = input.direction === "outflow" ? input.categoryId : null;
      const endDate = input.recurrence === "monthly" ? input.endDate : null;
      if (isEdit && flow) {
        await update.mutateAsync({
          id: flow.id,
          input: { name: input.name, amountMinor, categoryId, recurrence: input.recurrence, startDate: input.startDate, endDate },
        });
      } else {
        await create.mutateAsync({
          name: input.name, currency: input.currency as CurrencyCode, amountMinor, categoryId,
          recurrence: input.recurrence, startDate: input.startDate, endDate,
        });
      }
      toast.success(isEdit ? "Flujo planeado actualizado" : "Flujo planeado creado");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  const expenseCategories = (categories.data ?? []).filter((category) => category.kind === "expense" || category.kind === "both");
  const pending = create.isPending || update.isPending;

  return <ResponsiveDialog
    description="Una intención declarada por ti. No mueve dinero ni crea un movimiento real hasta que de verdad ocurra."
    footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={pending} form="planned-cash-flow-form" type="submit">{pending ? "Guardando…" : isEdit ? "Guardar" : "Crear"}</Button></>}
    onOpenChange={onOpenChange} open={open} size="small" title={isEdit ? "Editar flujo planeado" : "Nuevo flujo planeado"}
  >
    <form className="space-y-5" id="planned-cash-flow-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.name?.message} id="flow-name" label="Nombre">
        <Input autoFocus id="flow-name" placeholder="Renta, aguinaldo, colegiatura…" {...form.register("name")} />
      </FormField>

      {!isEdit ? <FormField error={form.formState.errors.currency?.message} id="flow-currency" label="Moneda">
        <Select id="flow-currency" {...form.register("currency")}>
          <option value="">Elige una moneda</option>
          {(currencies.data ?? []).map((currency) => <option key={currency.code} value={currency.code}>{currency.code}</option>)}
        </Select>
      </FormField> : null}

      <FormField id="flow-direction" label="Tipo">
        <Select id="flow-direction" {...form.register("direction")}>
          <option value="outflow">Salida (gasto)</option>
          <option value="income">Entrada (ingreso)</option>
        </Select>
      </FormField>

      <FormField error={form.formState.errors.amount?.message} id="flow-amount" label="Monto">
        <Input id="flow-amount" inputMode="decimal" placeholder="10,000.00" {...form.register("amount")} />
      </FormField>

      {direction === "outflow" ? <FormField hint="Si eliges una, este flujo consumirá parte del presupuesto restante de esa categoría en vez de sumarse aparte." id="flow-category" label="Categoría (opcional)">
        <Select id="flow-category" {...form.register("categoryId")}>
          <option value="">Sin categoría</option>
          {expenseCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
        </Select>
      </FormField> : null}

      <FormField id="flow-recurrence" label="Repetición">
        <Select id="flow-recurrence" {...form.register("recurrence")}>
          <option value="one_time">Una sola vez</option>
          <option value="monthly">Cada mes</option>
        </Select>
      </FormField>

      <FormField error={form.formState.errors.startDate?.message} id="flow-start" label={recurrence === "monthly" ? "Desde" : "Fecha"}>
        <Input id="flow-start" type="date" {...form.register("startDate")} />
      </FormField>

      {recurrence === "monthly" ? <FormField hint="Déjalo vacío si no sabes cuándo terminará." id="flow-end" label="Hasta (opcional)">
        <Input id="flow-end" type="date" {...form.register("endDate")} />
      </FormField> : null}

      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
