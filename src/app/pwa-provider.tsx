import { createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { registerSW } from "virtual:pwa-register";

import { PwaUpdatePrompt } from "@/components/pwa-update-prompt";
import { getPwaEnvironment, type BeforeInstallPromptEvent, type PwaEnvironment } from "@/lib/pwa";

interface PwaContextValue extends PwaEnvironment {
  canInstall: boolean;
  install: () => Promise<"accepted" | "dismissed" | "unavailable">;
}

const PwaContext = createContext<PwaContextValue | null>(null);

export function PwaProvider({ children }: PropsWithChildren) {
  const [environment, setEnvironment] = useState<PwaEnvironment>(getPwaEnvironment);
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent>();
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [updateDismissed, setUpdateDismissed] = useState(false);
  const updateServiceWorker = useRef<(reloadPage?: boolean) => Promise<void>>(async () => undefined);

  useEffect(() => {
    let active = true;
    updateServiceWorker.current = registerSW({
      immediate: true,
      onNeedRefresh() {
        if (active) {
          setUpdateAvailable(true);
          setUpdateDismissed(false);
        }
      },
      onRegisterError(error) {
        if (import.meta.env.DEV) console.error("No fue posible registrar la PWA de Nexo.", error);
      },
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    function onBeforeInstallPrompt(event: Event) {
      event.preventDefault();
      setInstallPrompt(event as BeforeInstallPromptEvent);
    }
    function onInstalled() {
      setInstallPrompt(undefined);
      setEnvironment(getPwaEnvironment());
    }
    window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
    window.addEventListener("appinstalled", onInstalled);
    return () => {
      window.removeEventListener("beforeinstallprompt", onBeforeInstallPrompt);
      window.removeEventListener("appinstalled", onInstalled);
    };
  }, []);

  const install = useCallback(async () => {
    if (!installPrompt) return "unavailable" as const;
    await installPrompt.prompt();
    const { outcome } = await installPrompt.userChoice;
    if (outcome === "accepted") setInstallPrompt(undefined);
    return outcome;
  }, [installPrompt]);

  const value = useMemo<PwaContextValue>(() => ({
    ...environment,
    canInstall: Boolean(installPrompt) && !environment.isStandalone,
    install,
  }), [environment, install, installPrompt]);

  return (
    <PwaContext.Provider value={value}>
      {children}
      <PwaUpdatePrompt
        onDismiss={() => setUpdateDismissed(true)}
        onUpdate={() => void updateServiceWorker.current(true)}
        open={updateAvailable && !updateDismissed}
      />
    </PwaContext.Provider>
  );
}

export function usePwa() {
  const context = useContext(PwaContext);
  if (!context) throw new Error("usePwa debe usarse dentro de PwaProvider.");
  return context;
}
