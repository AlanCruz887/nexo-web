import { supabase } from "@/lib/supabase";
import { reportError } from "@/lib/errors";
import type { ContactInput, PersonPaymentInput } from "@/schemas/contact";
import type { ContactActivity, ContactSummary, PersonCollectionProjection, PersonInstallmentSummary, PersonStatement, ReceivableBalance } from "@/types/database";

export const contactService = {
  // contact_balance_summary (name, per-currency debt) is the base data the
  // list can never render without. contact_period_overview (this-period /
  // saldo a favor) is a secondary enrichment computed in a single extra
  // query for every contact at once, not one call per contact: if it fails,
  // the list still renders with `periods` left undefined per contact.
  async list(): Promise<ContactSummary[]> {
    const [contacts, overview] = await Promise.all([
      supabase.from("contact_balance_summary").select("*").order("is_active", { ascending: false }).order("name"),
      supabase.from("contact_period_overview").select("*"),
    ]);
    if (contacts.error) throw contacts.error;
    if (overview.error) reportError("contactService.list:periods", overview.error);
    const periodsByContact = new Map((overview.data ?? []).map((row) => [row.contact_id, row.periods]));
    return contacts.data.map((contact) => ({ ...contact, periods: periodsByContact.get(contact.id) }));
  },
  async get(id: string): Promise<ContactSummary | null> { const { data, error } = await supabase.from("contact_balance_summary").select("*").eq("id", id).maybeSingle(); if (error) throw error; return data; },
  async receivables(id: string): Promise<ReceivableBalance[]> { const { data, error } = await supabase.from("receivable_balances").select("*").eq("contact_id", id).order("occurred_on", { ascending: false }); if (error) throw error; return data; },
  async activity(id: string): Promise<ContactActivity[]> { const { data, error } = await supabase.from("contact_activity").select("*").eq("contact_id", id).order("occurred_on", { ascending: false }).order("created_at", { ascending: false }); if (error) throw error; return data; },
  async create(input: ContactInput, key: string) { const { data, error } = await supabase.rpc("create_contact", { p_name: input.name, p_email: input.email || null, p_phone: input.phone || null, p_notes: input.notes || null, p_idempotency_key: key }); if (error) throw error; return data; },
  async update(id: string, input: ContactInput, key: string) { const { data, error } = await supabase.rpc("update_contact", { p_contact_id: id, p_name: input.name, p_email: input.email || null, p_phone: input.phone || null, p_notes: input.notes || null, p_idempotency_key: key }); if (error) throw error; return data; },
  async setActive(id: string, active: boolean, key: string) { const { data, error } = await supabase.rpc("set_contact_active", { p_contact_id: id, p_active: active, p_idempotency_key: key }); if (error) throw error; return data; },
  async payment(contactId: string, input: PersonPaymentInput, amountMinor: string, key: string) { const { data, error } = await supabase.rpc("create_person_payment", { p_contact_id: contactId, p_account_id: input.account_id, p_amount_minor: amountMinor, p_occurred_on: input.occurred_on, p_notes: input.notes || null, p_idempotency_key: key }); if (error) throw error; return data; },
  async reversePayment(eventId: string, key: string) { const { data, error } = await supabase.rpc("reverse_person_payment", { p_event_id: eventId, p_idempotency_key: key }); if (error) throw error; return data; },
  async period(contactId: string): Promise<PersonCollectionProjection> { const { data, error } = await supabase.rpc("get_person_collection_period", { p_contact_id: contactId }); if (error) throw error; return data; },
  async statement(contactId: string): Promise<PersonStatement> { const { data, error } = await supabase.rpc("get_person_statement", { p_contact_id: contactId }); if (error) throw error; return data; },
  async installments(contactId: string): Promise<PersonInstallmentSummary[]> { const { data, error } = await supabase.from("person_installment_summaries").select("*").eq("contact_id", contactId).order("current_statement_date"); if (error) throw error; return data; },
  async applyCredit(contactId: string, currency: string, amountMinor: string, key: string) { const { data, error } = await supabase.rpc("apply_person_credit", { p_contact_id: contactId, p_currency: currency, p_amount_minor: amountMinor, p_idempotency_key: key }); if (error) throw error; return data; },
  async recordExport(contactId: string, start: string, end: string, format: "pdf" | "xlsx" | "csv", key: string) { const { data, error } = await supabase.rpc("record_person_statement_export", { p_contact_id: contactId, p_period_start: start, p_period_end: end, p_format: format, p_idempotency_key: key }); if (error) throw error; return data; },
};
