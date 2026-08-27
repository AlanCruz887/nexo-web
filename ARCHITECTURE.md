# Nexo — Arquitectura propuesta

## 1. Objetivo arquitectónico

Construir Nexo por fases sin cambiar el significado financiero de los datos al agregar tarjetas, MSI, terceros, conciliación, planificación y reportes. La arquitectura separa tres capas:

1. **Comandos:** intención del usuario, por ejemplo registrar una compra compartida.
2. **Hechos financieros:** evento inmutable y sus efectos atómicos.
3. **Proyecciones:** saldos, statements, presupuestos, patrimonio y reportes derivados de esos hechos.

La interfaz nunca escribe saldos calculados directamente. Envía comandos validados; PostgreSQL ejecuta la operación completa y las consultas reconstruyen o proyectan el resultado.

Esta separación es interna. La UI y los textos del producto hablan exclusivamente en términos de **Compra, Pago, Transferencia, MSI, Cobro, Reembolso y Reversión**. No exponen asientos, débitos/créditos ni complejidad contable al usuario.

## 2. Stack y límites

### Cliente

- React + TypeScript + Vite.
- Tailwind CSS y shadcn/ui para tokens y componentes.
- TanStack Query para estado remoto, caché e invalidación.
- React Hook Form + Zod para captura y validación de comandos.
- Motion/Framer Motion para transiciones con `prefers-reduced-motion`.
- Recharts para visualizaciones explicables.
- date-fns para presentación y aritmética de fechas, siempre con zona/fecha financiera explícita.

### Backend

- Supabase Auth para identidad.
- PostgreSQL como única fuente de verdad financiera.
- RLS para aislamiento por propietario.
- Funciones/RPC PostgreSQL para comandos compuestos y atómicos.
- Supabase Storage privado para recibos y artefactos exportados temporales.
- Edge Functions solo para trabajo que requiera secretos, composición externa o procesamiento asíncrono; no para sustituir transacciones que pertenecen a PostgreSQL.

### Esquemas lógicos previstos

- `public`: recursos seguros expuestos al cliente, con RLS.
- `private`: helpers, implementación privilegiada y tablas internas no expuestas.
- `audit`: eventos de auditoría con acceso de solo lectura controlado.
- `staging`: lotes y filas de importación aislados del libro productivo.

Los nombres son una propuesta para las migraciones futuras; esta fase no crea esquemas ni tablas.

## 3. Modelo de dominio

### 3.1 Identidad y configuración

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `profiles` | Preferencias del propietario | `user_id`, locale, timezone, `base_currency` |
| `user_preferences` | UI y privacidad | theme, hide_amounts, motion preference |
| `financial_commands` | Evitar comandos duplicados | `user_id`, `idempotency_key`, command_type, payload canónico, result_id |

### 3.2 Catálogo financiero

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `currencies` | Escala monetaria conocida | ISO code, minor_unit_scale |
| `accounts` | Activos líquidos/inversión | `user_id`, type, `currency`, `opening_balance_minor`, `is_active` |
| `credit_cards` | Línea/pasivo de crédito | owner, issuer, product, `currency`, limit, statement_day, payment_days, archived_at |
| `card_baselines` | Punto de partida de deuda | card, policy enum, effective_date, amount_minor, evidence |
| `people` | Terceros de cuentas por cobrar | owner, display_name, contact data, archived_at |
| `categories` | Catálogo mínimo de clasificación | id estable, kind, nombre, orden; categorías personalizadas son futuras |
| `merchants` | Normalización opcional | owner, canonical_name |

`accounts` y `credit_cards` no comparten una tabla de “cuentas genéricas”. Pueden implementar una interfaz común de medio financiero en la aplicación, pero mantienen restricciones, ciclos y cálculos distintos.

### 3.3 Núcleo de eventos

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `financial_events` | Cabecera inmutable del hecho | owner, type, transaction_date, optional purchase/posted date, occurred_at, currency, amount_minor, effect_scope, status, source |
| `account_entries` | Efectos exactos implementados para cuentas | event, account, `signed_amount_minor`; inmutable |
| `event_entries` | Evolución conceptual multiledger | event, ledger_kind, account/card/receivable/person-credit reference, signed_amount_minor |
| `expense_allocations` | División personal/terceros | event, allocation_type, person, amount_minor, category |
| `event_links` | Relaciones semánticas | source_event, target_event, relation_type |
| `reversals` | Pareja original-compensación | original_event, reversal_event, reason |

`financial_events` expresa qué sucedió. En Fase 2, `account_entries` materializa únicamente deltas de cuentas; fases posteriores ampliarán el patrón para tarjetas, receivables y saldos a favor sin reinterpretar estas entradas. `expense_allocations` seguirá conservando por separado el gasto personal y las partes de terceros cuando exista el agregado compra.

No se expone al cliente una operación genérica para insertar `event_entries`. Solo RPC tipados pueden crear hechos financieros asentados.

### 3.4 Tarjetas, ciclos y pagos

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `card_cycles` | Ventana calculada de corte | card, cycle_start, effective statement_date, due_date, status |
| `card_statements` | Fuente de verdad del corte cerrado | cycle, statement_balance, payment_to_avoid_interest, minimum_payment, amount_paid, remaining_due, payment_due_date, status |
| `statement_items` | Componentes del statement | statement, event/entry, amount |
| `card_payments` | Comando de pago asentado o histórico | event, source_account, card, amount_minor, transaction_date, effect_scope |
| `card_payment_allocations` | Aplicación del pago | payment, statement, amount |

La membresía a un ciclo usa `[cycle_start, statement_date)`. Para días 29–31 inexistentes, la fecha efectiva es el último día del mes. Un pago puede reducir el pasivo total y asignarse a uno o más statements. Un pago histórico anterior al baseline puede conservar evidencia sin producir entradas de saldo.

### 3.5 MSI

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `installment_plans` | Contrato del plan | purchase_event, card, original_principal_minor, term, installment_amount_minor, reported_paid_before_import_minor, principal_paid_minor, mode, included_in_opening_balance |
| `installments` | Calendario y saldo por cuota | plan, number, due/cycle date, principal_minor, paid_minor, status |
| `installment_allocations` | Parte personal o de persona por cuota | installment, allocation, amount |

Las cuotas pasadas de un MSI histórico existen con estado `paid_before_import`, sin inventar movimientos bancarios. La cuota indicada como actual queda abierta según fecha y las posteriores quedan futuras. El plan conserva tanto el pago real reportado como el principal pagado reconciliado, el principal pendiente y su relación con baseline. Una compra MSI nueva crea desde la compra el efecto de tarjeta por el principal completo; los statements seleccionan solo las cuotas de su ciclo.

### 3.6 Personas y cobros

| Entidad | Responsabilidad | Campos conceptuales clave |
|---|---|---|
| `receivables` | Obligación de una persona | person, source allocation, principal, due context, status |
| `receivable_items` | Vencimientos/cuotas cobrables | receivable, installment, due_date, amount, paid_amount |
| `person_payments` | Cobro recibido | event, person, destination_account, amount |
| `person_payment_allocations` | Aplicación de cobro | payment, receivable_item, amount, order |
| `person_credit_entries` | Origen y aplicación de saldo a favor | person, payment/event, signed_amount_minor, reason |
| `person_statement_snapshots` | Documento reproducible | person, period, due_date, totals, generated_at |

El cobro genera en una sola transacción el abono bancario, la reducción del receivable, sus asignaciones y cualquier excedente como `credit_balance`. El crédito de la persona es un pasivo derivado de `person_credit_entries`; no toca ingresos. Un pago parcial deja el item abierto con su saldo exacto. El snapshot compartible no concede acceso a la aplicación ni revela obligaciones futuras.

### 3.7 Planeación y análisis

| Entidad | Responsabilidad |
|---|---|
| `budgets`, `budget_lines` | Límites por periodo/categoría basados en `personal_amount` |
| `recurrence_rules`, `recurrence_occurrences` | Plantillas y ocurrencias idempotentes |
| `subscriptions` | Metadatos y seguimiento de cargos recurrentes |
| `planned_events` | Hechos proyectados, separados de realizados |
| `valuation_snapshots` | Valuación fechada de inversiones/activos |
| `financial_health_snapshots` | Resultado versionado y explicable de indicadores |

Los reportes ordinarios se consultan desde vistas `security_invoker` o RPC de lectura. Las proyecciones materializadas solo se introducirán cuando la medición demuestre necesidad y siempre serán reconstruibles.

### 3.8 Conciliación, importación, archivos y auditoría

| Entidad | Responsabilidad |
|---|---|
| `reconciliations`, `reconciliation_items` | Comparación fechada, diferencias y resolución explícita |
| `import_batches`, `import_rows`, `import_mappings` | Staging, mapeo, preview, duplicados y confirmación |
| `automation_rules`, `rule_runs` | Reglas deterministas y trazabilidad |
| `attachments` | Metadatos de objetos privados de Storage |
| `export_jobs` | Generación y expiración de exportaciones |
| `audit_events` | Acción, actor, entidad, antes/después permitido, timestamp |

## 4. Relaciones principales

```text
User
 ├─ Accounts ───────────────┐
 ├─ CreditCards ─ CardCycles ─ CardStatements
 │        └─ CardBaselines  │          └─ StatementItems
 ├─ People ─ Receivables ─ ReceivableItems
 │      └─ PersonCreditEntries
 ├─ Categories              │
 └─ FinancialEvents ─ EventEntries
          ├─ ExpenseAllocations ─ Person
          ├─ InstallmentPlan ─ Installments ─ InstallmentAllocations
          ├─ CardPayment ─ CardPaymentAllocations
          ├─ PersonPayment ─ PersonPaymentAllocations
          └─ Reversal/EventLinks
```

Reglas de integridad relacional:

- toda entidad financiera tiene propietario directo o una ruta de propiedad no ambigua;
- las referencias cruzadas deben pertenecer al mismo propietario y moneda compatible;
- una entrada apunta exactamente al subledger que afecta;
- una asignación de tercero requiere persona; una personal no puede tenerla;
- una tarjeta baseline efectivo tiene una sola versión activa por punto de control;
- un evento asentado no cambia de propietario, moneda, importe ni fecha financiera.

## 5. Flujos atómicos previstos (RPC)

Cada RPC de escritura valida `auth.uid()`, ownership, estado, moneda e idempotencia; fija `search_path = ''` y tiene permisos mínimos. La implementación usa unicidad global `(user_id, idempotency_key)` y conserva tipo, payload canónico y resultado. Un replay idéntico devuelve el resultado persistido, cualquier reutilización distinta falla y la transacción PostgreSQL serializa competidores.

| RPC conceptual | Efectos indivisibles |
|---|---|
| `create_account` | cuenta, opening event/entry cuando es distinto de cero, comando y auditoría |
| `update_account` / `archive_account` | proyección descriptiva/estado y auditoría idempotente |
| `create_transaction` | evento de ingreso/gasto/ajuste, entrada firmada y auditoría |
| `create_transfer` | un evento y dos entradas equivalentes en cuentas propias de la misma moneda |
| `update_transaction` | reversión del original, reemplazo y auditoría |
| `reverse_transaction` / `reverse_transfer` | evento compensatorio y entradas opuestas |
| `update_transfer_notes` | anotación inmutable y auditable, sin efecto financiero |
| `record_purchase` | evento, cargo a cuenta/tarjeta, gasto personal, receivables y vínculos |
| `create_installment_purchase` | compra, plan, cuotas, asignaciones y obligación de tarjeta |
| `import_started_installment_plan` | plan histórico, cuotas previas, pendiente y efecto baseline/no-baseline |
| `receive_person_payment` | abono a cuenta, aplicación parcial/total y excedente a saldo a favor |
| `apply_person_credit` | reducción coordinada de saldo a favor y receivable, sin nuevo flujo |
| `record_card_payment` | reducción de cuenta y pasivo, aplicación a statements o evidencia histórica no-impacting |
| `record_refund` | crédito financiero y reversión parcial/total del efecto personal/tercero |
| `reverse_financial_event` | evento compensatorio, vínculos y auditoría |
| `close_card_statement` | ciclo, snapshot, items, total y fecha límite |
| `confirm_import_batch` | filas aprobadas a eventos, vínculo de origen y marca idempotente |
| `archive_account` / `restore_account` | cambia disponibilidad de una cuenta propia, con idempotencia y auditoría; no altera entradas ni saldo |
| `reconcile_balance` | snapshot comparable y resoluciones explícitas, sin ajuste oculto |

Las funciones privilegiadas, si fueran estrictamente necesarias, vivirán fuera de esquemas expuestos, revocarán `EXECUTE` a `PUBLIC`, autorizarán al actor dentro del cuerpo y usarán un `search_path` fijo. Se prefiere `SECURITY INVOKER`; `SECURITY DEFINER` no se utilizará para eludir RLS.

`reverse_financial_event` compensa en la misma transacción todas las entradas, asignaciones, cuotas, saldos a favor y aplicaciones creadas por el evento original; después, todas las proyecciones compartidas reflejan el estado restaurado sin eliminar auditoría.

## 6. Consultas y proyecciones

Las proyecciones son contratos de lectura compartidos por UI, exportaciones y reportes. Ninguna pantalla replica estas fórmulas:

| Métrica | Fuente de verdad única |
|---|---|
| Saldo de cuenta | `sum(account_entries.amount_minor)`; el opening se materializa una sola vez como entrada |
| Saldo utilizado de tarjeta | baseline + entradas de tarjeta impacting: cargos, principal completo de MSI nuevo, remaining principal histórico no incluido, pagos y reembolsos |
| Pago actual | `remaining_due` del último `card_statement` cerrado aplicable, actualizado solo mediante asignaciones de pago/reversión |
| Acumulado del ciclo | items elegibles por `transaction_date` dentro del `card_cycle` abierto; no es pago requerido |
| Gasto personal | Fase 2: suma de `financial_events.personal_amount_minor` para gastos vigentes; cuando existan compras distribuidas, la proyección compartida sumará sus asignaciones personales sin cambiar el contrato |
| Ingreso | suma de `financial_events.amount_minor` para eventos `income` vigentes; transferencias, reembolsos, ajustes y cobros futuros nunca entran aquí |
| Cash flow | entradas y salidas firmadas de `account_entries` por `occurred_on`; se presentan por moneda y la clasificación del evento mantiene transferencias separadas de ingreso/gasto |
| Receivable pendiente | principal de `receivable_items` menos pagos, créditos aplicados, reembolsos y reversiones |
| Cuota actual de persona | `receivable_items` exigibles dentro del periodo consolidado actual, menos aplicaciones; excluye periodos futuros |
| Saldo a favor de persona | suma neta de `person_credit_entries` no aplicada |
| Patrimonio | por moneda: saldos de activos + receivables nominales - pasivos de tarjeta - saldos a favor/otros pasivos |
| Presupuesto consumido | `personal_amount` vigente por categoría y periodo |

Proyecciones implementadas: `account_balances` y `account_activity`, ambas vistas `security_invoker`; esta última excluye eventos revertidos y entrega el importe personal y la clasificación que consumen las métricas de Fase 2. Proyecciones futuras: `card_used_balances`, `card_current_payment`, `card_cycle_accumulated`, `receivable_balances`, `person_current_due`, `person_credit_balances`, `personal_expenses`, `cash_flow`, `budget_consumption`, `net_worth` y `card_comparison`.

Cada proyección devuelve IDs de desglose o cuenta con una consulta complementaria que explica sus componentes. Los totales no son columnas editables. Cualquier caché se invalida por las claves del agregado afectado después de que la RPC confirme.

## 7. Estrategia de fechas y dinero

- Todos los importes persistidos usan `bigint` en unidades menores y moneda ISO 4217; la escala proviene de `currencies`. No existe una segunda estrategia `numeric` para importes de negocio ni se usa `float`.
- Cada cuenta/tarjeta fija una moneda y solo acepta eventos compatibles. El MVP no realiza FX. `base_currency` no permite sumar monedas; los totales se separan por moneda.
- Una futura tasa de cambio será una entidad explícita con par, fecha, fuente y tasa decimal exacta; no cambia los importes originales.
- Para cuotas derivadas se usa `round half up` a la unidad menor en las primeras `n - 1`; la última es `principal - suma(cuotas anteriores)`. `installment_amount` real del banco prevalece cuando exista.
- `transaction_date` gobierna cortes, presupuestos, cash flow e informes del MVP.
- `purchase_date` y `posted_date` son opcionales y preparatorias; nunca se inventan. Usar `posted_date` para corte requerirá fuente bancaria declarada y regla versionada.
- `occurred_at` conserva el instante real y `created_at` el momento de captura.
- La zona horaria del perfil convierte el instante a fecha financiera; no se confía en la zona del navegador para cálculos persistidos.
- Los ciclos usan rangos de fecha semiabiertos.
- Para `statement_day` inexistente, se usa el último día válido del mes. El corte efectivo continúa siendo el límite superior exclusivo y pertenece al ciclo siguiente.

## 8. Índices previstos

Los índices se crean solo después de definir consultas y validar con `EXPLAIN`, pero el modelo reserva las siguientes rutas:

- `(user_id, transaction_date desc, id)` en eventos para timeline y paginación estable;
- `(user_id, type, transaction_date)` para reportes por tipo;
- `(account_id, transaction_date, id)` y `(card_id, transaction_date, id)` en entradas;
- `(card_id, statement_date)` único en ciclos/statements;
- `(card_id, status, cycle_start, statement_date)` para ciclo abierto/cerrado;
- `(person_id, status, due_date)` en items por cobrar;
- `(receivable_id, installment_id)` donde corresponda;
- `(installment_plan_id, installment_number)` único;
- `(user_id, category_id, period_start)` para consumo de presupuesto;
- `(user_id, archived_at)` parciales para selectores activos;
- `(user_id, command_type, idempotency_key)` único para reintentos;
- `(person_id, created_at, id)` en créditos de personas y ruta parcial para saldo no aplicado;
- `(user_id, external_source, external_id)` único/parcial para importaciones;
- `(import_batch_id, row_number)` único y huellas de duplicado indexadas;
- `(entity_type, entity_id, created_at desc)` en auditoría;
- índices sobre todas las claves foráneas utilizadas por RLS o borrado/restricción.

Los índices parciales de estados activos/vencidos evitan inflar rutas comunes. No se indexa cada columna por anticipado.

## 9. Estrategia RLS y seguridad

1. RLS habilitado en toda tabla expuesta y, como defensa adicional, en tablas privadas con datos de usuario.
2. Políticas dirigidas a `authenticated`, combinadas con propiedad: `(select auth.uid()) = user_id` o una relación de ownership validada.
3. `SELECT`, `INSERT`, `UPDATE` y, si existe, `DELETE` tienen políticas separadas. `UPDATE` incluye `USING` y `WITH CHECK`.
4. No se autoriza solo por rol. No se usa `user_metadata` para decisiones de acceso.
5. Las vistas expuestas usan `security_invoker = true`; las demás quedan en esquema no expuesto y sin grants al cliente.
6. Eventos y entradas asentados no tendrán `UPDATE/DELETE` directo para el cliente.
7. Audit logs son de solo lectura para el dueño cuando el producto lo requiera; ningún rol cliente puede insertarlos o modificarlos directamente.
8. Objetos de Storage usan rutas no adivinables vinculadas a `user_id`, bucket privado y políticas para propietario. URLs firmadas expiran.
9. La clave de servicio solo puede existir en backend controlado y nunca en Vite o el bundle web.
10. Pruebas de RLS usan dos usuarios y cubren lectura, escritura, referencias cruzadas, Storage y RPC.

La exposición por Data API y los `GRANT` se revisan por separado de RLS: tener política no concede acceso, y tener acceso no sustituye ownership.

## 10. Auditoría e inmutabilidad

- Triggers internos registran cambios permitidos en catálogos y acciones críticas.
- Las RPC agregan contexto de negocio: comando, actor, razón, correlación e idempotencia.
- Los hechos asentados son append-only.
- La reversión referencia al original y genera entradas compensatorias.
- Los valores sensibles del “antes/después” se minimizan; no se guardan secretos ni blobs de recibos en auditoría.
- Retención y exportación de auditoría se definirán antes de producción.

## 11. PWA, sincronización y privacidad

- El shell y catálogos no sensibles pueden cachearse para rendimiento.
- Los datos financieros persistidos localmente deben minimizarse; no se cachean respuestas sensibles sin una política explícita.
- Las escrituras financieras requieren confirmación del servidor. Una cola offline futura debe mostrar estado pendiente y usar idempotencia; no debe presentar saldos provisionales como confirmados.
- “Ocultar cantidades” se aplica en un componente monetario central y también en tooltips, gráficas, labels accesibles, notificaciones, exports/previews y estados de carga.
- Cerrar sesión limpia cachés de TanStack Query y almacenamiento local sensible.

## 12. Estructura de aplicación prevista

```text
src/
  app/                 # providers, router, query client
  components/          # design system y money/privacy primitives
  features/
    accounts/
    cards/
    transactions/
    people/
    installments/
    planning/
    reports/
    imports/
  domain/              # tipos, schemas Zod y cálculos puros
  infrastructure/      # cliente Supabase, repositorios, adapters
  lib/                 # dinero, fecha, errores, idempotencia
supabase/
  migrations/
  functions/
  tests/
```

Las features dependen de contratos del dominio, no unas de otras a través de componentes. Las reglas financieras críticas se prueban en PostgreSQL y, cuando son cálculos de presentación, también como funciones puras de TypeScript.

## 13. Verificación arquitectónica

Antes de cerrar cada fase:

- pruebas unitarias de dinero, fechas y asignaciones;
- pruebas SQL de restricciones y RPC con rollback ante error;
- pruebas de idempotencia y concurrencia;
- pruebas RLS de aislamiento entre dos usuarios;
- prueba de reconstrucción de saldos fila por fila;
- pruebas de contrato para proyecciones;
- pruebas E2E de los flujos añadidos;
- auditoría de accesibilidad y `prefers-reduced-motion` en UI;
- revisión de consultas e índices con datos representativos.

## 14. Registro de decisiones de dominio

Decisiones cerradas antes de la primera migración:

- cortes 29–31 se limitan al último día válido; el corte efectivo continúa siendo exclusivo;
- `transaction_date` es la fecha financiera del MVP; `purchase_date` y `posted_date` quedan opcionales para importaciones futuras;
- importes en `bigint` de unidades menores, moneda por cuenta/tarjeta y sin FX automático;
- gasto personal MSI reconocido una vez en la compra por `personal_amount`;
- MSI nuevo ocupa línea por el principal pendiente completo y el statement solo exige cuotas del ciclo;
- MSI histórico conserva pago real reportado, principal pagado y remaining principal sin duplicar baseline;
- sobrepago de persona se aplica a vencidos, actual, futuras del mismo plan y después crea `credit_balance`;
- receivables se valúan nominalmente y forman parte del patrimonio por moneda;
- statement cerrado controla pago actual; ciclo abierto solo controla acumulado;
- baseline es entidad financiera con política `current_bank_balance`, `after_last_statement` o `specific_date`;
- eventos históricos previos al baseline pueden ser `historical_non_impacting`;
- eventos complejos se revierten, no se borran;
- RPC financieros usan idempotencia por usuario, tipo de comando y payload.

Riesgos/decisiones que siguen abiertos para fases posteriores y no bloquean el esquema núcleo después de Fase 2:

- tratamiento del saldo a favor de una **tarjeta** y pagos de tarjeta superiores al pasivo;
- reglas específicas de emisores para mover fechas límite por fines de semana o festivos; el valor por defecto queda en días calendario sin ajuste;
- flujo permitido para correcciones posteriores al cierre de statement, conservando siempre reversión/auditoría;
- formatos bancarios prioritarios y cuándo una fuente externa autorizada puede usar `posted_date`;
- proveedor, almacenamiento y política de tasas FX futuras;
- granularidad/retención de auditoría, alcance offline y cifrado de caché local;
- fórmula versionada de salud financiera y objetivos de rendimiento, sin cambiar el uso obligatorio de `personal_amount`.

## 15. Dependencias entre módulos

- Personas, MSI, presupuestos y reportes dependen del núcleo de eventos y asignaciones.
- Statements y baseline dependen de tarjetas y reglas de fecha.
- Pagos de personas dependen de receivables y cuentas.
- Salud financiera y patrimonio dependen de proyecciones verificadas de activos, pasivos, gasto personal y receivables.
- Forecast depende de movimientos reales, reglas recurrentes, MSI, statements y receivables.
- Conciliación e importación dependen de idempotencia, eventos y explicación de saldos.
- Exportación depende de consultas estables y privacidad; no debe definir una segunda lógica de cálculo.

## 16. Estado de implementación después de Fase 2

Implementado:

- estructura React/Vite por aplicación, componentes, features, layouts, hooks, servicios, schemas, tipos y design system;
- providers de Auth, TanStack Query, tema y privacidad;
- cliente Supabase configurado solo con URL y publishable key públicas;
- registro, login, logout, recuperación/actualización de contraseña y persistencia de sesión;
- rutas protegidas con gate de onboarding;
- onboarding de nombre, moneda base y zona horaria;
- shell desktop/mobile y configuración base;
- `MoneyValue`, unidades menores exactas y frontera serializable;
- separación `date`/`timestamptz` en utilidades;
- migración de `currencies` y `profiles`, trigger 1:1, RLS y grants explícitos;
- pruebas frontend y reconstrucción/pruebas RLS sobre PostgreSQL 17 efímero.
- tablas `accounts`, `categories`, `financial_events`, `account_entries`, `financial_commands`, `audit_events` y `financial_event_notes`;
- vistas `account_balances` y `account_activity` con RLS heredada mediante `security_invoker`;
- RPC tipados para crear/editar/archivar/restaurar cuentas, registrar/editar/revertir movimientos y transferir/revertir;
- rutas canónicas de cuentas, detalle y movimientos, con alias `/accounts`, `/accounts/:id` y `/transactions`, queries TanStack, filtros y contexto preseleccionado;
- patrones visuales `PageHeader`, `SectionHeader`, `ActionMenu`, `FilterBar`, `Sheet`, `ConfirmDialog`, toast, skeletons y estados vacíos;
- capa visual reconstruida sobre tokens de color, spacing, radius, tipografía, sombras, motion, breakpoints y z-index; base blanca, gris neutro y azul financiero, con verde solo semántico para resultados positivos y rojo para gasto, error y destrucción;
- shell desacoplado en sidebar compacta, topbar, quick-add global, navegación móvil y command palette (`Cmd/Ctrl + K`);
- operaciones de creación y edición en dialog centrado para desktop y bottom sheet para mobile; drawers reservados a detalle e inspección;
- duplicación de movimiento como borrador local con fecha de hoy; no escribe hasta confirmar;
- dashboard narrativo, listas financieras, formularios responsivos y configuración por secciones, con light/dark, privacidad y reduced motion.

La representación monetaria implementada es:

```text
PostgreSQL bigint minor units
→ Data API string decimal
→ TypeScript bigint
→ UI formateada
```

No implementado y conservado únicamente como diseño futuro:

- baselines, ciclos, statements y pagos de tarjeta;
- personas, receivables, saldos a favor y cobros;
- installment plans/MSI;
- presupuestos, recurrencias, planificación, patrimonio y reportes;
- importación, conciliación, recibos y exportación.

No existen implementaciones parciales de tarjetas, statements, MSI, personas, receivables, presupuestos, planificación, salud, conciliación ni reportes. La Fase 3 requiere autorización explícita.
