// Pure presentation helper: available_minor from the domain can be negative
// (spent past the limit) -- showing "Disponible -$5,000" reads as if $5,000
// were still free to spend. Below zero, the same figure is reframed as how
// much was exceeded, using its absolute value; the domain value itself
// never changes.
export function resolveBudgetAvailability(availableMinor: string): { label: string; amountMinor: string; isExceeded: boolean } {
  const value = BigInt(availableMinor);
  if (value < 0n) return { label: "Excedido por", amountMinor: (-value).toString(), isExceeded: true };
  return { label: "Disponible", amountMinor: availableMinor, isExceeded: false };
}
