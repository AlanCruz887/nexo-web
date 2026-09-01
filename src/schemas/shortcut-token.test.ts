import { describe, expect, it } from "vitest";

import { shortcutTokenFormSchema } from "@/schemas/shortcut-token";

describe("shortcutTokenFormSchema", () => {
  it("accepts a trimmed device name", () => {
    const result = shortcutTokenFormSchema.safeParse({ name: "  Mi iPhone  " });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.name).toBe("Mi iPhone");
  });

  it("rejects an empty name", () => {
    expect(shortcutTokenFormSchema.safeParse({ name: "" }).success).toBe(false);
    expect(shortcutTokenFormSchema.safeParse({ name: "   " }).success).toBe(false);
  });

  it("rejects a name over 60 characters", () => {
    expect(shortcutTokenFormSchema.safeParse({ name: "a".repeat(61) }).success).toBe(false);
    expect(shortcutTokenFormSchema.safeParse({ name: "a".repeat(60) }).success).toBe(true);
  });
});
