import { createBrowserRouter, Navigate } from "react-router-dom";

import { AppShell } from "@/layouts/app-shell";
import { ProtectedRoute, PublicOnlyRoute } from "@/routes/route-guards";

export const router = createBrowserRouter([
  { path: "/", element: <Navigate replace to="/inicio" /> },
  {
    element: <PublicOnlyRoute />,
    children: [
      { path: "/login", lazy: async () => ({ Component: (await import("@/features/auth/login-page")).LoginPage }) },
      { path: "/registro", lazy: async () => ({ Component: (await import("@/features/auth/register-page")).RegisterPage }) },
      { path: "/recuperar-contrasena", lazy: async () => ({ Component: (await import("@/features/auth/recover-password-page")).RecoverPasswordPage }) },
    ],
  },
  { path: "/actualizar-contrasena", lazy: async () => ({ Component: (await import("@/features/auth/update-password-page")).UpdatePasswordPage }) },
  {
    element: <ProtectedRoute />,
    children: [
      { path: "/onboarding", lazy: async () => ({ Component: (await import("@/features/onboarding/onboarding-page")).OnboardingPage }) },
      {
        element: <AppShell />,
        children: [
          { path: "/inicio", lazy: async () => ({ Component: (await import("@/features/home/home-page")).HomePage }) },
          { path: "/configuracion", lazy: async () => ({ Component: (await import("@/features/settings/settings-page")).SettingsPage }) },
        ],
      },
    ],
  },
  { path: "*", lazy: async () => ({ Component: (await import("@/routes/not-found-page")).NotFoundPage }) },
]);
