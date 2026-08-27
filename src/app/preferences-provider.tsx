import {
  createContext,
  type PropsWithChildren,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

export type ThemePreference = "light" | "dark" | "system";

interface PreferencesContextValue {
  hideMoney: boolean;
  setHideMoney: (hidden: boolean) => void;
  setTheme: (theme: ThemePreference) => void;
  theme: ThemePreference;
}

const PreferencesContext = createContext<PreferencesContextValue | null>(null);
const themeKey = "nexo.theme";
const privacyKey = "nexo.hide_money";

function readTheme(): ThemePreference {
  const stored = localStorage.getItem(themeKey);
  return stored === "light" || stored === "dark" || stored === "system" ? stored : "system";
}

export function PreferencesProvider({ children }: PropsWithChildren) {
  const [theme, setThemeState] = useState<ThemePreference>(readTheme);
  const [hideMoney, setHideMoneyState] = useState(() => localStorage.getItem(privacyKey) === "true");

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const applyTheme = () => {
      document.documentElement.classList.toggle(
        "dark",
        theme === "dark" || (theme === "system" && media.matches),
      );
      document.documentElement.style.colorScheme =
        theme === "system" ? (media.matches ? "dark" : "light") : theme;
    };
    applyTheme();
    media.addEventListener("change", applyTheme);
    return () => media.removeEventListener("change", applyTheme);
  }, [theme]);

  const value = useMemo<PreferencesContextValue>(
    () => ({
      hideMoney,
      setHideMoney(hidden) {
        localStorage.setItem(privacyKey, String(hidden));
        setHideMoneyState(hidden);
      },
      setTheme(nextTheme) {
        localStorage.setItem(themeKey, nextTheme);
        setThemeState(nextTheme);
      },
      theme,
    }),
    [hideMoney, theme],
  );

  return <PreferencesContext.Provider value={value}>{children}</PreferencesContext.Provider>;
}

export function usePreferences() {
  const context = useContext(PreferencesContext);
  if (!context) throw new Error("usePreferences debe usarse dentro de PreferencesProvider.");
  return context;
}
