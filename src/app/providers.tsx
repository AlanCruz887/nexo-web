import { QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";

import { AuthProvider } from "@/app/auth-provider";
import { PreferencesProvider } from "@/app/preferences-provider";
import { queryClient } from "@/app/query-client";

export function AppProviders({ children }: PropsWithChildren) {
  return (
    <PreferencesProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>{children}</AuthProvider>
      </QueryClientProvider>
    </PreferencesProvider>
  );
}
