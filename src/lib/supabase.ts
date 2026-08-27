import { createClient } from "@supabase/supabase-js";

import { publicEnvironment } from "@/lib/env";
import type { Database } from "@/types/database";

export const supabase = createClient<Database>(
  publicEnvironment.VITE_SUPABASE_URL,
  publicEnvironment.VITE_SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
