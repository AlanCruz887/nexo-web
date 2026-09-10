import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { PwaUpdatePrompt } from "@/components/pwa-update-prompt";

describe("PwaUpdatePrompt", () => {
  it("permanece oculto mientras no exista una actualización", () => {
    render(<PwaUpdatePrompt onDismiss={vi.fn()} onUpdate={vi.fn()} open={false} />);
    expect(screen.queryByText("Hay una nueva versión de Nexo")).not.toBeInTheDocument();
  });

  it("solo actualiza después de una acción explícita", () => {
    const onUpdate = vi.fn();
    render(<PwaUpdatePrompt onDismiss={vi.fn()} onUpdate={onUpdate} open />);
    expect(onUpdate).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Actualizar" }));
    expect(onUpdate).toHaveBeenCalledOnce();
  });

  it("permite posponer la actualización", () => {
    const onDismiss = vi.fn();
    render(<PwaUpdatePrompt onDismiss={onDismiss} onUpdate={vi.fn()} open />);
    fireEvent.click(screen.getByRole("button", { name: "Actualizar más tarde" }));
    expect(onDismiss).toHaveBeenCalledOnce();
  });
});
