const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/** Strict YYYY-MM-DD check: format AND real calendar validity (rejects e.g. 2026-02-30). */
export function isValidDateString(value: string): boolean {
  if (!DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/**
 * Resolves "today" as YYYY-MM-DD in the given IANA timezone, never via
 * `new Date().toISOString().slice(0, 10)` (which is always UTC and can
 * land on the wrong calendar day for any user not on UTC, especially
 * near midnight). `now` is injectable for tests; defaults to the real
 * current instant.
 */
export function resolveLocalDate(timezone: string, now: Date = new Date()): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  } catch {
    // An invalid/unknown IANA zone would be a data-quality problem on
    // the profile, not something this specific purchase should fail
    // over -- fall back to UTC rather than rejecting the request.
    // (private.is_valid_timezone already guards profiles.timezone at
    // write time, so this branch is defensive, not expected to fire.)
    return new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  }
}
