import path from "node:path";
import { fileURLToPath } from "node:url";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import { defineConfig } from "vitest/config";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      injectRegister: false,
      registerType: "prompt",
      includeAssets: [
        "icons/favicon.svg",
        "icons/apple-touch-icon.png",
        "icons/nexo-icon-192.png",
        "icons/nexo-icon-512.png",
        "icons/nexo-maskable-512.png",
      ],
      manifest: {
        name: "Nexo",
        short_name: "Nexo",
        description: "Claridad para tu vida financiera.",
        lang: "es-MX",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "portrait-primary",
        theme_color: "#f7f9fc",
        background_color: "#f7f9fc",
        icons: [
          { src: "/icons/nexo-icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icons/nexo-icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "/icons/nexo-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: {
        cleanupOutdatedCaches: true,
        clientsClaim: false,
        skipWaiting: false,
        navigateFallback: "index.html",
        navigateFallbackDenylist: [/^\/(?:auth|rest|storage|functions|realtime)\//],
        globPatterns: ["**/*.{js,css,html,woff2}"],
      },
      devOptions: { enabled: false },
    }),
  ],
  resolve: {
    alias: {
      "@": path.resolve(currentDirectory, "src"),
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    css: true,
  },
});
