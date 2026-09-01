import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";

import { supabase } from "@/lib/supabase";
import { shortcutTokenService } from "@/services/shortcut-token-service";

vi.mock("@/lib/supabase", () => ({ supabase: { rpc: vi.fn() } }));

describe("shortcutTokenService", () => {
  it("list() calls list_shortcut_tokens with no arguments", async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: [], error: null } as never);
    await shortcutTokenService.list();
    expect(supabase.rpc).toHaveBeenCalledWith("list_shortcut_tokens");
  });

  // create_shortcut_token deliberately takes no idempotency key (see the
  // 7C-A migration's own comment) and always requests both scopes -- the
  // MVP has no permission picker yet.
  it("create() requests both scopes and no idempotency key", async () => {
    const created = { id: "1", token_plain: "x", name: "Mi iPhone", scopes: ["shortcut:options:read", "shortcut:transactions:write"], created_at: "2026-01-01T00:00:00Z", expires_at: null };
    vi.mocked(supabase.rpc).mockResolvedValue({ data: [created], error: null } as never);
    const result = await shortcutTokenService.create("Mi iPhone");
    expect(supabase.rpc).toHaveBeenCalledWith("create_shortcut_token", {
      p_name: "Mi iPhone",
      p_scopes: ["shortcut:options:read", "shortcut:transactions:write"],
    });
    expect(result).toEqual(created);
  });

  it("revoke() passes the token id and the given idempotency key", async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: "1", error: null } as never);
    await shortcutTokenService.revoke("1", "shortcut-token:revoke:abc");
    expect(supabase.rpc).toHaveBeenCalledWith("revoke_shortcut_token", { p_token_id: "1", p_idempotency_key: "shortcut-token:revoke:abc" });
  });
});

// CASO Q: no client-side source file may reference the service_role-only
// RPCs (execute_shortcut_transaction, get_shortcut_options, get_shortcut_
// transaction_context, check_shortcut_abuse_bucket) -- those exist only
// for the Edge Functions in supabase/functions/, never the browser. This
// scans every .ts/.tsx file under src/ (not just this service file) so
// the guarantee holds project-wide, not just for the one file most likely
// to be tempted to call them.
describe("service_role-only RPCs never referenced from src/", () => {
  const forbiddenRpcNames = [
    "execute_shortcut_transaction",
    "get_shortcut_options",
    "get_shortcut_transaction_context",
    "check_shortcut_abuse_bucket",
  ];

  function collectSourceFiles(dir: string): string[] {
    const entries = readdirSync(dir);
    return entries.flatMap((entry) => {
      const fullPath = path.join(dir, entry);
      const stats = statSync(fullPath);
      if (stats.isDirectory()) return collectSourceFiles(fullPath);
      if (/\.(ts|tsx)$/.test(entry)) return [fullPath];
      return [];
    });
  }

  it("finds zero references to any service_role-only shortcut RPC anywhere under src/", () => {
    const thisFile = fileURLToPath(import.meta.url);
    const srcDir = path.resolve(path.dirname(thisFile), "..");
    const files = collectSourceFiles(srcDir).filter((file) => file !== thisFile);
    const offenders: string[] = [];
    for (const file of files) {
      const contents = readFileSync(file, "utf8");
      for (const rpcName of forbiddenRpcNames) {
        // Quoted usage only ("name" / 'name'), the shape a real
        // `supabase.rpc("name", ...)` call would take -- a bare/unquoted
        // mention (e.g. explaining in a comment why a name is
        // deliberately NOT registered, as src/types/database.ts does)
        // is documentation, not a live reference, and must not trip this.
        if (contents.includes(`"${rpcName}"`) || contents.includes(`'${rpcName}'`)) {
          offenders.push(`${file} references "${rpcName}"`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });
});
