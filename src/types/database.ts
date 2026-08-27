export type CurrencyCode = "MXN" | "USD" | "EUR";

export type Currency = {
  code: CurrencyCode;
  name: string;
  symbol: string;
  minor_unit: number;
  created_at: string;
};

export type Profile = {
  id: string;
  full_name: string;
  base_currency: CurrencyCode;
  timezone: string;
  onboarding_completed: boolean;
  created_at: string;
  updated_at: string;
};

export type ProfileUpdate = Pick<
  Profile,
  "full_name" | "base_currency" | "timezone" | "onboarding_completed"
>;

export type Database = {
  public: {
    Tables: {
      currencies: {
        Row: Currency;
        Insert: Omit<Currency, "created_at"> & { created_at?: string };
        Update: Partial<Omit<Currency, "code">>;
        Relationships: [];
      };
      profiles: {
        Row: Profile;
        Insert: Omit<Profile, "created_at" | "updated_at"> & {
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<ProfileUpdate>;
        Relationships: [];
      };
    };
    Views: Record<never, never>;
    Functions: Record<never, never>;
    Enums: Record<never, never>;
    CompositeTypes: Record<never, never>;
  };
};
