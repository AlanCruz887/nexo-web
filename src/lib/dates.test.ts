import { describe, expect, it } from "vitest";

import {
  formatFinancialDate,
  formatAuditTimestamp,
  isValidTimezone,
  parseAuditTimestamp,
  parseFinancialDate,
} from "@/lib/dates";

describe("date boundaries", () => {
  it("keeps financial dates separate from timestamps", () => {
    expect(parseFinancialDate("2028-02-29")).toBe("2028-02-29");
    expect(formatFinancialDate("2028-02-29")).toBe("29/02/2028");
    expect(() => parseFinancialDate("2028-02-30")).toThrow();
  });

  it("requires time for audit timestamps", () => {
    expect(parseAuditTimestamp("2026-08-27T12:30:00Z")).toBeInstanceOf(Date);
    expect(formatAuditTimestamp("2026-08-27T12:30:00Z", "yyyy-MM-dd HH:mm")).toMatch(/^2026-08-27 /);
    expect(() => parseAuditTimestamp("2026-08-27")).toThrow();
  });

  it("validates profile timezones", () => {
    expect(isValidTimezone("America/Mexico_City")).toBe(true);
    expect(isValidTimezone("Not/A_Timezone")).toBe(false);
  });
});
