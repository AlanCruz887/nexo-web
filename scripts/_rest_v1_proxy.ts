// Tiny local-only reverse proxy for scripts/test-shortcut-http-local.sh:
// @supabase/supabase-js always targets "<SUPABASE_URL>/rest/v1/...",
// matching real Supabase's API gateway (Kong) mounting PostgREST under
// that path prefix. A bare local `postgrest` binary has no such prefix
// (it serves rpc/table routes at its own root) and has no built-in
// option to add one -- so this strips "/rest/v1" before forwarding,
// nothing else. Never used against Supabase real.
const target = Deno.env.get("PROXY_TARGET");
const port = Number(Deno.env.get("PROXY_PORT") ?? "0");
if (!target || !port) throw new Error("PROXY_TARGET and PROXY_PORT must be set");

Deno.serve({ port }, async (req) => {
  const url = new URL(req.url);
  const strippedPath = url.pathname.replace(/^\/rest\/v1/, "") || "/";
  const upstreamUrl = `${target}${strippedPath}${url.search}`;
  const upstream = await fetch(upstreamUrl, {
    method: req.method,
    headers: req.headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : await req.arrayBuffer(),
  });
  return new Response(upstream.body, { status: upstream.status, headers: upstream.headers });
});
