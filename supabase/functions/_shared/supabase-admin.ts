import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.112.4";

/**
 * The ONLY place in this codebase that reads SUPABASE_SERVICE_ROLE_KEY.
 * Supabase provisions this env var automatically inside every deployed
 * Edge Function -- it is never set by us, never checked into the repo,
 * never sent to the client, and never logged. This client is used
 * exclusively to call the narrow, service_role-only RPCs
 * (get_shortcut_options, get_shortcut_transaction_context,
 * execute_shortcut_transaction, check_shortcut_abuse_bucket) -- never to
 * select directly from a financial table.
 */
export function createAdminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY in the function environment.");
  }
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
