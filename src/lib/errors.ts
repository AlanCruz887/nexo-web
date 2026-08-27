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
};

export function toUserMessage(error: unknown): string {
  if (typeof error === "object" && error !== null) {
    const candidate = error as ErrorLike;
    const knownMessage = candidate.code ? knownMessages[candidate.code] : undefined;
    if (knownMessage) {
      return knownMessage;
    }

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
