import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "@/app/app";
import { AppProviders } from "@/app/providers";
import "@/styles.css";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("No se encontró el contenedor raíz de Nexo.");

createRoot(rootElement).render(
  <StrictMode>
    <AppProviders>
      <App />
    </AppProviders>
  </StrictMode>,
);
