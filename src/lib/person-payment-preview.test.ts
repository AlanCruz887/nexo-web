import { describe, expect, it } from "vitest";

import { previewCreditApplication, previewPersonPayment } from "@/lib/person-payment-preview";

describe("previewPersonPayment", () => {
  it("marks a payment below what is owed this period as partial", () => {
    expect(previewPersonPayment(200000n, 800000n, 100000n)).toEqual({ appliedToPeriodMinor: 100000n, missingMinor: 100000n, advancedMinor: 0n, creditMinor: 0n });
  });
  it("marks an exact payment as fully applied with nothing left over", () => {
    expect(previewPersonPayment(200000n, 200000n, 200000n)).toEqual({ appliedToPeriodMinor: 200000n, missingMinor: 0n, advancedMinor: 0n, creditMinor: 0n });
  });
  it("advances future obligations with the excess instead of creating credit while more is owed overall", () => {
    // e.g. a shared MSI: this period needs 1,000 but 7,000 is still owed across future installments
    expect(previewPersonPayment(100000n, 700000n, 150000n)).toEqual({ appliedToPeriodMinor: 100000n, missingMinor: 0n, advancedMinor: 50000n, creditMinor: 0n });
  });
  it("only sends the excess to saldo a favor once every future obligation is also covered", () => {
    expect(previewPersonPayment(100000n, 100000n, 150000n)).toEqual({ appliedToPeriodMinor: 100000n, missingMinor: 0n, advancedMinor: 0n, creditMinor: 50000n });
  });
  it("splits an overpayment between advancing the rest of the debt and real credit", () => {
    expect(previewPersonPayment(100000n, 300000n, 500000n)).toEqual({ appliedToPeriodMinor: 100000n, missingMinor: 0n, advancedMinor: 200000n, creditMinor: 200000n });
  });
  it("treats nothing owed at all as a full credit", () => {
    expect(previewPersonPayment(0n, 0n, 50000n)).toEqual({ appliedToPeriodMinor: 0n, missingMinor: 0n, advancedMinor: 0n, creditMinor: 50000n });
  });
});

describe("previewCreditApplication", () => {
  it("applies the full credit when it fits inside the outstanding debt", () => {
    expect(previewCreditApplication(50000n, 150000n)).toEqual({ appliedMinor: 50000n, remainingCreditMinor: 0n });
  });
  it("caps the applied amount at what is actually owed and keeps the rest as credit", () => {
    expect(previewCreditApplication(150000n, 50000n)).toEqual({ appliedMinor: 50000n, remainingCreditMinor: 100000n });
  });
});
