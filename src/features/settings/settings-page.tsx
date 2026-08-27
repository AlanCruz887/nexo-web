import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";

import { useAuth } from "@/app/auth-provider";
import { type ThemePreference, usePreferences } from "@/app/preferences-provider";
import { ErrorState } from "@/components/feedback";
import { FormField } from "@/components/form-field";
import { PageHeader } from "@/components/page-header";
import { PageTransition } from "@/components/page-transition";
import { SettingsSkeleton } from "@/components/skeletons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useCurrencies } from "@/hooks/use-currencies";
import { useProfile, useUpdateProfile } from "@/hooks/use-profile";
import { getBrowserTimezone } from "@/lib/dates";
import { reportError, toUserMessage } from "@/lib/errors";
import { profileFormSchema, type ProfileFormInput } from "@/schemas/profile";

export function SettingsPage() {
  const { signOut, user } = useAuth();
  const { hideMoney, setHideMoney, setTheme, theme } = usePreferences();
  const profile = useProfile(user?.id);
  const currencies = useCurrencies();
  const updateProfile = useUpdateProfile(user?.id ?? "missing");
  const [feedback, setFeedback] = useState<string>();
  const form = useForm<ProfileFormInput>({ resolver: zodResolver(profileFormSchema) });

  useEffect(() => {
    if (profile.data) {
      form.reset({
        full_name: profile.data.full_name,
        base_currency: profile.data.base_currency,
        timezone: profile.data.timezone,
      });
    }
  }, [form, profile.data]);

  if (!user || (profile.isLoading && !profile.data) || (currencies.isLoading && !currencies.data)) return <SettingsSkeleton />;
  if (profile.isError || currencies.isError || !profile.data) return <ErrorState message={toUserMessage(profile.error ?? currencies.error)} />;

  async function onSubmit(input: ProfileFormInput) {
    setFeedback(undefined);
    try {
      await updateProfile.mutateAsync({ ...input, onboarding_completed: true });
      setFeedback("Configuración guardada.");
    } catch (error) {
      reportError("settings", error);
      setFeedback(toUserMessage(error));
    }
  }

  const timezoneOptions = Array.from(new Set([profile.data.timezone, getBrowserTimezone(), "America/Mexico_City", "America/New_York", "Europe/Madrid", "UTC"]));

  return (
    <PageTransition>
      <div className="max-w-4xl space-y-10">
        <PageHeader eyebrow="Tu cuenta" subtitle="Perfil, privacidad y preferencias de Nexo." title="Configuración" />
        <div className="divide-y divide-border/60 border-y border-border/60">
          <section className="grid gap-6 py-8 md:grid-cols-[220px_1fr]"><div><h2 className="font-semibold">Perfil</h2><p className="mt-1 text-sm text-muted-foreground">Tu identidad y contexto financiero base.</p></div>
            <form className="grid gap-5 sm:grid-cols-2" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
              <div className="sm:col-span-2">
              <FormField error={form.formState.errors.full_name?.message} id="full_name" label="Nombre">
                <Input id="full_name" {...form.register("full_name")} />
              </FormField>
              </div>
              <FormField error={form.formState.errors.base_currency?.message} id="base_currency" label="Moneda base">
                <Select id="base_currency" {...form.register("base_currency")}>
                  {(currencies.data ?? []).map((currency) => <option key={currency.code} value={currency.code}>{currency.code} · {currency.name}</option>)}
                </Select>
              </FormField>
              <FormField error={form.formState.errors.timezone?.message} id="timezone" label="Zona horaria">
                <Select id="timezone" {...form.register("timezone")}>
                  {timezoneOptions.map((timezone) => <option key={timezone} value={timezone}>{timezone}</option>)}
                </Select>
              </FormField>
              <div className="flex items-center gap-3 sm:col-span-2"><Button disabled={updateProfile.isPending} type="submit">Guardar perfil</Button>{feedback ? <p className="text-sm text-muted-foreground" role="status">{feedback}</p> : null}</div>
            </form>
          </section>

          <section className="grid gap-6 py-8 md:grid-cols-[220px_1fr]"><div><h2 className="font-semibold">Apariencia</h2><p className="mt-1 text-sm text-muted-foreground">Tema y privacidad de cantidades.</p></div>
            <div className="grid gap-5 sm:grid-cols-2">
              <FormField id="theme" label="Tema">
                <Select id="theme" onChange={(event) => setTheme(event.target.value as ThemePreference)} value={theme}>
                  <option value="system">Sistema</option>
                  <option value="light">Claro</option>
                  <option value="dark">Oscuro</option>
                </Select>
              </FormField>
              <div className="space-y-2">
                <span className="block text-sm font-medium">Cantidades</span>
                <Button onClick={() => setHideMoney(!hideMoney)} type="button" variant="secondary">{hideMoney ? "Mostrar cantidades" : "Ocultar cantidades"}</Button>
              </div>
            </div>
          </section>

          <section className="grid gap-6 py-8 md:grid-cols-[220px_1fr]"><div><h2 className="font-semibold">Sesión</h2><p className="mt-1 text-sm text-muted-foreground">Acceso actual a Nexo.</p></div><div><p className="text-sm font-medium">{user.email}</p><Button className="mt-4" onClick={() => void signOut()} type="button" variant="secondary">Cerrar sesión</Button></div></section>
        </div>
      </div>
    </PageTransition>
  );
}
