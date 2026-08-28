import { supabase } from "@/lib/supabase";
import type { MovementFormInput, TransferFormInput } from "@/schemas/movement";
import type { AccountActivity } from "@/types/database";

export interface MovementFilters {
  accountId?: string;
  categoryId?: string;
  dateFrom?: string;
  dateTo?: string;
  kind?: "all" | "income" | "expense" | "transfer";
  minimumMinor?: string;
  maximumMinor?: string;
}

export const movementService = {
  async list(filters: MovementFilters = {}): Promise<AccountActivity[]> {
    let query = supabase
      .from("account_activity")
      .select("*")
      .order("occurred_on", { ascending: false })
      .order("created_at", { ascending: false });
    if (filters.accountId) query = query.eq("account_id", filters.accountId);
    if (filters.categoryId) query = query.eq("category_id", filters.categoryId);
    if (filters.kind && filters.kind !== "all") query = query.eq("kind", filters.kind);
    if (filters.dateFrom) query = query.gte("occurred_on", filters.dateFrom);
    if (filters.dateTo) query = query.lte("occurred_on", filters.dateTo);
    if (filters.minimumMinor) query = query.gte("amount_minor", filters.minimumMinor);
    if (filters.maximumMinor) query = query.lte("amount_minor", filters.maximumMinor);
    const { data, error } = await query;
    if (error) throw error;
    return data;
  },

  async get(eventId: string): Promise<AccountActivity[]> {
    const { data, error } = await supabase
      .from("account_activity")
      .select("*")
      .eq("event_id", eventId)
      .order("account_delta_minor", { ascending: true });
    if (error) throw error;
    return data;
  },

  async create(input: MovementFormInput, amountMinor: string, idempotencyKey: string) {
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
