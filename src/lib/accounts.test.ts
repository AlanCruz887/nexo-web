import { describe, expect, it } from "vitest";

import { selectActiveAccounts, sumBalancesByCurrency } from "@/lib/accounts";
import type { AccountBalance } from "@/types/database";

const baseAccount: AccountBalance = {
  id: "11111111-1111-1111-1111-111111111111",
  user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  name: "Principal",
  type: "checking",
  currency: "MXN",
  opening_balance_minor: "0",
  balance_minor: "100000",
  institution: null,
  last4: null,
  is_active: true,
  created_at: "2026-08-27T00:00:00Z",
  updated_at: "2026-08-27T00:00:00Z",
};

describe("account selectors", () => {
  it("keeps archived accounts out of selectors without deleting them", () => {
    const archived = { ...baseAccount, id: "22222222-2222-2222-2222-222222222222", is_active: false };
    const all = [baseAccount, archived];
    expect(selectActiveAccounts(all)).toEqual([baseAccount]);
    expect(all).toContain(archived);
  });

  it("keeps balances separated by currency", () => {
    const totals = sumBalancesByCurrency([
      { balance_minor: "100000", currency: "MXN" },
      { balance_minor: "50000", currency: "MXN" },
      { balance_minor: "2500", currency: "USD" },
    ]);
    expect(totals).toEqual({ MXN: 150000n, USD: 2500n });
  });
});
