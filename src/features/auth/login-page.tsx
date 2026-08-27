import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { Link, useNavigate } from "react-router-dom";

import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { AuthCard } from "@/features/auth/auth-card";
import { reportError, toUserMessage } from "@/lib/errors";
import { loginSchema, type LoginInput } from "@/schemas/auth";
import { authService } from "@/services/auth-service";

export function LoginPage() {
  const navigate = useNavigate();
  const [submitError, setSubmitError] = useState<string>();
  const form = useForm<LoginInput>({ resolver: zodResolver(loginSchema) });

  async function onSubmit(input: LoginInput) {
    setSubmitError(undefined);
    try {
      await authService.signIn(input);
      navigate("/inicio", { replace: true });
    } catch (error) {
      reportError("login", error);
      setSubmitError(toUserMessage(error));
    }
  }

  return (
    <AuthCard
      description="Tu espacio privado para construir claridad financiera, una fase a la vez."
      footer={<>¿Aún no tienes cuenta? <Link className="font-medium text-primary hover:underline" to="/registro">Crear cuenta</Link></>}
      title="Bienvenido de vuelta"
    >
      <form className="space-y-4" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
        <FormField error={form.formState.errors.email?.message} id="email" label="Correo">
          <Input autoComplete="email" id="email" inputMode="email" {...form.register("email")} />
        </FormField>
        <FormField error={form.formState.errors.password?.message} id="password" label="Contraseña">
          <Input autoComplete="current-password" id="password" type="password" {...form.register("password")} />
        </FormField>
        {submitError ? <p className="text-sm text-danger" role="alert">{submitError}</p> : null}
        <Button className="w-full" disabled={form.formState.isSubmitting} type="submit">
          {form.formState.isSubmitting ? "Entrando…" : "Iniciar sesión"}
        </Button>
        <div className="text-center">
          <Link className="text-sm font-medium text-primary hover:underline" to="/recuperar-contrasena">Olvidé mi contraseña</Link>
        </div>
      </form>
    </AuthCard>
  );
}
