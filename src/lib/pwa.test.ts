import { describe, expect, it } from "vitest";

import { detectPwaEnvironment } from "@/lib/pwa";

describe("detectPwaEnvironment", () => {
  it("reconoce iPhone y modo navegador", () => {
    expect(detectPwaEnvironment({
      displayModeStandalone: false,
      maxTouchPoints: 5,
      navigatorStandalone: false,
      platform: "iPhone",
      userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
    })).toEqual({ isIos: true, isStandalone: false });
  });

  it("reconoce iPad moderno aunque se identifique como Mac", () => {
    expect(detectPwaEnvironment({
      displayModeStandalone: false,
      maxTouchPoints: 5,
      navigatorStandalone: false,
      platform: "MacIntel",
      userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X)",
    }).isIos).toBe(true);
  });

  it("reconoce una app instalada por cualquiera de las señales soportadas", () => {
    const base = { maxTouchPoints: 0, platform: "Linux", userAgent: "Chrome" };
    expect(detectPwaEnvironment({ ...base, displayModeStandalone: true, navigatorStandalone: false }).isStandalone).toBe(true);
    expect(detectPwaEnvironment({ ...base, displayModeStandalone: false, navigatorStandalone: true }).isStandalone).toBe(true);
  });
});
