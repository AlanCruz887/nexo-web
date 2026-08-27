import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";

import { useAuth } from "@/app/auth-provider";
import { type ThemePreference, usePreferences } from "@/app/preferences-provider";
import { ErrorState, LoadingState } from "@/components/feedback";
import { FormField } from "@/components/form-field";
import { PageTransition } from "@/components/page-transition";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
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

  if (!user || profile.isLoading || currencies.isLoading) return <LoadingState label="Cargando configuración" />;
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
      <div className="max-w-2xl">
        <p className="text-sm font-semibold text-primary">Preferencias</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Configuración</h1>
        <div className="mt-6 space-y-5">
          <Card>
            <h2 className="text-lg font-semibold">Perfil</h2>
            <form className="mt-5 space-y-5" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
              <FormField error={form.formState.errors.full_name?.message} id="full_name" label="Nombre">
                <Input id="full_name" {...form.register("full_name")} />
              </FormField>
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
              <Button disabled={updateProfile.isPending} type="submit">Guardar perfil</Button>
              {feedback ? <p className="text-sm text-muted-foreground" role="status">{feedback}</p> : null}
            </form>
          </Card>

          <Card>
            <h2 className="text-lg font-semibold">Apariencia y privacidad</h2>
            <div className="mt-5 grid gap-5 sm:grid-cols-2">
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
          </Card>

          <Card>
            <h2 className="text-lg font-semibold">Sesión</h2>
            <p className="mt-1 text-sm text-muted-foreground">{user.email}</p>
            <Button className="mt-4" onClick={() => void signOut()} type="button" variant="secondary">Cerrar sesión</Button>
          </Card>
        </div>
      </div>
    </PageTransition>
  );
}
