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
| `installment_plans` | Contrato del plan nuevo o histórico | purchase_event, card, origin, original_amount_minor, term, installment_amount_minor, reported_paid_amount_minor, principal_paid_before_nexo_minor, included_in_opening_balance |
| `installments` | Calendario y principal por cuota | plan, number, due_statement_date, principal_amount_minor, reported_amount_minor, status |
| `installment_allocations` | Parte personal o de persona por cuota | installment, allocation, amount |

Las cuotas pasadas de un MSI histórico existen con estado `paid_before_nexo`, sin inventar movimientos bancarios. La cuota indicada como actual queda abierta según fecha y las posteriores quedan futuras. El plan conserva por separado el pago real reportado, el principal amortizado, el principal pendiente y su relación con el baseline. Una compra MSI nueva crea desde la compra el efecto de tarjeta por el principal completo; los statements seleccionan solo las cuotas de su ciclo.

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
| `budgets` (implementada, Fase 6A) | Límite mensual por categoría/moneda, con versiones recurrentes (`effective_from_month`/`effective_to_month`) y excepciones puntuales (`period_month`), mutuamente excluyentes |
| `goals`, `goal_entries` (implementadas, Fase 6B) | Meta con objetivo/fecha/cuenta vinculada opcional; libro firmado e inmutable de aportaciones/retiros/reversiones, `account_id` obligatorio identificando la cuenta real que respalda cada reserva |
| `planned_cash_flows` (implementada, Fase 6C, acotada a `one_time` desde 7A) | Intención declarada de una sola vez; nunca un `financial_event`, editable in-place. Toda recurrencia se movió a `recurring_rules` en Fase 7A |
| `recurring_rules`, `recurring_rule_versions` (implementadas, Fase 7A) | Identidad/ciclo de vida de una expectativa recurrente + versiones append-only de sus campos financieros/temporales (`update_recurring_rule` nunca reescribe una versión, siempre inserta una nueva con `effective_from_date`) |
| `recurring_rule_pauses`, `recurring_occurrences`, `recurring_occurrence_events` (implementadas, Fase 7A) | Pausas append-only ancladas siempre a `current_date`; una ocurrencia solo existe al confirmar/omitir (todo lo demás se deriva); eventos financieros por ocurrencia también append-only — el activo es una vista derivada, nunca una columna sobrescrita |
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
| `create_card_purchase` / `update_card_purchase` | evento inmutable, entrada de tarjeta, ciclo central, metadata y reversión/reemplazo |
| `create_card_payment` / `reverse_card_payment` | entrada negativa de cuenta y tarjeta, asignaciones firmadas a statements y restauración bilateral |
| `create_card_refund` / `reverse_card_refund` | crédito de tarjeta y reducción del gasto personal neto, con referencia opcional |
| `record_purchase` | agregado futuro para compras distribuidas, gasto personal, receivables y vínculos |
| `create_installment_purchase` | compra, plan, cuotas, asignaciones y obligación de tarjeta |
| `import_historical_installment_plan` | evento histórico no-gasto, plan, cuotas previas, principal pendiente y efecto incluido/no incluido en saldo inicial |
| `receive_person_payment` | abono a cuenta, aplicación parcial/total y excedente a saldo a favor |
| `apply_person_credit` | reducción coordinada de saldo a favor y receivable, sin nuevo flujo |
| `record_card_payment` | reducción de cuenta y pasivo, aplicación a statements o evidencia histórica no-impacting |
| `record_refund` | crédito financiero y reversión parcial/total del efecto personal/tercero |
| `reverse_financial_event` | evento compensatorio, vínculos y auditoría |
| `close_card_statement` | ciclo, snapshot, items, total y fecha límite |
| `confirm_import_batch` | filas aprobadas a eventos, vínculo de origen y marca idempotente |
| `archive_account` / `restore_account` | cambia disponibilidad de una cuenta propia, con idempotencia y auditoría; no altera entradas ni saldo |
| `reconcile_balance` | snapshot comparable y resoluciones explícitas, sin ajuste oculto |
| `create_budget` (implementada, 6A) | primera versión recurrente o excepción puntual de un presupuesto, idempotente |
| `update_recurring_budget_from_month` (implementada, 6A) | nueva versión de un presupuesto recurrente desde un mes elegido; nunca modifica una versión vigente en el pasado |
| `update_budget_exception_limit` (implementada, 6A) | edita el monto de una excepción puntual existente; rechaza una versión recurrente |
| `stop_recurring_budget` (implementada, 6A) | cierra la vigencia de la versión recurrente actual (`effective_to_month`) sin tocar versiones anteriores |
| `archive_budget` / `restore_budget` (implementadas, 6A) | archivan/restauran una excepción puntual; rechazan una versión recurrente (usar `stop_recurring_budget`) |

Las funciones privilegiadas, si fueran estrictamente necesarias, vivirán fuera de esquemas expuestos, revocarán `EXECUTE` a `PUBLIC`, autorizarán al actor dentro del cuerpo y usarán un `search_path` fijo. Se prefiere `SECURITY INVOKER`; `SECURITY DEFINER` no se utilizará para eludir RLS.

`reverse_financial_event` compensa en la misma transacción todas las entradas, asignaciones, cuotas, saldos a favor y aplicaciones creadas por el evento original; después, todas las proyecciones compartidas reflejan el estado restaurado sin eliminar auditoría.

## 6. Consultas y proyecciones

Las proyecciones son contratos de lectura compartidos por UI, exportaciones y reportes. Ninguna pantalla replica estas fórmulas:

| Métrica | Fuente de verdad única |
|---|---|
| Saldo de cuenta | `sum(account_entries.amount_minor)`; el opening se materializa una sola vez como entrada |
| Saldo utilizado de tarjeta | `card_summaries.used_balance_minor`: baseline + suma firmada de `card_entries` con `effect_scope = impacting` |
| Pago actual | `card_summaries.current_payment_minor`: `remaining_due_minor` del último `card_statement` cerrado aplicable |
| Compras netas del ciclo | `card_current_cycles.open_cycle_accumulated_minor`: cargos/refunds/ajustes con `cycle_start <= transaction_date < statement_date`; excluye pagos y no es saldo utilizado |
| Próximo estado cerrable | `card_statement_close_candidates`: primer corte vencido sin snapshot desde el baseline; nunca apunta al ciclo futuro |
| Saldo preliminar del estado | `card_statement_preview_balance`: baseline solo en su primer ciclo más actividad impactante del periodo; no usa `used_balance_minor` |
| Clasificación de pagos | `card_payment_classifications`: pago total, parte aplicada y excedente anticipado, derivados del ledger de asignaciones |
| Actividad por estado | `card_statement_activity_segments`: compras/refunds y segmentos aplicados/anticipados; el anticipo usa ciclo derivado, no un statement futuro ficticio |
| Disponible de tarjeta | `card_summaries.available_credit_minor`: límite menos saldo utilizado, sin FX |
| Fecha límite | `card_due_date(statement_date, payment_days_after_statement)`; usa días calendario y cruza mes/año |
| Gasto personal | eventos vigentes: `expense + card_charge - card_refund` usando `personal_amount_minor`; pagos y transferencias quedan excluidos |
| Ingreso | suma de `financial_events.amount_minor` para eventos `income` vigentes; transferencias, reembolsos, ajustes y cobros futuros nunca entran aquí |
| Cash flow | entradas y salidas firmadas de `account_entries` por `occurred_on`; se presentan por moneda y la clasificación del evento mantiene transferencias separadas de ingreso/gasto |
| Receivable pendiente | principal de `receivable_items` menos pagos, créditos aplicados, reembolsos y reversiones |
| Cuota actual de persona | `receivable_items` exigibles dentro del periodo consolidado actual, menos aplicaciones; excluye periodos futuros |
| Saldo a favor de persona | suma neta de `person_credit_entries` no aplicada |
| Patrimonio | por moneda: saldos de activos + receivables nominales - pasivos de tarjeta - saldos a favor/otros pasivos |
| Presupuesto consumido | `budget_period_spend`: `personal_amount` vigente por categoría, moneda y mes, unión de gasto no-MSI (`financial_activity`) y mensualidades MSI (`installments`), nunca ambas para la misma compra |

Proyecciones implementadas: `account_balances`, `account_activity`, `card_summaries`, `card_current_cycles` y `budget_period_spend`, todas `security_invoker`. `card_summaries` es el contrato único de saldo utilizado, disponible y pago actual; `card_current_cycles` define el periodo abierto y su acumulado; `budget_period_spend` es la única fuente de gasto presupuestado, consumida por `get_budgets_for_period`. Proyecciones futuras: `receivable_balances`, `person_current_due`, `person_credit_balances`, `personal_expenses`, `cash_flow`, `net_worth` y `card_comparison`.

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

## 16. Estado de implementación después de Fase 4A

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
- tablas `credit_cards`, `card_baselines`, `card_entries` y `card_statements`;
- funciones puras de ciclo en PostgreSQL y cierre de statement atómico/idempotente;
- vistas `card_summaries` y `card_current_cycles`, wallet y detalle de tarjeta;
- cierre cronológico mediante `card_statement_close_candidates`, con bloqueo de cortes futuros y cálculo por periodo;
- proyecciones `card_payment_classifications` y `card_statement_activity_segments` para separar pagos aplicados de anticipos sin duplicar persistencia;
- tablas inmutables `card_transaction_details` y `card_statement_payment_allocations`;
- RPC de compra, edición/reversión, pago/reversión y reembolso/reversión;
- vista `financial_activity` como contrato único para el timeline global de cuentas y tarjetas;
- asignación de pagos a statements pendientes por vencimiento y preservación del excedente como crédito;
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

- recurrencias/suscripciones completas (más allá de presupuestos, metas y los flujos planeados de Planeación), patrimonio y reportes;
- importación, conciliación, recibos y exportación (incluida la exportación de estado de persona, ver Fase 5B abajo).

Fases 4A–4B agregan `installment_plans`, `installments` y revisiones inmutables de metadata. Una compra nueva es el único impacto de su principal. Una importación histórica usa una entrada por principal pendiente solo cuando no estaba incluido en el saldo inicial; en caso contrario es `historical_non_impacting`. El calendario se consume en `card_statement_preview_balance` y `card_statement_activity_segments`, mientras `card_summaries` conserva el ledger como única fuente del saldo utilizado. `installment_plan_summaries` e `installment_schedule` son vistas `security_invoker`; todo cambio financiero pasa por RPC idempotentes con ownership.

Fase 5A agrega `contacts`, `receivables`, `purchase_allocations` y `receivable_entries`. Las cuatro tablas usan ownership explícito, RLS desde creación, grants mínimos e inmutabilidad en los libros financieros. `receivable_balances`, `contact_balance_summary`, `contact_activity`, `purchase_allocation_details` y `person_payment_activity` son vistas `security_invoker`.

Los comandos `create/update_shared_account_purchase` y `create/update_shared_card_purchase` validan en PostgreSQL la suma exacta de la distribución y crean evento, entrada financiera, receivables y auditoría en una sola transacción. `create_person_payment` bloquea filas y aplica FIFO por fecha; `reverse_person_payment` compensa cuenta y receivables. El frontend consume servicios y hooks, no llama Supabase desde componentes de presentación.

Fase 5B agrega `receivable_due_items`, `receivable_due_applications` y `person_credit_entries`, con RLS, ownership e inmutabilidad desde su creación. `receivable_due_items` reparte el nominal ya existente en `receivables`/`installments` por fecha exigible; no crea principal ni compite con `receivable_entries`, que sigue siendo la única fuente del saldo pendiente — cada aplicación (`receivable_due_applications`) escribe primero el detalle por obligación y de ahí deriva, en la misma transacción, la entrada agregada en `receivable_entries`. `person_credit_entries` es un libro aparte para saldo a favor por persona y moneda, desacoplado del saldo de receivables. `get_person_collection_period` es el contrato de lectura único para "a pagar este periodo" (`remaining_minor`) y "te debe en total" (`total_outstanding_minor`); ninguna pantalla sustituye uno por otro. `create_shared_installment_purchase` e `import_shared_historical_installment_plan` extienden el motor de MSI de Fases 4A–4B con reparto a personas, reutilizando `create_purchase_receivables`/`validate_purchase_split` de Fase 5A. `apply_person_credit` reduce saldo a favor y obligación en la misma transacción, sin movimiento bancario nuevo.

Corrección de Fase 5B sobre `contact_activity`: una aplicación de saldo a favor sí reduce `receivable_entries` (como cualquier pago), así que la vista ya la incluía, pero por la rama genérica que etiqueta como `purchase` todo lo que no sea `person_payment` — el resultado se veía como una compra nueva en vez de una reducción de deuda. La vista ahora excluye `person_credit_application` de esa rama y agrega una propia, sourced desde `receivable_due_applications`, con `activity_type = 'credit_applied'` y el concepto que cubrió (compra o "Mensualidad N de M"); `get_person_collection_period` gana `installment_count` por concepto con el mismo fin, sin que el frontend recalcule el plazo del plan.

Segunda corrección de Fase 5B: `get_person_collection_period` gana `overdue_minor` por periodo — suma de `outstanding_minor` de los conceptos cuya `payment_due_date` ya pasó, calculado en el mismo `lateral` que ya produce `remaining_minor` — para que "Vencido" no dependa de que el frontend compare fechas. `contact_activity` gana `personal_amount_minor` e `installment_count` (leídos directo de `financial_events`/`installment_plans`, mismas tablas que ya usa `get_person_collection_period`) para poder distinguir compra compartida / para un tercero / a meses sin una segunda fuente de esa clasificación.

Corrección de frontend (sin cambios en RPC ni en el esquema): la previsualización de "Registrar pago" asumía que cualquier excedente sobre `remaining_minor` del periodo actual era saldo a favor. `create_person_payment` en realidad reparte FIFO contra toda obligación pendiente de la persona en esa moneda antes de crear saldo a favor, así que un excedente moderado con MSI futuro sin cubrir simplemente adelanta esas mensualidades. La previsualización ahora usa `remaining_minor` y `total_outstanding_minor` juntos para distinguir pago parcial, periodo pagado con adelanto, y saldo a favor real.

Fase 5C agrega `get_person_statement`, que llama a `get_person_collection_period` para el periodo (sin duplicar esa lógica) y añade el desglose de cada pago real contra los conceptos que ese mismo periodo ya marcó como exigibles: cuánto se aplicó al periodo, cuánto adelantó deuda futura y cuánto se volvió saldo a favor, comparando `receivable_due_applications` contra los `id` de concepto que `get_person_collection_period` ya calculó — no una segunda regla de qué es "el periodo". `receivable_due_item_balances` y `get_person_collection_period` ganan dos campos aditivos: `overdue_since` y `purchase_amount_minor` por concepto.

`src/lib/person-statement.ts` (`buildStatementDocument`) es el único punto donde el JSON de `get_person_statement` se convierte en algo presentable; la pantalla `/personas/:id/estado` y las tres exportaciones (`statement-export-pdf.ts`, `statement-export-xlsx.ts`, `statement-export-csv.ts`) consumen esa misma estructura, así que no hay una segunda fuente de verdad para lo que aparece en cada formato. PDF usa `pdf-lib` (ya era dependencia) con paginación real; Excel construye OOXML a mano y lo empaqueta con `fflate` (también ya era dependencia); ninguna exportación pasa por captura de pantalla. `record_person_statement_export` (Fase 5B, sin cambios) se invoca al completar cada exportación real.

Decisión de arquitectura explícita: no se implementó reconstrucción de periodos históricos en 5C. `get_person_collection_period` computa `outstanding_minor` sobre el estado actual de cada `receivable_due_item`, no sobre una foto del pasado; pasarle una fecha anterior cambia qué corte se selecciona como vigente pero no qué estaba pagado en esa fecha. Verlo correctamente exigiría filtrar `receivable_due_applications` por `created_at` (posible, no implementado) o un snapshot inmutable (una fuente de verdad nueva, requiere decisión explícita antes de construirse). Documentado también en PLAN.md §12.

No existen implementaciones parciales de estados mensuales de personas, planificación, salud, conciliación ni reportes.

Fase 6A agrega `budgets` (RLS, ownership, `security_invoker` en su vista derivada) y la vista `budget_period_spend`, unión de dos fuentes ya existentes y nunca de un ledger nuevo: gasto no-MSI desde `financial_activity` (excluyendo cualquier `card_charge` de un `installment_plans.status = 'active'`) y mensualidades MSI desde `installments.status = 'scheduled'`, atribuidas al mes de su propio `due_statement_date` — nunca al mes de la compra. La parte personal de cada mensualidad es `installments.principal_minor` menos lo que `receivable_due_items` ya asigna a terceros para ese mismo `installment_id`: el complemento exacto del reparto proporcional con residuo que `create_installment_receivable_due_items` (Fase 5B) ya construye, sin ratio nuevo ni tabla adicional. `get_budgets_for_period` resuelve, por mes, la versión recurrente vigente (`effective_from_month` más reciente `<= M`, respetando `effective_to_month`) o la excepción puntual de ese mes si existe, y devuelve límite/gastado/disponible/porcentaje ya calculados. `get_budget_movements` explica el gasto fila por fila, incluyendo filas derivadas por mensualidad MSI sin crear ningún `financial_events` sintético. Un presupuesto recurrente nunca se edita in-place desde el frontend: `update_recurring_budget_from_month` siempre inserta una nueva versión; `stop_recurring_budget` cierra la vigencia de la versión actual sin tocar versiones anteriores. `create_card_refund` (Fase 3B) gana una validación: rechaza un reembolso directo sobre una compra que pertenece a un `installment_plans` activo, cerrando una discrepancia que DOMAIN_RULES.md ya documentaba pero el RPC no exigía — la vía correcta sigue siendo `reverse_installment_purchase`.

Fase 6B agrega `goals` y `goal_entries` (RLS, ownership, `goal_entries` inmutable con el mismo trigger `reject_financial_mutation`). `goal_entries.account_id` no es informativo: identifica la cuenta real que respalda cada reserva, y participa en un chequeo de capacidad transaccional (`available_for_goals = saldo_real - reservas_vigentes`), verificado con el mismo bloqueo `accounts ... FOR UPDATE` que ya usan `create_transaction`/`create_transfer`/`create_person_payment`/`create_card_payment` — ningún mecanismo de bloqueo nuevo. `private.execute_goal_transfer` duplica deliberadamente el núcleo de `create_transfer` (incluido el bloqueo `ORDER BY id` de las dos cuentas para evitar deadlocks) en vez de llamarlo, porque `create_transfer` resuelve su propia idempotencia bajo su propio `command_type` y anidarlo exigiría una segunda clave sintética sin beneficio real — mismo criterio que ya separa `private.apply_person_amount_to_due_items` (helper no idempotente por sí mismo) de los RPC públicos que lo envuelven.

El progreso de una meta (`saved_minor`) es siempre `sum(goal_entries.amount_minor)`, nunca un campo mutable. `backed_minor` — cuánto de ese progreso sigue cubierto por el saldo real actual de las cuentas que lo respaldan — se calcula en dos pasos, ambos vistas `security_invoker`, ambos reconstruibles desde `goal_entries` sin ninguna tabla ni columna adicional: `goal_lot_remaining` recalcula, por (meta, cuenta), cuánto de cada aportación todavía-viva (nunca revertida — un par revertido siempre suma cero y se excluye entero) sigue sin ser consumido por los retiros de esa misma meta contra esa misma cuenta, vía la misma técnica de suma acumulada con `least`/`greatest` que ya usa `create_installment_receivable_due_items` (Fase 5B) para repartir MSI entre terceros; `goal_account_backing` hace el mismo reparto pero entre TODAS las metas que comparten una cuenta, ordenando sus lotes vivos por antigüedad real y aplicando ese saldo como una cascada — una reserva liberada por completo y vuelta a aportar recibe una prioridad nueva, nunca la de la reserva antigua. `goal_balances` agrega ambos cálculos más el mes-a-mes recomendado cuando existe `target_date` (redondeo hacia arriba, nunca "a este ritmo" porque no hay velocidad histórica calculada). `goal_entry_activity` es el detalle trazable, incluida la cuenta de origen aunque esté archivada.

`contribute_to_goal`/`withdraw_from_goal` aceptan `p_move_real_money`: en `false` (reserva virtual) solo insertan `goal_entries`; en `true` reutilizan `private.execute_goal_transfer` entre la cuenta elegida y `goals.linked_account_id`, atómico con la fila de `goal_entries` que referencia el `financial_event_id` resultante. Un retiro virtual sin cuenta explícita reparte FIFO entre las cuentas que respaldan la meta (mismo patrón de bucle que `apply_person_amount_to_due_items`), pudiendo producir varias filas — cada una con su propio `account_id`, nunca ambiguo. `reverse_goal_entry` es append-only: bloquea la meta primero (mismo orden que contribute/withdraw), rechaza revertir una contribución cuyo lote ya fue parcialmente consumido por un retiro posterior, y si el original movió dinero real revierte también esa transferencia en la misma transacción.

Fase 6C agrega `planned_cash_flows` (RLS, ownership, editable in-place — no es un ledger, así que no lleva el trigger `reject_financial_mutation`) y un único RPC de lectura, `get_financial_plan(p_currency, p_as_of_date, p_horizon_months)`, `security definer stable`, sin ninguna escritura en ninguna rama. Todo lo demás que muestra Planeación es derivado en el momento, nunca persistido: cuentas/`goal_account_backing` para el saldo inicial, `card_statement_preview_balance`/`card_statements` para tarjetas, `get_budgets_for_period` para presupuestos, `goal_balances`/una simulación recursiva propia para metas, y `receivable_due_item_balances` para cobros de personas. Ninguna de estas fuentes se reconstruye a mano: se llaman tal cual existen.

Definición formal de `p_as_of_date` (DOMAIN_RULES.md §38): usa el estado financiero actualmente registrado y simula hacia adelante como si la fecha de referencia fuera `p_as_of_date` — nunca reconstruye cómo se veían las cuentas ese día en el pasado. La única garantía de reproducibilidad es determinismo estricto (mismo estado de base de datos + mismo `p_as_of_date` ⇒ mismo resultado, caso Z), no un snapshot histórico ni una promesa de que la misma llamada dentro de seis meses reproduzca lo mismo si los datos reales cambiaron.

El hallazgo central de esta fase, verificado leyendo el cuerpo de `card_statement_preview_balance` (no asumido): la función ya resuelve por sí sola el problema de "compra normal del ciclo abierto + su propia mensualidad MSI, en una sola cifra, sin duplicar" — excluye el `card_charge` de cualquier compra con `installment_plans.status = 'active'` y suma aparte, una sola vez, el `principal_minor` de la mensualidad cuyo `due_statement_date` coincide exactamente con el `statement_date` consultado. Esto colapsa lo que iba a ser una clasificación de tres niveles (confirmado/comprometido/estimado) en una jerarquía de dos: `card_statements` cerrado gana siempre que exista; si no, `card_statement_preview_balance` de ese corte exacto — nunca ambos, nunca una mensualidad sumada aparte encima de cualquiera de los dos. La misma función, llamada para un corte todavía más lejano cuyo ciclo no ha empezado a acumular, se reduce sola a solo esa mensualidad conocida (el gasto no-MSI da cero porque no existen `financial_events` ahí todavía) — no hizo falta una regla separada para "compromisos lejanos".

El saldo inicial usa respaldo real, no nominal: `apartado_respaldado` se agrega desde `goal_account_backing.backed_minor` por cuenta (no por meta), heredando el invariante ya probado en 6B de que nunca excede `max(saldo_real, 0)` — así que `disponible_sin_comprometer` de una cuenta nunca puede volverse negativo solo porque una meta tiene menos respaldo real del que registró en su momento. El faltante (`saved_minor - backed_minor`) se muestra aparte, informativo, sin generar una salida proyectada.

La simulación de metas (`projected_saved_minor`) vive enteramente dentro de una CTE recursiva de `get_financial_plan`, sembrada con el `saved_minor` real de `goal_balances` a `p_as_of_date` y avanzada mes a mes solo dentro de esa misma llamada — nunca toca `goals` ni `goal_entries`. `months_remaining` se recalcula una sola vez con la misma fórmula de 6B pero parametrizada por `p_as_of_date` en vez de `current_date`, y decrece por índice de mes con piso de 1, para no re-derivar `age()` doce veces.

Las tres series de escenario (`base`, `planned`, `planned_with_collections`) se calculan juntas en una sola pasada con funciones ventana (`sum(...) over (order by month_index rows between unbounded preceding and current row)`) sobre el neto de cada mes — sin recursión adicional, y cada una arrastrando su propio cierre como apertura del mes siguiente, nunca cruzadas entre sí. El frontend nunca pide una combinación distinta: las tres llegan siempre juntas para que alternar entre Base/Planeado y el interruptor de cobros esperados sea instantáneo, sin una segunda ida y vuelta a Supabase.

Fase 7A agrega movimientos recurrentes. `planned_cash_flows` se acota a `recurrence = 'one_time'` desde esta fase en tres capas: la RPC (`create_planned_cash_flow`/`update_planned_cash_flow` rechazan cualquier otro valor), la lectura (`get_financial_plan` solo lee `one_time`), y el `CHECK` de la tabla — aplicado en una **segunda migración separada** (`20260830090000_phase_7a_lock_planned_cash_flows_one_time.sql`), después de que la primera ya migró todo lo existente. Auditado explícitamente antes de decidir esto: `authenticated` no tiene `GRANT` de escritura sobre `planned_cash_flows` (solo `SELECT`, confirmado empíricamente con un intento directo que falla con "permission denied"), y el servicio de TypeScript solo hace `.select()`, nunca `.insert()`/`.update()`, sobre esa tabla — el único rol que podría reintroducir `monthly` es `service_role` (equivalente a acceso administrativo total). El `CHECK` cierra ese hueco de todos modos, sin debilitar la prueba de la migración contra datos preexistentes: `scripts/test-db.sh` corre un checkpoint dedicado (`supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql`, fuera del glob `*.test.sql` normal) exactamente entre las dos migraciones — la única ventana donde una fila `monthly` genuina todavía puede insertarse — y ese archivo nunca se vuelve a ejecutar después. Toda recurrencia vive en `recurring_rules` + `recurring_rule_versions`, con los campos financieros/temporales versionados append-only en vez de editados in-place — a diferencia de las metas o del nombre de la propia regla (cosméticos, editables directo), porque una ocurrencia confirmada nunca vuelve a leer la regla: su snapshot (`expected_amount_minor`, `category_id`, capturado en `recurring_occurrences` al confirmar/omitir) es la fuente de verdad para siempre, así que editar la regla después no tiene forma de reescribir la historia.

La pieza de diseño más delicada de 7A es la "guarda de vigencia" en `update_recurring_rule`: sin ella, cambiar `day_of_month` a mitad de un ciclo ya vencido podría hacer que ese mes derivara dos ocurrencias del mismo compromiso (la vieja y la nueva) o, al revés, que la ya-vencida desapareciera silenciosamente. La guarda exige que `effective_from_date` sea posterior a la última ocurrencia ya derivable bajo la versión actual — redondeado al inicio de un mes futuro para las frecuencias de familia mensual, exacto para `weekly`/`biweekly` — usando siempre `current_date` real (una escritura, no una proyección; mismo criterio que `close_card_statement`'s `NEXO_STATEMENT_NOT_DUE`, nunca `p_as_of_date`). Ninguna ocurrencia necesita materializarse antes de tiempo para quedar protegida: la versión vieja, que nunca se borra, sigue gobernando cualquier fecha anterior a la vigencia de la nueva, sin más máquina que esa.

El motor de calendario (`private.recurring_rule_occurrence_dates`) es una sola función SQL pura, consciente de versiones y de pausas, reutilizada tanto por `get_recurring_occurrences` (la vista `/recurrentes`) como por `get_financial_plan` — nunca dos implementaciones del mismo cálculo. `weekly`/`biweekly` son aritmética de días fija anclada en el `start_date` de la regla; las frecuencias de familia mensual caminan mes a mes reutilizando `card_effective_statement_date` para el clamp de día (cero lógica de fechas nueva); `semimonthly` clampa dos días independientes por mes, y usar `31` como el segundo es la forma deliberada de expresar "último día del mes" sin inventar un centinela.

Una ocurrencia solo se persiste al confirmar o al omitir — el mismo principio que `card_statements` (no existe hasta que cierras). `confirm_recurring_occurrence` (y `omit_recurring_occurrence`) adquiere `pg_advisory_xact_lock` sobre una clave derivada de `(rule_id, expected_date)` — literalmente la primera instrucción de la función, antes de cualquier `select`, de `create_transaction`/`create_card_purchase`, o de cualquier `insert` — así que dos confirmaciones concurrentes sobre el mismo slot se serializan ahí mismo, nunca dependen de que un `unique` falle después de haber creado dinero real. La clave (`private.recurring_occurrence_lock_key`) es un solo hash `md5` de 64 bits sobre una entrada namespaced con separadores de longitud fija (`'nexo.recurring_occurrence|rid|<uuid>|date|<fecha ISO>'`), no dos hashes `hashtext` de 32 bits combinados por separado — mezcla mejor la entropía del namespace y de ambos componentes en un solo digest, con delimitadores que no pueden ambigüarse entre un `rule_id` y una `expected_date` distintos. El financial_event real, la fila de `recurring_occurrences` y la de `recurring_occurrence_events` se crean dentro de la misma llamada de función (la misma transacción de Postgres), así que cualquier falla posterior revierte todo automáticamente, sin código de rollback explícito. `recurring_occurrence_events` es append-only: el evento económicamente activo de una ocurrencia es una vista derivada (`recurring_occurrence_current_event`), el más reciente cuyo evento no está revertido — mismo patrón que `is_reversed` en `goal_entry_activity` de 6B. Reconfirmar solo se permite cuando el único evento vivo ya fue revertido; nunca pueden coexistir dos activos.

La integración con Planeación es un único `not exists`: la CTE `flow_occurrences` de `get_financial_plan` fusiona `planned_cash_flows` (`one_time`) con las ocurrencias derivadas de `recurring_rules` que todavía no tienen fila en `recurring_occurrences`. En cuanto se confirma o se omite, ese filtro la excluye de la derivación — si se confirmó, su efecto real ya llega por los mecanismos existentes (`card_statement_preview_balance`/`card_statements`, saldo real de cuentas, `budget_period_spend`), sin ningún caso especial adicional en `get_financial_plan`.
