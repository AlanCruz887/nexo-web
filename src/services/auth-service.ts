import type { AuthChangeEvent, Session } from "@supabase/supabase-js";

import { supabase } from "@/lib/supabase";
import type {
  LoginInput,
  PasswordRecoveryInput,
  PasswordUpdateInput,
  RegistrationInput,
} from "@/schemas/auth";

export const authService = {
  async getSession() {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return data.session;
  },

  onAuthStateChange(callback: (event: AuthChangeEvent, session: Session | null) => void) {
    return supabase.auth.onAuthStateChange(callback).data.subscription;
  },

  async signIn(input: LoginInput) {
    const { data, error } = await supabase.auth.signInWithPassword(input);
    if (error) throw error;
    return data;
  },

  async signUp(input: RegistrationInput) {
    const { data, error } = await supabase.auth.signUp({
      email: input.email,
      password: input.password,
      options: { data: { full_name: input.fullName } },
    });
    if (error) throw error;
    return data;
  },

  async signOut() {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  },

  async requestPasswordReset(input: PasswordRecoveryInput) {
    const redirectTo = `${window.location.origin}/actualizar-contrasena`;
    const { error } = await supabase.auth.resetPasswordForEmail(input.email, { redirectTo });
    if (error) throw error;
  },

  async updatePassword(input: PasswordUpdateInput) {
    const { error } = await supabase.auth.updateUser({ password: input.password });
    if (error) throw error;
  },
};
