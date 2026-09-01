import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ToastProvider } from "@/components/toast";
import { ShortcutTokensSection } from "@/features/settings/shortcut-tokens-section";
import { shortcutTokenService } from "@/services/shortcut-token-service";
import type { ShortcutTokenSummary } from "@/types/database";

vi.mock("@/services/shortcut-token-service", () => ({
  shortcutTokenService: { list: vi.fn(), create: vi.fn(), revoke: vi.fn() },
}));

function renderSection() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}><ToastProvider>{children}</ToastProvider></QueryClientProvider>;
  }
  render(<ShortcutTokensSection />, { wrapper: Wrapper });
}

const activeToken: ShortcutTokenSummary = {
  id: "11111111-1111-1111-1111-111111111111",
  name: "Mi iPhone",
  scopes: ["shortcut:options:read", "shortcut:transactions:write"],
  created_at: "2026-08-20T12:00:00Z",
  last_used_at: null,
  expires_at: null,
  revoked_at: null,
};

const revokedToken: ShortcutTokenSummary = {
  ...activeToken,
  id: "22222222-2222-2222-2222-222222222222",
  name: "iPhone viejo",
  revoked_at: "2026-08-25T09:00:00Z",
};

describe("ShortcutTokensSection", () => {
  beforeEach(() => vi.clearAllMocks());

  // CASO A: empty list.
  it("shows the empty state and a Crear acceso CTA when there are no tokens", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([]);
    renderSection();
    expect(await screen.findByText("No tienes ningún iPhone conectado todavía.")).toBeInTheDocument();
    expect(screen.getAllByRole("button", { name: "Crear acceso" }).length).toBeGreaterThan(0);
  });

  // CASO B: an active token shows its name, "Activo", and a Revocar action.
  it("renders an active token with its status and a revoke action", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([activeToken]);
    renderSection();
    expect(await screen.findByText("Mi iPhone")).toBeInTheDocument();
    expect(screen.getByText("Activo")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Revocar acceso" })).toBeInTheDocument();
  });

  // CASO C: a revoked token shows "Revocado" and no revoke action.
  it("renders a revoked token without a revoke action", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([revokedToken]);
    renderSection();
    expect(await screen.findByText("iPhone viejo")).toBeInTheDocument();
    expect(screen.getByText("Revocado")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Revocar acceso" })).not.toBeInTheDocument();
  });

  // CASO D: last_used_at null shows the "never used" copy, never a crash/blank.
  it("shows 'Todavía no se ha usado' when last_used_at is null", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([activeToken]);
    renderSection();
    expect(await screen.findByText(/Todavía no se ha usado/)).toBeInTheDocument();
  });

  // CASO K/L: revoking calls the correct RPC via the service, and after it
  // resolves the row is still visible (now revoked), never removed outright.
  it("revokes via shortcutTokenService.revoke and keeps the row visible as Revocado", async () => {
    vi.mocked(shortcutTokenService.list)
      .mockResolvedValueOnce([activeToken])
      .mockResolvedValueOnce([{ ...activeToken, revoked_at: "2026-08-26T10:00:00Z" }]);
    vi.mocked(shortcutTokenService.revoke).mockResolvedValue(activeToken.id);

    renderSection();
    fireEvent.click(await screen.findByRole("button", { name: "Revocar acceso" }));
    fireEvent.click(await screen.findByRole("button", { name: "Revocar acceso" }));

    await waitFor(() => expect(shortcutTokenService.revoke).toHaveBeenCalledWith(activeToken.id, expect.stringContaining("shortcut-token:revoke:")));
    expect(await screen.findByText("Mi iPhone")).toBeInTheDocument();
    expect(await screen.findByText("Revocado")).toBeInTheDocument();
  });

  // CASO N: a revoke failure shows the exact required human message, never a raw error.
  it("shows a human error message when revoke fails", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([activeToken]);
    vi.mocked(shortcutTokenService.revoke).mockRejectedValue(new Error("NEXO_SHORTCUT_TOKEN_NOT_FOUND"));

    renderSection();
    fireEvent.click(await screen.findByRole("button", { name: "Revocar acceso" }));
    fireEvent.click(await screen.findByRole("button", { name: "Revocar acceso" }));

    expect(await screen.findByText("No pudimos revocar este acceso.")).toBeInTheDocument();
  });

  // CASO O/P: the UI never renders internal/technical vocabulary, even
  // though the mocked summary type could in principle carry it.
  it("never renders token_hash-like values or technical scope strings", async () => {
    vi.mocked(shortcutTokenService.list).mockResolvedValue([activeToken]);
    renderSection();
    await screen.findByText("Mi iPhone");
    const body = document.body.textContent ?? "";
    expect(body).not.toMatch(/token_hash/i);
    expect(body).not.toMatch(/shortcut:options:read/);
    expect(body).not.toMatch(/shortcut:transactions:write/);
    expect(body).not.toMatch(/\bJWT\b/);
    expect(body).not.toMatch(/service_role/i);
    expect(body).not.toMatch(/\bSHA-256\b/i);
    expect(body).not.toMatch(/\bRPC\b/);
  });
});
