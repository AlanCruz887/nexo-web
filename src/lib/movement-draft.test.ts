import { describe, expect, it } from "vitest";

import { movementDraftFromActivity } from "@/lib/movement-draft";
import type { FinancialActivity } from "@/types/database";

const movement: FinancialActivity = {
  event_id: "11111111-1111-1111-1111-111111111111",
  user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  kind: "expense",
  amount_minor: "145000",
  personal_amount_minor: "145000",
  description: "Supermercado",
  category_id: "food",
  category_name: "Comida",
  occurred_on: "2026-08-20",
  notes: "Compra semanal",
  created_at: "2026-08-20T18:00:00Z",
  account_id: "22222222-2222-2222-2222-222222222222",
  source_type: "account",
  card_id: null,
  source_name: "Santander",
  source_detail: "Santander",
  currency: "MXN",
  signed_amount_minor: "-145000",
  payment_method: null,
  statement_date: null,
  related_event_id: null,
  source_is_active: true,
  source_account_id: null,
  source_account_name: null,
  destination_account_id: null,
};

describe("movement draft", () => {
  it("duplicates into an unsaved draft with the original values and today's date", () => {
    expect(movementDraftFromActivity(movement, "duplicate", "2026-08-27")).toEqual({
      amount: "1450.00",
      account_id: movement.account_id,
      kind: "expense",
      category_id: "food",
      occurred_on: "2026-08-27",
      description: "Supermercado",
      notes: "Compra semanal",
      purchase_scope: "self",
      personal_amount: "1450.00",
      allocations: [],
    });
  });

  it("preserves the original financial date when editing", () => {
    expect(movementDraftFromActivity(movement, "edit", "2026-08-27").occurred_on).toBe("2026-08-20");
  });
});
