import { ArrowRight, CircleHelp, Smartphone } from "lucide-react";
import { useState } from "react";

import { Modal } from "@/components/responsive-dialog";
import { ConfirmDialog } from "@/components/sheet";
import { EmptyState, Skeleton } from "@/components/feedback";
import { useToast } from "@/components/toast";
import { Button } from "@/components/ui/button";
import { CreateShortcutTokenDialog } from "@/features/settings/create-shortcut-token-dialog";
import { useRevokeShortcutToken, useShortcutTokens } from "@/hooks/use-shortcut-tokens";
import { formatAuditTimestamp, formatRelativeTime } from "@/lib/dates";
import { reportError } from "@/lib/errors";
import type { ShortcutTokenSummary } from "@/types/database";

type TokenStatus = "active" | "expired" | "revoked";

function getTokenStatus(token: ShortcutTokenSummary): TokenStatus {
  if (token.revoked_at) return "revoked";
  if (token.expires_at && new Date(token.expires_at).getTime() <= Date.now()) return "expired";
  return "active";
}

const statusLabel: Record<TokenStatus, string> = { active: "Activo", expired: "Expirado", revoked: "Revocado" };
const statusStyle: Record<TokenStatus, string> = {
  active: "bg-success/10 text-success",
  expired: "bg-danger/10 text-danger",
  revoked: "bg-surface-secondary text-muted-foreground",
};

const setupSteps = ["Importe", "Cuenta o tarjeta", "Categoría", "Concepto", "Registrar"];

export function ShortcutTokensSection() {
  const tokens = useShortcutTokens();
  const revoke = useRevokeShortcutToken();
  const toast = useToast();
  const [createOpen, setCreateOpen] = useState(false);
  const [howToOpen, setHowToOpen] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<ShortcutTokenSummary>();

  async function handleRevoke() {
    if (!revokeTarget) return;
    try {
      await revoke.mutateAsync(revokeTarget.id);
      toast.success("Acceso revocado.");
      setRevokeTarget(undefined);
    } catch (error) {
      reportError("shortcut-tokens:revoke", error);
      toast.error("No pudimos revocar este acceso.");
    }
  }

  return (
    <section className="grid gap-6 py-8 md:grid-cols-[220px_1fr]">
      <div>
        <h2 className="font-semibold">Integraciones</h2>
        <p className="mt-1 text-sm text-muted-foreground">Conecta Nexo con otras apps de tu iPhone.</p>
      </div>

      <div className="space-y-6">
        <div>
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h3 className="font-medium">Atajos de iPhone</h3>
              <p className="mt-1 text-sm text-muted-foreground">Registra compras desde Atajos sin abrir Nexo.</p>
            </div>
            <Button onClick={() => setCreateOpen(true)} type="button">Crear acceso</Button>
          </div>

          <div className="mt-5">
            {tokens.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" delay={80} />
              </div>
            ) : tokens.isError ? (
              <p className="text-sm text-danger" role="alert">No pudimos cargar tus accesos.</p>
            ) : tokens.data && tokens.data.length > 0 ? (
              <ul className="divide-y divide-border/60 overflow-hidden rounded-2xl border border-border">
                {tokens.data.map((token) => {
                  const status = getTokenStatus(token);
                  return (
                    <li className="flex flex-wrap items-center justify-between gap-3 p-4" key={token.id}>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <Smartphone aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
                          <p className="truncate font-medium">{token.name}</p>
                          <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${statusStyle[status]}`}>{statusLabel[status]}</span>
                        </div>
                        <p className="mt-1 text-xs text-muted-foreground">
                          Creado el {formatAuditTimestamp(token.created_at, "d 'de' MMM, yyyy")} · {token.last_used_at ? `Último uso: ${formatRelativeTime(token.last_used_at)}` : "Todavía no se ha usado"}
                        </p>
                      </div>
                      {status === "active" ? (
                        <Button onClick={() => setRevokeTarget(token)} size="sm" type="button" variant="secondary">Revocar acceso</Button>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            ) : (
              <EmptyState
                action={<Button onClick={() => setCreateOpen(true)} type="button">Crear acceso</Button>}
                description="Conecta un iPhone para registrar compras desde Atajos, sin abrir Nexo."
                title="No tienes ningún iPhone conectado todavía."
              />
            )}
          </div>
        </div>

        <div className="rounded-2xl border border-border/70 bg-surface-secondary/40 p-5">
          <h4 className="font-medium">¿Qué puedes hacer?</h4>
          <p className="mt-1 text-sm text-muted-foreground">Registra una compra desde Atajos de iPhone sin abrir Nexo.</p>
          <ol className="mt-4 flex flex-wrap items-center gap-2 text-sm font-medium text-foreground">
            {setupSteps.map((step, index) => (
              <li className="flex items-center gap-2" key={step}>
                <span className="rounded-full border border-border bg-surface px-3 py-1">{step}</span>
                {index < setupSteps.length - 1 ? <ArrowRight aria-hidden="true" className="size-3.5 text-muted-foreground" /> : null}
              </li>
            ))}
          </ol>
          <Button className="mt-4" onClick={() => setHowToOpen(true)} size="sm" type="button" variant="ghost">
            <CircleHelp className="size-4" /> Ver cómo configurar
          </Button>
        </div>
      </div>

      <CreateShortcutTokenDialog onOpenChange={setCreateOpen} open={createOpen} />

      <ConfirmDialog
        confirmLabel="Revocar acceso"
        description="Este iPhone dejará de poder registrar compras en Nexo. Las compras que ya registraste no se eliminarán."
        isPending={revoke.isPending}
        onConfirm={() => void handleRevoke()}
        onOpenChange={(next) => { if (!next) setRevokeTarget(undefined); }}
        open={Boolean(revokeTarget)}
        title={`¿Revocar "${revokeTarget?.name ?? ""}"?`}
        tone="danger"
      />

      <Modal
        description="Necesitarás el acceso que generes aquí, la dirección del servicio de Nexo y el propio Atajo de iOS."
        onOpenChange={setHowToOpen}
        open={howToOpen}
        size="small"
        title="Configurar Atajo"
      >
        <div className="space-y-3 text-sm leading-relaxed text-muted-foreground">
          <p>Todavía estamos preparando la conexión con Atajos de iPhone. Cuando esté lista, aquí encontrarás:</p>
          <ul className="list-disc space-y-1 pl-5">
            <li>El acceso que crees en esta sección.</li>
            <li>La dirección del servicio de Nexo para tu Atajo.</li>
            <li>El Atajo listo para instalar en tu iPhone.</li>
          </ul>
        </div>
        <div className="mt-6 flex justify-end">
          <Button onClick={() => setHowToOpen(false)} type="button" variant="secondary">Entendido</Button>
        </div>
      </Modal>
    </section>
  );
}
