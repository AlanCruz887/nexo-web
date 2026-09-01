import { z } from "zod";

export const goalFormSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(120),
  currency: z.string().trim().length(3, "Elige una moneda."),
  target_amount: z.string().trim().min(1, "Escribe un monto objetivo."),
  target_date: z.string().trim(),
  linked_account_id: z.string().trim(),
});
export type GoalFormInput = z.infer<typeof goalFormSchema>;

export const goalContributionSchema = z.object({
  amount: z.string().trim().min(1, "Escribe un importe."),
  account_id: z.string().uuid("Elige una cuenta."),
  move_real_money: z.boolean(),
  occurred_on: z.iso.date("Usa una fecha válida."),
  notes: z.string().trim().max(2000),
});
export type GoalContributionInput = z.infer<typeof goalContributionSchema>;

export const goalWithdrawalSchema = z.object({
  amount: z.string().trim().min(1, "Escribe un importe."),
  account_id: z.string().trim(),
  move_real_money: z.boolean(),
  destination_account_id: z.string().trim(),
  occurred_on: z.iso.date("Usa una fecha válida."),
  notes: z.string().trim().max(2000),
});
export type GoalWithdrawalInput = z.infer<typeof goalWithdrawalSchema>;
