import { supabase } from "@/lib/supabase";
import type { CardPaymentInput, CardPurchaseInput, CardRefundInput } from "@/schemas/card-transaction";
import type { CardPaymentClassification, CardStatementActivitySegment, FinancialActivity } from "@/types/database";
import { resolvePurchaseSplit } from "@/lib/purchase-split";

async function addPurchaseAllocations(rows: FinancialActivity[]) {
  if (!rows.length) return rows;
  const { data, error } = await supabase.from("purchase_allocation_details").select("*").in("financial_event_id", rows.map((row) => row.event_id));
  if (error) throw error;
  const byEvent = new Map(data.map((item) => [item.financial_event_id, item.allocations]));
  return rows.map((row) => ({ ...row, third_party_allocations: byEvent.get(row.event_id) ?? [] }));
}

function addPaymentClassifications(rows: FinancialActivity[], classifications: CardPaymentClassification[]) {
  const byEvent = new Map(classifications.map((item) => [item.event_id, item]));
  return rows.map((row) => {
    const payment = byEvent.get(row.event_id);
    return payment ? {
      ...row,
      payment_state: payment.payment_state,
      payment_applied_minor: payment.applied_amount_minor,
      payment_advance_minor: payment.advance_amount_minor,
      payment_cycle_start: payment.cycle_start,
      payment_cycle_end: payment.cycle_end,
      payment_cycle_statement_date: payment.cycle_statement_date,
    } : row;
  });
}

export const cardTransactionService = {
  async list(cardId: string, kind: "all" | "card_charge" | "installments" | "card_payment" | "card_refund" = "all"): Promise<FinancialActivity[]> {
    let query = supabase.from("financial_activity_enriched").select("*").eq("card_id", cardId)
      .order("occurred_on", { ascending: false }).order("created_at", { ascending: false });
    if (kind === "installments") query = query.not("installment_plan_id", "is", null);
    else if (kind !== "all") query = query.eq("kind", kind);
    const { data, error } = await query;
    if (error) throw error;
    if (!data.some((row) => row.kind === "card_payment")) return addPurchaseAllocations(data);
    const { data: classifications, error: classificationError } = await supabase
      .from("card_payment_classifications").select("*").eq("card_id", cardId);
    if (classificationError) throw classificationError;
    return addPurchaseAllocations(addPaymentClassifications(data, classifications));
  },
  async statementActivity(cardId: string, statementDates: string[], kind: "all" | "card_charge" | "installments" | "card_payment" | "card_refund" = "all"): Promise<CardStatementActivitySegment[]> {
    if (statementDates.length === 0) return [];
    let query = supabase.from("card_statement_activity_segments").select("*").eq("card_id", cardId)
      .in("group_statement_date", statementDates)
      .order("group_statement_date", { ascending: false }).order("occurred_on", { ascending: false });
    if (kind === "installments") query = query.eq("segment_kind", "installment");
    else if (kind !== "all") query = query.eq("kind", kind);
    const { data, error } = await query;
    if (error) throw error;
    return data;
  },
  async createPurchase(input: CardPurchaseInput, amountMinor: string, idempotencyKey: string): Promise<string> {
    if (input.purchase_type === "single") {
      const split = resolvePurchaseSplit(input);
      const { data, error } = await supabase.rpc("create_shared_card_purchase", {
        p_card_id: input.card_id, p_amount_minor: amountMinor, p_personal_amount_minor: split.personalAmountMinor,
        p_allocations: split.allocations, p_description: input.description, p_category_id: input.category_id,
        p_occurred_on: input.occurred_on, p_payment_method: input.payment_method || null,
        p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
      });
      if (error) throw error; return data;
    }
    const { data, error } = await supabase.rpc("create_card_purchase", {
      p_card_id: input.card_id, p_amount_minor: amountMinor, p_description: input.description,
      p_category_id: input.category_id, p_occurred_on: input.occurred_on,
      p_payment_method: input.payment_method || null, p_notes: input.notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async updatePurchase(eventId: string, input: CardPurchaseInput, amountMinor: string, idempotencyKey: string): Promise<string> {
    if (input.purchase_type === "single") {
      const split = resolvePurchaseSplit(input);
      const { data, error } = await supabase.rpc("update_shared_card_purchase", {
        p_event_id: eventId, p_card_id: input.card_id, p_amount_minor: amountMinor,
        p_personal_amount_minor: split.personalAmountMinor, p_allocations: split.allocations,
        p_description: input.description, p_category_id: input.category_id, p_occurred_on: input.occurred_on,
        p_payment_method: input.payment_method || null, p_notes: input.notes || null,
        p_idempotency_key: idempotencyKey,
      });
      if (error) throw error; return data;
    }
    const { data, error } = await supabase.rpc("update_card_purchase", {
      p_event_id: eventId, p_card_id: input.card_id, p_amount_minor: amountMinor,
      p_description: input.description, p_category_id: input.category_id,
      p_occurred_on: input.occurred_on, p_payment_method: input.payment_method || null,
      p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async createPayment(input: CardPaymentInput, amountMinor: string, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("create_card_payment", {
      p_card_id: input.card_id, p_source_account_id: input.source_account_id,
      p_amount_minor: amountMinor, p_occurred_on: input.occurred_on,
      p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async createRefund(input: CardRefundInput, amountMinor: string, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("create_card_refund", {
      p_card_id: input.card_id, p_amount_minor: amountMinor, p_description: input.description,
      p_category_id: input.category_id || null, p_occurred_on: input.occurred_on,
      p_original_event_id: input.original_event_id || null, p_notes: input.notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async reverse(eventId: string, kind: "card_charge" | "card_payment" | "card_refund", idempotencyKey: string): Promise<string> {
    const rpc = kind === "card_charge" ? "reverse_card_purchase" : kind === "card_payment" ? "reverse_card_payment" : "reverse_card_refund";
    const { data, error } = await supabase.rpc(rpc, { p_event_id: eventId, p_idempotency_key: idempotencyKey });
    if (error) throw error;
    return data;
  },
};
