import { describe, expect, it } from "vitest";

import { cardUtilization } from "@/features/cards/card-utils";

describe("card utilization presentation", () => {
  it("calculates exact percentages from minor units", () => {
    expect(cardUtilization("2500000", "10000000")).toBe(25);
  });

  it("never produces NaN when the limit is zero or negative", () => {
    expect(cardUtilization("2500000", "0")).toBe(0);
    expect(cardUtilization("2500000", "-1")).toBe(0);
  });
});
