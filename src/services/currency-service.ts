import { supabase } from "@/lib/supabase";
import type { Currency } from "@/types/database";

export const currencyService = {
  async list(): Promise<Currency[]> {
    const { data, error } = await supabase.from("currencies").select("*").order("code");
    if (error) throw error;
    return data;
  },
};
