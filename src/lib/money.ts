import type { CurrencyCode } from "@/types/database";
import { currencyMinorUnits } from "@/types/money";
import type { MoneyMinor, MoneyMinorSerialized } from "@/types/money";
import { deserializeMoneyMinor, minorToDisplay } from "@/lib/money-core";

export type { MoneyMinor, MoneyMinorSerialized } from "@/types/money";
export {
  deserializeMoneyMinor,
  displayToMinor,
  minorToDisplay,
  parseMoneyInput,
  serializeMoneyMinor,
  splitPrincipalIntoInstallments,
} from "@/lib/money-core";

export interface FormatMoneyOptions {
  locale?: string;
  sign?: "auto" | "always" | "never";
}

export function formatMoney(
  value: MoneyMinor | MoneyMinorSerialized,
  currency: CurrencyCode,
  options: FormatMoneyOptions = {},
): string {
  const minor = typeof value === "bigint" ? value : deserializeMoneyMinor(value);
  const minorUnit = currencyMinorUnits[currency];
  const locale = options.locale ?? "es-MX";
  const sign = options.sign ?? "auto";
  const isNegative = minor < 0n;
  const absolute = isNegative ? -minor : minor;
  const decimal = minorToDisplay(absolute, minorUnit);
  const [whole = "0", fraction = ""] = decimal.split(".");
  const groupedWhole = new Intl.NumberFormat(locale, {
    useGrouping: true,
    maximumFractionDigits: 0,
  }).format(BigInt(whole));
  const signDisplay = sign === "always" ? "always" : "auto";
  const templateValue = isNegative && sign !== "never" ? -1 : 1;
  let integerWritten = false;

  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    minimumFractionDigits: minorUnit,
    maximumFractionDigits: minorUnit,
    signDisplay,
  })
    .formatToParts(templateValue)
    .map((part) => {
      if (part.type === "integer") {
        if (integerWritten) return "";
        integerWritten = true;
        return groupedWhole;
      }
      if (part.type === "group") return "";
      if (part.type === "fraction") return fraction;
      if (part.type === "minusSign" && sign === "never") return "";
      return part.value;
    })
    .join("");
}
