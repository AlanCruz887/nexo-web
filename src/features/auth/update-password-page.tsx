import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { Link } from "react-router-dom";

import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { AuthCard } from "@/features/auth/auth-card";
import { reportError, toUserMessage } from "@/lib/errors";
import { passwordUpdateSchema, type PasswordUpdateInput } from "@/schemas/auth";
import { authService } from "@/services/auth-service";

export function UpdatePasswordPage() {
  const [feedback, setFeedback] = useState<{ kind: "error" | "success"; message: string }>();
  const form = useForm<PasswordUpdateInput>({ resolver: zodResolver(passwordUpdateSchema) });

  async function onSubmit(input: PasswordUpdateInput) {
    setFeedback(undefined);
    try {
      await authService.updatePassword(input);
      setFeedback({ kind: "success", message: "Tu contraseña quedó actualizada." });
      form.reset();
    } catch (error) {
      reportError("password-update", error);
      setFeedback({ kind: "error", message: toUserMessage(error) });
    }
  }

  return (
    <AuthCard
      description="Elige una contraseña nueva para tu cuenta."
      footer={<Link className="inline-flex min-h-11 items-center px-2 font-medium text-primary hover:underline" to="/login">Continuar a Nexo</Link>}
      title="Nueva contraseña"
    >
      <form className="space-y-4" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
        <FormField error={form.formState.errors.password?.message} id="password" label="Nueva contraseña">
          <Input autoComplete="new-password" id="password" type="password" {...form.register("password")} />
        </FormField>
        <FormField error={form.formState.errors.confirmPassword?.message} id="confirmPassword" label="Confirmar contraseña">
          <Input autoComplete="new-password" id="confirmPassword" type="password" {...form.register("confirmPassword")} />
        </FormField>
        {feedback ? <p className={feedback.kind === "error" ? "text-sm text-danger" : "text-sm text-success"} role="status">{feedback.message}</p> : null}
        <Button className="w-full" disabled={form.formState.isSubmitting} type="submit">Guardar contraseña</Button>
      </form>
    </AuthCard>
  );
}
