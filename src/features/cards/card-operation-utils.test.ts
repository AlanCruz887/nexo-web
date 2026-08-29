import { describe, expect, it } from "vitest";

import { purchaseStartDateError } from "@/features/cards/card-operation-utils";

describe("card controlled-since boundary", () => {
  it("keeps a purchase on or after the card start date", () => expect(purchaseStartDateError("2026-07-15", "2026-07-15")).toBeNull());
  it("explains an earlier purchase without exposing baseline jargon", () => {
    const result = purchaseStartDateError("2026-07-08", "2026-07-15");
    expect(result?.message).toContain("comenzaste a llevar esta tarjeta en Nexo");
    expect(result?.message).toContain("15 de julio de 2026");
    expect(result?.message.toLowerCase()).not.toContain("baseline");
  });
});
