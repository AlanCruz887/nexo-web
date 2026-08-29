import { minorToDisplay } from "@/lib/money";
import type { MovementFormInput } from "@/schemas/movement";
import type { FinancialActivity } from "@/types/database";

export function movementDraftFromActivity(
  movement: FinancialActivity,
  mode: "edit" | "duplicate",
  today: string,
): MovementFormInput {
  const kind = movement.kind === "income" ? "income" : "expense";

  return {
    amount: minorToDisplay(BigInt(movement.amount_minor)),
    account_id: movement.account_id ?? "",
    kind,
    category_id: movement.category_id ?? (kind === "income" ? "other_income" : "other_expense"),
    occurred_on: mode === "edit" ? movement.occurred_on : today,
    description: movement.description,
    notes: movement.notes ?? "",
    purchase_scope: movement.third_party_allocations?.length ? (BigInt(movement.personal_amount_minor) === 0n ? "other" : "shared") : "self",
    personal_amount: minorToDisplay(BigInt(movement.personal_amount_minor)),
    allocations: movement.third_party_allocations?.map((item) => ({ contact_id: item.contact_id, amount: minorToDisplay(BigInt(item.amount_minor)) })) ?? [],
  };
}
