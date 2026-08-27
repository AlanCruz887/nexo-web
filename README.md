# Nexo

Nexo es una aplicación financiera personal construida por fases. La Fase 1 entrega únicamente el fundamento técnico: frontend, autenticación, perfil base, moneda, privacidad y seguridad inicial. Todavía no existen cuentas, tarjetas, movimientos, personas, MSI ni reportes.

## Estado

**Fase 1 completada — Fundamento técnico, autenticación y perfil base.**

Implementado:

- React 19, TypeScript 6, Vite 8 y Tailwind CSS 4;
- base compatible con shadcn/ui y tokens light/dark;
- TanStack Query, React Hook Form y Zod;
- Motion con soporte para `prefers-reduced-motion`;
- Supabase Auth: registro, login, logout y recuperación de contraseña;
- rutas protegidas y onboarding fundamental;
- `profiles` 1:1 con `auth.users` y catálogo `currencies`;
- RLS y grants mínimos explícitos;
- shell responsive, configuración y privacidad `hide_money`;
- frontera monetaria exacta PostgreSQL `bigint` ↔ API `string` ↔ TypeScript `bigint`;
- pruebas frontend y pruebas RLS contra PostgreSQL local efímero.

Diseño futuro, no implementado:

- cuentas, tarjetas y movimientos;
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

Rutas de la Fase 1:

- `/registro`
- `/login`
- `/recuperar-contrasena`
- `/actualizar-contrasena`
- `/onboarding`
- `/inicio`
- `/configuracion`

## Base de datos

La única migración productiva de esta fase está en `supabase/migrations/` y crea exclusivamente:

- `public.currencies` con MXN, USD y EUR;
- `public.profiles` relacionado 1:1 con `auth.users`;
- funciones privadas para creación de perfil y `updated_at`;
- RLS, políticas y grants mínimos.

Para aplicar el stack completo cuando Docker esté disponible:

```bash
npm exec supabase start
npm exec supabase db reset
```

La prueba local incluida no necesita Docker. Crea PostgreSQL en un directorio temporal, reconstruye todas las migraciones y valida el aislamiento de dos perfiles:

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

No debe comenzar la Fase 2 sin autorización explícita.
