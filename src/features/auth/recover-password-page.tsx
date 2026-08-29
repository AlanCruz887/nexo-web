import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { Link } from "react-router-dom";

import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { AuthCard } from "@/features/auth/auth-card";
import { reportError, toUserMessage } from "@/lib/errors";
import { passwordRecoverySchema, type PasswordRecoveryInput } from "@/schemas/auth";
import { authService } from "@/services/auth-service";

export function RecoverPasswordPage() {
  const [feedback, setFeedback] = useState<string>();
  const [error, setError] = useState<string>();
  const form = useForm<PasswordRecoveryInput>({ resolver: zodResolver(passwordRecoverySchema) });

  async function onSubmit(input: PasswordRecoveryInput) {
    setError(undefined);
    try {
      await authService.requestPasswordReset(input);
      setFeedback("Si existe una cuenta con ese correo, recibirás instrucciones para continuar.");
    } catch (submitError) {
      reportError("password-recovery", submitError);
      setError(toUserMessage(submitError));
    }
  }

  return (
    <AuthCard
      description="Te enviaremos un enlace seguro para elegir una contraseña nueva."
      footer={<Link className="inline-flex min-h-11 items-center px-2 font-medium text-primary hover:underline" to="/login">Volver al inicio de sesión</Link>}
      title="Recuperar contraseña"
    >
      <form className="space-y-4" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
        <FormField error={form.formState.errors.email?.message} id="email" label="Correo">
          <Input autoComplete="email" id="email" inputMode="email" {...form.register("email")} />
        </FormField>
        {feedback ? <p className="text-sm text-success" role="status">{feedback}</p> : null}
        {error ? <p className="text-sm text-danger" role="alert">{error}</p> : null}
        <Button className="w-full" disabled={form.formState.isSubmitting} type="submit">Enviar instrucciones</Button>
      </form>
    </AuthCard>
  );
}
