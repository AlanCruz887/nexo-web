// POST /shortcut-transactions -- registers a personal expense from the
// iPhone Shortcut. Never writes financial_events/account_entries/
// card_entries/accounts/credit_cards directly: it calls exactly two
// service_role-only RPCs (public.get_shortcut_transaction_context to
// resolve the source's real currency + the user's timezone, and
// public.execute_shortcut_transaction to run the actual mutation) --
// both of which, in turn, only ever reach the ledger through
// private.create_transaction_for_user/private.create_card_purchase_for_
// user, the exact same engine the web app uses. No parallel financial
// logic exists here.
import { handleOptions } from "../_shared/cors.ts";
import { HttpError, errorResponse, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { extractBearerToken, hashToken } from "../_shared/auth.ts";
import { createAdminClient } from "../_shared/supabase-admin.ts";
import { classifyError, logSafeError } from "../_shared/errors.ts";
import { guardInvalidTokenAttempt } from "../_shared/rate-limit.ts";
import { validateShortcutTransactionBody } from "../_shared/validation.ts";
import { resolveLocalDate } from "../_shared/date.ts";
import { currencyMinorUnits, parseMoneyInput } from "../_shared/money.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.112.4";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions("POST, OPTIONS");
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_code: "NEXO_METHOD_NOT_ALLOWED", message: "Método no permitido." }, 405);
  }

  const admin = createAdminClient();

  try {
    const tokenPlain = extractBearerToken(req);
    const body = await parseJsonBody(req);
    const input = validateShortcutTransactionBody(body);
    const tokenHash = await hashToken(tokenPlain);

    // Step 1: resolve the source's REAL currency and the user's
    // timezone -- never trust anything the phone claims about either.
    const contextResult = await admin.rpc("get_shortcut_transaction_context", {
      p_token_hash: tokenHash,
      p_source_type: input.sourceType,
      p_source_id: input.sourceId,
    });

    if (contextResult.error) {
      return await handleDomainError(admin, req, contextResult.error.message, "shortcut-transactions:context");
    }
    const context = (Array.isArray(contextResult.data) ? contextResult.data[0] : contextResult.data) as
      | { currency: string; timezone: string }
      | undefined;
    if (!context) {
      logSafeError("shortcut-transactions", "get_shortcut_transaction_context returned no row");
      return jsonResponse({ ok: false, error_code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." }, 500);
    }

    // Step 2: decimal string -> exact bigint minor units, scaled by the
    // SOURCE's real currency -- never parseFloat, never Number(x) * 100.
    const minorUnit = currencyMinorUnits[context.currency];
    if (minorUnit === undefined) {
      logSafeError("shortcut-transactions", `unknown currency from context: ${context.currency}`);
      return jsonResponse({ ok: false, error_code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." }, 500);
    }
    let amountMinor: bigint;
    try {
      amountMinor = parseMoneyInput(input.amount, minorUnit);
    } catch {
      return jsonResponse({ ok: false, error_code: "NEXO_INVALID_AMOUNT", message: "El importe no es válido." }, 400);
    }
    if (amountMinor <= 0n) {
      return jsonResponse({ ok: false, error_code: "NEXO_INVALID_AMOUNT", message: "El importe debe ser mayor que cero." }, 400);
    }

    // Step 3: resolve the transaction date -- explicit value used as-is
    // (already format+calendar validated), otherwise "today" in the
    // user's own profile timezone, never the server's clock.
    const transactionDate = input.transactionDate ?? resolveLocalDate(context.timezone);

    // Step 4: the one and only call that touches money.
    const execResult = await admin.rpc("execute_shortcut_transaction", {
      p_token_hash: tokenHash,
      p_shortcut_execution_id: input.shortcutExecutionId,
      p_source_type: input.sourceType,
      p_source_id: input.sourceId,
      p_amount_minor: amountMinor.toString(),
      p_category_id: input.categoryId,
      p_description: input.description,
      p_transaction_date: transactionDate,
    });

    if (execResult.error) {
      return await handleDomainError(admin, req, execResult.error.message, "shortcut-transactions:execute");
    }
    const outcome = (Array.isArray(execResult.data) ? execResult.data[0] : execResult.data) as
      | { ok: boolean; event_id: string | null; error_code: string | null }
      | undefined;
    if (!outcome) {
      logSafeError("shortcut-transactions", "execute_shortcut_transaction returned no row");
      return jsonResponse({ ok: false, error_code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." }, 500);
    }

    if (!outcome.ok) {
      const mapped = classifyError(outcome.error_code ?? "");
      if (mapped.status === 500) logSafeError("shortcut-transactions", outcome.error_code ?? "unknown");
      return jsonResponse({ ok: false, error_code: mapped.code, message: mapped.message }, mapped.status);
    }

    return jsonResponse(
      {
        ok: true,
        transaction_id: outcome.event_id,
        message: "Compra registrada",
        amount_display: input.amount,
      },
      201,
    );
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
    logSafeError("shortcut-transactions", err instanceof Error ? err.message : String(err));
    return jsonResponse({ ok: false, error_code: "NEXO_UNEXPECTED_ERROR", message: "No pudimos completar la solicitud." }, 500);
  }
});

async function handleDomainError(admin: SupabaseClient, req: Request, rawMessage: string, context: string): Promise<Response> {
  const mapped = classifyError(rawMessage);
  if (mapped.status === 401) {
    const withinBudget = await guardInvalidTokenAttempt(admin, req);
    if (!withinBudget) {
      return jsonResponse(
        { ok: false, error_code: "NEXO_SHORTCUT_RATE_LIMITED", message: "Demasiados intentos. Intenta de nuevo más tarde." },
        429,
      );
    }
  }
  if (mapped.status === 500) logSafeError(context, rawMessage);
  return jsonResponse({ ok: false, error_code: mapped.code, message: mapped.message }, mapped.status);
}
