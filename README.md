# Nexo

Nexo es una aplicación financiera personal construida por fases. La Fase 5A permite registrar personas, compras compartidas, cuentas por cobrar y pagos recibidos.

## Estado

**Fase 5A completada — Personas, compras compartidas y dinero por cobrar.**

El cierre de estados avanza desde el corte vencido más antiguo y mantiene el ciclo actual abierto hasta su fecha efectiva de corte.

Los pagos sin deuda cerrada pendiente se muestran como anticipos asociados al ciclo abierto y se aplican al statement únicamente cuando este se cierra, sin duplicar el movimiento financiero.

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
- tarjetas en MXN, USD o EUR con límite, corte, fecha límite derivada y themes desacoplados;
- baselines `current_bank_balance`, `after_last_statement` y `specific_date`;
- motor único de ciclos semiabiertos con ajuste de días 29–31;
- saldo utilizado, disponible, pago actual y acumulado del ciclo como métricas independientes;
- cierre manual e idempotente de statements, historial y restauración de tarjetas.
- compras personales de tarjeta, método de pago informativo y asignación central de ciclo;
- pagos atómicos cuenta↔tarjeta, asignados a statements pendientes sin crear gasto;
- reembolsos parciales, movimientos globales unificados y correcciones auditables.
- compras nuevas a MSI con principal único, mensualidad exacta, calendario por corte, progreso por statement pagado y reversión dedicada.
- importación de MSI personales ya iniciados, con cuotas pagadas antes de Nexo, mensualidad bancaria real y control explícito de inclusión en saldo inicial.
- personas activas/archivadas, saldos por moneda y detalle de actividad;
- compras de cuenta o tarjeta para mí, otra persona o compartidas entre varias personas;
- receivables nominales inmutables, pagos parciales FIFO y reversión auditable;
- cobros que aumentan la cuenta y reducen el receivable sin crear ingreso ni gasto.

Diseño futuro, no implementado:

- MSI de terceros o compartidos;
- MSI de terceros o compartidos, estado de cobro compartible y sobrepagos de personas;
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
- `/cards` y `/cards/:id`
- `/tarjetas` y `/tarjetas/:id`
- `/personas` y `/personas/:id`
- `/people` y `/people/:id` (alias compatibles)
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
- tablas, proyecciones y RPC para tarjetas, baselines, ciclos y statements.
- metadatos de operaciones, asignaciones de pago a statements, actividad global `security_invoker` y RPC de compras/pagos/reembolsos/reversiones.
- `contacts`, `receivables`, `purchase_allocations` y `receivable_entries`, con vistas `security_invoker` y RPC atómicos para compras distribuidas y pagos de personas.
- `installment_plans`, `installments`, revisiones de metadata y proyecciones MSI `security_invoker`, operadas exclusivamente por RPC idempotentes.

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
- [PRODUCT_LANGUAGE.md](./PRODUCT_LANGUAGE.md) — diccionario y reglas para el lenguaje visible de Nexo.

No se implementaron Personas, receivables, MSI de terceros/compartidos ni compras compartidas.
