import { supabase } from "@/lib/supabase";
import type { ShortcutTokenCreated, ShortcutTokenScope, ShortcutTokenSummary } from "@/types/database";

// The MVP always requests both scopes -- there is no permission picker
// yet (see PLAN.md/DOMAIN_RULES.md Fase 7C-A/7C-C). This is the only
// place that decides that default, so a future scope picker only needs
// to change this one call site.
const DEFAULT_SCOPES: ShortcutTokenScope[] = ["shortcut:options:read", "shortcut:transactions:write"];

export const shortcutTokenService = {
  async list(): Promise<ShortcutTokenSummary[]> {
    const { data, error } = await supabase.rpc("list_shortcut_tokens");
    if (error) throw error;
    return data;
  },

  // No idempotency key: create_shortcut_token deliberately doesn't take
  // one (see the migration's own comment) -- the one thing a retry could
  // never recover is the plaintext token itself, so pretending a retry
  // returns "the same result" would either lie about the plaintext or
  // omit it. A double-submit just creates a second, harmless, revocable
  // token.
  async create(name: string): Promise<ShortcutTokenCreated> {
    const { data, error } = await supabase.rpc("create_shortcut_token", { p_name: name, p_scopes: DEFAULT_SCOPES });
    if (error) throw error;
    const [created] = data;
    if (!created) throw new Error("NEXO_SHORTCUT_TOKEN_CREATE_EMPTY_RESPONSE");
    return created;
  },

  async revoke(id: string, key: string): Promise<string> {
    const { data, error } = await supabase.rpc("revoke_shortcut_token", { p_token_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
};
