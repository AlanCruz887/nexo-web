const loaders: Record<string, () => Promise<unknown>> = {
  "/inicio": () => import("@/features/home/home-page"),
  "/cuentas": () => import("@/features/accounts/accounts-page"),
  "/movimientos": () => import("@/features/movements/movements-page"),
  "/tarjetas": () => import("@/features/cards/cards-page"),
  "/cards": () => import("@/features/cards/cards-page"),
  "/configuracion": () => import("@/features/settings/settings-page"),
};

export function prefetchRoute(href: string) {
  void loaders[href]?.();
}
