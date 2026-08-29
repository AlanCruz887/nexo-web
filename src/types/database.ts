export type CurrencyCode = "MXN" | "USD" | "EUR";
export type AccountType = "checking" | "savings" | "cash" | "debit" | "investment" | "other";
export type TransactionKind = "income" | "expense" | "adjustment";
export type FinancialEventKind = TransactionKind | "opening" | "transfer" | "reversal" | "card_charge" | "card_payment" | "card_refund" | "card_adjustment" | "person_payment" | "person_credit_application";
export type CardTheme = "bbva_oro" | "banamex_clasica" | "banamex_joy" | "nu" | "generic";
export type CardBaselinePolicy = "current_bank_balance" | "after_last_statement" | "specific_date";
export type CardStatementStatus = "open" | "closed" | "paid";
export type CardPaymentMethod = "physical_card" | "apple_pay" | "google_pay" | "online" | "other";
export type InstallmentPlanStatus = "active" | "completed" | "reversed";
export type InstallmentPlanOrigin = "new" | "historical";
export type InstallmentStatus = "future" | "pending" | "paid" | "paid_before_nexo" | "reversed";
export type FinancialSourceType = "account" | "card" | "transfer";

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

export type CardStatementCloseCandidate = {
  card_id: string; user_id: string; statement_date: string;
  cycle_start: string; cycle_end: string; payment_due_date: string;
  statement_balance_minor: string;
};

export type CardPaymentClassification = {
  event_id: string; user_id: string; card_id: string; source_account_id: string;
  amount_minor: string; applied_amount_minor: string; advance_amount_minor: string;
  payment_state: "advance" | "applied" | "mixed"; cycle_start: string;
  cycle_end: string; cycle_statement_date: string;
};

export type CardStatementActivitySegment = {
  segment_id: string; event_id: string; user_id: string; card_id: string;
  kind: "card_charge" | "card_payment" | "card_refund";
  segment_kind: "purchase" | "installment" | "refund" | "payment_applied" | "payment_advance";
  amount_minor: string; description: string; occurred_on: string;
  group_statement_date: string; cycle_start: string; cycle_end: string;
  source_account_name: string | null; source_is_active: boolean;
};

export type PurchaseAllocationDetail = { contact_id: string; contact_name: string; amount_minor: string };

export type Contact = {
  id: string; user_id: string; name: string; email: string | null; phone: string | null;
  notes: string | null; is_active: boolean; created_at: string; updated_at: string;
};
export type ContactBalance = { currency: CurrencyCode; outstanding_minor: string };
export type ContactSummary = Contact & { balances: ContactBalance[]; last_activity_on: string | null; last_activity_description: string | null; periods?: PersonCollectionPeriod[] };
export type ReceivableBalance = {
  id: string; user_id: string; contact_id: string; contact_name: string; source_event_id: string;
  source_kind: string; description: string; original_amount_minor: string; outstanding_minor: string;
  paid_minor: string; currency: CurrencyCode; occurred_on: string; created_at: string; status: "open" | "paid";
};
export type ContactActivity = {
  event_id: string; contact_id: string; user_id: string; kind: string; amount_minor: string;
  description: string; occurred_on: string; notes: string | null; created_at: string;
  currency: CurrencyCode; activity_type: "purchase" | "payment" | "credit_applied";
  application_id: string | null; personal_amount_minor: string | null; installment_count: number | null;
};

export type PersonPeriodConcept = {
  id: string; description: string; statement_date: string | null; payment_due_date: string;
  amount_minor: string; paid_minor: string; outstanding_minor: string;
  credit_applied_minor: string; installment_id: string | null; installment_number: number;
  installment_count: number | null;
};
export type PersonCollectionPeriod = {
  currency: CurrencyCode; period_start: string | null; payment_due_date: string | null;
  subtotal_minor: string; paid_minor: string; credit_applied_minor: string;
  remaining_minor: string; overdue_minor: string; total_outstanding_minor: string; credit_balance_minor: string;
  concepts: PersonPeriodConcept[];
};
export type PersonCollectionProjection = { as_of_date: string; periods: PersonCollectionPeriod[] };
export type PersonInstallmentSummary = {
  plan_id: string; user_id: string; contact_id: string; card_id: string;
  origin: InstallmentPlanOrigin; installment_count: number; currency: CurrencyCode;
  description: string; assigned_total_minor: string; outstanding_minor: string;
  current_installment_number: number | null; current_statement_date: string | null;
  current_period_minor: string | null;
};

export type FinancialActivity = {
  event_id: string; user_id: string; kind: Exclude<FinancialEventKind, "reversal">;
  amount_minor: string; personal_amount_minor: string; description: string;
  category_id: string | null; category_name: string | null; occurred_on: string;
  notes: string | null; created_at: string; source_type: FinancialSourceType;
  account_id: string | null; card_id: string | null; source_name: string;
  source_detail: string | null; currency: CurrencyCode; signed_amount_minor: string;
  payment_method: CardPaymentMethod | null; statement_date: string | null;
  related_event_id: string | null; source_is_active: boolean;
  source_account_id: string | null; source_account_name: string | null;
  destination_account_id: string | null;
  payment_state?: CardPaymentClassification["payment_state"];
  payment_applied_minor?: string;
  payment_advance_minor?: string;
  payment_cycle_start?: string;
  payment_cycle_end?: string;
  payment_cycle_statement_date?: string;
  installment_plan_id?: string | null;
  installment_count?: number | null;
  installment_amount_minor?: string | null;
  installment_plan_status?: InstallmentPlanStatus | null;
  installment_description?: string | null;
  installment_category_id?: string | null;
  installment_category_name?: string | null;
  installment_notes?: string | null;
  installment_origin?: InstallmentPlanOrigin | null;
  third_party_allocations?: PurchaseAllocationDetail[];
};

export type InstallmentPlanSummary = {
  id: string; user_id: string; card_id: string; purchase_event_id: string;
  original_amount_minor: string; installment_count: number; installment_amount_minor: string;
  currency: CurrencyCode; start_date: string; first_statement_date: string;
  status: InstallmentPlanStatus; created_at: string; updated_at: string; card_name: string;
  origin: InstallmentPlanOrigin; included_in_opening_balance: boolean;
  reported_paid_amount_minor: string; principal_paid_before_nexo_minor: string;
  initial_paid_before_count: number; additional_card_impact_minor: string;
  description: string; category_id: string | null; category_name: string | null; notes: string | null;
  paid_before_nexo_count: number; paid_in_nexo_count: number;
  paid_count: number; pending_count: number; remaining_principal_minor: string;
  current_installment_number: number | null; current_installment_minor: string | null;
  current_installment_principal_minor: string | null;
  next_statement_date: string | null;
};

export type InstallmentSchedule = {
  id: string; user_id: string; plan_id: string; installment_number: number;
  due_statement_date: string; principal_minor: string; reported_amount_minor: string;
  effective_status: InstallmentStatus;
  statement_id: string | null; statement_remaining_due_minor: string | null; created_at: string;
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
      card_transaction_details: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      card_statement_payment_allocations: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      installment_plans: { Row: InstallmentPlanSummary; Insert: never; Update: never; Relationships: [] };
      installments: { Row: InstallmentSchedule; Insert: never; Update: never; Relationships: [] };
      installment_plan_metadata_revisions: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      contacts: { Row: Contact; Insert: never; Update: never; Relationships: [] };
      receivables: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      purchase_allocations: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      receivable_entries: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      receivable_due_items: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      receivable_due_applications: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      person_credit_entries: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
    };
    Views: {
      account_balances: { Row: AccountBalance; Relationships: [] };
      account_activity: { Row: AccountActivity; Relationships: [] };
      card_summaries: { Row: CardSummary; Relationships: [] };
      card_current_cycles: { Row: CardCurrentCycle; Relationships: [] };
      card_statement_close_candidates: { Row: CardStatementCloseCandidate; Relationships: [] };
      card_payment_classifications: { Row: CardPaymentClassification; Relationships: [] };
      card_statement_activity_segments: { Row: CardStatementActivitySegment; Relationships: [] };
      financial_activity: { Row: FinancialActivity; Relationships: [] };
      financial_activity_enriched: { Row: FinancialActivity; Relationships: [] };
      installment_plan_summaries: { Row: InstallmentPlanSummary; Relationships: [] };
      installment_schedule: { Row: InstallmentSchedule; Relationships: [] };
      contact_balance_summary: { Row: ContactSummary; Relationships: [] };
      receivable_balances: { Row: ReceivableBalance; Relationships: [] };
      contact_activity: { Row: ContactActivity; Relationships: [] };
      purchase_allocation_details: { Row: { financial_event_id: string; user_id: string; allocations: PurchaseAllocationDetail[] }; Relationships: [] };
      person_payment_activity: { Row: FinancialActivity; Relationships: [] };
      receivable_due_item_balances: { Row: Record<string, unknown>; Relationships: [] };
      person_credit_balances: { Row: { contact_id: string; user_id: string; currency: CurrencyCode; credit_balance_minor: string }; Relationships: [] };
      person_installment_summaries: { Row: PersonInstallmentSummary; Relationships: [] };
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
      card_next_pending_statement_date: { Args: { p_card_id: string; p_as_of_date: string }; Returns: string | null };
      card_statement_preview_balance: { Args: { p_card_id: string; p_statement_date: string }; Returns: string | null };
      update_card_statement: { Args: { p_statement_id: string; p_payment_to_avoid_interest_minor: string; p_minimum_payment_minor: string; p_amount_paid_minor: string; p_idempotency_key: string }; Returns: string };
      create_card_purchase: { Args: { p_card_id: string; p_amount_minor: string; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      update_card_purchase: { Args: { p_event_id: string; p_card_id: string; p_amount_minor: string; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_card_purchase: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      create_card_payment: { Args: { p_card_id: string; p_source_account_id: string; p_amount_minor: string; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_card_payment: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      create_card_refund: { Args: { p_card_id: string; p_amount_minor: string; p_description: string; p_category_id: string | null; p_occurred_on: string; p_original_event_id: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_card_refund: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      create_installment_purchase: { Args: { p_card_id: string; p_amount_minor: string; p_installment_count: number; p_installment_amount_minor: string | null; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      create_shared_installment_purchase: { Args: { p_card_id: string; p_amount_minor: string; p_personal_amount_minor: string; p_allocations: unknown; p_installment_count: number; p_installment_amount_minor: string | null; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      update_installment_plan_metadata: { Args: { p_plan_id: string; p_description: string; p_category_id: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_installment_purchase: { Args: { p_plan_id: string; p_idempotency_key: string }; Returns: string };
      import_historical_installment_plan: { Args: { p_card_id: string; p_description: string; p_original_amount_minor: string; p_installment_count: number; p_installment_amount_minor: string; p_original_purchase_date: string; p_current_installment_number: number; p_paid_before_count: number; p_reported_paid_amount_minor: string; p_principal_paid_minor: string; p_next_statement_date: string; p_category_id: string | null; p_notes: string | null; p_included_in_opening_balance: boolean; p_idempotency_key: string }; Returns: string };
      import_shared_historical_installment_plan: { Args: { p_card_id: string; p_description: string; p_original_amount_minor: string; p_remaining_personal_amount_minor: string; p_allocations: unknown; p_installment_count: number; p_installment_amount_minor: string; p_original_purchase_date: string; p_current_installment_number: number; p_paid_before_count: number; p_reported_paid_amount_minor: string; p_principal_paid_minor: string; p_next_statement_date: string; p_category_id: string | null; p_notes: string | null; p_included_in_opening_balance: boolean; p_idempotency_key: string }; Returns: string };
      create_contact: { Args: { p_name: string; p_email: string | null; p_phone: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      update_contact: { Args: { p_contact_id: string; p_name: string; p_email: string | null; p_phone: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      set_contact_active: { Args: { p_contact_id: string; p_active: boolean; p_idempotency_key: string }; Returns: string };
      create_shared_account_purchase: { Args: { p_account_id: string; p_amount_minor: string; p_personal_amount_minor: string; p_allocations: unknown; p_description: string; p_category_id: string | null; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      update_shared_account_purchase: { Args: { p_event_id: string; p_amount_minor: string; p_personal_amount_minor: string; p_allocations: unknown; p_description: string; p_category_id: string | null; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      create_shared_card_purchase: { Args: { p_card_id: string; p_amount_minor: string; p_personal_amount_minor: string; p_allocations: unknown; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      update_shared_card_purchase: { Args: { p_event_id: string; p_card_id: string; p_amount_minor: string; p_personal_amount_minor: string; p_allocations: unknown; p_description: string; p_category_id: string | null; p_occurred_on: string; p_payment_method: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      create_person_payment: { Args: { p_contact_id: string; p_account_id: string; p_amount_minor: string; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_person_payment: { Args: { p_event_id: string; p_idempotency_key: string }; Returns: string };
      apply_person_credit: { Args: { p_contact_id: string; p_currency: string; p_amount_minor: string; p_idempotency_key: string }; Returns: string };
      get_person_collection_period: { Args: { p_contact_id: string; p_as_of_date?: string }; Returns: PersonCollectionProjection };
      record_person_statement_export: { Args: { p_contact_id: string; p_period_start: string; p_period_end: string; p_format: string; p_idempotency_key: string }; Returns: string };
    };
    Enums: Record<never, never>;
    CompositeTypes: Record<never, never>;
  };
};
