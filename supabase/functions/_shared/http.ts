import { corsHeaders } from "./cors.ts";

/** A rejection with a known HTTP status, a stable NEXO_* code, and a message safe to show the user. */
export class HttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function jsonResponse(body: unknown, status: number, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders, ...extraHeaders },
  });
}

export function errorResponse(err: HttpError): Response {
  return jsonResponse({ ok: false, error_code: err.code, message: err.message }, err.status);
}

const MAX_BODY_BYTES = 16 * 1024;

/** Parses the request body as a plain JSON object. Rejects anything malformed, empty, or oversized before any field is even looked at. */
export async function parseJsonBody(req: Request): Promise<Record<string, unknown>> {
  let text: string;
  try {
    text = await req.text();
  } catch {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "No pudimos leer la solicitud.");
  }
  if (!text) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "El cuerpo de la solicitud está vacío.");
  }
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "La solicitud es demasiado grande.");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "El cuerpo de la solicitud no es JSON válido.");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new HttpError(400, "NEXO_INVALID_PAYLOAD", "El cuerpo de la solicitud debe ser un objeto JSON.");
  }
  return parsed as Record<string, unknown>;
}
