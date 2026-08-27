import { QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";

import { AuthProvider } from "@/app/auth-provider";
import { PreferencesProvider } from "@/app/preferences-provider";
import { queryClient } from "@/app/query-client";
import { ToastProvider } from "@/components/toast";

export function AppProviders({ children }: PropsWithChildren) {
  return (
    <PreferencesProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider><ToastProvider>{children}</ToastProvider></AuthProvider>
      </QueryClientProvider>
    </PreferencesProvider>
  );
}
