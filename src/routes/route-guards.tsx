import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { ErrorState, LoadingState } from "@/components/feedback";
import { toUserMessage } from "@/lib/errors";
import { useProfile } from "@/hooks/use-profile";

export function ProtectedRoute() {
  const { isLoading, user } = useAuth();
  if (isLoading) return <LoadingState label="Preparando tu espacio" />;
  if (!user) return <Navigate replace to="/login" />;
  return <ProfileGate userId={user.id} />;
}

function ProfileGate({ userId }: { userId: string }) {
  const location = useLocation();
  const profile = useProfile(userId);

  if (profile.isLoading) return <LoadingState label="Cargando tu perfil" />;
  if (profile.isError) {
    return <ErrorState message={toUserMessage(profile.error)} onRetry={() => void profile.refetch()} />;
  }
  if (!profile.data) return <ErrorState message="No encontramos tu perfil." />;

  const isOnboarding = location.pathname === "/onboarding";
  if (!profile.data.onboarding_completed && !isOnboarding) {
    return <Navigate replace to="/onboarding" />;
  }
  if (profile.data.onboarding_completed && isOnboarding) {
    return <Navigate replace to="/inicio" />;
  }
  return <Outlet />;
}

export function PublicOnlyRoute() {
  const { isLoading, user } = useAuth();
  if (isLoading) return <LoadingState label="Comprobando sesión" />;
  return user ? <Navigate replace to="/inicio" /> : <Outlet />;
}
