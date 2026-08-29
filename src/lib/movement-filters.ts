export type MovementOrigin = "all" | "accounts" | "cards";

export function normalizeOriginChange(origin: MovementOrigin) {
  return { origin, accountId: "", cardId: "" };
}

export function instrumentFilterForOrigin(origin: MovementOrigin, accountId: string, cardId: string) {
  if (origin === "accounts") return { accountId, cardId: "" };
  if (origin === "cards") return { accountId: "", cardId };
  return { accountId: "", cardId: "" };
}

export function visibleInstruments<T extends { is_active: boolean }>(items: T[], includeArchived: boolean) {
  return includeArchived ? items : items.filter((item) => item.is_active);
}

export function sourceTypesForOrigin(origin: MovementOrigin) {
  if (origin === "accounts") return ["account", "transfer"] as const;
  if (origin === "cards") return ["card"] as const;
  return null;
}
