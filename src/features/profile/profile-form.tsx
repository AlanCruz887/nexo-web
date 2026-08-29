import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { getBrowserTimezone } from "@/lib/dates";
import { profileFormSchema, type ProfileFormInput } from "@/schemas/profile";
import type { Currency, Profile } from "@/types/database";

interface ProfileFormProps {
  currencies: Currency[];
  isPending: boolean;
  onSubmit: (input: ProfileFormInput) => Promise<void>;
  profile: Profile;
  submitLabel: string;
}

export function ProfileForm({ currencies, isPending, onSubmit, profile, submitLabel }: ProfileFormProps) {
  const form = useForm<ProfileFormInput>({
    resolver: zodResolver(profileFormSchema),
    defaultValues: {
      full_name: profile.full_name,
      base_currency: profile.base_currency,
      timezone: profile.timezone === "UTC" ? getBrowserTimezone() : profile.timezone,
    },
  });

  useEffect(() => {
    form.reset({
      full_name: profile.full_name,
      base_currency: profile.base_currency,
      timezone: profile.timezone === "UTC" ? getBrowserTimezone() : profile.timezone,
    });
  }, [form, profile]);

  const browserTimezone = getBrowserTimezone();
  const timezoneOptions = Array.from(new Set([browserTimezone, "America/Mexico_City", "America/New_York", "Europe/Madrid", "UTC"]));

  return (
    <form className="space-y-5" onSubmit={(event) => void form.handleSubmit(onSubmit)(event)}>
      <FormField error={form.formState.errors.full_name?.message} id="full_name" label="Nombre">
        <Input autoComplete="name" id="full_name" {...form.register("full_name")} />
      </FormField>
      <FormField error={form.formState.errors.base_currency?.message} hint="Será la moneda principal de tus resúmenes. Las demás se mostrarán por separado." id="base_currency" label="Moneda principal">
        <Select id="base_currency" {...form.register("base_currency")}>
          {currencies.map((currency) => <option key={currency.code} value={currency.code}>{currency.code} · {currency.name}</option>)}
        </Select>
      </FormField>
      <FormField error={form.formState.errors.timezone?.message} hint="Ayuda a mostrar las fechas en tu horario local." id="timezone" label="Zona horaria">
        <Select id="timezone" {...form.register("timezone")}>
          {timezoneOptions.map((timezone) => <option key={timezone} value={timezone}>{timezone}</option>)}
        </Select>
      </FormField>
      <Button disabled={isPending} type="submit">{isPending ? "Guardando…" : submitLabel}</Button>
    </form>
  );
}
