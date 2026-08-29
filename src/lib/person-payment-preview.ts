// Pure display preview for a payment or credit application the user is still
// typing. It only compares two already-projected totals (never recomputes
// them): how much is still owed right now, and the amount being offered.
// The actual FIFO distribution across obligations stays server-side in
// get_person_collection_period / create_person_payment / apply_person_credit.

// create_person_payment applies FIFO across every due item with a balance —
// not just this period's — before any excess becomes saldo a favor. So an
// amount above what's due this period first advances future obligations
// (installments, other pending purchases); it only becomes credit once
// nothing else is owed. remainingMinor and totalOutstandingMinor both come
// straight from get_person_collection_period.
export function previewPersonPayment(remainingMinor: bigint, totalOutstandingMinor: bigint, amountMinor: bigint) {
  const appliedToPeriodMinor = amountMinor < remainingMinor ? amountMinor : remainingMinor;
  const missingMinor = remainingMinor - appliedToPeriodMinor;
  const excessMinor = amountMinor - appliedToPeriodMinor;
  const advanceCapacityMinor = totalOutstandingMinor > remainingMinor ? totalOutstandingMinor - remainingMinor : 0n;
  const advancedMinor = excessMinor < advanceCapacityMinor ? excessMinor : advanceCapacityMinor;
  const creditMinor = excessMinor - advancedMinor;
  return { appliedToPeriodMinor, missingMinor, advancedMinor, creditMinor };
}

export function previewCreditApplication(creditBalanceMinor: bigint, totalOutstandingMinor: bigint) {
  const appliedMinor = creditBalanceMinor < totalOutstandingMinor ? creditBalanceMinor : totalOutstandingMinor;
  const remainingCreditMinor = creditBalanceMinor - appliedMinor;
  return { appliedMinor, remainingCreditMinor };
}
