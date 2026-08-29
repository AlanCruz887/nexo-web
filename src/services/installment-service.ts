import { supabase } from "@/lib/supabase";
import { resolveInstallmentCount, type CardPurchaseInput } from "@/schemas/card-transaction";
import { historicalPaidBeforeCount, resolveHistoricalInstallmentCount, type HistoricalInstallmentInput } from "@/schemas/historical-installment";
import type { InstallmentPlanSummary, InstallmentSchedule } from "@/types/database";
import { resolvePurchaseSplit } from "@/lib/purchase-split";
import { minorToDisplay } from "@/lib/money";

export const installmentService = {
  async list(cardId: string): Promise<InstallmentPlanSummary[]> {
    const { data, error } = await supabase.from("installment_plan_summaries").select("*")
      .eq("card_id", cardId).neq("status", "reversed").order("created_at", { ascending: false });
    if (error) throw error;
    return data;
  },
  async get(planId: string): Promise<InstallmentPlanSummary | null> {
    const { data, error } = await supabase.from("installment_plan_summaries").select("*")
      .eq("id", planId).maybeSingle();
    if (error) throw error;
    return data;
  },
  async schedule(planId: string): Promise<InstallmentSchedule[]> {
    const { data, error } = await supabase.from("installment_schedule").select("*")
      .eq("plan_id", planId).order("installment_number");
    if (error) throw error;
    return data;
  },
  async create(input: CardPurchaseInput, amountMinor: string, installmentMinor: string | null, idempotencyKey: string): Promise<string> {
    const split = resolvePurchaseSplit(input);
    const { data, error } = await supabase.rpc("create_shared_installment_purchase", {
      p_card_id: input.card_id, p_amount_minor: amountMinor,
      p_personal_amount_minor: split.personalAmountMinor, p_allocations: split.allocations,
      p_installment_count: resolveInstallmentCount(input),
      p_installment_amount_minor: installmentMinor,
      p_description: input.description, p_category_id: input.category_id,
      p_occurred_on: input.occurred_on, p_payment_method: input.payment_method || null,
      p_notes: input.notes || null, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async importHistorical(input: HistoricalInstallmentInput, values: { originalMinor: string; installmentMinor: string; reportedPaidMinor: string; principalPaidMinor: string }, idempotencyKey: string): Promise<string> {
    const remaining = BigInt(values.originalMinor) - BigInt(values.principalPaidMinor);
    const split = resolvePurchaseSplit({ ...input, amount: minorToDisplay(remaining) });
    const { data, error } = await supabase.rpc("import_shared_historical_installment_plan", {
      p_card_id: input.card_id, p_description: input.description,
      p_original_amount_minor: values.originalMinor,
      p_remaining_personal_amount_minor: split.personalAmountMinor,
      p_allocations: split.allocations,
      p_installment_count: resolveHistoricalInstallmentCount(input),
      p_installment_amount_minor: values.installmentMinor,
      p_original_purchase_date: input.original_purchase_date,
      p_current_installment_number: Number(input.current_installment_number),
      p_paid_before_count: historicalPaidBeforeCount(input.current_installment_number),
      p_reported_paid_amount_minor: values.reportedPaidMinor,
      p_principal_paid_minor: values.principalPaidMinor,
      p_next_statement_date: input.next_statement_date,
      p_category_id: input.category_id || null, p_notes: input.notes || null,
      p_included_in_opening_balance: input.opening_balance_inclusion === "included",
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async updateMetadata(planId: string, description: string, categoryId: string | null, notes: string, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("update_installment_plan_metadata", {
      p_plan_id: planId, p_description: description, p_category_id: categoryId,
      p_notes: notes || null, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
  async reverse(planId: string, idempotencyKey: string): Promise<string> {
    const { data, error } = await supabase.rpc("reverse_installment_purchase", {
      p_plan_id: planId, p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;
    return data;
  },
};
