import { supabase } from "@/lib/supabase";
import type { Profile, ProfileUpdate } from "@/types/database";

export const profileService = {
  async getProfile(userId: string): Promise<Profile> {
    const { data, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .single();
    if (error) throw error;
    return data;
  },

  async updateProfile(userId: string, update: ProfileUpdate): Promise<Profile> {
    const { data, error } = await supabase
      .from("profiles")
      .update(update)
      .eq("id", userId)
      .select("*")
      .single();
    if (error) throw error;
    return data;
  },
};
