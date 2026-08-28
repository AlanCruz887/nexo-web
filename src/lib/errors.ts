interface ErrorLike {
  code?: string;
  message?: string;
  status?: number;
}

const knownMessages: Record<string, string> = {
  invalid_credentials: "El correo o la contraseña no coinciden.",
  email_not_confirmed: "Confirma tu correo antes de iniciar sesión.",
  user_already_exists: "Ya existe una cuenta con ese correo.",
  weak_password: "Usa una contraseña más segura.",
  over_email_send_rate_limit: "Espera un momento antes de solicitar otro correo.",
  NEXO_ACCOUNT_ARCHIVED: "Esta cuenta está archivada y no acepta movimientos nuevos.",
  NEXO_ACCOUNT_NOT_FOUND: "No encontramos una de las cuentas o no tienes acceso a ella.",
  NEXO_IDEMPOTENCY_CONFLICT: "Esta solicitud ya se usó con datos diferentes. Actualiza e inténtalo de nuevo.",
  NEXO_INVALID_AMOUNT: "Revisa el importe e inténtalo de nuevo.",
  NEXO_TRANSFER_CURRENCY_MISMATCH: "Las transferencias entre monedas distintas todavía no están disponibles.",
  NEXO_TRANSFER_SAME_ACCOUNT: "Elige una cuenta de destino diferente.",
  NEXO_TRANSACTION_ALREADY_REVERSED: "Este movimiento ya fue revertido.",
  NEXO_CARD_NOT_FOUND: "No encontramos la tarjeta o no tienes acceso a ella.",
  NEXO_CARD_ARCHIVED: "Esta tarjeta está archivada.",
  NEXO_INVALID_BASELINE_AMOUNT: "Revisa el saldo del banco y el importe que quieres excluir.",
  NEXO_STATEMENT_ALREADY_CLOSED: "Ese estado de cuenta ya fue cerrado.",
  NEXO_INVALID_STATEMENT_DATE: "La fecha no corresponde a un corte válido de esta tarjeta.",
  NEXO_STATEMENT_BEFORE_BASELINE: "No puedes cerrar un estado anterior al baseline de la tarjeta.",
};

export function toUserMessage(error: unknown): string {
  if (typeof error === "object" && error !== null) {
    const candidate = error as ErrorLike;
    const knownMessage = candidate.code ? knownMessages[candidate.code] : undefined;
    if (knownMessage) {
      return knownMessage;
    }
    const domainMessage = candidate.message
      ? Object.entries(knownMessages).find(([code]) => candidate.message?.includes(code))?.[1]
      : undefined;
    if (domainMessage) return domainMessage;

    if (candidate.status === 429) {
      return "Demasiados intentos. Inténtalo de nuevo en unos minutos.";
    }
  }

  return "No pudimos completar la operación. Inténtalo de nuevo.";
}

export function reportError(context: string, error: unknown) {
  if (import.meta.env.DEV) {
    console.error(`[Nexo:${context}]`, error);
  }
}
