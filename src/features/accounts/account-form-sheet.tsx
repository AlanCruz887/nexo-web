import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";

import { FormField } from "@/components/form-field";
import { ResponsiveDialog } from "@/components/responsive-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useToast } from "@/components/toast";
import { useCreateAccount, useUpdateAccount } from "@/hooks/use-accounts";
import { toUserMessage } from "@/lib/errors";
import { minorToDisplay } from "@/lib/money";
import { accountFormSchema, type AccountFormInput } from "@/schemas/account";
import type { AccountBalance, CurrencyCode } from "@/types/database";
import { accountTypeOptions } from "@/features/accounts/account-utils";

export function AccountFormSheet({
  account,
  baseCurrency,
  onOpenChange,
  open,
}: {
  account?: AccountBalance;
  baseCurrency: CurrencyCode;
  onOpenChange: (open: boolean) => void;
  open: boolean;
}) {
  const createAccount = useCreateAccount();
  const updateAccount = useUpdateAccount(account?.id ?? "missing");
  const toast = useToast();
  const form = useForm<AccountFormInput>({
    resolver: zodResolver(accountFormSchema),
    defaultValues: {
      name: "",
      type: "checking",
      currency: baseCurrency,
      opening_balance: "0.00",
      institution: "",
      last4: "",
    },
  });

  useEffect(() => {
    form.reset(account ? {
      name: account.name,
      type: account.type,
      currency: account.currency,
      opening_balance: minorToDisplay(BigInt(account.opening_balance_minor)),
      institution: account.institution ?? "",
      last4: account.last4 ?? "",
    } : {
      name: "",
      type: "checking",
      currency: baseCurrency,
      opening_balance: "0.00",
      institution: "",
      last4: "",
    });
  }, [account, baseCurrency, form, open]);

  const mutation = account ? updateAccount : createAccount;

  async function handleSubmit(input: AccountFormInput) {
    try {
      if (account) {
        await updateAccount.mutateAsync({
          name: input.name,
          type: input.type,
          institution: input.institution,
          last4: input.last4,
        });
        toast.success("Cuenta actualizada");
      } else {
        await createAccount.mutateAsync(input);
        toast.success("Cuenta agregada");
      }
      onOpenChange(false);
    } catch (error) {
      form.setError("root", { message: toUserMessage(error) });
    }
  }

  return (
    <ResponsiveDialog
      description={account ? "Actualiza los datos descriptivos sin alterar su historial." : "Agrega el punto de partida de tu dinero disponible."}
      footer={<><Button onClick={() => onOpenChange(false)} type="button" variant="ghost">Cancelar</Button><Button disabled={mutation.isPending} form="account-form" type="submit">{mutation.isPending ? "Guardando…" : account ? "Guardar cambios" : "Agregar cuenta"}</Button></>}
      onOpenChange={onOpenChange}
      open={open}
      size="medium"
      title={account ? "Editar cuenta" : "Nueva cuenta"}
    >
      <form id="account-form" onSubmit={(event) => void form.handleSubmit(handleSubmit)(event)}>
        <div className="grid gap-6 sm:grid-cols-2">
          <div className="sm:col-span-2">
          <FormField error={form.formState.errors.name?.message} id="account-name" label="Nombre">
            <Input autoFocus id="account-name" placeholder="Santander" {...form.register("name")} />
          </FormField>
          </div>
            <FormField error={form.formState.errors.type?.message} id="account-type" label="Tipo">
              <Select id="account-type" {...form.register("type")}>
                {accountTypeOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </Select>
            </FormField>
            {!account ? (
              <FormField error={form.formState.errors.currency?.message} id="account-currency" label="Moneda">
                <Select id="account-currency" {...form.register("currency")}>
                  <option value="MXN">MXN</option><option value="USD">USD</option><option value="EUR">EUR</option>
                </Select>
              </FormField>
            ) : null}
          {!account ? (
            <div className="sm:col-span-2 rounded-2xl bg-surface-secondary p-5"><FormField error={form.formState.errors.opening_balance?.message} hint="El saldo con el que esta cuenta entra a Nexo." id="opening-balance" label="Saldo inicial">
              <Input className="h-16 border-0 bg-transparent px-0 text-3xl font-semibold tabular-nums shadow-none focus-visible:ring-0" id="opening-balance" inputMode="decimal" placeholder="$ 0.00" {...form.register("opening_balance")} />
            </FormField>
            </div>
          ) : null}
          <FormField error={form.formState.errors.institution?.message} id="institution" label="Institución (opcional)">
            <Input id="institution" placeholder="Banco o institución" {...form.register("institution")} />
          </FormField>
          <FormField error={form.formState.errors.last4?.message} hint="Solo se guardan cuatro dígitos para reconocerla." id="last4" label="Últimos 4 dígitos (opcional)">
            <Input id="last4" inputMode="numeric" maxLength={4} placeholder="4201" {...form.register("last4")} />
          </FormField>
          {form.formState.errors.root ? <p className="text-sm text-danger sm:col-span-2" role="alert">{form.formState.errors.root.message}</p> : null}
        </div>
      </form>
    </ResponsiveDialog>
  );
}
