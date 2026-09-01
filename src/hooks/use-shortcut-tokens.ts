import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createIdempotencyKey } from "@/lib/idempotency";
import { shortcutTokenService } from "@/services/shortcut-token-service";

function useInvalidateShortcutTokens() {
  const client = useQueryClient();
  return () => client.invalidateQueries({ queryKey: ["shortcut-tokens"] });
}

export function useShortcutTokens() {
  return useQuery({ queryKey: ["shortcut-tokens"], queryFn: shortcutTokenService.list });
}

export function useCreateShortcutToken() {
  const invalidate = useInvalidateShortcutTokens();
  return useMutation({
    mutationFn: (name: string) => shortcutTokenService.create(name),
    onSuccess: invalidate,
  });
}

export function useRevokeShortcutToken() {
  const invalidate = useInvalidateShortcutTokens();
  return useMutation({
    mutationFn: (id: string) => shortcutTokenService.revoke(id, createIdempotencyKey("shortcut-token:revoke")),
    onSuccess: invalidate,
  });
}
