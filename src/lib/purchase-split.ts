import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";

export type PurchaseSplitInput = {
  amount: string;
  purchase_scope: "self" | "other" | "shared";
  personal_amount: string;
  allocations: { contact_id: string; amount: string }[];
};

export function resolvePurchaseSplit(input: PurchaseSplitInput) {
  const total = parseMoneyInput(input.amount);
  if (input.purchase_scope === "self") return { personalAmountMinor: serializeMoneyMinor(total), allocations: [] };
  const allocations = input.allocations.map((item, index) => ({
    contact_id: item.contact_id,
    amount_minor: serializeMoneyMinor(input.purchase_scope === "other" && index === 0 ? total : parseMoneyInput(item.amount)),
  }));
  const personal = input.purchase_scope === "other" ? 0n : parseMoneyInput(input.personal_amount);
  const allocated = allocations.reduce((sum, item) => sum + BigInt(item.amount_minor), 0n);
  if (allocations.length === 0 || allocations.some((item) => BigInt(item.amount_minor) <= 0n) || total !== personal + allocated) {
    throw new Error("NEXO_PURCHASE_SPLIT_MISMATCH");
  }
  return { personalAmountMinor: serializeMoneyMinor(personal), allocations };
}
