import { supabase } from "@/lib/supabase";
import type {
  CurrencyCode,
  RecurringDirection,
  RecurringFrequency,
  RecurringOccurrenceActivity,
  RecurringOccurrenceCandidate,
  RecurringRule,
  RecurringRuleVersion,
} from "@/types/database";

export const recurringRuleService = {
  async list(): Promise<RecurringRule[]> {
    const { data, error } = await supabase.from("recurring_rules").select("*").order("name", { ascending: true });
    if (error) throw error;
    return data;
  },
  async currentVersion(ruleId: string): Promise<RecurringRuleVersion> {
    const { data, error } = await supabase.from("recurring_rule_versions").select("*")
      .eq("rule_id", ruleId).order("effective_from_date", { ascending: false }).limit(1).single();
    if (error) throw error;
    return data;
  },
  async occurrences(fromDate: string, toDate: string): Promise<RecurringOccurrenceCandidate[]> {
    const { data, error } = await supabase.rpc("get_recurring_occurrences", { p_from_date: fromDate, p_to_date: toDate });
    if (error) throw error;
    return data;
  },
  async history(ruleId: string): Promise<RecurringOccurrenceActivity[]> {
    const { data, error } = await supabase.from("recurring_occurrence_activity").select("*")
      .eq("rule_id", ruleId).order("expected_date", { ascending: false });
    if (error) throw error;
    return data;
  },
  async create(
    input: {
      name: string; direction: RecurringDirection; currency: CurrencyCode; amountMinor: string;
      categoryId: string | null; frequency: RecurringFrequency; dayOfMonth: number | null;
      dayOfMonthSecondary: number | null; accountId: string | null; cardId: string | null;
      startDate: string; endDate: string | null; subtype: string | null;
    },
    key: string,
  ) {
    const { data, error } = await supabase.rpc("create_recurring_rule", {
      p_name: input.name, p_direction: input.direction, p_currency: input.currency, p_amount_minor: input.amountMinor,
      p_category_id: input.categoryId, p_frequency: input.frequency, p_day_of_month: input.dayOfMonth,
      p_day_of_month_secondary: input.dayOfMonthSecondary, p_account_id: input.accountId, p_card_id: input.cardId,
      p_start_date: input.startDate, p_end_date: input.endDate, p_subtype: input.subtype, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async update(
    id: string,
    input: {
      name: string; endDate: string | null; effectiveFromDate: string | null; amountMinor: string;
      categoryId: string | null; frequency: RecurringFrequency; dayOfMonth: number | null;
      dayOfMonthSecondary: number | null; accountId: string | null; cardId: string | null;
    },
    key: string,
  ) {
    const { data, error } = await supabase.rpc("update_recurring_rule", {
      p_rule_id: id, p_name: input.name, p_end_date: input.endDate, p_effective_from_date: input.effectiveFromDate,
      p_amount_minor: input.amountMinor, p_category_id: input.categoryId, p_frequency: input.frequency,
      p_day_of_month: input.dayOfMonth, p_day_of_month_secondary: input.dayOfMonthSecondary,
      p_account_id: input.accountId, p_card_id: input.cardId, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async pause(id: string, key: string) {
    const { data, error } = await supabase.rpc("pause_recurring_rule", { p_rule_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async resume(id: string, key: string) {
    const { data, error } = await supabase.rpc("resume_recurring_rule", { p_rule_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async archive(id: string, key: string) {
    const { data, error } = await supabase.rpc("archive_recurring_rule", { p_rule_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async restore(id: string, key: string) {
    const { data, error } = await supabase.rpc("restore_recurring_rule", { p_rule_id: id, p_idempotency_key: key });
    if (error) throw error;
    return data;
  },
  async confirm(
    input: {
      ruleId: string; expectedDate: string; actualAmountMinor: string; actualDate: string;
      sourceAccountId: string | null; sourceCardId: string | null; notes: string | null;
    },
    key: string,
  ) {
    const { data, error } = await supabase.rpc("confirm_recurring_occurrence", {
      p_rule_id: input.ruleId, p_expected_date: input.expectedDate, p_actual_amount_minor: input.actualAmountMinor,
      p_actual_date: input.actualDate, p_source_account_id: input.sourceAccountId, p_source_card_id: input.sourceCardId,
      p_notes: input.notes, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
  async omit(ruleId: string, expectedDate: string, notes: string | null, key: string) {
    const { data, error } = await supabase.rpc("omit_recurring_occurrence", {
      p_rule_id: ruleId, p_expected_date: expectedDate, p_notes: notes, p_idempotency_key: key,
    });
    if (error) throw error;
    return data;
  },
};
