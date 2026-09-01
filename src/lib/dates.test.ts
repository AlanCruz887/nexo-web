import { describe, expect, it } from "vitest";

import {
  formatFinancialDate,
  formatAuditTimestamp,
  formatRelativeTime,
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

  // Built from LOCAL date components (never a hardcoded "...Z" instant)
  // so this holds regardless of the machine/CI runner's timezone --
  // "Hoy"/"Ayer" are calendar-day comparisons in local time, and "HH:mm"
  // is rendered in local time too, matching how formatRelativeTime is
  // actually used (last_used_at shown to a person in their own clock).
  it("formats last-used timestamps in human-relative terms", () => {
    const now = new Date(2026, 7, 30, 12, 0, 0); // 30 Aug 2026, noon local
    const threeMinAgo = new Date(now.getTime() - 3 * 60_000);
    const todayEarlier = new Date(2026, 7, 30, 9, 42, 0);
    const yesterday = new Date(2026, 7, 29, 12, 0, 0);
    const weeksAgo = new Date(2026, 7, 1, 9, 42, 0);

    expect(formatRelativeTime(threeMinAgo.toISOString(), now)).toBe("Hace 3 min");
    expect(formatRelativeTime(todayEarlier.toISOString(), now)).toBe("Hoy, 09:42");
    expect(formatRelativeTime(yesterday.toISOString(), now)).toBe("Ayer");
    expect(formatRelativeTime(weeksAgo.toISOString(), now)).toBe("1 de ago, 2026");
  });
});
