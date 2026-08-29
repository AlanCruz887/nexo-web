import { describe, expect, it } from "vitest";
import { resolvePurchaseSplit } from "@/lib/purchase-split";

describe("purchase allocation invariant", () => {
  it("keeps a personal purchase fully personal", () => expect(resolvePurchaseSplit({ amount: "1000", purchase_scope: "self", personal_amount: "", allocations: [] })).toEqual({ personalAmountMinor: "100000", allocations: [] }));
  it("supports a purchase entirely for another person", () => expect(resolvePurchaseSplit({ amount: "10000", purchase_scope: "other", personal_amount: "0", allocations: [{ contact_id: "carlos", amount: "10000" }] })).toEqual({ personalAmountMinor: "0", allocations: [{ contact_id: "carlos", amount_minor: "1000000" }] }));
  it("supports several people and a personal part", () => expect(resolvePurchaseSplit({ amount: "10000", purchase_scope: "shared", personal_amount: "3000", allocations: [{ contact_id: "carlos", amount: "4000" }, { contact_id: "ana", amount: "3000" }] }).personalAmountMinor).toBe("300000"));
  it("rejects a split that does not equal the purchase total", () => expect(() => resolvePurchaseSplit({ amount: "10000", purchase_scope: "shared", personal_amount: "3000", allocations: [{ contact_id: "carlos", amount: "6000" }] })).toThrow("NEXO_PURCHASE_SPLIT_MISMATCH"));
});
