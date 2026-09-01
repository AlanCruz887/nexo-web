import { z } from "zod";

export const shortcutTokenFormSchema = z.object({
  name: z.string().trim().min(1, "Escribe un nombre para este dispositivo.").max(60, "Usa un nombre más corto."),
});

export type ShortcutTokenFormInput = z.infer<typeof shortcutTokenFormSchema>;
