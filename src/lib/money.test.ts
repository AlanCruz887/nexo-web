import { describe, expect, it } from "vitest";

import {
  deserializeMoneyMinor,
  displayToMinor,
  formatMoney,
  minorToDisplay,
  serializeMoneyMinor,
} from "@/lib/money";

describe("money boundary", () => {
  it("converts display values to exact minor units without floats", () => {
    expect(displayToMinor("1,234.56", 2)).toBe(123456n);
    expect(displayToMinor("1.234,56", 2)).toBe(123456n);
    expect(displayToMinor("-$42.05", 2)).toBe(-4205n);
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

  it("formats exact units for the configured currency", () => {
    const formatted = formatMoney("123456", "MXN");
    expect(formatted).toContain("1,234.56");
    expect(formatted).toContain("$");
  });

  it("rejects malformed serialized money", () => {
    expect(() => deserializeMoneyMinor("1.5")).toThrow();
    expect(() => displayToMinor("12.345", 2)).not.toThrow();
    expect(() => displayToMinor("12.3.4", 2)).toThrow();
  });
});
