import { minorToDisplay } from "@/lib/money";
import type { MovementFormInput } from "@/schemas/movement";
import type { AccountActivity } from "@/types/database";

export function movementDraftFromActivity(
  movement: AccountActivity,
  mode: "edit" | "duplicate",
  today: string,
): MovementFormInput {
  const kind = movement.kind === "income" ? "income" : "expense";

  return {
    amount: minorToDisplay(BigInt(movement.amount_minor)),
    account_id: movement.account_id,
    kind,
    category_id: movement.category_id ?? (kind === "income" ? "other_income" : "other_expense"),
    occurred_on: mode === "edit" ? movement.occurred_on : today,
    description: movement.description,
    notes: movement.notes ?? "",
  };
}
