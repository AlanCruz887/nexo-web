import { describe, expect, it } from "vitest";

import {
  deserializeMoneyMinor,
  displayToMinor,
  minorToDisplay,
  parseMoneyInput,
  serializeMoneyMinor,
  splitPrincipalIntoInstallments,
} from "@/lib/money-core";

describe("money-core (pure, zero-dependency module)", () => {
  it("converts display values to exact minor units without floats", () => {
    expect(parseMoneyInput("1,234.56", 2)).toBe(123456n);
    expect(parseMoneyInput("1.234,56", 2)).toBe(123456n);
    expect(parseMoneyInput("-$42.05", 2)).toBe(-4205n);
    expect(displayToMinor).toBe(parseMoneyInput);
  });

  it("converts minor units to an exact decimal string", () => {
    expect(minorToDisplay(123456n, 2)).toBe("1234.56");
    expect(minorToDisplay(-5n, 2)).toBe("-0.05");
  });

  it("serializes bigint safely across JSON/PostgREST boundaries", () => {
    const serialized = serializeMoneyMinor(9_007_199_254_740_993n);
    expect(serialized).toBe("9007199254740993");
    expect(deserializeMoneyMinor(serialized)).toBe(9_007_199_254_740_993n);
  });

  it("rejects malformed input", () => {
    expect(() => deserializeMoneyMinor("1.5")).toThrow();
    expect(() => parseMoneyInput("12.3.4", 2)).toThrow();
  });

  it("keeps MSI division exact and moves rounding to the last installment", () => {
    expect(splitPrincipalIntoInstallments(1_000_000n, 3)).toEqual([333_333n, 333_333n, 333_334n]);
  });
});
