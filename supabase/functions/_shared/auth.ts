import { HttpError } from "./http.ts";

// nexo_shortcut_<32 random bytes base64url, unpadded -- 43 chars>. The
// length window is intentionally a little generous around 43 so a
// future change to the encoding does not need this pattern touched too.
const TOKEN_PATTERN = /^nexo_shortcut_[A-Za-z0-9_-]{20,80}$/;

/**
 * Extracts and format-validates the bearer token from the Authorization
 * header. Never logs the header or the token -- a malformed/absent
 * header only ever produces a generic HttpError whose message never
 * echoes what was received.
 */
export function extractBearerToken(req: Request): string {
  const header = req.headers.get("Authorization");
  if (!header) {
    throw new HttpError(401, "NEXO_SHORTCUT_TOKEN_MISSING", "Falta el token de acceso.");
  }
  if (!header.startsWith("Bearer ")) {
    throw new HttpError(401, "NEXO_SHORTCUT_TOKEN_INVALID", "El token no tiene un formato válido.");
  }
  const token = header.slice("Bearer ".length).trim();
  if (!TOKEN_PATTERN.test(token)) {
    throw new HttpError(401, "NEXO_SHORTCUT_TOKEN_INVALID", "El token no tiene un formato válido.");
  }
  return token;
}

/** SHA-256 of the plain token, as lowercase hex -- matches token_hash's `^[0-9a-f]{64}$` check in Postgres. */
export async function hashToken(tokenPlain: string): Promise<string> {
  const bytes = new TextEncoder().encode(tokenPlain);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
