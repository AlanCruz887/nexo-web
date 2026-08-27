import { CheckCircle2, ShieldCheck } from "lucide-react";

import { PageTransition } from "@/components/page-transition";
import { MoneyValue } from "@/components/money-value";
import { Card } from "@/components/ui/card";

export function HomePage() {
  return (
    <PageTransition>
      <div className="flex flex-col gap-6">
        <div>
          <p className="text-sm font-semibold text-primary">Fundamento técnico</p>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight">Tu espacio Nexo está listo</h1>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted-foreground">Esta fase establece identidad, perfil, privacidad y una base segura. Todavía no registra actividad financiera.</p>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <ShieldCheck aria-hidden="true" className="size-5 text-primary" />
            <h2 className="mt-4 font-semibold">Perfil protegido</h2>
            <p className="mt-1 text-sm text-muted-foreground">El acceso está aislado por usuario desde PostgreSQL.</p>
          </Card>
          <Card>
            <CheckCircle2 aria-hidden="true" className="size-5 text-success" />
            <h2 className="mt-4 font-semibold">Privacidad preparada</h2>
            <p className="mt-1 text-sm text-muted-foreground">MoneyValue centraliza formato y ocultamiento.</p>
            <div className="mt-4 rounded-xl bg-muted px-4 py-3">
              <MoneyValue amount="0" currency="MXN" size="lg" />
            </div>
          </Card>
        </div>
      </div>
    </PageTransition>
  );
}
