export type CurrencyCode = "MXN" | "USD" | "EUR";
export type AccountType = "checking" | "savings" | "cash" | "debit" | "investment" | "other";
export type TransactionKind = "income" | "expense" | "adjustment";
export type FinancialEventKind = TransactionKind | "opening" | "transfer" | "reversal" | "card_charge" | "card_payment" | "card_refund" | "card_adjustment";
export type CardTheme = "bbva_oro" | "banamex_clasica" | "banamex_joy" | "nu" | "generic";
export type CardBaselinePolicy = "current_bank_balance" | "after_last_statement" | "specific_date";
export type CardStatementStatus = "open" | "closed" | "paid";

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

export type CreditCard = {
  id: string; user_id: string; name: string; issuer: string; product_name: string | null;
  currency: CurrencyCode; credit_limit_minor: string; statement_day: number;
  payment_days_after_statement: number; last4: string | null; visual_theme: CardTheme;
  is_active: boolean; created_at: string; updated_at: string;
};

export type CardSummary = CreditCard & {
  baseline_id: string; baseline_policy: CardBaselinePolicy; baseline_date: string;
  reported_bank_balance_minor: string; excluded_statement_amount_minor: string | null;
  baseline_balance_minor: string; next_statement_date: string; used_balance_minor: string;
  open_cycle_accumulated_minor: string; available_credit_minor: string;
  next_payment_due_date: string; current_payment_minor: string | null;
  current_payment_due_date: string | null; current_statement_id: string | null;
  current_statement_date: string | null;
};

export type CardStatement = {
  id: string; user_id: string; card_id: string; statement_date: string;
  cycle_start: string; cycle_end: string; statement_balance_minor: string;
  payment_due_date: string; payment_to_avoid_interest_minor: string;
  minimum_payment_minor: string | null; amount_paid_minor: string;
  remaining_due_minor: string; status: CardStatementStatus;
  created_at: string; updated_at: string;
};

export type CardCurrentCycle = {
  card_id: string; user_id: string; cycle_start: string; cycle_end: string;
  statement_date: string; payment_due_date: string; open_cycle_accumulated_minor: string;
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
      credit_cards: { Row: CreditCard; Insert: never; Update: never; Relationships: [] };
      card_baselines: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      card_entries: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      card_statements: { Row: CardStatement; Insert: never; Update: never; Relationships: [] };
    };
    Views: {
      account_balances: { Row: AccountBalance; Relationships: [] };
      account_activity: { Row: AccountActivity; Relationships: [] };
      card_summaries: { Row: CardSummary; Relationships: [] };
      card_current_cycles: { Row: CardCurrentCycle; Relationships: [] };
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
      restore_account: { Args: { p_account_id: string; p_idempotency_key: string }; Returns: string };
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
      create_credit_card: {
        Args: { p_name: string; p_issuer: string; p_product_name: string | null; p_currency: string; p_credit_limit_minor: string; p_statement_day: number; p_payment_days_after_statement: number; p_last4: string | null; p_visual_theme: string; p_baseline_policy: string; p_baseline_date: string; p_reported_bank_balance_minor: string; p_excluded_statement_amount_minor: string | null; p_baseline_notes: string | null; p_idempotency_key: string };
        Returns: string;
      };
      update_credit_card: {
        Args: { p_card_id: string; p_name: string; p_issuer: string; p_product_name: string | null; p_credit_limit_minor: string; p_statement_day: number; p_payment_days_after_statement: number; p_last4: string | null; p_visual_theme: string; p_idempotency_key: string };
        Returns: string;
      };
      archive_credit_card: { Args: { p_card_id: string; p_idempotency_key: string }; Returns: string };
      restore_credit_card: { Args: { p_card_id: string; p_idempotency_key: string }; Returns: string };
      close_card_statement: { Args: { p_card_id: string; p_statement_date: string; p_payment_to_avoid_interest_minor: string | null; p_minimum_payment_minor: string | null; p_idempotency_key: string }; Returns: string };
      update_card_statement: { Args: { p_statement_id: string; p_payment_to_avoid_interest_minor: string; p_minimum_payment_minor: string; p_amount_paid_minor: string; p_idempotency_key: string }; Returns: string };
    };
    Enums: Record<never, never>;
    CompositeTypes: Record<never, never>;
  };
};
