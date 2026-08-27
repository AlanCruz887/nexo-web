import { z } from "zod";

export const emailSchema = z.email("Escribe un correo válido.");

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, "Escribe tu contraseña."),
});

export const registrationSchema = z
  .object({
    fullName: z.string().trim().min(2, "Escribe tu nombre.").max(120),
    email: emailSchema,
    password: z.string().min(8, "Usa al menos 8 caracteres.").max(72),
    confirmPassword: z.string(),
  })
  .refine((values) => values.password === values.confirmPassword, {
    path: ["confirmPassword"],
    message: "Las contraseñas no coinciden.",
  });

export const passwordRecoverySchema = z.object({ email: emailSchema });

export const passwordUpdateSchema = z
  .object({
    password: z.string().min(8, "Usa al menos 8 caracteres.").max(72),
    confirmPassword: z.string(),
  })
  .refine((values) => values.password === values.confirmPassword, {
    path: ["confirmPassword"],
    message: "Las contraseñas no coinciden.",
  });

export type LoginInput = z.infer<typeof loginSchema>;
export type RegistrationInput = z.infer<typeof registrationSchema>;
export type PasswordRecoveryInput = z.infer<typeof passwordRecoverySchema>;
export type PasswordUpdateInput = z.infer<typeof passwordUpdateSchema>;
