import { z } from "zod";

import { isValidTimezone } from "@/lib/dates";

export const currencyCodeSchema = z.enum(["MXN", "USD", "EUR"]);

export const profileFormSchema = z.object({
  full_name: z.string().trim().min(2, "Escribe tu nombre.").max(120),
  base_currency: currencyCodeSchema,
  timezone: z
    .string()
    .trim()
    .min(1, "Selecciona una zona horaria.")
    .refine(isValidTimezone, "La zona horaria no es válida."),
});

export type ProfileFormInput = z.infer<typeof profileFormSchema>;
