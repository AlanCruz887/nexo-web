import { supabase } from "@/lib/supabase";
import type { CardEditInput, CardFormInput } from "@/schemas/card";
import type { CardCurrentCycle, CardStatement, CardStatementCloseCandidate, CardSummary } from "@/types/database";

export const cardService = {
  async list(): Promise<CardSummary[]> {
    const { data, error } = await supabase.from("card_summaries").select("*").order("is_active", { ascending: false }).order("created_at");
    if (error) throw error;
    return data;
  },
  async get(cardId: string): Promise<CardSummary> {
    const { data, error } = await supabase.from("card_summaries").select("*").eq("id", cardId).single();
    if (error) throw error;
    return data;
  },
  async cycle(cardId: string): Promise<CardCurrentCycle> {
    const { data, error } = await supabase.from("card_current_cycles").select("*").eq("card_id", cardId).single();
    if (error) throw error;
    return data;
  },
  async statements(cardId: string): Promise<CardStatement[]> {
    const { data, error } = await supabase.from("card_statements").select("*").eq("card_id", cardId).order("statement_date", { ascending: false });
    if (error) throw error;
    return data;
  },
  async statementCloseCandidate(cardId: string): Promise<CardStatementCloseCandidate | null> {
    const { data, error } = await supabase.from("card_statement_close_candidates").select("*").eq("card_id", cardId).maybeSingle();
    if (error) throw error;
    return data;
  },
  async create(input: CardFormInput, amounts: { limit: string; bank: string; excluded: string | null }, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("create_credit_card", {
      p_name: input.name, p_issuer: input.issuer, p_product_name: input.product_name || null,
      p_currency: input.currency, p_credit_limit_minor: amounts.limit,
      p_statement_day: Number(input.statement_day), p_payment_days_after_statement: Number(input.payment_days_after_statement),
      p_last4: input.last4 || null, p_visual_theme: input.visual_theme,
      p_baseline_policy: input.baseline_policy, p_baseline_date: input.baseline_date,
      p_reported_bank_balance_minor: amounts.bank, p_excluded_statement_amount_minor: amounts.excluded,
      p_baseline_notes: input.baseline_notes || null, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async update(cardId: string, input: CardEditInput, limitMinor: string, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("update_credit_card", {
      p_card_id: cardId, p_name: input.name, p_issuer: input.issuer, p_product_name: input.product_name || null,
      p_credit_limit_minor: limitMinor, p_statement_day: Number(input.statement_day),
      p_payment_days_after_statement: Number(input.payment_days_after_statement), p_last4: input.last4 || null,
      p_visual_theme: input.visual_theme, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async setActive(cardId: string, active: boolean, idempotencyKey: string): Promise<string> {
    const rpc = active ? "restore_credit_card" : "archive_credit_card";
    const { data, error } = await supabase.rpc(rpc, { p_card_id: cardId, p_idempotency_key: idempotencyKey });
    if (error) throw error;
    return data;
  },
  async closeStatement(cardId: string, statementDate: string, minimumPaymentMinor: string | null, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("close_card_statement", {
      p_card_id: cardId, p_statement_date: statementDate, p_payment_to_avoid_interest_minor: null,
      p_minimum_payment_minor: minimumPaymentMinor, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
};
