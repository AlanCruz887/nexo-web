import { skipToken, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createIdempotencyKey } from "@/lib/idempotency";
import { parseMoneyInput, serializeMoneyMinor } from "@/lib/money";
import type { ContactInput, PersonPaymentInput } from "@/schemas/contact";
import { contactService } from "@/services/contact-service";

function useInvalidatePeople() { const client = useQueryClient(); return () => Promise.all([client.invalidateQueries({ queryKey: ["contacts"] }), client.invalidateQueries({ queryKey: ["contact"] }), client.invalidateQueries({ queryKey: ["contact-receivables"] }), client.invalidateQueries({ queryKey: ["contact-activity"] }), client.invalidateQueries({ queryKey: ["contact-period"] }), client.invalidateQueries({ queryKey: ["contact-installments"] }), client.invalidateQueries({ queryKey: ["accounts"] }), client.invalidateQueries({ queryKey: ["transactions"] })]); }
export function useContacts() { return useQuery({ queryKey: ["contacts"], queryFn: contactService.list }); }
export function useContact(id?: string) { return useQuery({ queryKey: ["contact", id], queryFn: id ? () => contactService.get(id) : skipToken }); }
export function useContactReceivables(id?: string) { return useQuery({ queryKey: ["contact-receivables", id], queryFn: id ? () => contactService.receivables(id) : skipToken }); }
export function useContactActivity(id?: string) { return useQuery({ queryKey: ["contact-activity", id], queryFn: id ? () => contactService.activity(id) : skipToken }); }
export function useContactPeriod(id?: string) { return useQuery({ queryKey: ["contact-period", id], queryFn: id ? () => contactService.period(id) : skipToken }); }
export function useContactInstallments(id?: string) { return useQuery({ queryKey: ["contact-installments", id], queryFn: id ? () => contactService.installments(id) : skipToken }); }
export function useCreateContact() { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: (input: ContactInput) => contactService.create(input, createIdempotencyKey("contact:create")), onSuccess: invalidate }); }
export function useUpdateContact(id: string) { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: (input: ContactInput) => contactService.update(id, input, createIdempotencyKey("contact:update")), onSuccess: invalidate }); }
export function useSetContactActive() { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: ({ id, active }: { id: string; active: boolean }) => contactService.setActive(id, active, createIdempotencyKey("contact:active")), onSuccess: invalidate }); }
export function useCreatePersonPayment(contactId: string) { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: (input: PersonPaymentInput) => contactService.payment(contactId, input, serializeMoneyMinor(parseMoneyInput(input.amount)), createIdempotencyKey("person:payment")), onSuccess: invalidate }); }
export function useReversePersonPayment() { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: (eventId: string) => contactService.reversePayment(eventId, createIdempotencyKey("person:payment:reverse")), onSuccess: invalidate }); }
export function useApplyPersonCredit(contactId: string) { const invalidate = useInvalidatePeople(); return useMutation({ mutationFn: ({ currency, amountMinor }: { currency: string; amountMinor: string }) => contactService.applyCredit(contactId, currency, amountMinor, createIdempotencyKey("person:credit:apply")), onSuccess: invalidate }); }
export function useRecordPersonStatementExport(contactId: string) { return useMutation({ mutationFn: ({ start, end, format }: { start: string; end: string; format: "pdf" | "xlsx" | "csv" }) => contactService.recordExport(contactId, start, end, format, createIdempotencyKey(`person:statement:${format}`)) }); }
