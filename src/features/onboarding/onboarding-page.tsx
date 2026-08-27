import { Sparkles } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { ErrorState, LoadingState } from "@/components/feedback";
import { Card } from "@/components/ui/card";
import { ProfileForm } from "@/features/profile/profile-form";
import { useCurrencies } from "@/hooks/use-currencies";
import { useProfile, useUpdateProfile } from "@/hooks/use-profile";
import { reportError, toUserMessage } from "@/lib/errors";
import type { ProfileFormInput } from "@/schemas/profile";

export function OnboardingPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const profile = useProfile(user?.id);
  const currencies = useCurrencies();
  const updateProfile = useUpdateProfile(user?.id ?? "missing");
  const [error, setError] = useState<string>();

  if (!user || profile.isLoading || currencies.isLoading) return <LoadingState label="Preparando bienvenida" />;
  if (profile.isError || currencies.isError || !profile.data) {
    return <ErrorState message={toUserMessage(profile.error ?? currencies.error)} />;
  }

  async function handleSubmit(input: ProfileFormInput) {
    setError(undefined);
    try {
      await updateProfile.mutateAsync({ ...input, onboarding_completed: true });
      navigate("/inicio", { replace: true });
    } catch (submitError) {
      reportError("onboarding", submitError);
      setError(toUserMessage(submitError));
    }
  }

  return (
    <main className="grid min-h-screen place-items-center bg-background px-4 py-10 sm:px-6">
      <Card className="w-full max-w-2xl p-6 sm:p-10">
        <div className="mb-6 flex size-11 items-center justify-center rounded-xl bg-primary-soft text-primary">
          <Sparkles aria-hidden="true" className="size-5" />
        </div>
        <p className="text-sm font-semibold text-primary">Bienvenido a Nexo</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-[-0.04em] sm:text-4xl">Empecemos por lo esencial</h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground">Solo necesitamos tu nombre, moneda base y zona horaria. Las cuentas y tarjetas llegarán en sus fases correspondientes.</p>
        <div className="mt-8">
          <ProfileForm currencies={currencies.data ?? []} isPending={updateProfile.isPending} onSubmit={handleSubmit} profile={profile.data} submitLabel="Entrar a Nexo" />
        </div>
        {error ? <p className="mt-4 text-sm text-danger" role="alert">{error}</p> : null}
      </Card>
    </main>
  );
}
