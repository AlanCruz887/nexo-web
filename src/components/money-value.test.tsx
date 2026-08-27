import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { PreferencesProvider, usePreferences } from "@/app/preferences-provider";
import { MoneyValue } from "@/components/money-value";

function PrivacyFixture() {
  const { hideMoney, setHideMoney } = usePreferences();
  return (
    <>
      <MoneyValue amount="123456" currency="MXN" data-testid="money" />
      <button onClick={() => setHideMoney(!hideMoney)} type="button">Cambiar privacidad</button>
    </>
  );
}

describe("MoneyValue", () => {
  it("uses tabular numbers and formats currency", () => {
    render(<PreferencesProvider><MoneyValue amount="123456" currency="MXN" /></PreferencesProvider>);
    expect(screen.getByText(/1,234\.56/)).toHaveClass("tabular-nums");
  });

  it("hides values through the global privacy preference", async () => {
    const user = userEvent.setup();
    render(<PreferencesProvider><PrivacyFixture /></PreferencesProvider>);
    await user.click(screen.getByRole("button", { name: "Cambiar privacidad" }));
    expect(screen.getByTestId("money")).toHaveTextContent("••••••");
    expect(screen.getByTestId("money")).toHaveAccessibleName("Cantidad oculta");
  });

  it("supports an explicit privacy override", () => {
    render(<PreferencesProvider><MoneyValue amount="500" currency="USD" privacy /></PreferencesProvider>);
    expect(screen.getByText("••••••")).toBeInTheDocument();
  });
});
