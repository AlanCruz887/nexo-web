import { supabase } from "@/lib/supabase";
import type { Category } from "@/types/database";

export const categoryService = {
  async list(): Promise<Category[]> {
    const { data, error } = await supabase.from("categories").select("*").order("sort_order");
    if (error) throw error;
    return data;
  },
};
