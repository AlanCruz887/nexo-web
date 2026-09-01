export interface MappedError {
  status: number;
  code: string;
  message: string;
}

// Every NEXO_* code the SQL layer can hand back to these two Edge
// Functions, mapped once, here, to an HTTP status and a message safe to
// show the user. Never derived ad hoc at each call site.
const KNOWN_ERRORS: Record<string, MappedError> = {
  NEXO_SHORTCUT_TOKEN_MISSING: { status: 401, code: "NEXO_SHORTCUT_TOKEN_MISSING", message: "Falta el token de acceso." },
  NEXO_SHORTCUT_TOKEN_INVALID: { status: 401, code: "NEXO_SHORTCUT_TOKEN_INVALID", message: "El token no es válido." },
  NEXO_SHORTCUT_TOKEN_REVOKED: { status: 401, code: "NEXO_SHORTCUT_TOKEN_REVOKED", message: "Este acceso fue revocado." },
  NEXO_SHORTCUT_TOKEN_EXPIRED: { status: 401, code: "NEXO_SHORTCUT_TOKEN_EXPIRED", message: "Este acceso expiró." },
  NEXO_SHORTCUT_SCOPE_DENIED: { status: 403, code: "NEXO_SHORTCUT_SCOPE_DENIED", message: "Este acceso no tiene permiso para esta acción." },
  NEXO_SHORTCUT_RATE_LIMITED: { status: 429, code: "NEXO_SHORTCUT_RATE_LIMITED", message: "Demasiadas solicitudes. Intenta de nuevo en un momento." },
  NEXO_SHORTCUT_INVALID_SOURCE_TYPE: { status: 400, code: "NEXO_SHORTCUT_INVALID_SOURCE_TYPE", message: "El tipo de origen no es válido." },
  NEXO_SHORTCUT_EXECUTION_ID_REQUIRED: { status: 400, code: "NEXO_SHORTCUT_EXECUTION_ID_REQUIRED", message: "Falta el identificador de la operación." },
  NEXO_IDEMPOTENCY_CONFLICT: { status: 409, code: "NEXO_IDEMPOTENCY_CONFLICT", message: "Esta compra ya había sido registrada con datos diferentes." },
  NEXO_ACCOUNT_NOT_FOUND: { status: 404, code: "NEXO_ACCOUNT_NOT_FOUND", message: "No encontramos esa cuenta." },
  NEXO_CARD_NOT_FOUND: { status: 404, code: "NEXO_CARD_NOT_FOUND", message: "No encontramos esa tarjeta." },
  NEXO_ACCOUNT_ARCHIVED: { status: 409, code: "NEXO_ACCOUNT_ARCHIVED", message: "Esa cuenta ya no está activa." },
  NEXO_CARD_ARCHIVED: { status: 409, code: "NEXO_CARD_ARCHIVED", message: "Esa tarjeta ya no está activa." },
  NEXO_INVALID_AMOUNT: { status: 400, code: "NEXO_INVALID_AMOUNT", message: "El importe no es válido." },
  NEXO_EVENT_BEFORE_BASELINE: { status: 400, code: "NEXO_EVENT_BEFORE_BASELINE", message: "La fecha es anterior al inicio de esta tarjeta en Nexo." },
  NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED: { status: 409, code: "NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED", message: "El corte de esa fecha ya está cerrado." },
  NEXO_CATEGORY_INVALID: { status: 400, code: "NEXO_CATEGORY_INVALID", message: "La categoría no es válida." },
};

const GENERIC_ERROR: MappedError = { status: 500, code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." };

/**
 * Maps a raw error string (a NEXO_* code, or -- for the one case with no
 * synthetic code, an invalid category_id -- a raw Postgres foreign_key_
 * violation message) to a safe HTTP response. Anything unrecognized
 * becomes a generic 500: the real message is for server-side logs only,
 * never echoed to the client (see logSafeError in this same file).
 */
export function classifyError(rawMessage: string): MappedError {
  const trimmed = rawMessage.trim();
  const known = KNOWN_ERRORS[trimmed];
  if (known) return known;
  if (/foreign key/i.test(trimmed) && /category_id/i.test(trimmed)) {
    return KNOWN_ERRORS.NEXO_CATEGORY_INVALID;
  }
  return GENERIC_ERROR;
}

/**
 * Logs an error server-side (Supabase Function logs), truncated and
 * with no request data attached, for operators to debug -- never
 * returned to the client. Callers must pass ONLY the error text, never
 * the Authorization header or the raw token.
 */
export function logSafeError(context: string, message: string): void {
  console.error(`[${context}]`, message.slice(0, 500));
}
