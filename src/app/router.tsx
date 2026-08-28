import { createBrowserRouter, Navigate, Outlet } from "react-router-dom";

import { StartupSplash } from "@/components/skeletons";
import { AppShell } from "@/layouts/app-shell";
import { ProtectedRoute, PublicOnlyRoute } from "@/routes/route-guards";

export const router = createBrowserRouter([
  {
    element: <Outlet />,
    hydrateFallbackElement: <StartupSplash />,
    children: [
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
              { path: "/cuentas", lazy: async () => ({ Component: (await import("@/features/accounts/accounts-page")).AccountsPage }) },
              { path: "/cuentas/:id", lazy: async () => ({ Component: (await import("@/features/accounts/account-detail-page")).AccountDetailPage }) },
              { path: "/movimientos", lazy: async () => ({ Component: (await import("@/features/movements/movements-page")).MovementsPage }) },
              { path: "/accounts", lazy: async () => ({ Component: (await import("@/features/accounts/accounts-page")).AccountsPage }) },
              { path: "/accounts/:id", lazy: async () => ({ Component: (await import("@/features/accounts/account-detail-page")).AccountDetailPage }) },
              { path: "/transactions", lazy: async () => ({ Component: (await import("@/features/movements/movements-page")).MovementsPage }) },
              { path: "/cards", lazy: async () => ({ Component: (await import("@/features/cards/cards-page")).CardsPage }) },
              { path: "/cards/:id", lazy: async () => ({ Component: (await import("@/features/cards/card-detail-page")).CardDetailPage }) },
              { path: "/tarjetas", lazy: async () => ({ Component: (await import("@/features/cards/cards-page")).CardsPage }) },
              { path: "/tarjetas/:id", lazy: async () => ({ Component: (await import("@/features/cards/card-detail-page")).CardDetailPage }) },
              { path: "/configuracion", lazy: async () => ({ Component: (await import("@/features/settings/settings-page")).SettingsPage }) },
            ],
          },
        ],
      },
      { path: "*", lazy: async () => ({ Component: (await import("@/routes/not-found-page")).NotFoundPage }) },
    ],
  },
]);
