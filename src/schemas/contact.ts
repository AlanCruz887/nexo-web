import { z } from "zod";

export const contactSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre.").max(120),
  email: z.union([z.literal(""), z.email("Escribe un correo válido.")]),
  phone: z.string().trim().max(40),
  notes: z.string().trim().max(2000),
});

export const personPaymentSchema = z.object({
  amount: z.string().trim().min(1, "Escribe un importe."),
  account_id: z.string().uuid("Elige una cuenta."),
  occurred_on: z.iso.date("Usa una fecha válida."),
  notes: z.string().trim().max(2000),
});

export type ContactInput = z.infer<typeof contactSchema>;
export type PersonPaymentInput = z.infer<typeof personPaymentSchema>;
