import { z } from "zod";

export const movementFormSchema = z.object({
  amount: z.string().trim().min(1, "Escribe un importe."),
  account_id: z.string().uuid("Elige una cuenta."),
  kind: z.enum(["income", "expense"]),
  category_id: z.string().min(1, "Elige una categoría."),
  occurred_on: z.iso.date("Usa una fecha válida."),
  description: z.string().trim().min(1, "Escribe una descripción.").max(160),
  notes: z.string().trim().max(2000),
  purchase_scope: z.enum(["self", "other", "shared"]),
  personal_amount: z.string(),
  allocations: z.array(z.object({ contact_id: z.string().uuid(), amount: z.string().trim().min(1) })),
});

export const transferFormSchema = z.object({
  amount: z.string().trim().min(1, "Escribe un importe."),
  from_account_id: z.string().uuid("Elige la cuenta origen."),
  to_account_id: z.string().uuid("Elige la cuenta destino."),
  occurred_on: z.iso.date("Usa una fecha válida."),
  description: z.string().trim().max(160),
  notes: z.string().trim().max(2000),
}).refine((value) => value.from_account_id !== value.to_account_id, {
  message: "Elige dos cuentas diferentes.",
  path: ["to_account_id"],
});

export type MovementFormInput = z.infer<typeof movementFormSchema>;
export type TransferFormInput = z.infer<typeof transferFormSchema>;
