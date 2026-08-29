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
| Presupuesto consumido | `personal_amount` vigente por categoría y periodo |

Proyecciones implementadas: `account_balances`, `account_activity`, `card_summaries` y `card_current_cycles`, todas `security_invoker`. `card_summaries` es el contrato único de saldo utilizado, disponible y pago actual; `card_current_cycles` define el periodo abierto y su acumulado. Proyecciones futuras: `receivable_balances`, `person_current_due`, `person_credit_balances`, `personal_expenses`, `cash_flow`, `budget_consumption`, `net_worth` y `card_comparison`.

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

- presupuestos, recurrencias, planificación, patrimonio y reportes;
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

No existen implementaciones parciales de estados mensuales de personas, presupuestos, planificación, salud, conciliación ni reportes.
