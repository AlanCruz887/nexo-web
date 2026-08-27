import type { CurrencyCode } from "@/types/database";

/** Exact domain representation while money is inside TypeScript. */
export type MoneyMinor = bigint;

/** JSON/PostgREST-safe representation for PostgreSQL bigint values. */
export type MoneyMinorSerialized = string;

export const currencyMinorUnits: Readonly<Record<CurrencyCode, number>> = {
  MXN: 2,
  USD: 2,
  EUR: 2,
};
