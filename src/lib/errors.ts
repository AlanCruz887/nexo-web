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
  NEXO_STATEMENT_BEFORE_BASELINE: "No puedes cerrar un estado anterior a la fecha desde la que llevas esta tarjeta en Nexo.",
  NEXO_STATEMENT_NOT_DUE: "Ese corte todavía no ha llegado y no puede cerrarse anticipadamente.",
  NEXO_NO_STATEMENT_DUE: "No hay estados vencidos pendientes de cierre.",
  NEXO_STATEMENT_OUT_OF_ORDER: "Primero debes cerrar el estado pendiente más antiguo.",
  NEXO_CARD_PURCHASE_NOT_FOUND: "No encontramos la compra o no tienes acceso a ella.",
  NEXO_CARD_PAYMENT_NOT_FOUND: "No encontramos el pago o no tienes acceso a él.",
  NEXO_CARD_REFUND_NOT_FOUND: "No encontramos el reembolso o no tienes acceso a él.",
  NEXO_CLOSED_STATEMENT_CORRECTION_REQUIRED: "Esa compra ya pertenece a un estado cerrado. Registra un reembolso para corregirla sin perder el historial.",
  NEXO_CURRENCY_MISMATCH: "Elige una cuenta y una tarjeta con la misma moneda.",
  NEXO_EVENT_BEFORE_BASELINE: "No puedes registrar este movimiento porque es anterior a la fecha desde la que comenzaste a llevar esta tarjeta en Nexo.",
  NEXO_ORIGINAL_PURCHASE_NOT_FOUND: "La compra original no existe, fue revertida o pertenece a otra tarjeta.",
  NEXO_REFUND_EXCEEDS_PURCHASE: "Los reembolsos vinculados no pueden superar el importe de la compra original.",
  NEXO_INVALID_INSTALLMENT_COUNT: "Elige un plazo MSI válido entre 2 y 60 meses.",
  NEXO_INVALID_INSTALLMENT_AMOUNT: "La mensualidad no coincide con el importe total. Revisa los valores.",
  NEXO_INSTALLMENT_PLAN_NOT_FOUND: "No encontramos el plan MSI o no tienes acceso a él.",
  NEXO_MSI_REFUND_UNSUPPORTED: "Los reembolsos vinculados a MSI todavía no están disponibles. Registra una corrección solo cuando exista una política aprobada.",
  NEXO_MSI_REVERSE_REQUIRED: "Esta compra pertenece a un plan MSI y debe revertirse desde su detalle.",
  NEXO_MSI_CLOSED_STATEMENT_CORRECTION_REQUIRED: "Una mensualidad de este plan ya pertenece a un estado cerrado. Registra la corrección sin modificar ese estado.",
  NEXO_INVALID_HISTORICAL_INSTALLMENT_PROGRESS: "La mensualidad actual y las mensualidades pagadas no coinciden con el plazo del plan.",
  NEXO_INVALID_HISTORICAL_INSTALLMENT_AMOUNTS: "Revisa el importe original, cuánto has pagado y cuánto todavía debes.",
  NEXO_HISTORICAL_PURCHASE_IN_FUTURE: "La fecha original de compra de un MSI existente no puede estar en el futuro.",
  NEXO_HISTORICAL_MSI_NOT_IN_OPENING_PERIOD: "Este MSI comenzó después del inicio del seguimiento, así que no puede estar incluido en el saldo con el que registraste la tarjeta.",
  NEXO_CONTACT_NOT_FOUND: "No encontramos a la persona o ya no está disponible.",
  NEXO_PURCHASE_SPLIT_MISMATCH: "La parte personal y lo asignado a otras personas deben sumar el total de la compra.",
  NEXO_INVALID_PURCHASE_SPLIT: "Revisa cómo distribuiste esta compra.",
  NEXO_PERSON_PAYMENT_EXCEEDS_BALANCE: "El pago supera lo que esta persona te debe en la moneda de la cuenta elegida.",
  NEXO_PERSON_PAYMENT_NOT_FOUND: "No encontramos el pago recibido o no tienes acceso a él.",
  NEXO_RECEIVABLE_HAS_PAYMENTS: "Esta compra ya tiene cobros aplicados. En esta fase no puede editarse ni revertirse sin conservar esa aplicación.",
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
