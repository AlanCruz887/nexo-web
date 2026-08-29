import { formatFinancialDate } from "@/lib/dates";

export function purchaseStartDateError(transactionDate: string, controlledSince: string) {
  if (transactionDate >= controlledSince) return null;
  const formatted = formatFinancialDate(controlledSince, "dd 'de' MMMM 'de' yyyy");
  return {
    field: `Elige una fecha a partir del ${formatted}.`,
    message: `No puedes registrar esta compra porque es anterior a la fecha desde la que comenzaste a llevar esta tarjeta en Nexo. Esta tarjeta se controla desde el ${formatted}.`,
  };
}
