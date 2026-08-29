import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { PreferencesProvider } from "@/app/preferences-provider";
import { MovementList } from "@/features/movements/movement-list";
import type { FinancialActivity } from "@/types/database";

const macbook: FinancialActivity = {
  event_id: "11111111-1111-1111-1111-111111111111",
  user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  kind: "card_charge",
  amount_minor: "1200000",
  personal_amount_minor: "1200000",
  description: "MacBook Pro",
  category_id: "technology",
  category_name: "Tecnología",
  occurred_on: "2026-08-28",
  notes: null,
  created_at: "2026-08-28T12:00:00Z",
  source_type: "card",
  account_id: null,
  card_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  source_name: "Joy prueba 2",
  source_detail: null,
  currency: "MXN",
  signed_amount_minor: "-1200000",
  payment_method: "online",
  statement_date: "2026-09-09",
  related_event_id: null,
  source_is_active: true,
  source_account_id: null,
  source_account_name: null,
  destination_account_id: null,
  installment_plan_id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
  installment_count: 12,
  installment_amount_minor: "100000",
  installment_plan_status: "active",
  installment_description: "MacBook Pro",
  installment_category_id: "technology",
  installment_category_name: "Tecnología",
  installment_notes: null,
  installment_origin: "new",
};

describe("MovementList MSI presentation", () => {
  it("renders one real purchase with MSI context and opens its event", () => {
    const onSelect = vi.fn();
    render(<PreferencesProvider><MovementList movements={[macbook]} onSelect={onSelect} /></PreferencesProvider>);

    expect(screen.getAllByText("MacBook Pro")).toHaveLength(1);
    expect(screen.getByText(/12 meses/)).toBeInTheDocument();
    expect(screen.queryByText(/Mensualidad 2 de 12/)).not.toBeInTheDocument();
    expect(screen.getByText(/28 ago · Joy prueba 2/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /MacBook Pro/i }));
    expect(onSelect).toHaveBeenCalledWith(macbook.event_id);
  });

  it("names the people attached to a shared purchase without changing the financial amount", () => {
    const shared: FinancialActivity = { ...macbook, installment_plan_id: null, installment_count: null,
      installment_amount_minor: null, personal_amount_minor: "300000", third_party_allocations: [
        { contact_id: "dddddddd-dddd-dddd-dddd-dddddddddddd", contact_name: "Carlos", amount_minor: "900000" },
      ] };
    render(<PreferencesProvider><MovementList movements={[shared]} onSelect={() => undefined} /></PreferencesProvider>);
    expect(screen.getByText(/Joy prueba 2 · Tecnología · Carlos/)).toBeInTheDocument();
    expect(screen.getByText("-$12,000.00")).toBeInTheDocument();
  });
});
