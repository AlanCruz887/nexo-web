import { useQuery } from "@tanstack/react-query";

import { currencyService } from "@/services/currency-service";

export function useCurrencies() {
  return useQuery({
    queryKey: ["currencies"],
    queryFn: currencyService.list,
    staleTime: Number.POSITIVE_INFINITY,
  });
}
