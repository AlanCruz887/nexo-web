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
import { useCreateBudget } from "@/hooks/use-budgets";
import { useCurrencies } from "@/hooks/use-currencies";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import { toUserMessage } from "@/lib/errors";
import { budgetCreateSchema, type BudgetCreateInput } from "@/schemas/budget";
import type { CurrencyCode } from "@/types/database";

export function BudgetForm({ onOpenChange, open, periodMonth }: { onOpenChange: (open: boolean) => void; open: boolean; periodMonth: string }) {
  const categories = useCategories();
  const currencies = useCurrencies();
  const create = useCreateBudget();
  const toast = useToast();
  const form = useForm<BudgetCreateInput>({ resolver: zodResolver(budgetCreateSchema), defaultValues: { category_id: "", currency: "", amount: "" } });
  useEffect(() => { if (open) form.reset({ category_id: "", currency: "", amount: "" }); }, [open, form]);

  async function submit(input: BudgetCreateInput) {
    try {
      await create.mutateAsync({
        categoryId: input.category_id,
        currency: input.currency as CurrencyCode,
        limitMinor: serializeMoneyMinor(parseMoneyInput(input.amount)),
        effectiveFromMonth: periodMonth,
        periodMonth: null,
      });
      toast.success("Presupuesto creado");
      onOpenChange(false);
    } catch (error) { form.setError("root", { message: toUserMessage(error) }); }
  }

  const expenseCategories = (categories.data ?? []).filter((category) => category.kind === "expense" || category.kind === "both");

  return <ResponsiveDialog description="Se aplicará desde este mes en adelante, hasta que lo cambies." footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={create.isPending} form="budget-form" type="submit">{create.isPending ? "Guardando…" : "Crear"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title="Nuevo presupuesto">
    <form className="space-y-5" id="budget-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.category_id?.message} id="budget-category" label="Categoría">
        <Select id="budget-category" {...form.register("category_id")}>
          <option value="">Elige una categoría</option>
          {expenseCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
        </Select>
      </FormField>
      <FormField error={form.formState.errors.currency?.message} id="budget-currency" label="Moneda">
        <Select id="budget-currency" {...form.register("currency")}>
          <option value="">Elige una moneda</option>
          {(currencies.data ?? []).map((currency) => <option key={currency.code} value={currency.code}>{currency.code}</option>)}
        </Select>
      </FormField>
      <FormField error={form.formState.errors.amount?.message} id="budget-amount" label="Monto mensual">
        <Input autoFocus id="budget-amount" inputMode="decimal" placeholder="6,000.00" {...form.register("amount")} />
      </FormField>
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
