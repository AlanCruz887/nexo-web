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
export type ContactSummary = Contact & { balances: ContactBalance[]; last_activity_on: string | null; last_activity_description: string | null; periods?: PersonCollectionPeriod[] | undefined };
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
  credit_applied_minor: string; reconciled_minor: string; purchase_amount_minor: string;
  installment_id: string | null; installment_number: number; installment_count: number | null;
};
export type PersonCollectionPeriod = {
  currency: CurrencyCode; period_start: string | null; payment_due_date: string | null;
  subtotal_minor: string; paid_minor: string; credit_applied_minor: string; reconciled_minor: string;
  remaining_minor: string; overdue_minor: string; overdue_since: string | null;
  total_outstanding_minor: string; credit_balance_minor: string;
  concepts: PersonPeriodConcept[];
};
export type PersonCollectionProjection = { as_of_date: string; periods: PersonCollectionPeriod[] };
export type PersonStatementPayment = {
  event_id: string; occurred_on: string; currency: CurrencyCode; account_name: string | null;
  amount_minor: string; applied_to_period_minor: string; applied_to_future_minor: string;
  credit_generated_minor: string;
};
export type PersonStatement = PersonCollectionProjection & { payments: PersonStatementPayment[] };

export type BudgetPeriodSummary = {
  id: string; category_id: string; category_name: string; category_icon: string;
  currency: CurrencyCode; limit_minor: string; is_recurring: boolean; period_month: string;
  spent_minor: string; available_minor: string; percentage: number;
};
export type BudgetMovement = {
  row_kind: "movement" | "installment";
  event_id: string;
  description: string | null;
  occurred_on: string;
  personal_amount_minor: string;
  // movement-only
  event_kind?: string;
  source_type?: string;
  source_name?: string | null;
  amount_minor?: string;
  // installment-only
  plan_id?: string;
  installment_number?: number;
  installment_count?: number;
};
export type GoalStatus = "active" | "paused";
export type GoalBalance = {
  id: string; user_id: string; name: string; currency: CurrencyCode;
  target_minor: string; target_date: string | null; linked_account_id: string | null;
  icon: string | null; status: GoalStatus; archived_at: string | null;
  created_at: string; updated_at: string;
  saved_minor: string; backed_minor: string; remaining_minor: string;
  percentage: number; is_achieved: boolean;
  months_remaining: number | null; recommended_monthly_minor: string | null;
};
export type GoalEntryKind = "contribution" | "withdrawal" | "reversal";
export type GoalEntryActivity = {
  id: string; user_id: string; goal_id: string; entry_kind: GoalEntryKind;
  amount_minor: string; occurred_on: string; notes: string | null; created_at: string;
  reverses_entry_id: string | null; is_reversed: boolean;
  account_id: string; account_name: string; account_is_active: boolean;
  financial_event_id: string | null; is_real_movement: boolean;
};
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

export type PlannedCashFlowRecurrence = "one_time" | "monthly";
export type PlannedCashFlow = {
  id: string; user_id: string; name: string; currency: CurrencyCode;
  amount_minor: string; category_id: string | null; recurrence: PlannedCashFlowRecurrence;
  start_date: string; end_date: string | null; archived_at: string | null;
  created_at: string; updated_at: string;
};

export type FinancialPlanAccountLine = {
  account_id: string; name: string; balance_minor: string; backed_minor: string; available_minor: string;
};
export type FinancialPlanGoalShortfall = { goal_id: string; name: string; shortfall_minor: string };
export type FinancialPlanSaldoInicial = {
  accounts: FinancialPlanAccountLine[];
  saldo_en_cuentas_minor: string;
  apartado_respaldado_minor: string;
  disponible_sin_comprometer_minor: string;
  faltante_de_respaldo_minor: string;
  faltante_de_respaldo_por_meta: FinancialPlanGoalShortfall[];
};
export type FinancialPlanCardObligation = {
  card_id: string; name: string; statement_date: string; payment_due_date: string;
  is_closed: boolean; amount_minor: string;
};
export type FinancialPlanFlowLine = {
  flow_id: string; name: string; category_id: string | null; amount_minor: string; occurred_on: string;
};
export type FinancialPlanBudgetLine = {
  category_id: string; category_name: string; category_icon: string;
  limit_minor: string; spent_minor: string; available_minor: string;
  planned_categorized_minor: string; flexible_additional_minor: string;
};
export type FinancialPlanGoalLine = {
  goal_id: string; name: string; status: GoalStatus; target_minor: string; target_date: string | null;
  target_date_passed: boolean; recommended_minor: string; projected_saved_minor: string;
};
export type FinancialPlanCollectionLine = { contact_id: string; contact_name: string; outstanding_minor: string };
export type FinancialPlanScenarioPoint = { opening_minor: string; closing_minor: string };
export type FinancialPlanMonth = {
  month_index: number; month_start: string;
  card_obligations: FinancialPlanCardObligation[]; card_obligations_total_minor: string;
  planned_flows: FinancialPlanFlowLine[]; planned_income_total_minor: string; planned_outflow_total_minor: string;
  budgets: FinancialPlanBudgetLine[]; flexible_additional_total_minor: string;
  goals: FinancialPlanGoalLine[]; goals_recommended_total_minor: string;
  expected_collections: FinancialPlanCollectionLine[]; expected_collections_total_minor: string;
  base: FinancialPlanScenarioPoint; planned: FinancialPlanScenarioPoint; planned_with_collections: FinancialPlanScenarioPoint;
};
export type FinancialPlan = {
  as_of_date: string; currency: CurrencyCode; horizon_months: number;
  saldo_inicial: FinancialPlanSaldoInicial; months: FinancialPlanMonth[];
};

export type RecurringDirection = "income" | "expense";
export type RecurringStatus = "active" | "paused";
export type RecurringFrequency =
  | "weekly" | "biweekly" | "semimonthly" | "monthly" | "bimonthly" | "quarterly" | "semiannual" | "annual";

export type RecurringRule = {
  id: string; user_id: string; name: string; direction: RecurringDirection; currency: CurrencyCode;
  start_date: string; end_date: string | null; status: RecurringStatus; archived_at: string | null;
  subtype: string | null; migrated_from_planned_cash_flow_id: string | null;
  created_at: string; updated_at: string;
};
export type RecurringRuleVersion = {
  id: string; user_id: string; rule_id: string; effective_from_date: string;
  amount_minor: string; category_id: string | null; frequency: RecurringFrequency;
  day_of_month: number | null; day_of_month_secondary: number | null;
  account_id: string | null; card_id: string | null; created_at: string;
};
export type RecurringOccurrenceStatus = "confirmed" | "omitted";
export type RecurringOccurrenceCandidate = {
  rule_id: string; name: string; direction: RecurringDirection; currency: CurrencyCode;
  occurred_on: string; amount_minor: string; category_id: string | null;
  account_id: string | null; card_id: string | null;
  existing_occurrence_id: string | null; existing_status: RecurringOccurrenceStatus | null;
};
export type RecurringOccurrenceActivity = {
  id: string; user_id: string; rule_id: string; rule_name: string; currency: CurrencyCode;
  direction: RecurringDirection; expected_date: string; status: RecurringOccurrenceStatus;
  expected_amount_minor: string; category_id: string | null; notes: string | null; created_at: string;
  financial_event_id: string | null; actual_amount_minor: string | null; actual_date: string | null;
  account_id: string | null; card_id: string | null; is_reversed_without_replacement: boolean;
};

/** Phase 7C-A: iPhone Shortcuts personal tokens (domain only, no HTTP layer yet). */
export type ShortcutTokenScope = "shortcut:options:read" | "shortcut:transactions:write";
export type ShortcutTokenCreated = {
  id: string; token_plain: string; name: string; scopes: ShortcutTokenScope[];
  created_at: string; expires_at: string | null;
};
export type ShortcutTokenSummary = {
  id: string; name: string; scopes: ShortcutTokenScope[]; created_at: string;
  last_used_at: string | null; expires_at: string | null; revoked_at: string | null;
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
      planned_cash_flows: { Row: PlannedCashFlow; Insert: never; Update: never; Relationships: [] };
      recurring_rules: { Row: RecurringRule; Insert: never; Update: never; Relationships: [] };
      recurring_rule_versions: { Row: RecurringRuleVersion; Insert: never; Update: never; Relationships: [] };
      recurring_rule_pauses: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      recurring_occurrences: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
      recurring_occurrence_events: { Row: Record<string, unknown>; Insert: never; Update: never; Relationships: [] };
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
      contact_period_overview: { Row: { contact_id: string; user_id: string; periods: PersonCollectionPeriod[] }; Relationships: [] };
      goal_balances: { Row: GoalBalance; Relationships: [] };
      goal_entry_activity: { Row: GoalEntryActivity; Relationships: [] };
      recurring_occurrence_activity: { Row: RecurringOccurrenceActivity; Relationships: [] };
      recurring_occurrence_current_event: { Row: Record<string, unknown>; Relationships: [] };
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
      get_person_statement: { Args: { p_contact_id: string; p_as_of_date?: string }; Returns: PersonStatement };
      record_person_statement_export: { Args: { p_contact_id: string; p_period_start: string; p_period_end: string; p_format: string; p_idempotency_key: string }; Returns: string };
      get_budgets_for_period: { Args: { p_month: string; p_currency: string | null }; Returns: BudgetPeriodSummary[] };
      get_budget_movements: { Args: { p_category_id: string; p_currency: string; p_month: string }; Returns: BudgetMovement[] };
      create_budget: { Args: { p_category_id: string; p_currency: string; p_limit_minor: string; p_effective_from_month: string | null; p_period_month: string | null; p_idempotency_key: string }; Returns: string };
      update_recurring_budget_from_month: { Args: { p_category_id: string; p_currency: string; p_limit_minor: string; p_effective_from_month: string; p_idempotency_key: string }; Returns: string };
      update_budget_exception_limit: { Args: { p_budget_id: string; p_limit_minor: string; p_idempotency_key: string }; Returns: string };
      stop_recurring_budget: { Args: { p_category_id: string; p_currency: string; p_last_active_month: string; p_idempotency_key: string }; Returns: string };
      archive_budget: { Args: { p_budget_id: string; p_idempotency_key: string }; Returns: string };
      restore_budget: { Args: { p_budget_id: string; p_idempotency_key: string }; Returns: string };
      create_goal: { Args: { p_name: string; p_currency: string; p_target_minor: string; p_target_date: string | null; p_linked_account_id: string | null; p_icon: string | null; p_idempotency_key: string }; Returns: string };
      update_goal: { Args: { p_goal_id: string; p_name: string; p_target_minor: string; p_target_date: string | null; p_linked_account_id: string | null; p_icon: string | null; p_idempotency_key: string }; Returns: string };
      set_goal_status: { Args: { p_goal_id: string; p_status: string; p_idempotency_key: string }; Returns: string };
      archive_goal: { Args: { p_goal_id: string; p_idempotency_key: string }; Returns: string };
      restore_goal: { Args: { p_goal_id: string; p_idempotency_key: string }; Returns: string };
      contribute_to_goal: { Args: { p_goal_id: string; p_amount_minor: string; p_source_account_id: string; p_move_real_money: boolean; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      withdraw_from_goal: { Args: { p_goal_id: string; p_amount_minor: string; p_account_id: string | null; p_move_real_money: boolean; p_destination_account_id: string | null; p_occurred_on: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      reverse_goal_entry: { Args: { p_entry_id: string; p_idempotency_key: string }; Returns: string };
      create_planned_cash_flow: { Args: { p_name: string; p_currency: string; p_amount_minor: string; p_category_id: string | null; p_recurrence: string; p_start_date: string; p_end_date: string | null; p_idempotency_key: string }; Returns: string };
      update_planned_cash_flow: { Args: { p_flow_id: string; p_name: string; p_amount_minor: string; p_category_id: string | null; p_recurrence: string; p_start_date: string; p_end_date: string | null; p_idempotency_key: string }; Returns: string };
      archive_planned_cash_flow: { Args: { p_flow_id: string; p_idempotency_key: string }; Returns: string };
      restore_planned_cash_flow: { Args: { p_flow_id: string; p_idempotency_key: string }; Returns: string };
      get_financial_plan: { Args: { p_currency: string; p_as_of_date?: string; p_horizon_months?: number }; Returns: FinancialPlan };
      create_recurring_rule: { Args: { p_name: string; p_direction: string; p_currency: string; p_amount_minor: string; p_category_id: string | null; p_frequency: string; p_day_of_month: number | null; p_day_of_month_secondary: number | null; p_account_id: string | null; p_card_id: string | null; p_start_date: string; p_end_date: string | null; p_subtype: string | null; p_idempotency_key: string }; Returns: string };
      update_recurring_rule: { Args: { p_rule_id: string; p_name: string; p_end_date: string | null; p_effective_from_date: string | null; p_amount_minor: string; p_category_id: string | null; p_frequency: string; p_day_of_month: number | null; p_day_of_month_secondary: number | null; p_account_id: string | null; p_card_id: string | null; p_idempotency_key: string }; Returns: string };
      pause_recurring_rule: { Args: { p_rule_id: string; p_idempotency_key: string }; Returns: string };
      resume_recurring_rule: { Args: { p_rule_id: string; p_idempotency_key: string }; Returns: string };
      archive_recurring_rule: { Args: { p_rule_id: string; p_idempotency_key: string }; Returns: string };
      restore_recurring_rule: { Args: { p_rule_id: string; p_idempotency_key: string }; Returns: string };
      confirm_recurring_occurrence: { Args: { p_rule_id: string; p_expected_date: string; p_actual_amount_minor: string; p_actual_date: string; p_source_account_id: string | null; p_source_card_id: string | null; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      omit_recurring_occurrence: { Args: { p_rule_id: string; p_expected_date: string; p_notes: string | null; p_idempotency_key: string }; Returns: string };
      get_recurring_occurrences: { Args: { p_from_date: string; p_to_date: string }; Returns: RecurringOccurrenceCandidate[] };
      // Phase 7C-A: web-app-facing token management only. execute_shortcut_transaction
      // is service_role-only and deliberately NOT registered here -- the browser client
      // must never be able to reference it, even at the type level.
      create_shortcut_token: { Args: { p_name: string; p_scopes: ShortcutTokenScope[] }; Returns: ShortcutTokenCreated[] };
      list_shortcut_tokens: { Args: Record<string, never>; Returns: ShortcutTokenSummary[] };
      revoke_shortcut_token: { Args: { p_token_id: string; p_idempotency_key: string }; Returns: string };
    };
    Enums: Record<never, never>;
    CompositeTypes: Record<never, never>;
  };
};
