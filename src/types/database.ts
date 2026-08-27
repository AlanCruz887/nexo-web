export type CurrencyCode = "MXN" | "USD" | "EUR";
export type AccountType = "checking" | "savings" | "cash" | "debit" | "investment" | "other";
export type TransactionKind = "income" | "expense" | "adjustment";
export type FinancialEventKind = TransactionKind | "opening" | "transfer" | "reversal";

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

export type Category = {
  id: string;
  name: string;
  kind: "expense" | "income" | "both";
  icon: string;
  sort_order: number;
  created_at: string;
};

export type Account = {
  id: string;
  user_id: string;
  name: string;
  type: AccountType;
  currency: CurrencyCode;
  opening_balance_minor: string;
  institution: string | null;
  last4: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type AccountBalance = Account & { balance_minor: string };

export type FinancialEvent = {
  id: string;
  user_id: string;
  kind: FinancialEventKind;
  amount_minor: string;
  personal_amount_minor: string;
  description: string;
  category_id: string | null;
  occurred_on: string;
  notes: string | null;
  reverses_event_id: string | null;
  created_at: string;
};

export type AccountActivity = {
  event_id: string;
  user_id: string;
  kind: Exclude<FinancialEventKind, "reversal">;
  amount_minor: string;
  personal_amount_minor: string;
  description: string;
  category_id: string | null;
  category_name: string | null;
  occurred_on: string;
  notes: string | null;
  created_at: string;
  account_id: string;
  account_delta_minor: string;
  account_name: string;
  account_type: AccountType;
  currency: CurrencyCode;
  account_is_active: boolean;
};

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
      categories: {
        Row: Category;
        Insert: Omit<Category, "created_at"> & { created_at?: string };
        Update: Partial<Omit<Category, "id">>;
        Relationships: [];
      };
      accounts: {
        Row: Account;
        Insert: Omit<Account, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Account, "id" | "user_id" | "currency" | "opening_balance_minor" | "created_at">>;
        Relationships: [];
      };
      financial_events: {
        Row: FinancialEvent;
        Insert: Omit<FinancialEvent, "id" | "created_at"> & { id?: string; created_at?: string };
        Update: never;
        Relationships: [];
      };
      account_entries: {
        Row: {
          id: string;
          user_id: string;
          financial_event_id: string;
          account_id: string;
          amount_minor: string;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      financial_commands: {
        Row: {
          id: string;
          user_id: string;
          idempotency_key: string;
          command_type: string;
          payload: unknown;
          result_id: string;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      audit_events: {
        Row: {
          id: string;
          user_id: string;
          action: string;
          entity_type: string;
          entity_id: string;
          metadata: unknown;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      financial_event_notes: {
        Row: {
          id: string;
          user_id: string;
          financial_event_id: string;
          notes: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: {
      account_balances: { Row: AccountBalance; Relationships: [] };
      account_activity: { Row: AccountActivity; Relationships: [] };
    };
    Functions: {
      create_account: {
        Args: {
          p_name: string;
          p_type: string;
          p_currency: string;
          p_opening_balance_minor: string;
          p_institution: string | null;
          p_last4: string | null;
          p_idempotency_key: string;
        };
        Returns: string;
      };
      update_account: {
        Args: {
          p_account_id: string;
          p_name: string;
          p_type: string;
          p_institution: string | null;
          p_last4: string | null;
          p_idempotency_key: string;
        };
        Returns: string;
      };
      archive_account: { Args: { p_account_id: string; p_idempotency_key: string }; Returns: string };
      create_transaction: {
        Args: {
          p_account_id: string;
          p_kind: string;
          p_amount_minor: string;
          p_description: string;
          p_category_id: string | null;
          p_occurred_on: string;
          p_notes: string | null;
          p_idempotency_key: string;
        };
        Returns: string;
      };
      create_transfer: {
        Args: {
          p_from_account_id: string;
          p_to_account_id: string;
          p_amount_minor: string;
          p_description: string;
          p_occurred_on: string;
          p_notes: string | null;
          p_idempotency_key: string;
        };
        Returns: string;
      };
      reverse_transaction: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      reverse_transfer: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      update_transaction: {
        Args: {
          p_event_id: string;
          p_amount_minor: string;
          p_description: string;
          p_category_id: string | null;
          p_occurred_on: string;
          p_notes: string | null;
          p_idempotency_key: string;
        };
        Returns: string;
      };
      update_transfer_notes: {
        Args: { p_event_id: string; p_notes: string | null; p_idempotency_key: string };
        Returns: string;
      };
    };
    Enums: Record<never, never>;
    CompositeTypes: Record<never, never>;
  };
};
