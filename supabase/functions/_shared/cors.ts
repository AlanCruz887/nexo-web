// The iPhone Shortcut is not a browser -- it never sends an Origin
// header and never enforces CORS. These headers exist only so the
// endpoints are also reachable from a browser-based tool (curl behaves
// identically with or without them) while developing/testing locally.
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

export function handleOptions(allowMethods: string): Response {
  return new Response(null, {
    status: 204,
    headers: { ...corsHeaders, "Access-Control-Allow-Methods": allowMethods },
  });
}
