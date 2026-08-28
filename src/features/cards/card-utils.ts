import type { CardTheme } from "@/types/database";

export const cardThemes: Record<CardTheme, { label: string; className: string; accent: string }> = {
  bbva_oro: { label: "BBVA Oro", className: "from-[#172c62] via-[#254b91] to-[#b79655] text-white", accent: "bg-amber-300/80" },
  banamex_clasica: { label: "Banamex Clásica", className: "from-[#073a78] via-[#0758a5] to-[#0f7bc2] text-white", accent: "bg-white/80" },
  banamex_joy: { label: "Banamex Joy", className: "from-[#49236f] via-[#7443a4] to-[#d2589e] text-white", accent: "bg-pink-200/90" },
  nu: { label: "Nu", className: "from-[#2d123d] via-[#54206f] to-[#76258e] text-white", accent: "bg-white/80" },
  generic: { label: "Genérica", className: "from-[#152b55] via-[#23477d] to-[#4772a9] text-white", accent: "bg-sky-200/90" },
};

export function cardUtilization(used: string | bigint, limit: string | bigint): number {
  const usedMinor = typeof used === "bigint" ? used : BigInt(used);
  const limitMinor = typeof limit === "bigint" ? limit : BigInt(limit);
  if (limitMinor <= 0n) return 0;
  return Math.max(0, Number((usedMinor * 10_000n) / limitMinor) / 100);
}
