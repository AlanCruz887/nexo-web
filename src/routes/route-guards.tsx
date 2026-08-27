import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useAuth } from "@/app/auth-provider";
import { ErrorState } from "@/components/feedback";
import { StartupSplash } from "@/components/skeletons";
import { toUserMessage } from "@/lib/errors";
import { useProfile } from "@/hooks/use-profile";

export function ProtectedRoute() {
  const { isLoading, user } = useAuth();
  if (isLoading) return <StartupSplash />;
  if (!user) return <Navigate replace to="/login" />;
  return <ProfileGate userId={user.id} />;
}

function ProfileGate({ userId }: { userId: string }) {
  const location = useLocation();
  const profile = useProfile(userId);

  if (profile.isLoading) return <StartupSplash />;
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
  if (isLoading) return <StartupSplash />;
  return user ? <Navigate replace to="/inicio" /> : <Outlet />;
}
