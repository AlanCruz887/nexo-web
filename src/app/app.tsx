import { RouterProvider } from "react-router-dom";

import { router } from "@/app/router";
import { isSupabaseConfigured } from "@/lib/env";

export function App() {
  if (!isSupabaseConfigured) {
    return (
      <main className="grid min-h-screen place-items-center px-5">
        <div className="max-w-lg rounded-2xl border border-warning/30 bg-surface p-6 shadow-card">
          <p className="text-sm font-semibold uppercase tracking-widest text-warning">Configuración requerida</p>
          <h1 className="mt-2 text-2xl font-semibold tracking-tight">Conecta Nexo con Supabase</h1>
          <p className="mt-3 text-sm leading-relaxed text-muted-foreground">
            Copia <code>.env.example</code> a <code>.env</code> y agrega la URL y la publishable key de tu proyecto. Nunca uses una secret key ni service role en el navegador.
          </p>
        </div>
      </main>
    );
  }
  return <RouterProvider router={router} />;
}
