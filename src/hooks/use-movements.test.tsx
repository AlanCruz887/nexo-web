import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, renderHook, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { transactionQueryKey, useMovement, useUpdateMovement } from "@/hooks/use-movements";
import { movementService } from "@/services/movement-service";
import type { Category, FinancialActivity } from "@/types/database";

vi.mock("@/services/movement-service", () => ({
  movementService: {
    get: vi.fn(),
    update: vi.fn(),
  },
}));

const originalEventId = "11111111-1111-1111-1111-111111111111";
const updatedEventId = "22222222-2222-2222-2222-222222222222";
const original: FinancialActivity = {
  event_id: originalEventId,
  user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  kind: "expense",
  amount_minor: "150000",
  personal_amount_minor: "150000",
  description: "Supermercado",
  category_id: "food",
  category_name: "Comida",
  occurred_on: "2026-08-20",
  notes: null,
  created_at: "2026-08-20T18:00:00Z",
  account_id: "33333333-3333-3333-3333-333333333333",
  source_type: "account",
  card_id: null,
  source_name: "Santander",
  source_detail: "Santander",
  currency: "MXN",
  signed_amount_minor: "-150000",
  payment_method: null,
  statement_date: null,
  related_event_id: null,
  source_is_active: true,
  source_account_id: null,
  source_account_name: null,
  destination_account_id: null,
};

function createWrapper(queryClient: QueryClient) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
  };
}

function DetailProbe({ eventId }: { eventId: string | undefined }) {
  const detail = useMovement(eventId);
  if (!eventId) return null;
  if (detail.isPending) return <p>Cargando movimiento</p>;
  return <p>{detail.data?.[0]?.description ?? "Movimiento no encontrado"}</p>;
}

describe("movement edit cache handoff", () => {
  beforeEach(() => vi.clearAllMocks());

  it("moves detail to the replacement event and keeps it resolvable after amount and metadata edits", async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const updatedFromServer = [{
      ...original,
      event_id: updatedEventId,
      amount_minor: "120000",
      personal_amount_minor: "120000",
      signed_amount_minor: "-120000",
      description: "Supermercado semanal",
      category_id: "transport",
      category_name: "Transporte",
      occurred_on: "2026-08-27",
      notes: "Editado",
    }];
    queryClient.setQueryData(transactionQueryKey(originalEventId), [original]);
    queryClient.setQueryData<Category[]>(["categories"], [{ id: "transport", name: "Transporte", kind: "expense", icon: "car", sort_order: 2, created_at: "2026-08-01T00:00:00Z" }]);
    vi.mocked(movementService.update).mockResolvedValue(updatedEventId);
    vi.mocked(movementService.get).mockResolvedValue(updatedFromServer);

    const wrapper = createWrapper(queryClient);
    const mutation = renderHook(() => useUpdateMovement(originalEventId), { wrapper });
    const input = {
      amount: "1200.00",
      account_id: original.account_id as string,
      kind: "expense" as const,
      category_id: "transport",
      occurred_on: "2026-08-27",
      description: "Supermercado semanal",
      notes: "Editado",
      purchase_scope: "self" as const,
      personal_amount: "1200.00",
      allocations: [],
    };

    let replacementId: string | undefined;
    await act(async () => {
      replacementId = await mutation.result.current.mutateAsync(input);
    });

    expect(replacementId).toBe(updatedEventId);
    expect(queryClient.getQueryData<FinancialActivity[]>(transactionQueryKey(updatedEventId))?.[0]).toMatchObject({
      event_id: updatedEventId,
      amount_minor: "120000",
      signed_amount_minor: "-120000",
      description: "Supermercado semanal",
      category_id: "transport",
      category_name: "Transporte",
      occurred_on: "2026-08-27",
      notes: "Editado",
    });

    const detail = renderHook(() => useMovement(replacementId), { wrapper });
    await waitFor(() => expect(detail.result.current.data?.[0]?.event_id).toBe(updatedEventId));
    render(<DetailProbe eventId={replacementId} />, { wrapper });
    expect(screen.getByText("Supermercado semanal")).toBeInTheDocument();
    expect(screen.queryByText("Movimiento no encontrado")).not.toBeInTheDocument();
    expect(movementService.get).toHaveBeenCalledWith(updatedEventId);
    expect(movementService.get).not.toHaveBeenCalledWith(originalEventId);
  });

  it("does not request or render a missing detail after selection is cleared", async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const wrapper = createWrapper(queryClient);
    const detail = renderHook(() => useMovement(undefined), { wrapper });
    render(<DetailProbe eventId={undefined} />, { wrapper });

    expect(detail.result.current.fetchStatus).toBe("idle");
    expect(detail.result.current.data).toBeUndefined();
    expect(screen.queryByText("Movimiento no encontrado")).not.toBeInTheDocument();
    expect(movementService.get).not.toHaveBeenCalled();
  });
});
