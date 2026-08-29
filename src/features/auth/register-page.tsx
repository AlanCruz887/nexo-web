import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { Link, useNavigate } from "react-router-dom";

import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { AuthCard } from "@/features/auth/auth-card";
import { reportError, toUserMessage } from "@/lib/errors";
import { registrationSchema, type RegistrationInput } from "@/schemas/auth";
import { authService } from "@/services/auth-service";

export function RegisterPage() {
  const navigate = useNavigate();
  const [feedback, setFeedback] = useState<{ kind: "error" | "success"; message: string }>();
  const form = useForm<RegistrationInput>({ resolver: zodResolver(registrationSchema) });

  async function onSubmit(input: RegistrationInput) {
    setFeedback(undefined);
    try {
      const result = await authService.signUp(input);
      if (result.session) {
        navigate("/onboarding", { replace: true });
      } else {
        setFeedback({ kind: "success", message: "Revisa tu correo para confirmar la cuenta." });
      }
    } catch (error) {
      reportError("registration", error);
      setFeedback({ kind: "error", message: toUserMessage(error) });
    }
  }

  return (
    <AuthCard
      description="Crea tu acceso. La configuración financiera comienza después del fundamento inicial."
      footer={<>¿Ya tienes cuenta? <Link className="-mx-2 inline-flex min-h-11 items-center px-2 font-medium text-primary hover:underline" to="/login">Iniciar sesión</Link></>}
      title="Crear cuenta"
    >
      <form className="space-y-4" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
        <FormField error={form.formState.errors.fullName?.message} id="fullName" label="Nombre">
          <Input autoComplete="name" id="fullName" {...form.register("fullName")} />
        </FormField>
        <FormField error={form.formState.errors.email?.message} id="email" label="Correo">
          <Input autoComplete="email" id="email" inputMode="email" {...form.register("email")} />
        </FormField>
        <FormField error={form.formState.errors.password?.message} hint="Mínimo 8 caracteres." id="password" label="Contraseña">
          <Input autoComplete="new-password" id="password" type="password" {...form.register("password")} />
        </FormField>
        <FormField error={form.formState.errors.confirmPassword?.message} id="confirmPassword" label="Confirmar contraseña">
          <Input autoComplete="new-password" id="confirmPassword" type="password" {...form.register("confirmPassword")} />
        </FormField>
        {feedback ? <p className={feedback.kind === "error" ? "text-sm text-danger" : "text-sm text-success"} role="status">{feedback.message}</p> : null}
        <Button className="w-full" disabled={form.formState.isSubmitting} type="submit">
          {form.formState.isSubmitting ? "Creando…" : "Crear mi cuenta"}
        </Button>
      </form>
    </AuthCard>
  );
}
