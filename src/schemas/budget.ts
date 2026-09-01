import { z } from "zod";

export const budgetCreateSchema = z.object({
  category_id: z.string().trim().min(1, "Elige una categoría."),
  currency: z.string().trim().length(3, "Elige una moneda."),
  amount: z.string().trim().min(1, "Escribe un importe."),
});

export type BudgetCreateInput = z.infer<typeof budgetCreateSchema>;
