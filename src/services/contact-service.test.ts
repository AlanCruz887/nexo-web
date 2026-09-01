import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ from: vi.fn() }));

vi.mock("@/lib/supabase", () => ({ supabase: { from: mocks.from } }));

import { contactService } from "@/services/contact-service";
import type { ContactSummary, PersonCollectionPeriod } from "@/types/database";

type QueryResult<T> = { data: T | null; error: { code?: string; message: string } | null };

function makeQuery<T>(result: QueryResult<T>) {
  const promise = Promise.resolve(result) as Promise<QueryResult<T>> & {
    select: () => typeof promise; order: () => typeof promise; eq: () => typeof promise; maybeSingle: () => Promise<QueryResult<T>>;
  };
  promise.select = () => promise;
  promise.order = () => promise;
  promise.eq = () => promise;
  promise.maybeSingle = () => Promise.resolve(result);
  return promise;
}

const carlos: Omit<ContactSummary, "periods"> = {
  id: "carlos", user_id: "user-a", name: "Carlos", email: null, phone: null, notes: null,
  is_active: true, created_at: "2026-08-01T00:00:00Z", updated_at: "2026-08-01T00:00:00Z",
  balances: [{ currency: "MXN", outstanding_minor: "800000" }],
  last_activity_on: "2026-08-15", last_activity_description: "MacBook Pro",
};

const ana: Omit<ContactSummary, "periods"> = {
  id: "ana", user_id: "user-a", name: "Ana", email: null, phone: null, notes: null,
  is_active: true, created_at: "2026-08-01T00:00:00Z", updated_at: "2026-08-01T00:00:00Z",
  balances: [], last_activity_on: null, last_activity_description: null,
};

const carlosPeriod: PersonCollectionPeriod = {
  currency: "MXN", period_start: "2026-09-09", payment_due_date: "2026-09-29",
  subtotal_minor: "66667", paid_minor: "0", credit_applied_minor: "0", reconciled_minor: "0",
  remaining_minor: "66667", overdue_minor: "0", overdue_since: null, total_outstanding_minor: "800000",
  credit_balance_minor: "0", concepts: [],
};

function mockTables(overviewResult: QueryResult<Array<{ contact_id: string; user_id: string; periods: PersonCollectionPeriod[] }>>) {
  mocks.from.mockImplementation((table: string) => {
    if (table === "contact_balance_summary") return makeQuery({ data: [carlos, ana], error: null });
    if (table === "contact_period_overview") return makeQuery(overviewResult);
    throw new Error(`unexpected table ${table}`);
  });
}

describe("contactService.list", () => {
  beforeEach(() => { mocks.from.mockReset(); });

  it("A: returns a contact's total debt and this-period figures when both queries succeed", async () => {
    mockTables({ data: [{ contact_id: "carlos", user_id: "user-a", periods: [carlosPeriod] }], error: null });
    const result = await contactService.list();
    const found = result.find((item) => item.id === "carlos");
    expect(found?.balances[0]?.outstanding_minor).toBe("800000");
    expect(found?.periods).toEqual([carlosPeriod]);
  });

  it("B: keeps a contact's total debt even when the period overview has no row for them", async () => {
    mockTables({ data: [], error: null });
    const result = await contactService.list();
    const found = result.find((item) => item.id === "carlos");
    expect(found?.balances[0]?.outstanding_minor).toBe("800000");
    expect(found?.periods).toEqual(undefined);
  });

  it("C: a contact with no debt has empty balances and no crash", async () => {
    mockTables({ data: [{ contact_id: "carlos", user_id: "user-a", periods: [carlosPeriod] }], error: null });
    const result = await contactService.list();
    const found = result.find((item) => item.id === "ana");
    expect(found?.balances).toEqual([]);
  });

  it("D: surfaces saldo a favor from the period overview untouched", async () => {
    const withCredit: PersonCollectionPeriod = { ...carlosPeriod, remaining_minor: "0", credit_balance_minor: "50000" };
    mockTables({ data: [{ contact_id: "carlos", user_id: "user-a", periods: [withCredit] }], error: null });
    const result = await contactService.list();
    const found = result.find((item) => item.id === "carlos");
    expect(found?.periods?.[0]?.credit_balance_minor).toBe("50000");
  });

  it("E: a null secondary response leaves periods undefined instead of crashing", async () => {
    mockTables({ data: null, error: null });
    const result = await contactService.list();
    expect(result).toHaveLength(2);
    expect(result.find((item) => item.id === "carlos")?.periods).toBeUndefined();
  });

  it("F: an error in the period overview (e.g. the 5B view isn't deployed) never loses the base list", async () => {
    mockTables({ data: null, error: { code: "PGRST202", message: "Could not find the function public.get_person_collection_period in the schema cache" } });
    const result = await contactService.list();
    expect(result).toHaveLength(2);
    expect(result.find((item) => item.id === "carlos")?.balances[0]?.outstanding_minor).toBe("800000");
    expect(result.every((item) => item.periods === undefined)).toBe(true);
  });

  it("still throws when the base contact list query itself fails", async () => {
    mocks.from.mockImplementation((table: string) => {
      if (table === "contact_balance_summary") return makeQuery({ data: null, error: { message: "relation does not exist" } });
      if (table === "contact_period_overview") return makeQuery({ data: [], error: null });
      throw new Error(`unexpected table ${table}`);
    });
    await expect(contactService.list()).rejects.toBeTruthy();
  });
});
