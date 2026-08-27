import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  signUp: vi.fn(),
}));

vi.mock("@/lib/supabase", () => ({
  supabase: {
    auth: {
      signUp: mocks.signUp,
    },
  },
}));

import { authService } from "@/services/auth-service";

describe("authService registration", () => {
  beforeEach(() => {
    mocks.signUp.mockResolvedValue({ data: { user: { id: "user-a" }, session: null }, error: null });
  });

  it("registers through Supabase and only sends profile seed metadata", async () => {
    await authService.signUp({
      fullName: "Alan Cruz",
      email: "alan@example.com",
      password: "correct-horse",
      confirmPassword: "correct-horse",
    });

    expect(mocks.signUp).toHaveBeenCalledWith({
      email: "alan@example.com",
      password: "correct-horse",
      options: { data: { full_name: "Alan Cruz" } },
    });
  });
});
