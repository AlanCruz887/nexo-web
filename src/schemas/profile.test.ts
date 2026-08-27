import { describe, expect, it } from "vitest";

import { profileFormSchema } from "@/schemas/profile";

describe("profile schema", () => {
  it.each(["MXN", "USD", "EUR"])("accepts supported base currency %s", (baseCurrency) => {
    expect(
      profileFormSchema.safeParse({
        full_name: "Alan Cruz",
        base_currency: baseCurrency,
        timezone: "America/Mexico_City",
      }).success,
    ).toBe(true);
  });

  it("rejects unsupported currencies and invalid timezones", () => {
    expect(profileFormSchema.safeParse({ full_name: "Alan", base_currency: "GBP", timezone: "UTC" }).success).toBe(false);
    expect(profileFormSchema.safeParse({ full_name: "Alan", base_currency: "MXN", timezone: "Mars/Base" }).success).toBe(false);
  });
});
