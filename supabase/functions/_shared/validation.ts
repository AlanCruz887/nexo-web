import { HttpError } from "./http.ts";
import { isValidDateString } from "./date.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const AMOUNT_PATTERN = /^-?[\d.,]{1,20}$/;

export function isValidUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export interface ShortcutTransactionInput {
  shortcutExecutionId: string;
  sourceType: "account" | "card";
  sourceId: string;
  amount: string;
  categoryId: string;
  description: string;
  transactionDate?: string;
}

/**
 * Validates the raw JSON body against the fixed HTTP contract, before
 * anything is passed to the domain. Every rejection here is a 400 --
 * never a hint about which financial rule matched, since none has been
 * evaluated yet.
 */
export function validateShortcutTransactionBody(body: Record<string, unknown>): ShortcutTransactionInput {
  const shortcutExecutionId = body.shortcut_execution_id;
  if (!isValidUuid(shortcutExecutionId)) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "shortcut_execution_id debe ser un UUID válido.");
  }

  const sourceType = body.source_type;
  if (sourceType !== "account" && sourceType !== "card") {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "source_type debe ser 'account' o 'card'.");
  }

  const sourceId = body.source_id;
  if (!isValidUuid(sourceId)) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "source_id debe ser un UUID válido.");
  }

  const amount = body.amount;
  if (typeof amount !== "string" || !AMOUNT_PATTERN.test(amount)) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "amount debe ser un importe decimal en texto, por ejemplo \"450.50\".");
  }

  const categoryId = body.category_id;
  if (typeof categoryId !== "string" || categoryId.length === 0 || categoryId.length > 40) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "category_id es obligatorio.");
  }

  const description = body.description;
  if (typeof description !== "string" || description.trim().length === 0 || description.length > 160) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "description debe tener entre 1 y 160 caracteres.");
  }

  let transactionDate: string | undefined;
  if (body.transaction_date !== undefined && body.transaction_date !== null) {
    if (typeof body.transaction_date !== "string" || !isValidDateString(body.transaction_date)) {
      throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "transaction_date debe tener el formato YYYY-MM-DD y ser una fecha real.");
    }
    transactionDate = body.transaction_date;
  }

  return {
    shortcutExecutionId: shortcutExecutionId as string,
    sourceType,
    sourceId: sourceId as string,
    amount,
    categoryId,
    description: description.trim(),
    transactionDate,
  };
}
