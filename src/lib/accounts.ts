import type { AccountBalance, CurrencyCode } from "@/types/database";

export function selectActiveAccounts(accounts: AccountBalance[]) {
  return accounts.filter((account) => account.is_active);
}

export function sumBalancesByCurrency(accounts: Array<{ balance_minor: string; currency: CurrencyCode }>) {
  return accounts.reduce<Partial<Record<CurrencyCode, bigint>>>((totals, account) => {
    totals[account.currency] = (totals[account.currency] ?? 0n) + BigInt(account.balance_minor);
    return totals;
  }, {});
}
