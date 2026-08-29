import { z } from "zod";

const amount = z.string().trim().min(1, "Escribe un importe.");
const date = z.iso.date("Usa una fecha válida.");
const notes = z.string().trim().max(2000);
export const standardInstallmentTerms = [3, 6, 9, 12, 18, 24] as const;

export function resolveInstallmentCount(input: Pick<CardPurchaseInput, "installment_count" | "custom_installment_count">) {
  return Number(input.installment_count === "custom" ? input.custom_installment_count : input.installment_count);
}

export const cardPurchaseSchema = z.object({
  amount,
  purchase_type: z.enum(["single", "installments"]),
  installment_count: z.string(),
  custom_installment_count: z.string(),
  installment_amount: z.string(),
  card_id: z.string().uuid("Elige una tarjeta."),
  category_id: z.string().min(1, "Elige una categoría."),
  occurred_on: date,
  description: z.string().trim().min(1, "Escribe una descripción.").max(160),
  payment_method: z.enum(["", "physical_card", "apple_pay", "google_pay", "online", "other"]),
  notes,
  purchase_scope: z.enum(["self", "other", "shared"]),
  personal_amount: z.string(),
  allocations: z.array(z.object({ contact_id: z.string().uuid(), amount: z.string().trim().min(1) })),
}).superRefine((value, context) => {
  if (value.purchase_type !== "installments") return;
  const count = Number(value.installment_count === "custom" ? value.custom_installment_count : value.installment_count);
  if (!Number.isInteger(count) || count < 2 || count > 60) {
    context.addIssue({ code: "custom", path: [value.installment_count === "custom" ? "custom_installment_count" : "installment_count"], message: "Elige entre 2 y 60 meses." });
  }
});

export const cardPaymentSchema = z.object({
  amount,
  source_account_id: z.string().uuid("Elige una cuenta origen."),
  card_id: z.string().uuid("Elige una tarjeta."),
  occurred_on: date,
  notes,
});

export const cardRefundSchema = z.object({
  amount,
  card_id: z.string().uuid("Elige una tarjeta."),
  occurred_on: date,
  description: z.string().trim().min(1, "Escribe una descripción.").max(160),
  category_id: z.string(),
  original_event_id: z.string(),
  notes,
});

export type CardPurchaseInput = z.infer<typeof cardPurchaseSchema>;
export type CardPaymentInput = z.infer<typeof cardPaymentSchema>;
export type CardRefundInput = z.infer<typeof cardRefundSchema>;
