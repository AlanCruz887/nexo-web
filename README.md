# Nexo

Nexo es una aplicación financiera personal construida por fases. La Fase 2 agrega cuentas, movimientos simples y transferencias sobre el fundamento seguro de identidad, moneda y privacidad de la Fase 1.

## Estado

**Fase 2 completada — Cuentas, movimientos base y transferencias.**

Implementado:

- React 19, TypeScript 6, Vite 8 y Tailwind CSS 4;
- base compatible con shadcn/ui y tokens light/dark;
- TanStack Query, React Hook Form y Zod;
- Motion con soporte para `prefers-reduced-motion`;
- Supabase Auth: registro, login, logout y recuperación de contraseña;
- rutas protegidas y onboarding fundamental;
- `profiles` 1:1 con `auth.users` y catálogo `currencies`;
- RLS, grants mínimos explícitos y validación IANA de zona horaria;
- shell responsive, configuración y privacidad `hide_money`;
- frontera monetaria exacta PostgreSQL `bigint` ↔ API `string` ↔ TypeScript `bigint`;
- pruebas frontend y pruebas RLS contra PostgreSQL local efímero.
- cuentas en MXN, USD o EUR, con archivado, restauración e historial preservado;
- saldos reconstruidos desde eventos y entradas inmutables;
- ingresos, gastos personales y ajustes simples;
- transferencias atómicas, de dos entradas y sin efecto en ingreso/gasto;
- RPC financieros idempotentes y reversión auditable;
- timeline de movimientos, filtros, drawers/bottom sheets y UI premium responsive.

Diseño futuro, no implementado:

- tarjetas de crédito y statements;
- statements, baseline y MSI;
- personas y receivables;
- presupuestos, planificación y reportes;
- conciliación, importación y exportación.

## Requisitos

- Node.js 22 o posterior;
- npm 11 o posterior;
- PostgreSQL 17 con `initdb`, `pg_ctl`, `createdb` y `psql` para `npm run test:db`;
- Docker únicamente si se desea ejecutar el stack completo con Supabase CLI.

## Configuración

```bash
npm install
cp .env.example .env
```

Completa en `.env`:

```text
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

El navegador solo recibe la URL y la publishable key. Nunca agregues `service_role`, secret keys o credenciales de base de datos a variables `VITE_*`.

## Desarrollo

```bash
npm run dev
```

Rutas implementadas:

- `/registro`
- `/login`
- `/recuperar-contrasena`
- `/actualizar-contrasena`
- `/onboarding`
- `/inicio`
- `/cuentas`
- `/cuentas/:id`
- `/movimientos`
- `/accounts` y `/accounts/:id` (alias compatibles)
- `/transactions` (alias compatible)
- `/configuracion`

## Base de datos

Las migraciones productivas están en `supabase/migrations/` y crean:

- `public.currencies` con MXN, USD y EUR;
- `public.profiles` relacionado 1:1 con `auth.users`;
- funciones privadas para creación de perfil y `updated_at`;
- RLS, políticas y grants mínimos.
- `public.accounts` y catálogo mínimo `public.categories`;
- `public.financial_events` y `public.account_entries` inmutables;
- `public.financial_commands`, `public.audit_events` y notas versionadas;
- vistas `security_invoker` para saldos y actividad;
- RPC tipados para cuentas, restauración, movimientos, transferencias, edición y reversión.

Para aplicar el stack completo cuando Docker esté disponible:

```bash
npm exec supabase start
npm exec supabase db reset
```

La prueba local incluida no necesita Docker. Crea PostgreSQL en un directorio temporal, reconstruye todas las migraciones y valida aislamiento A/B, saldos, archivado/restauración, transferencias, reversión, auditoría e idempotencia:

```bash
npm run test:db
```

## Verificación

```bash
npm run typecheck
npm run lint
npm run test
npm run test:db
npm run build
```

## Dinero y JSON

- PostgreSQL: `bigint` en unidades menores.
- Data API/JSON: cadena decimal entera, por ejemplo `"2400000"`.
- TypeScript de dominio: `bigint`, por ejemplo `2400000n`.
- UI: cadena formateada solo al presentar.

`bigint` nunca se envía directamente a `JSON.stringify`. Usa `serializeMoneyMinor` y `deserializeMoneyMinor` en la frontera API.

## Documentación de contrato

- [PRODUCT_SPEC.md](./PRODUCT_SPEC.md)
- [DOMAIN_RULES.md](./DOMAIN_RULES.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [PLAN.md](./PLAN.md)

No debe comenzar la Fase 3 sin autorización explícita.
