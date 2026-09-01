import { z } from "zod";

export const plannedCashFlowSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(120, "Máximo 120 caracteres."),
  currency: z.string().trim().length(3, "Elige una moneda."),
  amount: z.string().trim().min(1, "Escribe un importe."),
  direction: z.enum(["income", "outflow"]),
  categoryId: z.string().trim().min(1).nullable(),
  recurrence: z.enum(["one_time", "monthly"]),
  startDate: z.string().trim().min(1, "Elige una fecha."),
  endDate: z.string().trim().min(1).nullable(),
});

export type PlannedCashFlowInput = z.infer<typeof plannedCashFlowSchema>;
