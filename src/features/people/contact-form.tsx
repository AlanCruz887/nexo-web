import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { FormField } from "@/components/form-field";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/toast";
import { useCreateContact, useUpdateContact } from "@/hooks/use-contacts";
import { toUserMessage } from "@/lib/errors";
import { contactSchema, type ContactInput } from "@/schemas/contact";
import type { Contact } from "@/types/database";

export function ContactForm({ contact, onOpenChange, open }: { contact?: Contact; onOpenChange: (open: boolean) => void; open: boolean }) {
  const create = useCreateContact(); const update = useUpdateContact(contact?.id ?? "missing"); const toast = useToast();
  const form = useForm<ContactInput>({ resolver: zodResolver(contactSchema), defaultValues: { name: "", email: "", phone: "", notes: "" } });
  useEffect(() => { form.reset(contact ? { name: contact.name, email: contact.email ?? "", phone: contact.phone ?? "", notes: contact.notes ?? "" } : { name: "", email: "", phone: "", notes: "" }); }, [contact, form, open]);
  async function submit(input: ContactInput) { try { await (contact ? update : create).mutateAsync(input); toast.success(contact ? "Persona actualizada" : "Persona agregada"); onOpenChange(false); } catch (error) { form.setError("root", { message: toUserMessage(error) }); } }
  const mutation = contact ? update : create;
  return <ResponsiveDialog description="Guarda solo los datos que necesites para identificarla." footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="contact-form" type="submit">{mutation.isPending ? "Guardando…" : "Guardar"}</Button></>} onOpenChange={onOpenChange} open={open} size="small" title={contact ? "Editar persona" : "Nueva persona"}>
    <form className="space-y-5" id="contact-form" onSubmit={(event) => void form.handleSubmit(submit)(event)}>
      <FormField error={form.formState.errors.name?.message} id="contact-name" label="Nombre"><Input autoFocus id="contact-name" placeholder="Carlos" {...form.register("name")} /></FormField>
      <FormField error={form.formState.errors.email?.message} id="contact-email" label="Correo (opcional)"><Input id="contact-email" inputMode="email" {...form.register("email")} /></FormField>
      <FormField error={form.formState.errors.phone?.message} id="contact-phone" label="Teléfono (opcional)"><Input id="contact-phone" inputMode="tel" {...form.register("phone")} /></FormField>
      <FormField error={form.formState.errors.notes?.message} id="contact-notes" label="Notas (opcional)"><textarea className="min-h-24 w-full resize-none rounded-xl border border-border bg-surface px-3.5 py-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/20" id="contact-notes" {...form.register("notes")} /></FormField>
      {form.formState.errors.root ? <p className="text-sm text-danger" role="alert">{form.formState.errors.root.message}</p> : null}
    </form>
  </ResponsiveDialog>;
}
