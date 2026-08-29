import { z } from "zod";

import { standardInstallmentTerms } from "@/schemas/card-transaction";

export { standardInstallmentTerms };

export const historicalInstallmentSchema = z.object({
  description: z.string().trim().min(1, "Escribe un nombre.").max(160),
  card_id: z.string().uuid("Elige una tarjeta."),
  original_amount: z.string().trim().min(1, "Escribe el importe original."),
  installment_count: z.string(),
  custom_installment_count: z.string(),
  installment_amount: z.string().trim().min(1, "Escribe la mensualidad del banco."),
  original_purchase_date: z.iso.date("Usa una fecha válida."),
  current_installment_number: z.string(),
  reported_paid_amount: z.string().trim().min(1, "Escribe el total pagado reportado."),
  principal_paid: z.string().trim().min(1, "Escribe cuánto del importe original ya pagaste."),
  next_statement_date: z.iso.date("Usa una fecha de corte válida."),
  category_id: z.string().min(1, "Elige una categoría."),
  notes: z.string().trim().max(2000),
  opening_balance_inclusion: z.enum(["included", "excluded"]),
  purchase_scope: z.enum(["self", "other", "shared"]),
  personal_amount: z.string(),
  allocations: z.array(z.object({ contact_id: z.string().uuid(), amount: z.string().trim().min(1) })),
}).superRefine((value, context) => {
  const count = resolveHistoricalInstallmentCount(value);
  const current = Number(value.current_installment_number);
  if (!Number.isInteger(count) || count < 2 || count > 60) {
    context.addIssue({ code: "custom", path: [value.installment_count === "custom" ? "custom_installment_count" : "installment_count"], message: "Elige entre 2 y 60 meses." });
  }
  if (!Number.isInteger(current) || current < 1 || current > count) {
    context.addIssue({ code: "custom", path: ["current_installment_number"], message: "La mensualidad actual debe estar dentro del plan." });
  }
});

export type HistoricalInstallmentInput = z.infer<typeof historicalInstallmentSchema>;

export function resolveHistoricalInstallmentCount(input: Pick<HistoricalInstallmentInput, "installment_count" | "custom_installment_count">) {
  return Number(input.installment_count === "custom" ? input.custom_installment_count : input.installment_count);
}

export function historicalPaidBeforeCount(currentInstallmentNumber: string | number) {
  const current = Number(currentInstallmentNumber);
  return Number.isInteger(current) && current > 0 ? current - 1 : 0;
}
