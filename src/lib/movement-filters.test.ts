import { describe, expect, it } from "vitest";

import { instrumentFilterForOrigin, normalizeOriginChange, sourceTypesForOrigin, visibleInstruments } from "@/lib/movement-filters";

describe("movement origin filters", () => {
  it("clears incompatible instrument ids whenever origin changes", () => {
    expect(normalizeOriginChange("accounts")).toEqual({ origin: "accounts", accountId: "", cardId: "" });
    expect(normalizeOriginChange("cards")).toEqual({ origin: "cards", accountId: "", cardId: "" });
    expect(normalizeOriginChange("all")).toEqual({ origin: "all", accountId: "", cardId: "" });
  });
  it("hides archived instruments by default and exposes them only explicitly", () => {
    const items = [{ id: "active", is_active: true }, { id: "archived", is_active: false }];
    expect(visibleInstruments(items, false).map((item) => item.id)).toEqual(["active"]);
    expect(visibleInstruments(items, true).map((item) => item.id)).toEqual(["active", "archived"]);
  });
  it("maps Todos, Cuentas and Tarjetas to non-overlapping source filters", () => {
    expect(sourceTypesForOrigin("all")).toBeNull();
    expect(sourceTypesForOrigin("accounts")).toEqual(["account", "transfer"]);
    expect(sourceTypesForOrigin("cards")).toEqual(["card"]);
  });
  it("keeps only the selected account when the origin is Cuentas", () => {
    expect(instrumentFilterForOrigin("accounts", "santander", "bbva-oro")).toEqual({ accountId: "santander", cardId: "" });
  });
  it("keeps only the selected card when the origin is Tarjetas", () => {
    expect(instrumentFilterForOrigin("cards", "santander", "bbva-oro")).toEqual({ accountId: "", cardId: "bbva-oro" });
  });
  it("does not apply an instrument selector when the origin is Todos", () => {
    expect(instrumentFilterForOrigin("all", "santander", "bbva-oro")).toEqual({ accountId: "", cardId: "" });
  });
});
