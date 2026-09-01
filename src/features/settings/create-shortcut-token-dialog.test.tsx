import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ToastProvider } from "@/components/toast";
import { CreateShortcutTokenDialog } from "@/features/settings/create-shortcut-token-dialog";
import { shortcutTokenService } from "@/services/shortcut-token-service";
import type { ShortcutTokenCreated } from "@/types/database";

vi.mock("@/services/shortcut-token-service", () => ({
  shortcutTokenService: { list: vi.fn(), create: vi.fn(), revoke: vi.fn() },
}));

const created: ShortcutTokenCreated = {
  id: "33333333-3333-3333-3333-333333333333",
  token_plain: "nexo_shortcut_test_only_fixture_value_do_not_reuse",
  name: "Mi iPhone",
  scopes: ["shortcut:options:read", "shortcut:transactions:write"],
  created_at: "2026-08-30T12:00:00Z",
  expires_at: null,
};

function renderDialog(open: boolean, onOpenChange: (open: boolean) => void) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}><ToastProvider>{children}</ToastProvider></QueryClientProvider>;
  }
  return render(<CreateShortcutTokenDialog onOpenChange={onOpenChange} open={open} />, { wrapper: Wrapper });
}

async function fillNameAndSubmit(name = "Mi iPhone") {
  fireEvent.change(screen.getByLabelText("Nombre del dispositivo"), { target: { value: name } });
  fireEvent.click(screen.getByRole("button", { name: "Crear acceso" }));
  await screen.findByText("Tu acceso está listo");
}

describe("CreateShortcutTokenDialog", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(navigator, { clipboard: { writeText: vi.fn().mockResolvedValue(undefined) } });
  });

  // CASO E/F: submitting the name form calls the service and reveals the
  // plaintext token exactly once, selectable, with the required copy.
  it("creates the access and reveals the plaintext token", async () => {
    vi.mocked(shortcutTokenService.create).mockResolvedValue(created);
    renderDialog(true, () => undefined);

    await fillNameAndSubmit();

    expect(shortcutTokenService.create).toHaveBeenCalledWith("Mi iPhone");
    expect(screen.getByDisplayValue(created.token_plain)).toBeInTheDocument();
    expect(screen.getByText("Guarda este acceso ahora. Por seguridad, Nexo no podrá volver a mostrarlo.")).toBeInTheDocument();
  });

  // CASO J: clicking Copiar writes the token via the Clipboard API and
  // flips the feedback to "Copiado.".
  it("copies the token and shows feedback", async () => {
    vi.mocked(shortcutTokenService.create).mockResolvedValue(created);
    renderDialog(true, () => undefined);
    await fillNameAndSubmit();

    expect(screen.queryByText("Copiado.")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Copiar acceso" }));

    await waitFor(() => expect(navigator.clipboard.writeText).toHaveBeenCalledWith(created.token_plain));
    expect(await screen.findByText("Copiado.")).toBeInTheDocument();
  });

  // CASO I: attempting to close (via the dialog's own dismiss path) while
  // the token is showing and was never copied asks for confirmation
  // instead of closing immediately.
  it("asks for confirmation before closing an uncopied revealed token", async () => {
    vi.mocked(shortcutTokenService.create).mockResolvedValue(created);
    const onOpenChange = vi.fn();
    renderDialog(true, onOpenChange);
    await fillNameAndSubmit();

    fireEvent.click(screen.getByRole("button", { name: "Cerrar" }));

    expect(await screen.findByText("¿Cerrar sin copiar?")).toBeInTheDocument();
    expect(onOpenChange).not.toHaveBeenCalledWith(false);

    fireEvent.click(screen.getByRole("button", { name: "Cerrar de todos modos" }));
    await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
  });

  // CASO G/H: after confirming a close while the token was still showing,
  // the plaintext is gone from the DOM and the component falls back to
  // the name-entry step -- proving `resetAll` really cleared React state
  // (revealedToken), not just that the dialog was told to hide.
  it("clears the revealed token from state on confirmed close", async () => {
    vi.mocked(shortcutTokenService.create).mockResolvedValue(created);
    const onOpenChange = vi.fn();
    renderDialog(true, onOpenChange);
    await fillNameAndSubmit();

    fireEvent.click(screen.getByRole("button", { name: "Cerrar" }));
    fireEvent.click(await screen.findByRole("button", { name: "Cerrar de todos modos" }));

    await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
    expect(document.body.textContent ?? "").not.toContain(created.token_plain);
    expect((await screen.findAllByText("Crear acceso")).length).toBeGreaterThan(0);
    expect(screen.queryByText("Tu acceso está listo")).not.toBeInTheDocument();
  });

  // CASO M: a creation failure shows the exact required human message.
  it("shows a human error message when creation fails", async () => {
    vi.mocked(shortcutTokenService.create).mockRejectedValue(new Error("network error"));
    renderDialog(true, () => undefined);

    fireEvent.change(screen.getByLabelText("Nombre del dispositivo"), { target: { value: "Mi iPhone" } });
    fireEvent.click(screen.getByRole("button", { name: "Crear acceso" }));

    expect(await screen.findByText("No pudimos crear el acceso. Intenta de nuevo.")).toBeInTheDocument();
    expect(screen.queryByText("Tu acceso está listo")).not.toBeInTheDocument();
  });
});
