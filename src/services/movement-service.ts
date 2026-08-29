import { supabase } from "@/lib/supabase";
import { sourceTypesForOrigin, type MovementOrigin } from "@/lib/movement-filters";
import type { MovementFormInput, TransferFormInput } from "@/schemas/movement";
import type { FinancialActivity } from "@/types/database";
import { resolvePurchaseSplit } from "@/lib/purchase-split";

async function withAllocations(rows: FinancialActivity[]) {
  if (!rows.length) return rows;
  const { data, error } = await supabase.from("purchase_allocation_details").select("*").in("financial_event_id", rows.map((row) => row.event_id));
  if (error) throw error;
  const allocations = new Map(data.map((item) => [item.financial_event_id, item.allocations]));
  return rows.map((row) => ({ ...row, third_party_allocations: allocations.get(row.event_id) ?? [] }));
}

export interface MovementFilters {
  accountId?: string;
  cardId?: string;
  origin?: MovementOrigin;
  categoryId?: string;
  dateFrom?: string;
  dateTo?: string;
  kind?: "all" | "income" | "expense" | "transfer" | "card_charge" | "installments" | "card_payment" | "card_refund";
  minimumMinor?: string;
  maximumMinor?: string;
}

export const movementService = {
  async list(filters: MovementFilters = {}): Promise<FinancialActivity[]> {
    let query = supabase
      .from("financial_activity_enriched")
      .select("*")
      .order("occurred_on", { ascending: false })
      .order("created_at", { ascending: false });
    if (filters.accountId) query = query.or(`account_id.eq.${filters.accountId},source_account_id.eq.${filters.accountId},destination_account_id.eq.${filters.accountId}`);
    if (filters.cardId) query = query.eq("card_id", filters.cardId);
    const sourceTypes = sourceTypesForOrigin(filters.origin ?? "all");
    if (sourceTypes) query = query.in("source_type", [...sourceTypes]);
    if (filters.categoryId) query = query.eq("category_id", filters.categoryId);
    if (filters.kind === "expense") query = query.in("kind", ["expense", "card_charge"]);
    else if (filters.kind === "installments") query = query.not("installment_plan_id", "is", null);
    else if (filters.kind && filters.kind !== "all") query = query.eq("kind", filters.kind);
    if (filters.dateFrom) query = query.gte("occurred_on", filters.dateFrom);
    if (filters.dateTo) query = query.lte("occurred_on", filters.dateTo);
    if (filters.minimumMinor) query = query.gte("amount_minor", filters.minimumMinor);
    if (filters.maximumMinor) query = query.lte("amount_minor", filters.maximumMinor);
    let paymentQuery = supabase.from("person_payment_activity").select("*").order("occurred_on", { ascending: false }).order("created_at", { ascending: false });
    if (filters.accountId) paymentQuery = paymentQuery.eq("account_id", filters.accountId);
    if (filters.cardId || filters.origin === "cards" || (filters.kind && filters.kind !== "all")) paymentQuery = paymentQuery.limit(0);
    if (filters.dateFrom) paymentQuery = paymentQuery.gte("occurred_on", filters.dateFrom);
    if (filters.dateTo) paymentQuery = paymentQuery.lte("occurred_on", filters.dateTo);
    if (filters.minimumMinor) paymentQuery = paymentQuery.gte("amount_minor", filters.minimumMinor);
    if (filters.maximumMinor) paymentQuery = paymentQuery.lte("amount_minor", filters.maximumMinor);
    const [{ data, error }, { data: payments, error: paymentsError }] = await Promise.all([query, paymentQuery]);
    if (error) throw error;
    if (paymentsError) throw paymentsError;
    return withAllocations([...(data as FinancialActivity[]), ...(payments as FinancialActivity[])]
      .sort((a, b) => b.occurred_on.localeCompare(a.occurred_on) || b.created_at.localeCompare(a.created_at)));
  },

  async get(eventId: string): Promise<FinancialActivity[]> {
    const { data, error } = await supabase
      .from("financial_activity_enriched")
      .select("*")
      .eq("event_id", eventId);
    if (error) throw error;
    if (!data.length) {
      const { data: payment, error: paymentError } = await supabase.from("person_payment_activity").select("*").eq("event_id", eventId);
      if (paymentError) throw paymentError;
      return withAllocations(payment as FinancialActivity[]);
    }
    if (data[0]?.kind !== "card_payment") return withAllocations(data);
    const { data: payment, error: paymentError } = await supabase
      .from("card_payment_classifications").select("*").eq("event_id", eventId).maybeSingle();
    if (paymentError) throw paymentError;
    if (!payment) return data;
    return withAllocations(data.map((row) => ({
      ...row,
      payment_state: payment.payment_state,
      payment_applied_minor: payment.applied_amount_minor,
      payment_advance_minor: payment.advance_amount_minor,
      payment_cycle_start: payment.cycle_start,
      payment_cycle_end: payment.cycle_end,
      payment_cycle_statement_date: payment.cycle_statement_date,
    })));
  },

  async create(input: MovementFormInput, amountMinor: string, idempotencyKey: string) {
    if (input.kind === "expense") {
      const split = resolvePurchaseSplit(input);
      const { data, error } = await supabase.rpc("create_shared_account_purchase", {
        p_account_id: input.account_id, p_amount_minor: amountMinor,
        p_personal_amount_minor: split.personalAmountMinor, p_allocations: split.allocations,
        p_description: input.description, p_category_id: input.category_id,
        p_occurred_on: input.occurred_on, p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
      });
      if (error) throw error; return data;
    }
    const { data, error } = await supabase.rpc("create_transaction", {
      p_account_id: input.account_id,
      p_kind: input.kind,
      p_amount_minor: amountMinor,
      p_description: input.description,
      p_category_id: input.category_id,
      p_occurred_on: input.occurred_on,
      p_notes: input.notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async update(eventId: string, input: MovementFormInput, amountMinor: string, idempotencyKey: string): Promise<string> {
    if (input.kind === "expense") {
      const split = resolvePurchaseSplit(input);
      const { data, error } = await supabase.rpc("update_shared_account_purchase", {
        p_event_id: eventId, p_amount_minor: amountMinor, p_personal_amount_minor: split.personalAmountMinor,
        p_allocations: split.allocations, p_description: input.description, p_category_id: input.category_id,
        p_occurred_on: input.occurred_on, p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
      });
      if (error) throw error; return data;
    }
    const { data, error } = await supabase.rpc("update_transaction", {
      p_event_id: eventId,
      p_amount_minor: amountMinor,
      p_description: input.description,
      p_category_id: input.category_id,
      p_occurred_on: input.occurred_on,
      p_notes: input.notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    if (!data) throw new Error("NEXO_UPDATE_RESPONSE_INVALID");
    return data;
  },

  async transfer(input: TransferFormInput, amountMinor: string, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("create_transfer", {
      p_from_account_id: input.from_account_id,
      p_to_account_id: input.to_account_id,
      p_amount_minor: amountMinor,
      p_description: input.description || "Transferencia",
      p_occurred_on: input.occurred_on,
      p_notes: input.notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async reverse(eventId: string, isTransfer: boolean, idempotencyKey: string) {
    const functionName = isTransfer ? "reverse_transfer" : "reverse_transaction";
    const { data, error } = await supabase.rpc(functionName, {
      p_event_id: eventId,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },

  async updateTransferNotes(eventId: string, notes: string, idempotencyKey: string) {
    const { data, error } = await supabase.rpc("update_transfer_notes", {
      p_event_id: eventId,
      p_notes: notes || null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
};
