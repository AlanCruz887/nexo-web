import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { PreferencesProvider } from "@/app/preferences-provider";
import { CardStatementActivity } from "@/features/cards/card-statement-activity";
import type { CardStatementActivitySegment } from "@/types/database";

const base = {
  user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  card_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  occurred_on: "2026-08-20",
  group_statement_date: "2026-09-09",
  cycle_start: "2026-08-09",
  cycle_end: "2026-09-09",
  source_account_name: null,
  source_is_active: true,
} as const;

const segments: CardStatementActivitySegment[] = [
  { ...base, segment_id: "purchase-1", event_id: "11111111-1111-1111-1111-111111111111", kind: "card_charge", segment_kind: "purchase", amount_minor: "200000", description: "PS5 Alan" },
  { ...base, segment_id: "purchase-2", event_id: "22222222-2222-2222-2222-222222222222", kind: "card_charge", segment_kind: "purchase", amount_minor: "100000", description: "Audífonos prueba" },
  { ...base, segment_id: "refund", event_id: "33333333-3333-3333-3333-333333333333", kind: "card_refund", segment_kind: "refund", amount_minor: "40000", description: "Reembolso" },
  { ...base, segment_id: "advance-500", event_id: "44444444-4444-4444-4444-444444444444", kind: "card_payment", segment_kind: "payment_advance", amount_minor: "50000", description: "Pago a Joy", source_account_name: "Santander" },
  { ...base, segment_id: "advance-600", event_id: "55555555-5555-5555-5555-555555555555", kind: "card_payment", segment_kind: "payment_advance", amount_minor: "60000", description: "Pago a Joy", source_account_name: "Santander" },
];

describe("CardStatementActivity", () => {
  it("groups advance payments with the open cycle and never renders an unassigned-state label", () => {
    render(<PreferencesProvider><CardStatementActivity closedStatementDates={[]} currency="MXN" onSelect={vi.fn()} openStatementDate="2026-09-09" segments={segments} /></PreferencesProvider>);
    expect(screen.getByText("Estado 09 sep 2026")).toBeInTheDocument();
    expect(screen.getByText("Periodo actual")).toBeInTheDocument();
    expect(screen.getAllByText("Pago anticipado")).toHaveLength(2);
    expect(screen.getByText("Compras del periodo")).toBeInTheDocument();
    expect(screen.getByText("Después de pagos")).toBeInTheDocument();
    expect(screen.queryByText(/Sin estado asignado/i)).not.toBeInTheDocument();
  });

  it("keeps 12, 18, and 24 month projections out of the main statement view", () => {
    const projected = [12, 18, 24].flatMap((term, planIndex) => Array.from({ length: term }, (_, installmentIndex): CardStatementActivitySegment => {
      const date = new Date(Date.UTC(2026, 8 + installmentIndex, 9)).toISOString().slice(0, 10);
      return {
        ...base,
        segment_id: `plan-${planIndex}-installment-${installmentIndex + 1}`,
        event_id: `plan-${planIndex}`,
        kind: "card_charge",
        segment_kind: "installment",
        amount_minor: "100000",
        description: `MSI ${String.fromCharCode(65 + planIndex)} · Mensualidad ${installmentIndex + 1} de ${term}`,
        group_statement_date: date,
        cycle_end: date,
      };
    }));

    render(<PreferencesProvider><CardStatementActivity closedStatementDates={[]} currency="MXN" onSelect={vi.fn()} openStatementDate="2026-09-09" segments={projected} /></PreferencesProvider>);
    expect(screen.getByText("Estado 09 sep 2026")).toBeInTheDocument();
    expect(screen.getAllByText("1 de 12")).toHaveLength(1);
    expect(screen.getAllByText("1 de 18")).toHaveLength(1);
    expect(screen.getAllByText("1 de 24")).toHaveLength(1);
    expect(screen.queryByText("Estado 09 oct 2026")).not.toBeInTheDocument();
    expect(screen.queryByText("Estado 09 ago 2028")).not.toBeInTheDocument();
  });

  it("separates the MSI total and makes each installment easy to scan", () => {
    const installmentSegments: CardStatementActivitySegment[] = [
      { ...base, segment_id: "macbook-1", event_id: "66666666-6666-6666-6666-666666666666", kind: "card_charge", segment_kind: "installment", amount_minor: "100000", description: "MacBook Pro · Mensualidad 1 de 12" },
      { ...base, segment_id: "existing-2", event_id: "77777777-7777-7777-7777-777777777777", kind: "card_charge", segment_kind: "installment", amount_minor: "100000", description: "Prueba · Mensualidad 2 de 12" },
    ];

    render(<PreferencesProvider><CardStatementActivity closedStatementDates={[]} currency="MXN" onSelect={vi.fn()} openStatementDate="2026-09-09" segments={installmentSegments} /></PreferencesProvider>);

    expect(screen.getByText("MSI del periodo")).toBeInTheDocument();
    expect(screen.getByText("MacBook Pro")).toBeInTheDocument();
    expect(screen.getByText("Prueba")).toBeInTheDocument();
    expect(screen.getByText("1 de 12")).toBeInTheDocument();
    expect(screen.getByText("2 de 12")).toBeInTheDocument();
  });
});
