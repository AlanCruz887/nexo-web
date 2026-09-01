import { z } from "zod";

export const recurringRuleSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(120, "Máximo 120 caracteres."),
  direction: z.enum(["income", "expense"]),
  currency: z.string().trim().length(3, "Elige una moneda."),
  amount: z.string().trim().min(1, "Escribe un importe."),
  categoryId: z.string().trim().min(1).nullable(),
  frequency: z.enum(["weekly", "biweekly", "semimonthly", "monthly", "bimonthly", "quarterly", "semiannual", "annual"]),
  dayOfMonth: z.string().trim().nullable(),
  dayOfMonthSecondary: z.string().trim().nullable(),
  sourceType: z.enum(["account", "card", "none"]),
  accountId: z.string().trim().min(1).nullable(),
  cardId: z.string().trim().min(1).nullable(),
  startDate: z.string().trim().min(1, "Elige una fecha."),
  endDate: z.string().trim().min(1).nullable(),
});

export type RecurringRuleInput = z.infer<typeof recurringRuleSchema>;

export const confirmOccurrenceSchema = z.object({
  actualAmount: z.string().trim().min(1, "Escribe un importe."),
  actualDate: z.string().trim().min(1, "Elige una fecha."),
  sourceType: z.enum(["default", "account", "card"]),
  accountId: z.string().trim().min(1).nullable(),
  cardId: z.string().trim().min(1).nullable(),
  notes: z.string().trim().nullable(),
});

export type ConfirmOccurrenceInput = z.infer<typeof confirmOccurrenceSchema>;
