import { z } from "zod";

const moneyInput = z.string().trim().min(1, "Escribe un importe.");
const day = z.string().regex(/^\d+$/, "Escribe un día válido.").refine((value) => Number(value) >= 1 && Number(value) <= 31, "Usa un día entre 1 y 31.");
const paymentDays = z.string().regex(/^\d+$/, "Escribe días válidos.").refine((value) => Number(value) >= 0 && Number(value) <= 90, "Usa entre 0 y 90 días.");

const cardBaseSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(80),
  issuer: z.string().trim().min(1, "Escribe el emisor.").max(100),
  product_name: z.string().trim().max(100),
  currency: z.enum(["MXN", "USD", "EUR"]),
  credit_limit: moneyInput,
  statement_day: day,
  payment_days_after_statement: paymentDays,
  last4: z.string().trim().refine((value) => value === "" || /^\d{4}$/.test(value), "Escribe exactamente 4 dígitos."),
  visual_theme: z.enum(["bbva_oro", "banamex_clasica", "banamex_joy", "nu", "generic"]),
  baseline_policy: z.enum(["current_bank_balance", "after_last_statement", "specific_date"]),
  baseline_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Selecciona una fecha."),
  bank_balance: moneyInput,
  excluded_statement_amount: z.string(),
  baseline_notes: z.string().trim().max(2000),
});

export const cardFormSchema = cardBaseSchema.superRefine((value, context) => {
  if (value.baseline_policy === "after_last_statement" && value.excluded_statement_amount.trim() === "") {
    context.addIssue({ code: "custom", path: ["excluded_statement_amount"], message: "Escribe el estado anterior que quieres excluir." });
  }
});

export const cardEditSchema = cardBaseSchema.pick({
  name: true, issuer: true, product_name: true, credit_limit: true,
  statement_day: true, payment_days_after_statement: true, last4: true, visual_theme: true,
});

export type CardFormInput = z.infer<typeof cardFormSchema>;
export type CardEditInput = z.infer<typeof cardEditSchema>;
