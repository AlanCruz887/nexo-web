import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { profileService } from "@/services/profile-service";
import type { ProfileUpdate } from "@/types/database";

export const profileQueryKey = (userId: string) => ["profile", userId] as const;

export function useProfile(userId: string | undefined) {
  return useQuery({
    queryKey: profileQueryKey(userId ?? "missing"),
    queryFn: () => profileService.getProfile(userId as string),
    enabled: Boolean(userId),
  });
}

export function useUpdateProfile(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (update: ProfileUpdate) => profileService.updateProfile(userId, update),
    onSuccess: (profile) => queryClient.setQueryData(profileQueryKey(userId), profile),
  });
}
