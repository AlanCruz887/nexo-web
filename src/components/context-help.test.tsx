import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ContextHelp } from "@/components/context-help";

describe("ContextHelp", () => {
  it("exposes its explanation to keyboard and assistive technology users", () => {
    render(<ContextHelp label="Saldo utilizado" text="Incluye todo el crédito que estás usando." />);

    const trigger = screen.getByRole("button", { name: "Más información sobre Saldo utilizado" });
    const tooltip = screen.getByRole("tooltip");

    expect(trigger).toHaveAttribute("aria-describedby", tooltip.id);
    expect(tooltip).toHaveTextContent("Incluye todo el crédito que estás usando.");
  });
});
