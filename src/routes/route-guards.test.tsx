import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  profile: vi.fn(),
}));

vi.mock("@/app/auth-provider", () => ({ useAuth: mocks.auth }));
vi.mock("@/hooks/use-profile", () => ({ useProfile: mocks.profile }));

import { ProtectedRoute } from "@/routes/route-guards";

function renderProtected(initialPath = "/inicio") {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <Routes>
        <Route path="/login" element={<p>Página login</p>} />
        <Route element={<ProtectedRoute />}>
          <Route path="/inicio" element={<p>Contenido privado</p>} />
          <Route path="/onboarding" element={<p>Onboarding base</p>} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

describe("protected routes", () => {
  it("redirects signed-out visitors to login", () => {
    mocks.auth.mockReturnValue({ isLoading: false, user: null });
    renderProtected();
    expect(screen.getByText("Página login")).toBeInTheDocument();
  });

  it("allows an onboarded user into protected content", () => {
    mocks.auth.mockReturnValue({ isLoading: false, user: { id: "user-a" } });
    mocks.profile.mockReturnValue({ isLoading: false, isError: false, data: { onboarding_completed: true } });
    renderProtected();
    expect(screen.getByText("Contenido privado")).toBeInTheDocument();
  });

  it("sends an incomplete profile to onboarding", () => {
    mocks.auth.mockReturnValue({ isLoading: false, user: { id: "user-a" } });
    mocks.profile.mockReturnValue({ isLoading: false, isError: false, data: { onboarding_completed: false } });
    renderProtected();
    expect(screen.getByText("Onboarding base")).toBeInTheDocument();
  });
});
