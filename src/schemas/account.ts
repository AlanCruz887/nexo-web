import { z } from "zod";

const accountTypes = ["checking", "savings", "cash", "debit", "investment", "other"] as const;

export const accountFormSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(80, "Usa máximo 80 caracteres."),
  type: z.enum(accountTypes),
  currency: z.enum(["MXN", "USD", "EUR"]),
  opening_balance: z.string().trim().min(1, "Escribe el saldo para empezar."),
  institution: z.string().trim().max(100, "Usa máximo 100 caracteres."),
  last4: z.string().trim().refine((value) => value === "" || /^\d{4}$/.test(value), "Escribe exactamente 4 dígitos."),
});

export const accountEditSchema = accountFormSchema.omit({ currency: true, opening_balance: true });

export type AccountFormInput = z.infer<typeof accountFormSchema>;
export type AccountEditInput = z.infer<typeof accountEditSchema>;
