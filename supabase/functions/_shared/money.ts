// Re-exports the SAME pure module the frontend uses (src/lib/money.ts
// re-exports from this exact file too) -- one implementation of decimal
// string -> exact bigint minor units, imported by both Vite and Deno via
// plain relative paths, never copied. See src/lib/money-core.ts.
export { currencyMinorUnits, parseMoneyInput } from "../../../src/lib/money-core.ts";
