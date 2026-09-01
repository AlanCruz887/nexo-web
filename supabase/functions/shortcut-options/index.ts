// GET /shortcut-options -- lets the iPhone Shortcut populate its own
// pickers (account/card/category) without hardcoding IDs. Read-only.
// Never touches a financial table directly: everything goes through
// public.get_shortcut_options, a single service_role-only RPC that
// resolves the token, checks the shortcut:options:read scope, and
// returns exactly {accounts, cards, categories} -- no balances, no
// limits, no statement data, nothing beyond what a picker needs.
import { handleOptions } from "../_shared/cors.ts";
import { HttpError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { extractBearerToken, hashToken } from "../_shared/auth.ts";
import { createAdminClient } from "../_shared/supabase-admin.ts";
import { classifyError, logSafeError } from "../_shared/errors.ts";
import { guardInvalidTokenAttempt } from "../_shared/rate-limit.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions("GET, OPTIONS");
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_code: "NEXO_METHOD_NOT_ALLOWED", message: "Método no permitido." }, 405);
  }

  const admin = createAdminClient();

  try {
    const tokenPlain = extractBearerToken(req);
    const tokenHash = await hashToken(tokenPlain);

    const { data, error } = await admin.rpc("get_shortcut_options", { p_token_hash: tokenHash });

    if (error) {
      const mapped = classifyError(error.message);
      if (mapped.status === 401) {
        const withinBudget = await guardInvalidTokenAttempt(admin, req);
        if (!withinBudget) {
          return jsonResponse(
            { ok: false, error_code: "NEXO_SHORTCUT_RATE_LIMITED", message: "Demasiados intentos. Intenta de nuevo más tarde." },
            429,
          );
        }
      }
      if (mapped.status === 500) logSafeError("shortcut-options", error.message);
      return jsonResponse({ ok: false, error_code: mapped.code, message: mapped.message }, mapped.status);
    }

    return jsonResponse({ ok: true, ...(data as Record<string, unknown>) }, 200);
  } catch (err) {
    if (err instanceof HttpError) {
      if (err.status === 401) {
        const withinBudget = await guardInvalidTokenAttempt(admin, req);
        if (!withinBudget) {
          return jsonResponse(
            { ok: false, error_code: "NEXO_SHORTCUT_RATE_LIMITED", message: "Demasiados intentos. Intenta de nuevo más tarde." },
            429,
          );
        }
      }
      return errorResponse(err);
    }
    logSafeError("shortcut-options", err instanceof Error ? err.message : String(err));
    return jsonResponse({ ok: false, error_code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." }, 500);
  }
});
