import type { CurrencyCode } from "@/types/database";
import {
  currencyMinorUnits,
  type MoneyMinor,
  type MoneyMinorSerialized,
} from "@/types/money";

export interface FormatMoneyOptions {
  locale?: string;
  sign?: "auto" | "always" | "never";
}

function assertMinorUnit(minorUnit: number) {
  if (!Number.isInteger(minorUnit) || minorUnit < 0 || minorUnit > 6) {
    throw new RangeError("La escala monetaria debe ser un entero entre 0 y 6.");
  }
}

export function serializeMoneyMinor(value: MoneyMinor): MoneyMinorSerialized {
  return value.toString();
}

export function deserializeMoneyMinor(value: MoneyMinorSerialized): MoneyMinor {
  if (!/^-?\d+$/.test(value)) {
    throw new TypeError("El importe serializado debe contener unidades menores enteras.");
  }

  return BigInt(value);
}

export function minorToDisplay(value: MoneyMinor, minorUnit = 2): string {
  assertMinorUnit(minorUnit);

  const negative = value < 0n;
  const absolute = negative ? -value : value;
  const digits = absolute.toString().padStart(minorUnit + 1, "0");

  if (minorUnit === 0) {
    return `${negative ? "-" : ""}${digits}`;
  }

  const whole = digits.slice(0, -minorUnit);
  const fraction = digits.slice(-minorUnit);
  return `${negative ? "-" : ""}${whole}.${fraction}`;
}

export function parseMoneyInput(input: string, minorUnit = 2): MoneyMinor {
  assertMinorUnit(minorUnit);

  const compact = input.trim().replace(/[\s\p{Sc}\p{L}]/gu, "");
  if (!compact) {
    throw new TypeError("Escribe un importe.");
  }

  const negative = compact.startsWith("-");
  const unsigned = compact.replace(/^[+-]/, "");
  if (!/^[\d.,]+$/.test(unsigned)) {
    throw new TypeError("El importe contiene caracteres no válidos.");
  }

  const separatorIndex = Math.max(unsigned.lastIndexOf("."), unsigned.lastIndexOf(","));
  const digitsAfterSeparator =
    separatorIndex >= 0 ? unsigned.length - separatorIndex - 1 : 0;
  const separatorIsDecimal =
    separatorIndex >= 0 && digitsAfterSeparator > 0 && digitsAfterSeparator <= minorUnit;

  const wholeSource = separatorIsDecimal ? unsigned.slice(0, separatorIndex) : unsigned;
  const fractionSource = separatorIsDecimal ? unsigned.slice(separatorIndex + 1) : "";
  const decimalSeparator = separatorIsDecimal ? unsigned[separatorIndex] : undefined;
  if (decimalSeparator && wholeSource.includes(decimalSeparator)) {
    throw new TypeError("El importe contiene separadores decimales ambiguos.");
  }
  const whole = wholeSource.replace(/[.,]/g, "") || "0";
  const fraction = fractionSource.padEnd(minorUnit, "0");

  if (fraction.length > minorUnit || !/^\d+$/.test(`${whole}${fraction}`)) {
    throw new TypeError("El importe tiene demasiados decimales.");
  }

  const units = BigInt(`${whole}${fraction}` || "0");
  return negative ? -units : units;
}

export const displayToMinor = parseMoneyInput;

export function splitPrincipalIntoInstallments(principal: MoneyMinor, count: number, regularAmount?: MoneyMinor): MoneyMinor[] {
  if (principal <= 0n || !Number.isInteger(count) || count < 2) throw new RangeError("El plan MSI no es válido.");
  const regular = regularAmount ?? principal / BigInt(count);
  const last = principal - regular * BigInt(count - 1);
  if (regular <= 0n || last <= 0n) throw new RangeError("La mensualidad no permite completar el importe original.");
  return [...Array<MoneyMinor>(count - 1).fill(regular), last];
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
