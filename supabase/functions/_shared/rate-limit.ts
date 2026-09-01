import type { SupabaseClient } from "npm:@supabase/supabase-js@2.112.4";
import { logSafeError } from "./errors.ts";

/** Stricter than the 30/min per-token budget: this bucket exists purely to slow down invalid-token guessing, not normal use. */
export const INVALID_TOKEN_ABUSE_LIMIT = 10;

/**
 * Picks the bucket key used to throttle requests presenting an invalid
 * token (no token_id exists yet to bucket by normally).
 *
 * Only `cf-connecting-ip` is trusted: Supabase Edge Functions run behind
 * Cloudflare, and Cloudflare's edge sets this header itself on every
 * request it forwards -- a client cannot override it. `x-forwarded-for`
 * is deliberately NOT used: a client can prepend arbitrary values to it,
 * and while the genuine IP is appended by Supabase's own hop, correctly
 * picking "the right entry" out of a client-influenced list is exactly
 * the kind of fragile parsing that turns into a false sense of security.
 *
 * When neither is present -- notably, `supabase functions serve` locally
 * does not sit behind Cloudflare, so this fallback is what actually
 * fires in local development -- every invalid-token attempt from every
 * caller shares one global bucket. This is a real, documented
 * limitation: it throttles the aggregate rate of invalid-token guessing
 * platform-wide when no trusted per-client signal exists, not any one
 * abusive caller specifically. It is not pretend security; it is the
 * honest floor of what is possible without a trusted origin identifier.
 */
export function resolveAbuseBucketKey(req: Request): { key: string; trusted: boolean } {
  const cfIp = req.headers.get("cf-connecting-ip");
  if (cfIp && cfIp.trim().length > 0) {
    return { key: `ip:${cfIp.trim()}`, trusted: true };
  }
  return { key: "invalid-token:global-fallback", trusted: false };
}

/**
 * Consumes one unit of the invalid-token abuse bucket. Returns true when
 * the request is still within budget (proceed to return the normal 401),
 * false when the bucket is exhausted (return 429 instead). Fails OPEN on
 * an infrastructure error in the limiter itself -- a broken rate limiter
 * must never turn every legitimate 401 into a 500.
 */
export async function guardInvalidTokenAttempt(admin: SupabaseClient, req: Request): Promise<boolean> {
  const { key } = resolveAbuseBucketKey(req);
  const { data, error } = await admin.rpc("check_shortcut_abuse_bucket", {
    p_bucket_key: key,
    p_limit: INVALID_TOKEN_ABUSE_LIMIT,
  });
  if (error) {
    logSafeError("rate-limit", `abuse bucket check failed: ${error.message}`);
    return true;
  }
  return data === true;
}
