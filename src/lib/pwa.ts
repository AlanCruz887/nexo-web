export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

export interface PwaEnvironment {
  isIos: boolean;
  isStandalone: boolean;
}

interface PwaSignals {
  displayModeStandalone: boolean;
  maxTouchPoints: number;
  navigatorStandalone: boolean;
  platform: string;
  userAgent: string;
}

interface IosNavigator extends Navigator {
  standalone?: boolean;
}

export function getPwaEnvironment(): PwaEnvironment {
  if (typeof window === "undefined" || typeof navigator === "undefined") {
    return { isIos: false, isStandalone: false };
  }
  return detectPwaEnvironment({
    displayModeStandalone: window.matchMedia("(display-mode: standalone)").matches,
    maxTouchPoints: navigator.maxTouchPoints,
    navigatorStandalone: Boolean((navigator as IosNavigator).standalone),
    platform: navigator.platform,
    userAgent: navigator.userAgent,
  });
}

export function detectPwaEnvironment(signals: PwaSignals): PwaEnvironment {
  const isIos = /iPad|iPhone|iPod/.test(signals.userAgent)
    || (signals.platform === "MacIntel" && signals.maxTouchPoints > 1);
  return {
    isIos,
    isStandalone: signals.displayModeStandalone || signals.navigatorStandalone,
  };
}
