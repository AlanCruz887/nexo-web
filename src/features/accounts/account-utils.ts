import type { AccountType } from "@/types/database";

export const accountTypeLabels: Record<AccountType, string> = {
  checking: "Cuenta corriente",
  savings: "Ahorro",
  cash: "Efectivo",
  debit: "Débito",
  investment: "Inversión",
  other: "Otra cuenta",
};

export const accountTypeOptions = Object.entries(accountTypeLabels) as Array<[AccountType, string]>;
