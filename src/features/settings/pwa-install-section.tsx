import { CheckCircle2, Download, Share2, Smartphone } from "lucide-react";
import { useState } from "react";

import { usePwa } from "@/app/pwa-provider";
import { Button } from "@/components/ui/button";

export function PwaInstallSection() {
  const { canInstall, install, isIos, isStandalone } = usePwa();
  const [dismissed, setDismissed] = useState(false);

  async function handleInstall() {
    const outcome = await install();
    setDismissed(outcome === "dismissed");
  }

  return (
    <section className="grid gap-6 py-8 md:grid-cols-[220px_1fr]">
      <div><h2 className="font-semibold">Aplicación</h2><p className="mt-1 text-sm text-muted-foreground">Instala Nexo en este dispositivo.</p></div>
      <div className="rounded-2xl border border-border bg-surface-secondary/55 p-5">
        {isStandalone ? (
          <div className="flex items-start gap-3"><CheckCircle2 className="mt-0.5 size-5 shrink-0 text-success" /><div><p className="text-sm font-semibold">Nexo está instalada</p><p className="mt-1 text-sm text-muted-foreground">Se abre como una aplicación independiente en este dispositivo.</p></div></div>
        ) : canInstall ? (
          <div className="flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-3"><Download className="mt-0.5 size-5 shrink-0 text-primary" /><div><p className="text-sm font-semibold">Instalar Nexo</p><p className="mt-1 text-sm text-muted-foreground">Añádela a tu dispositivo para abrirla sin la interfaz del navegador.</p>{dismissed ? <p className="mt-2 text-xs text-muted-foreground" role="status">Puedes volver a intentarlo cuando quieras.</p> : null}</div></div><Button onClick={() => void handleInstall()} type="button">Instalar Nexo</Button></div>
        ) : isIos ? (
          <div className="flex items-start gap-3"><Share2 className="mt-0.5 size-5 shrink-0 text-primary" /><div><p className="text-sm font-semibold">Instalar en iPhone o iPad</p><p className="mt-1 text-sm leading-relaxed text-muted-foreground">Abre Nexo en Safari, toca <strong className="font-medium text-foreground">Compartir</strong> y elige <strong className="font-medium text-foreground">Añadir a pantalla de inicio</strong>.</p></div></div>
        ) : (
          <div className="flex items-start gap-3"><Smartphone className="mt-0.5 size-5 shrink-0 text-primary" /><div><p className="text-sm font-semibold">Disponible como aplicación</p><p className="mt-1 text-sm text-muted-foreground">Usa la opción “Instalar aplicación” del menú de Chrome o Edge si el navegador todavía no muestra el botón.</p></div></div>
        )}
      </div>
    </section>
  );
}
