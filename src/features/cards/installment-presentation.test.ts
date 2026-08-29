import { describe, expect, it } from "vitest";

import { installmentPeriodLabel, installmentTotalForStatement, parseInstallmentSegmentDescription } from "@/features/cards/installment-presentation";
import type { InstallmentPlanSummary } from "@/types/database";

function plan(overrides: Partial<InstallmentPlanSummary>): InstallmentPlanSummary {
  return {
    id: "plan", user_id: "user", card_id: "card", purchase_event_id: "event",
    original_amount_minor: "1200000", installment_count: 12, installment_amount_minor: "100000",
    currency: "MXN", start_date: "2026-08-28", first_statement_date: "2026-09-09",
    status: "active", created_at: "2026-08-28T12:00:00Z", updated_at: "2026-08-28T12:00:00Z", card_name: "Joy",
    origin: "new", included_in_opening_balance: false, reported_paid_amount_minor: "0",
    principal_paid_before_nexo_minor: "0", initial_paid_before_count: 0, additional_card_impact_minor: "1200000",
    description: "MacBook Pro", category_id: null, category_name: null, notes: null,
    paid_before_nexo_count: 0, paid_in_nexo_count: 0, paid_count: 0, pending_count: 12,
    remaining_principal_minor: "1200000", current_installment_number: 1,
    current_installment_minor: "100000", current_installment_principal_minor: "100000",
    next_statement_date: "2026-09-09", ...overrides,
  };
}

describe("installment presentation", () => {
  it("totals only installments that belong to the current statement", () => {
    const plans = [
      plan({ id: "macbook", description: "MacBook Pro" }),
      plan({ id: "existing", description: "Prueba", origin: "historical", paid_count: 1, current_installment_number: 2, remaining_principal_minor: "1100000" }),
      plan({ id: "future", next_statement_date: "2026-10-09" }),
    ];

    expect(installmentTotalForStatement(plans, "2026-09-09")).toBe(200000n);
    expect(installmentPeriodLabel(plans[0]!.next_statement_date, "2026-09-09")).toBe("Mensualidad de este periodo");
    expect(installmentPeriodLabel(plans[2]!.next_statement_date, "2026-09-09")).toBe("Próxima mensualidad");
  });

  it("reflects the following installment after the statement is covered", () => {
    const updated = [
      plan({ id: "macbook", paid_count: 1, current_installment_number: 2, next_statement_date: "2026-10-09", remaining_principal_minor: "1100000" }),
      plan({ id: "existing", origin: "historical", paid_count: 2, current_installment_number: 3, next_statement_date: "2026-10-09", remaining_principal_minor: "1000000" }),
    ];

    expect(installmentTotalForStatement(updated, "2026-09-09")).toBe(0n);
    expect(installmentTotalForStatement(updated, "2026-10-09")).toBe(200000n);
    expect(updated.map((item) => item.current_installment_number)).toEqual([2, 3]);
  });

  it("turns the statement segment into a concise plan name and progress", () => {
    expect(parseInstallmentSegmentDescription("MacBook Pro · Mensualidad 1 de 12")).toEqual({ description: "MacBook Pro", progress: "1 de 12" });
  });
});
