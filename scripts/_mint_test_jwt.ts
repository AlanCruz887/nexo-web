// Mints a throwaway local HS256 JWT for scripts/test-shortcut-http-local.sh.
// Reads the signing secret from JWT_SECRET_FOR_TEST -- never a real
// Supabase secret, only used against the ephemeral local PostgREST
// instance that script starts.
const secret = Deno.env.get("JWT_SECRET_FOR_TEST");
if (!secret) throw new Error("JWT_SECRET_FOR_TEST not set");

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const header = { alg: "HS256", typ: "JWT" };
const nowSeconds = Math.floor(Date.now() / 1000);
const payload = { role: "service_role", iss: "nexo-local-http-test", iat: nowSeconds, exp: nowSeconds + 3600 };

const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsigned)));

console.log(`${unsigned}.${base64url(signature)}`);
