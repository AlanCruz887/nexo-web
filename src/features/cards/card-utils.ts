import type { CardTheme } from "@/types/database";

export const cardThemes: Record<CardTheme, { label: string; className: string; accent: string }> = {
  bbva_oro: { label: "BBVA Oro", className: "from-[#172c62] via-[#254b91] to-[#b79655] text-white", accent: "bg-amber-300/80" },
  banamex_clasica: { label: "Banamex Clásica", className: "from-[#073a78] via-[#0758a5] to-[#0f7bc2] text-white", accent: "bg-white/80" },
  banamex_joy: { label: "Banamex Joy", className: "from-[#49236f] via-[#7443a4] to-[#d2589e] text-white", accent: "bg-pink-200/90" },
  nu: { label: "Nu", className: "from-[#2d123d] via-[#54206f] to-[#76258e] text-white", accent: "bg-white/80" },
  generic: { label: "Genérica", className: "from-[#152b55] via-[#23477d] to-[#4772a9] text-white", accent: "bg-sky-200/90" },
};

export type CardProductTheme = {
  brand: string;
  product: string;
  surfaceClass: string;
  primaryTextClass: string;
  secondaryTextClass: string;
  trackClass: string;
  progressClass: string;
  borderClass: string;
};

/** Visual identity used by the physical-card treatment in “Tus tarjetas”. */
export const cardProductThemes: Record<CardTheme, CardProductTheme> = {
  bbva_oro: {
    brand: "BBVA",
    product: "ORO",
    surfaceClass: "bg-[#bfa76f]",
    primaryTextClass: "text-[#101827]",
    secondaryTextClass: "text-[#243044]/65",
    trackClass: "bg-[#182235]/12",
    progressClass: "bg-[#182235]/75",
    borderClass: "border-[#fff8dc]/32",
  },
  banamex_clasica: {
    brand: "Banamex",
    product: "CLÁSICA",
    surfaceClass: "bg-[#d7193f]",
    primaryTextClass: "text-white",
    secondaryTextClass: "text-white/68",
    trackClass: "bg-white/18",
    progressClass: "bg-white/88",
    borderClass: "border-white/18",
  },
  banamex_joy: {
    brand: "Banamex",
    product: "JOY",
    surfaceClass: "bg-[#00a7cf]",
    primaryTextClass: "text-white",
    secondaryTextClass: "text-white/72",
    trackClass: "bg-[#003f69]/22",
    progressClass: "bg-white/90",
    borderClass: "border-white/22",
  },
  nu: {
    brand: "nu",
    product: "CRÉDITO",
    surfaceClass: "bg-[#6f238e]",
    primaryTextClass: "text-white",
    secondaryTextClass: "text-white/68",
    trackClass: "bg-white/16",
    progressClass: "bg-white/88",
    borderClass: "border-white/16",
  },
  generic: {
    brand: "NEXO",
    product: "CRÉDITO",
    surfaceClass: "bg-[#17386f]",
    primaryTextClass: "text-white",
    secondaryTextClass: "text-white/66",
    trackClass: "bg-white/15",
    progressClass: "bg-white/85",
    borderClass: "border-white/14",
  },
};

export function cardUtilization(used: string | bigint, limit: string | bigint): number {
  const usedMinor = typeof used === "bigint" ? used : BigInt(used);
  const limitMinor = typeof limit === "bigint" ? limit : BigInt(limit);
  if (limitMinor <= 0n) return 0;
  return Math.max(0, Number((usedMinor * 10_000n) / limitMinor) / 100);
}
