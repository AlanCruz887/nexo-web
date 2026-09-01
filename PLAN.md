# Nexo — Plan de implementación por fases

## 1. Principio de ejecución

Cada fase termina con software verificable y documentación actualizada. No se inicia la siguiente si fallan invariantes financieras, aislamiento RLS o reconstrucción de saldos. Las fases agregan capacidades sobre el mismo núcleo; no crean modelos paralelos para cuentas, tarjetas, personas o reportes.

Estado actual: **Fase 7A (Movimientos recurrentes) implementada y validada localmente (migración, pruebas SQL, servicios/hooks y UI). Pendiente de aplicar las migraciones 6A, 6B, 6C y 7A al Supabase real del usuario, en ese orden, y de validación manual antes de continuar a una fase posterior.**

Fase 6B (Metas de ahorro) completada: migración, pruebas SQL, servicios/hooks y UI implementados y validados localmente.

Fase 6A (Presupuestos) completada: migración, pruebas SQL, servicios/hooks y UI implementados y validados localmente.

Fase 5C completada: estado de persona consolidado con exportación PDF/Excel/CSV, compartir e impresión. Cierra el módulo de Personas iniciado en 5A/5B.

Corrección posterior verificada: cierre cronológico de statements, saldo por periodo y bloqueo de cierres anticipados.

Corrección posterior verificada: pagos anticipados derivados por ciclo, aplicación al cierre sin doble impacto y pago mínimo nulo sin valor inventado.

## 2. Secuencia recomendada

### Fase 0 — Contrato y arquitectura

Entregables:

- `PRODUCT_SPEC.md`;
- `DOMAIN_RULES.md`;
- `ARCHITECTURE.md`;
- `PLAN.md`.

Puerta de salida:

- revisión y aprobación de arquitectura, entidades, relaciones, invariantes, fases y riesgos;
- aprobación explícita de las decisiones cerradas y aceptación de los riesgos diferidos que no bloquean Fase 1.

### Fase 1 — Fundamento técnico, autenticación y perfil base — Completada

Objetivo cumplido: establecer una base segura y reusable sin adelantar modelos financieros de fases posteriores.

Alcance:

- scaffold React/TypeScript/Vite y sistema de diseño base;
- Supabase local/configuración de entornos y Auth;
- perfiles y preferencias mínimas;
- estrategia monetaria única `bigint` en unidades menores, catálogo de escalas y `base_currency`; moneda por cuenta se aplicará cuando exista `accounts`;
- migración mínima para `currencies` y `profiles`, sin cuentas, eventos ni tablas financieras anticipadas;
- utilidades que separan fechas financieras `date` de timestamps de auditoría, sin crear aún columnas transaccionales;
- RLS y pruebas de aislamiento;
- servicios y hooks base para Auth/perfil, sin RPC ni movimientos financieros;
- componente monetario con modo privacidad;
- shell responsive desktop/mobile, tema y privacidad base.

Verificación:

- registro crea perfil 1:1 mediante trigger;
- dos usuarios no pueden leer ni modificar el perfil ajeno;
- catálogo MXN/USD/EUR y `base_currency` válida;
- conversión exacta minor/display y frontera JSON serializable;
- timezone/perfil, rutas protegidas y privacidad `MoneyValue`;
- migración reconstruible desde PostgreSQL limpio.

Resultado verificado: typecheck, lint, 19 pruebas frontend, build y reconstrucción limpia en PostgreSQL con pruebas RLS A/B. No incluye cuentas, tarjetas, transacciones, terceros, MSI, presupuestos ni importación.

### Fase 2 — Cuentas, movimientos base y transferencias — Completada

Objetivo cumplido: introducir activos líquidos y actividad base sobre el núcleo de eventos sin adelantar tarjetas, personas u obligaciones futuras.

Alcance implementado:

- cuentas `checking`, `savings`, `cash`, `debit`, `investment` y `other`, con moneda, archivado y restauración;
- categorías mínimas de sistema;
- eventos financieros y entradas de cuenta inmutables;
- saldo derivado desde entradas, sin `current_balance` editable;
- ingresos, gastos simples con `personal_amount_minor = amount_minor` y ajustes preparados internamente;
- transferencias atómicas entre cuentas de la misma moneda;
- edición por reversión más reemplazo y eliminación/reversión compensatoria;
- idempotencia transaccional, auditoría y notas versionadas;
- RLS A/B, vistas `security_invoker` y queries sin N+1;
- rutas canónicas `/cuentas`, `/cuentas/:id` y `/movimientos`, más alias `/accounts`, `/accounts/:id` y `/transactions`, con UI premium responsive;
- detalle con fecha de creación, duplicación a borrador fechado hoy y confirmaciones que identifican movimiento e importe;
- resumen de transferencia origen/destino antes de confirmar.

Verificación cumplida:

- opening 10,000 + ingreso 5,000 - gasto 2,000 - transferencia 1,000 = 12,000 en origen y +1,000 en destino;
- la transferencia no altera ingreso ni gasto;
- retry devuelve el mismo resultado y payload distinto falla;
- reversión restaura ambas cuentas;
- usuario A no lee ni opera recursos del usuario B;
- una cuenta archivada sale de selectores y conserva historial;
- restaurar es idempotente, auditable y vuelve a habilitar actividad sin alterar saldo ni historia;
- eliminar un movimiento simple registra `transaction_deleted`, pero internamente conserva el evento y lo compensa;
- frontend, migraciones limpias y suite RLS/PostgreSQL pasan.

### Fase 3A — Tarjetas, ciclos, baseline y statements — Completada

Alcance implementado:

- `credit_cards`, `card_baselines`, `card_entries` y `card_statements` con RLS y grants mínimos;
- motor PostgreSQL único para corte efectivo, ciclo semiabierto, corte anterior y fecha límite;
- baselines de saldo bancario actual, después del último estado y fecha específica;
- proyecciones `card_summaries` y `card_current_cycles` con `security_invoker`;
- cierre manual, atómico e idempotente; actualización auditada de importes reportados del statement;
- wallet, detalle, historial y themes visuales sin reglas financieras;
- tests de cortes 9/13/31, bisiesto, cambio de año, current payment/open cycle/used balance y RLS A/B.

No incluye compras productivas de tarjeta, pagos desde cuentas, refunds, MSI, personas ni receivables.

### Fase 4 — Personas, compras compartidas y receivables — Completada (incluye 5B y 5C: estado de persona y exportación)

Objetivo: implementar la diferenciación que define a Nexo.

Alcance:

- personas y archivado;
- compra personal, para tercero y compartida desde cuenta;
- receivables e items cobrables;
- pagos parciales/completos/adelantados y sobrepagos con prioridad predeterminada;
- saldo a favor de persona mediante entradas de crédito aplicables a obligaciones futuras;
- estado simple de persona en UI, aún sin PDF final;
- reversión de estos eventos.

Verificación:

- `purchase_amount = personal_amount + suma(third_party_allocations)` en toda compra distribuida;
- un cobro mueve receivable a banco y no crea ingreso/patrimonio;
- concurrencia no sobreaplica pagos;
- pago parcial conserva pendiente y sobrepago conserva `credit_balance` sin crear ingreso;
- entidades archivadas conservan historial y salen de selectores.

### Fase 3B — Compras, pagos y reembolsos de tarjeta — Completada

Objetivo: agregar operaciones productivas al motor de tarjeta ya implementado sin confundirlas con cuentas.

Alcance implementado:

- compras personales con categoría, fecha, método de pago y asignación al ciclo central;
- pagos atómicos desde cuentas de la misma moneda y asignación oldest-first a statements;
- reembolsos parciales, opcionalmente vinculados a la compra original;
- edición/reversión segura, actividad global de cuentas/tarjetas y filtros por origen;
- ledger firmado, RLS, idempotencia y auditoría de todas las operaciones.

Reglas ya cerradas para esta fase:

- reutiliza el motor de ciclos, baseline y statements de Fase 3A;
- estados cerrados no se reescriben: una compra/reembolso de ese ciclo exige corrección posterior;
- el excedente de pago permanece como saldo a favor de tarjeta mediante saldo utilizado negativo.

Verificación:

- pruebas de límites inclusivo/exclusivo;
- baseline sin duplicidad;
- pago de tarjeta no es gasto;
- las tres métricas de tarjeta cuadran y se explican;
- pago y su reversión restauran de forma coordinada cuenta, tarjeta y `remaining_due`;
- reembolso reduce gasto personal neto y nunca crea ingreso.

### Fases 4A–4B — MSI nuevos e históricos personales (completada)

Objetivo: agregar planes sin duplicar deuda o gasto.

Alcance:

- MSI personal nuevo e histórico;
- plazos estándar y personalizados;
- calendario y redondeo determinista;
- `installment_amount` real y última cuota ajustable a principal exacto;
- importación manual de MSI ya iniciado;
- pago real reportado separado del principal pagado;
- `paid_before_nexo`;
- integración con baseline, statements y pagos.

MSI de terceros/compartidos y su integración con receivables permanecen fuera de alcance hasta Personas.

Verificación:

- suma de cuotas igual al principal;
- pendiente igual a cuotas abiertas;
- compra MSI nueva ocupa línea por principal pendiente completo y el statement incluye solo cuotas del ciclo;
- plan incluido en baseline tiene impacto adicional cero;
- plan no incluido agrega solo principal pendiente;
- una cuota anterior importada no crea flujo bancario ficticio.

### Fase 6A — Presupuestos — Implementada localmente, pendiente de aplicar a producción

Objetivo cumplido: convertir el gasto ya registrado en un límite mensual entendible por categoría, sin crear una segunda contabilidad ni duplicar principal de MSI.

Alcance:

- `budgets` con versiones recurrentes (`effective_from_month`/`effective_to_month`) y excepciones puntuales (`period_month`), mutuamente excluyentes;
- `budget_period_spend`, unión de gasto no-MSI (`financial_activity`) y mensualidades MSI (`installments.status = 'scheduled'`, atribuidas al mes de su `due_statement_date`), nunca ambas para la misma compra;
- parte personal de una mensualidad derivada de `installments.principal_minor` menos lo que `receivable_due_items` ya asigna a terceros — sin ratio nuevo, sin tabla adicional;
- `get_budgets_for_period` (resolución + gasto + disponible + porcentaje) y `get_budget_movements` (detalle trazable, incluidas filas MSI derivadas sin evento sintético);
- `create_budget`, `update_recurring_budget_from_month`, `update_budget_exception_limit`, `stop_recurring_budget`, `archive_budget`, `restore_budget`;
- corrección en `create_card_refund`: rechaza un reembolso directo sobre una compra de un plan MSI activo (usar `reverse_installment_purchase`);
- UI: `/presupuestos` (alias `/budgets`) con tarjetas por categoría, navegación de mes, separación por moneda, modal de creación y detalle con movimientos.

Verificación:

- porciones de terceros no consumen presupuesto (casos A-C);
- pagos de tarjeta, cobros de personas y transferencias no consumen presupuesto (casos D-F);
- reembolso reduce el gasto neto y reversión elimina el impacto (casos G-H);
- monedas nunca se agregan (casos I/S);
- `transaction_date`/`due_statement_date` deciden el periodo, nunca `created_at` (caso K);
- RLS aísla presupuestos entre usuarios (caso L);
- MSI personal y compartido nunca duplican principal + mensualidades, con invariante explícito (casos M, N);
- MSI histórico excluye `paid_before_nexo` de presupuestos (caso O);
- cambiar un límite recurrente no reescribe meses pasados; una excepción puntual no afecta el mes siguiente (casos P, Q);
- refund directo sobre MSI activo se rechaza (caso R).

Alcance explícitamente diferido a una fase posterior autorizada: recurrencias/suscripciones (más allá del propio modelo de versiones de presupuesto), reglas automáticas con preview, reembolso de gasto directo de cuenta (hoy solo existe reembolso de tarjeta).

### Fase 6B — Metas de ahorro — Implementada localmente, pendiente de aplicar a producción

Objetivo cumplido: convertir un plan de ahorro en progreso verificable, sin crear una segunda contabilidad ni permitir que dos metas reserven el mismo dinero real.

Alcance:

- `goals` (objetivo, fecha opcional, cuenta vinculada opcional, `status` activo/pausado, `archived_at`) y `goal_entries` (libro firmado e inmutable de aportaciones/retiros/reversiones; `account_id` obligatorio identifica la cuenta real que respalda cada reserva);
- reserva virtual con chequeo de capacidad transaccional (`saldo_real - reservas_vigentes`) usando el mismo bloqueo `accounts ... FOR UPDATE` que ya usan `create_transaction`/`create_transfer`/`create_person_payment`/`create_card_payment`;
- aportación/retiro real reutilizando el motor de transferencias (`private.execute_goal_transfer`, mismo orden de bloqueo `ORDER BY id` que `create_transfer` para evitar deadlocks), atómico con el `goal_entries` correspondiente;
- `saved_minor` (progreso registrado, `sum(goal_entries)`) separado de `backed_minor` (cuánto de ese progreso sigue cubierto por el saldo real actual), con reparto FIFO determinista entre metas que comparten una cuenta (`goal_lot_remaining` + `goal_account_backing`, ambas vistas derivadas, sin tabla ni columna adicional);
- `goal_balances` (progreso, respaldo, mes-a-mes recomendado) y `goal_entry_activity` (detalle trazable) como contratos de lectura únicos;
- `create_goal`, `update_goal`, `set_goal_status`, `archive_goal`, `restore_goal`, `contribute_to_goal`, `withdraw_from_goal`, `reverse_goal_entry`;
- UI: `/metas` (alias `/goals`) con tarjetas por meta, modal de creación mínimo, detalle con advertencia de respaldo cuando aplica, aportar/retirar/editar/pausar/archivar.

Verificación:

- crear, aportar, aportar de nuevo, retirar y un objetivo superado sin truncar (casos A-E);
- ninguna operación de meta crea income/expense, y una transferencia real no cambia el patrimonio neto (casos F-H);
- moneda distinta se rechaza, tanto para respaldo como para cuenta vinculada (casos I, X);
- cuenta archivada conserva historial pero no acepta nuevas reservas (casos J, W);
- archivar una meta conserva su historial (caso K);
- reversión reconstruye el progreso, tanto virtual como real, atómicamente (casos L, U, V);
- fecha objetivo calcula el mensual recomendado con redondeo hacia arriba; sin fecha, la meta funciona igual sin ese cálculo (casos N, O);
- dos metas nunca pueden reservar simultáneamente el mismo saldo, verificado en el momento exacto de reservar (casos P, Q, S);
- retiro virtual libera la reserva de la cuenta correcta, con FIFO determinista entre varias cuentas (casos R, T);
- una reserva liberada por completo y vuelta a aportar recibe prioridad nueva, nunca la antigua (caso Y);
- `backed_minor` se reparte determinísticamente cuando el saldo de una cuenta baja después de reservar, con `0 <= backed_minor <= saved_minor` por meta y la suma nunca por encima del saldo real (caso Z);
- una misma `goal_entries` no se revierte dos veces, y una operación real fallida no deja rastros huérfanos (casos AA, AB);
- aislamiento RLS entre usuarios (caso M).

Alcance explícitamente diferido a una fase posterior autorizada: metas con conversión FX entre monedas, notificaciones/recordatorios de aportación, reglas de aportación automática recurrente.

### Fase 6C — Planeación financiera — Implementada localmente, pendiente de aplicar a producción

Objetivo cumplido: proyectar liquidez hacia adelante (3/6/12 meses) sin crear una segunda contabilidad, sin duplicar dinero ni gasto, y sin confundir presupuesto con obligación ni cobro de persona con ingreso.

Alcance:

- `planned_cash_flows` (entrada/salida declarada manualmente, `one_time`/`monthly`, `category_id` nullable, editable in-place, nunca un `financial_event`) y sus RPC de CRUD (`create/update/archive/restore_planned_cash_flow`);
- `get_financial_plan(p_currency, p_as_of_date, p_horizon_months)`: única RPC de lectura, `security definer stable`, sin ninguna escritura; parametrizada por `p_as_of_date` en cada rama (nunca `current_date` implícito), para que las pruebas puedan fijar una fecha;
- saldo inicial por cuenta usando respaldo real (`goal_account_backing.backed_minor`), nunca `saved_minor` nominal — el faltante de respaldo se muestra aparte, informativo, sin restar la liquidez dos veces;
- obligaciones de tarjeta con jerarquía de dos niveles (statement cerrado > `card_statement_preview_balance` del corte exacto, nunca ambos ni una mensualidad sumada aparte), verificada leyendo el cuerpo real de esa función en vez de asumir qué incluye;
- `planned_cash_flows` categorizados consumen el presupuesto restante de su categoría (`flexible_additional = max(available_minor - planned_categorized, 0)`) en vez de sumarse encima del límite completo; sin categoría, quedan fuera de cualquier presupuesto;
- simulación recursiva y no persistida de aportación recomendada por meta (`projected_saved_minor`), sembrada en el `saved_minor` real y avanzada mes a mes solo dentro de la misma llamada — nunca escribe en `goals` ni `goal_entries`;
- cobros de personas agregados desde `receivable_due_item_balances` por mes de `payment_due_date`, sin recorrer el RPC por-contacto uno por uno (evita N+1) y siempre como "posible", nunca como ingreso;
- tres series de escenario en una sola pasada (`base`, `planned`, `planned_with_collections`), cada una con su propio arrastre mes a mes, nunca cruzadas;
- UI: `/planeacion` (alias `/planning`) con selector de moneda/horizonte/escenario, interruptor de cobros esperados, línea de tiempo mensual y detalle expandible por mes con lenguaje de consumidor (Obligaciones/Planeado/Flexible/Posibles entradas), más gestión de flujos planeados (crear/editar/archivar/restaurar).

Verificación (casos A-AW en `supabase/tests/financial_planning.test.sql`): CRUD y validación de `planned_cash_flows` (A-H); aislamiento RLS (I); un saldo con menos respaldo real que lo ahorrado nunca vuelve negativa la liquidez disponible (AF); una compra normal de ciclo abierto aparece en la obligación futura sin desaparecer hasta que cierre el statement (AG); el preview de un corte no cerrado ya incluye, en una sola cifra, el gasto normal y su propia mensualidad MSI (AH); cerrar el statement sustituye al preview sin duplicar (AI); presupuesto + flujo planeado categorizado nunca suma más que el límite (AJ, AK); un flujo sin categoría nunca toca ningún presupuesto (AL); la proyección de una meta se mantiene coherente mes a mes y dejan de recomendarse aportaciones una vez alcanzado el objetivo dentro de la simulación (AM, AN); los tres escenarios arrastran de forma independiente y el interruptor de cobros esperados no contamina Base ni Planeado (AO, AP); un flujo mensual con día 31 conserva la intención original en meses más cortos sin arrastrar el recorte a los meses siguientes (AQ); un preview o un statement en cero nunca genera una fila de obligación visible (AR, AS); un flujo ya ocurrido este mes no se vuelve a proyectar (AT); ninguna RPC de Planeación escribe en el motor financiero real (AU); cada agregado visible suma exactamente sus líneas (AV) y cada cierre mensual reproduce exactamente el neto de sus propios componentes (AW).

Alcance explícitamente diferido a una fase posterior autorizada: patrimonio por fecha, valuaciones de inversión e indicadores de salud financiera (quedan en Fase 8); recurrencias/suscripciones (movimientos recurrentes básicos llegaron en Fase 7A; RRULE/calendario empresarial complejo siguen fuera); conversión FX automática entre monedas dentro de una misma proyección.

### Fase 7A — Movimientos recurrentes — Implementada localmente, pendiente de aplicar a producción

Objetivo cumplido: registrar lo que se repite (Netflix, renta, nómina) sin que definir la expectativa se confunda jamás con que ya ocurrió, y sin que Planeación termine sumando el mismo compromiso dos veces por tener dos fuentes distintas para representarlo.

Alcance:

- `recurring_rules` (identidad/ciclo de vida: `direction`, `currency`, `start_date`/`end_date`, `status` activo/pausado, `archived_at`) + `recurring_rule_versions` (append-only: `amount_minor`, `category_id`, `frequency`, `day_of_month`/`day_of_month_secondary`, `account_id`/`card_id`, cada una con su `effective_from_date` — `update_recurring_rule` nunca reescribe una versión, siempre inserta una nueva);
- ocho frecuencias sin RRULE (`weekly`/`biweekly`/`semimonthly`/`monthly`/`bimonthly`/`quarterly`/`semiannual`/`annual`), una sola función de derivación (`private.recurring_rule_occurrence_dates`) reutilizada por `get_recurring_occurrences` y por `get_financial_plan`, con clamp de día vía `card_effective_statement_date` (cero lógica de fechas nueva) y `biweekly` genuinamente distinto de `semimonthly`;
- `recurring_rule_pauses` (append-only, siempre ancladas a `current_date`, nunca retroactivas) y una "guarda de vigencia" en `update_recurring_rule` que impide que un cambio de calendario borre o duplique una ocurrencia ya vencida/pendiente;
- `recurring_occurrences` (existe únicamente al confirmar u omitir; todo lo demás se deriva) + `recurring_occurrence_events` (append-only: cada financial_event real vinculado a una ocurrencia, con `recurring_occurrence_current_event` como vista derivada del evento activo — nunca una columna sobrescrita, nunca dos eventos activos a la vez);
- `confirm_recurring_occurrence` reutiliza `create_transaction`/`create_card_purchase` sin ledger paralelo, resuelve la fuente con prioridad explícita-de-confirmación > predeterminada-de-versión > rechazo, y serializa la primera confirmación con `pg_advisory_xact_lock` sobre `(rule_id, expected_date)` antes de tocar cualquier tabla — nunca depende de que un `unique` falle después de haber creado dinero real;
- `planned_cash_flows` se acota a `one_time` en la capa de RPC y de lectura (nunca en el `CHECK` de la tabla, para no romper la prueba de migración contra datos preexistentes) y una función idempotente/auditable (`private.migrate_planned_cash_flow_monthly_rows`, `migrated_from_planned_cash_flow_id` como ancla) convierte cada fila `monthly` existente en su `recurring_rule` equivalente, archivando la fila vieja sin borrarla;
- `get_financial_plan` fusiona `planned_cash_flows` (`one_time`) con las ocurrencias derivadas de `recurring_rules` que todavía no tienen fila en `recurring_occurrences` — un solo `not exists` es el interruptor anti-doble-conteo completo, tanto para tarjetas/cuentas como para presupuestos;
- UI: `/recurrentes` (alias `/recurring`) con "Próximos" (agrupado por fecha, Registrar/Omitir), "Recurrentes activos", modal de creación en lenguaje de consumidor, modal de confirmación con importe/fecha/fuente reales precargados pero editables, y detalle con historial real (nunca reconstruido desde la regla actual).

Verificación (casos A-BH): definir una regla nunca crea `financial_events`/`account_entries` (A, B); calendario correcto para día 31 cruzando febrero (C), `biweekly` exactamente cada 14 días y distinto de `semimonthly` (D, E); pausa sin deuda fantasma y reactivación sin atrasados ficticios (F, G, AN); omitir una ocurrencia no afecta la siguiente (H); confirmar cuenta/tarjeta/ingreso crea exactamente un movimiento real del tipo correcto (I, J, K); doble confirmación nunca duplica (L); importe y fecha reales distintos del esperado se conservan junto con lo esperado (M, N); editar importe/día/fuente después de confirmar nunca reescribe una ocurrencia ya confirmada (O, P, Q); la guarda de vigencia protege una ocurrencia pendiente sin duplicarla en el mes de transición, verificado letra por letra contra el ejemplo exacto de la auditoría de cierre — mensual (BB, BC), semimensual (BD) y quincenal (BE), además de (AL, AM, AX, AY); archivar conserva `financial_events` y saldos (R, AF); fuente explícita en la confirmación funciona sin fuente predeterminada y nunca modifica la regla (AO, AP); evento revertido y su reemplazo quedan ambos trazables, nunca dos activos simultáneos (AQ, AR), doble confirmación concurrente serializada por el advisory lock nunca crea dos eventos (AS, AV), y una falla real dentro de la confirmación no deja huérfanos en ninguna tabla (AW); ninguna ocurrencia se materializa antes de tiempo y la derivación es determinista (AC, AD, AE); presupuesto categorizado antes/después de confirmar nunca dobla el descuento (U, V, AH); ingreso recurrente alimenta Planeación como entrada esperada (W); multimoneda separada y fuente con moneda distinta rechazada (X, Y); aislamiento RLS total sobre reglas y ocurrencias (Z); ningún camino normal de escritura puede crear un `planned_cash_flow` monthly nuevo, ni por RPC ni por el `CHECK` de la tabla (AG, BF); migración de filas `monthly` preexistentes (una y varias a la vez) es idempotente, auditable, preserva la misma expectativa económica una sola vez por mes en Planeación antes y después, y queda archivada sin excepción (AJ, AK, AU, BA, BG, BH — estos seis, específicamente, corren en `supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql`, la única ventana de la secuencia de migraciones donde una fila `monthly` real todavía puede insertarse); y confirmar/omitir en tarjeta nunca duplica la proyección frente al preview/statement (AI, AZ).

Alcance explícitamente diferido a 7B: detección automática de recurrencias desde histórico, ejecución automática, notificaciones, transferencias recurrentes, aportaciones recurrentes a metas, receivables recurrentes, RRULE/calendario empresarial complejo.

### Fase 7B — Conciliación e importaciones

Objetivo: incorporar datos externos sin ocultar diferencias ni contaminar el núcleo.

Alcance:

- conciliación de cuenta y tarjeta;
- staging de archivos, mapeo, preview, duplicados y confirmación;
- reglas de categorización aplicables en staging;
- resolución explícita de diferencias;
- recibos privados en Storage.

Verificación:

- staging no afecta saldos;
- confirmar es atómico e idempotente;
- reimportar no duplica;
- saldo comparable y fecha/alcance coinciden;
- Storage bloquea acceso cruzado.

### Fase 8 — Patrimonio y salud financiera

Objetivo: evaluar posición personal a partir de hechos verificados. El forecast de liquidez, tarjetas, cuotas y cobros ya se implementó en Fase 6C (Planeación) — esta fase cubre lo que queda: patrimonio y salud.

Alcance:

- patrimonio por fecha;
- valuaciones de inversión;
- indicadores explicables de salud financiera.

Verificación:

- proyecciones no alteran saldos reales;
- cobro de receivable no cambia patrimonio;
- compra de tercero no aumenta gasto personal;
- cada indicador muestra componentes, periodo y política.

### Fase 9 — Reportes, exportación y estados compartibles

Objetivo: presentar y compartir información sin crear una segunda fuente de cálculo.

Alcance:

- reportes por cuenta, tarjeta, emisor, producto, categoría, persona y periodo;
- comparativas completas de tarjetas;
- PDF simple de persona;
- PDF, Excel y CSV para recursos contratados;
- desglose navegable desde agregados.

Verificación:

- export y UI cuadran contra las mismas proyecciones;
- el PDF de persona omite deuda futura;
- modo privacidad cubre previews;
- redondeos y totales son consistentes entre formatos.

### Fase 10 — PWA avanzada, hardening y lanzamiento

Objetivo: llevar el producto a calidad operativa sin relajar seguridad financiera.

Alcance:

- instalación y actualización PWA robustas;
- estrategia offline explícita e idempotente;
- rendimiento, accesibilidad y motion final;
- observabilidad, backups, recuperación y retención;
- threat model, revisión de permisos, advisors y carga;
- migración/seed de producción y runbook.

Verificación:

- actualización de service worker no pierde comandos;
- caché sensible se limpia al cerrar sesión;
- restore de backup ensayado;
- pruebas de carga en timelines/reportes;
- revisión RLS/RPC/Storage sin hallazgos críticos.

## 3. Dependencias críticas

```text
Núcleo de eventos + RLS + idempotencia
 ├─ Personas y receivables
 ├─ Tarjetas, baseline y statements
 │    └─ MSI
 ├─ Presupuestos y recurrencias
 └─ Importación y conciliación
      ↓
Forecast + patrimonio + salud
      ↓
Reportes + exportaciones
      ↓
Hardening y lanzamiento
```

La UI puede evolucionar en paralelo dentro de una fase, pero los reportes no deben preceder la definición y prueba de sus fuentes financieras.

## 4. Estrategia de entrega

Para cada fase:

1. confirmar decisiones de dominio pendientes;
2. actualizar especificación y ADR si cambia una decisión;
3. diseñar migración y contratos Zod/TypeScript;
4. implementar restricciones, RLS y RPC;
5. probar el dominio en SQL;
6. integrar repositorios/TanStack Query;
7. construir UI y estados de interacción;
8. ejecutar pruebas unitarias, RLS, integración y E2E;
9. revisar rendimiento, accesibilidad y seguridad;
10. documentar resultado, limitaciones y criterios cumplidos.

No se agregan optimizaciones, tablas resumen o Edge Functions hasta demostrar su necesidad.

## 5. Riesgos técnicos y mitigaciones

| Riesgo | Impacto | Mitigación prevista |
|---|---|---|
| Doble conteo entre baseline, MSI y movimientos | Saldos y deuda incorrectos | Proveniencia explícita, vínculo a baseline y pruebas de reconstrucción |
| Ambigüedad de fechas/cortes | Compra asignada al statement equivocado | `transaction_date`, zona explícita, último día válido, rangos semiabiertos y matriz de límites |
| Redondeo de MSI/asignaciones | Cuotas que no suman principal | Aritmética exacta y residuo determinista |
| Operaciones parciales o reintentos | Dinero duplicado/descuadrado | RPC transaccional, idempotencia y bloqueo/concurrencia |
| Sobreaplicación concurrente de pagos | Receivable o statement negativo | Locks/restricciones y prueba de carreras |
| RLS incompleta en tablas hijas/vistas | Fuga entre usuarios | Ownership comprobable, vistas `security_invoker` y pruebas con dos usuarios |
| Funciones privilegiadas expuestas | Escalada de acceso | Esquema privado, grants mínimos, `auth.uid()`, `search_path` fijo |
| Importaciones duplicadas | Saldos inflados | Staging, fingerprint, IDs externos y confirmación idempotente |
| Métricas divergentes en UI/export | Pérdida de confianza | Proyecciones compartidas y pruebas de contrato |
| Caché/PWA con datos sensibles o obsoletos | Privacidad y decisiones incorrectas | Caché mínima, limpieza de sesión y estado confirmado/pending visible |
| Audit log excesivo o insuficiente | Riesgo de privacidad o falta de trazabilidad | Política de minimización, retención y eventos tipados |
| Performance por ledger append-only | Timelines/reportes lentos | Índices guiados por consultas, keyset pagination y proyecciones medibles |
| Reglas de negocio repartidas en frontend | Bypass e inconsistencias | Invariantes y operaciones críticas en PostgreSQL; frontend como cliente |
| Cambios del ecosistema Supabase | Configuración obsoleta/insegura | Revisar changelog y documentación oficial antes de cada implementación |

## 6. Decisiones cerradas antes de Fase 1

- Persistencia monetaria: `bigint` en unidades menores; moneda por cuenta/tarjeta; `base_currency` en perfil; sin FX automático.
- Fecha financiera: `transaction_date`; fechas de compra/posteo opcionales y no inventadas.
- Gasto personal: `personal_amount`, incluido MSI reconocido una sola vez al comprar.
- Cortes inexistentes: último día válido; el día efectivo pertenece al siguiente ciclo.
- Baseline: entidad financiera con tres políticas explícitas y eventos previos no-impacting.
- Statements: cierre como fuente de verdad del pago actual; ciclo abierto como acumulado.
- Receivables: valor nominal en patrimonio, pagos parciales y excedente a saldo a favor.
- MSI: mensualidad real, residuo en última cuota, principal completo en línea y cuota del ciclo en statement.
- Reversión e idempotencia: obligatorias para todos los RPC financieros.

## 7. Riesgos que permanecen abiertos

No bloquean la base de Fase 1, pero deben resolverse antes de su módulo:

- Fase 4: saldo a favor de tarjeta/sobrepago del pasivo y flujo exacto de corrección post-cierre.
- Fase 4: excepciones de emisores para fines de semana/festivos; por defecto se usan días calendario.
- Fase 7: formatos bancarios prioritarios, fingerprints y autorización de `posted_date` por proveedor.
- Fase 8: fórmula versionada de salud y política de valuación de inversiones; receivables ya quedan nominales.
- Fase 9/10: proveedor y política de FX futuro, retención de auditoría, alcance offline, cifrado local y objetivos de rendimiento.

## 8. Suite permanente de invariantes

Estas pruebas se agregan en la primera fase donde exista la entidad necesaria y nunca se eliminan:

1. compra para tercero no es gasto personal;
2. cobro de tercero no es ingreso;
3. pago de tarjeta no es gasto;
4. transferencia no es ingreso ni gasto;
5. MSI histórico no duplica baseline;
6. cuotas pagadas reducen `remaining_principal`;
7. compra en el día de corte entra al siguiente ciclo, incluidos cortes efectivos por fin de mes;
8. statement cerrado controla pago actual;
9. ciclo abierto no afecta pago actual;
10. presupuestos usan `personal_amount`;
11. salud financiera usa `personal_amount` para gasto;
12. cobro de receivable no cambia patrimonio;
13. pago parcial conserva saldo correcto y estado abierto;
14. sobrepago conserva crédito a favor y no crea ingreso;
15. reversión restaura el estado previo de todas las proyecciones;
16. monedas distintas no se agregan sin FX explícito;
17. doble click/retry/reenvío produce un único evento;
18. una clave idempotente reutilizada con payload diferente falla;
19. pago de tarjeta histórico no-impacting no modifica saldo;
20. UI, export y reporte consumen el mismo contrato de proyección para cada métrica.
21. el invariante `purchase_amount = personal_amount + third_party_allocations` se exige en compras y no se aplica indebidamente a otros tipos de evento;
22. una compra MSI nueva impacta el principal de tarjeta una sola vez y sus cuotas no vuelven a sumar el mismo principal;
23. el cronograma de cobro por periodo reparte deuda ya existente y nunca crea principal nuevo: la suma de sus items por obligación es exactamente el nominal de esa obligación;
24. "te debe en total" y "a pagar este periodo" son proyecciones distintas y ninguna sustituye a la otra en UI, export ni reporte;
25. una aplicación de saldo a favor reduce lo pendiente igual que un pago pero no crea movimiento bancario ni ingreso, y aparece en la actividad de la persona con su propia etiqueta;
26. un pago de persona que excede lo exigible del periodo actual adelanta obligaciones futuras de esa persona antes de convertirse en saldo a favor; solo el remanente después de saldar toda su deuda pendiente se guarda como saldo a favor;
27. aplicar saldo a favor sin ninguna obligación pendiente elegible se rechaza en vez de crear un movimiento sin destino;
28. el estado de persona y sus exportaciones (PDF/Excel/CSV) muestran exactamente las mismas cifras que la proyección de dominio; ninguna exportación recalcula ni redondea de forma distinta a la pantalla;
29. una exportación nunca mezcla monedas: cada moneda de la persona aparece en su propio bloque, tabla u hoja, sin conversión automática;
30. una exportación real nunca contiene identificadores internos, nombres de tabla ni nombres de RPC, y siempre muestra los importes completos aunque el modo de privacidad esté activo en pantalla;
31. un presupuesto nunca usa `amount` cuando debe usar `personal_amount`, y una compra para tercero nunca consume presupuesto;
32. una compra MSI activa nunca aparece en presupuestos a la vez como principal completo y como mensualidades: solo una de las dos representaciones;
33. una mensualidad MSI consume presupuesto en el mes de su propio `due_statement_date`, nunca en el mes de la compra ni con el principal completo;
34. una cuota `paid_before_nexo` de un MSI histórico nunca contribuye a ningún presupuesto;
35. cambiar el límite de un presupuesto recurrente crea una nueva versión y nunca modifica el monto que ya aplicó a un mes pasado;
36. un reembolso directo sobre una compra de un plan MSI activo se rechaza; la única vía válida para deshacerla es revertir el plan completo;
37. el progreso de una meta (`saved_minor`) es siempre `sum(goal_entries.amount_minor)`, nunca un campo mutable;
38. `0 <= backed_minor <= saved_minor` para cada meta, y la suma de `backed_minor` de las metas que comparten una cuenta nunca supera `max(saldo_real, 0)`;
39. una nueva reserva contra una cuenta nunca puede exceder su saldo disponible en el momento exacto de reservar, verificado con el mismo bloqueo de fila que usan las demás operaciones financieras sobre `accounts`;
40. una aportación o retiro virtual de meta nunca crea `account_entries`; un movimiento real de meta usa el motor de transferencias y suma cero entre las dos cuentas;
41. ninguna operación de meta crea `income` ni `expense`;
42. una reversión de meta es append-only y nunca se aplica dos veces sobre la misma entrada;
43. ninguna RPC de Planeación crea `financial_events`, `account_entries`, `card_statements`, `installments`, `goal_entries`, `budgets` ni `receivable_entries`, bajo ningún escenario ni horizonte;
44. la liquidez disponible de una cuenta nunca se muestra negativa solo porque una meta tiene menos respaldo real del que registró — el respaldo usado en Planeación nunca excede `max(saldo_real, 0)`;
45. una obligación de tarjeta en Planeación aparece exactamente una vez por corte: nunca un statement cerrado y su preview a la vez, y nunca una mensualidad MSI sumada aparte de la cifra que ya la contiene;
46. un flujo planeado categorizado nunca hace que la presión total de una categoría exceda su límite salvo que el propio flujo, por sí solo, ya lo exceda;
47. la simulación de aportación recomendada de una meta en Planeación nunca escribe en `goals` ni `goal_entries`, y dejan de recomendarse aportaciones una vez que la propia simulación asume el objetivo alcanzado;
48. las series de escenario de Planeación (`base`, `planned`, `planned_with_collections`) arrastran su propio cierre como apertura del mes siguiente, nunca el de otro escenario;
49. cada agregado que muestra Planeación (obligaciones, flexible de presupuesto, recomendación de metas, cobros esperados) es exactamente la suma de las líneas que también expone para ese mismo mes;
50. definir o editar una regla recurrente nunca crea `financial_events`, `account_entries` ni `card_entries`; solo `confirm_recurring_occurrence` lo hace, reutilizando el motor real;
51. `update_recurring_rule` nunca reescribe una versión existente en `recurring_rule_versions`, siempre inserta una nueva con `effective_from_date`, y esa fecha nunca puede ser anterior o igual al mes/fecha de la última ocurrencia ya derivable bajo la versión actual;
52. una ocurrencia confirmada u omitida nunca vuelve a leer la regla para sus propios valores históricos (`expected_amount_minor`, `category_id` quedan congelados en el momento de la acción);
53. `recurring_rule_pauses` solo excluye fechas dentro de `[paused_at, resumed_at)`, y `paused_at` es siempre `current_date` en el momento de pausar — nunca retroactivo;
54. dos confirmaciones concurrentes sobre el mismo `(rule_id, expected_date)` nunca pueden dejar más de un `financial_event` real activo, garantizado por `pg_advisory_xact_lock` adquirido antes de cualquier escritura;
55. `recurring_occurrence_events` es append-only: nunca se sobrescribe un evento existente, y nunca puede haber dos eventos económicamente activos (no revertidos) para la misma ocurrencia;
56. una recurrencia confirmada deja de contribuir como expectativa en Planeación en el instante en que existe su fila en `recurring_occurrences`, sin excepción y sin caso especial adicional por tipo de fuente;
57. `planned_cash_flows` nunca acepta un valor de `recurrence` distinto de `one_time` desde Fase 7A — reforzado en tres capas independientes (RPC, lectura, y el `CHECK` de la tabla), ninguna de las tres es la única línea de defensa;
58. la guarda de vigencia de `update_recurring_rule` nunca permite un `effective_from_date` que erosione o duplique una ocurrencia ya derivable bajo la versión actual — verificado explícitamente para monthly/semimonthly/biweekly, no solo argumentado.

## 9. Estado después de Fase 4B

Fases 4A–4B implementan compras MSI nuevas y la importación controlada de MSI personales ya iniciados: plan, calendario proyectado, pago histórico reportado separado del principal amortizado, integración incluido/no incluido con saldo inicial, statements, UI, reversión, auditoría, idempotencia y RLS. Personas, receivables, MSI de terceros/compartidos, presupuestos y conciliación siguen sin iniciar.

Tests permanentes incorporados: 3/6/12 MSI, mensualidad real, residuo en última cuota, límite de corte, primera mensualidad, importación 5 de 12, cuotas pagadas antes de Nexo, saldo inicial incluido/no incluido, gasto personal único, saldo/disponible sin doble conteo, progreso por statement pagado, pago parcial/completo, reversión dedicada, idempotencia y aislamiento A/B.

## 10. Estado después de Fase 5A

Implementado: personas activas/archivadas; compras personales, para otra persona o repartidas entre varias; receivables nominales por moneda; pagos parciales aplicados FIFO al saldo más antiguo; reversión, idempotencia, auditoría y RLS. La compra conserva un único impacto financiero en su cuenta o tarjeta, mientras `personal_amount` y las asignaciones determinan gasto personal y cuentas por cobrar.

Pruebas permanentes incorporadas: invariante de distribución exacta, compra para tercero sin gasto personal, varias personas, pago parcial FIFO, cobro sin ingreso, conservación de patrimonio económico, bloqueo de sobrepago, reversión de cobro, idempotencia y aislamiento A/B.

Pendiente para 5B o fases autorizadas: MSI de terceros/compartidos, periodos mensuales de cobro, estado compartible, saldo a favor por sobrepago, recordatorios y automatización.

## 11. Estado después de Fase 5B

Implementado: MSI de terceros y compartidos (`create_shared_installment_purchase`, `import_shared_historical_installment_plan`) con la misma UI de compra/MSI histórico que ya existía, ahora con reparto de persona; un cronograma de cobro por obligación (`receivable_due_items`) que asigna la fecha exigible de cada porción ya nominal en `receivables`/`installments`, sin crear principal nuevo; aplicaciones firmadas e inmutables de pago o saldo a favor sobre ese cronograma (`receivable_due_applications`), que a su vez mueven `receivable_entries` — la única fuente de verdad del saldo pendiente — de modo que el cronograma sigue siendo proyección, no un segundo motor; saldo a favor por persona y moneda con su propio libro (`person_credit_entries`), desacoplado del saldo de receivables; `get_person_collection_period` como contrato único de lectura que entrega, ya calculados, el pago del periodo, lo que falta, la fecha límite, la deuda total y el saldo a favor, consumido igual por la tarjeta de la lista de personas y por el detalle.

Corrección posterior verificada: la actividad de la persona (`contact_activity`) etiquetaba una aplicación de saldo a favor como si fuera una compra nueva, porque toda entrada que no fuera `person_payment` caía en la rama genérica "purchase". Ahora tiene su propia rama y etiqueta ("Saldo a favor aplicado"), sin bank movement asociado. `get_person_collection_period` también gana `installment_count` por concepto para poder mostrar "Mensualidad N de M" sin que el frontend vuelva a calcular el plazo del plan.

Corrección posterior verificada: `get_person_collection_period` gana `overdue_minor` por periodo (subconjunto de "a pagar este periodo" cuya fecha ya pasó) para poder mostrar "Vencido" sin que el frontend decida qué cuenta como vencido. `contact_activity` gana `personal_amount_minor` e `installment_count` en su rama de compras para poder distinguir "Compra compartida" / "Compra para [persona]" / "Compra a meses" sin inferirlo fuera de los datos ya existentes.

Corrección posterior verificada, encontrada al validar manualmente los escenarios de esta entrega: la previsualización de "Registrar pago" en el frontend comparaba el importe tecleado únicamente contra lo que falta del periodo actual para decidir si el excedente era saldo a favor. El dominio real reparte cualquier pago FIFO contra **toda** la deuda pendiente de la persona (incluidas mensualidades futuras de un MSI activo) antes de crear saldo a favor — confirmado registrando compras y pagos reales contra una reconstrucción limpia de las migraciones. La previsualización ahora distingue tres desenlaces: pago parcial, periodo pagado con el resto adelantando futuras obligaciones, y saldo a favor real solo cuando ya no queda nada pendiente. Ningún RPC cambió; el error estaba solo en la previsualización de React.

UI de Personas completada: tarjeta y detalle muestran "A pagar este periodo" con jerarquía visual por encima de "Te debe en total" (nunca como sustituto), "Vencido" cuando aplica, "Este periodo" con los conceptos exigibles tal como los entrega el cronograma, "Compras a meses" con la parte de la persona en cada plan (te debe, mensualidad actual, próximo corte, progreso), saldo a favor con acción de aplicarlo (previsualizando saldo disponible, cuánto se aplicará y qué queda pendiente después, sin crear movimiento bancario) y "Registrar pago" con previsualización correcta de pago parcial/periodo completo con adelanto/saldo a favor real.

Pruebas permanentes incorporadas: personas con MSI de tercero/compartido sin volver a duplicar principal ni gasto personal, reparto de cuotas persona por persona sin perder centavos, periodo consolidado con fecha límite derivada del corte de tarjeta correspondiente, vencido expuesto correctamente para fechas pasadas, pago parcial y sobrepago generando saldo a favor, aplicación de saldo a favor idempotente y sin segundo movimiento bancario, rechazo de aplicar saldo a favor sin obligación elegible, aislamiento A/B del cronograma y de la aplicación de crédito, la aplicación de saldo a favor visible en la actividad de la persona con la etiqueta correcta, y las compras MSI de la persona etiquetadas con su reparto y plazo correctos en esa misma actividad.

Pendiente, explícitamente fuera de este bloque: exportación de estado de persona en PDF/Excel/CSV. `record_person_statement_export` queda como infraestructura de auditoría ya preparada (recibe la intención, valida formato y persona, y audita), sin generar ningún archivo todavía. Se retoma como el subbloque final de 5B, después de validar manualmente el resto de esta fase.

## 12. Estado después de Fase 5C

Implementado: `get_person_statement`, una función nueva que llama a `get_person_collection_period` (sin duplicar su lógica de periodo) y agrega, leyendo el mismo ledger, el desglose de cada pago real en aplicado al periodo / adelantado a deuda futura / saldo a favor generado, comparando cada aplicación contra los conceptos que el propio periodo ya marcó como exigibles. Dos extensiones aditivas sobre `get_person_collection_period` y `receivable_due_item_balances`: `overdue_since` (fecha del vencido más antiguo) y `purchase_amount_minor` por concepto (el total de la compra detrás de la parte de la persona, para poder mostrar "de un total de $X" sin una segunda consulta).

Ruta `/personas/:id/estado` (alias `/people/:id/estado`): documento limpio con resumen (a pagar este periodo, fecha límite, te debe en total, pagado, falta, vencido si aplica, saldo a favor si aplica, siempre como cifras separadas), desglose "Este periodo" con cada concepto y su tipo (mensualidad o compra compartida), "MSI activos" con la parte de la persona por plan, y "Pagos recibidos" con el desglose exacto de cada pago. Toda la pantalla lee `src/lib/person-statement.ts` (`buildStatementDocument`), la misma capa que alimenta las tres exportaciones — no hay una segunda fuente de datos entre pantalla y archivo.

Exportaciones reales, no capturas de pantalla: PDF con `pdf-lib` (ya era dependencia, sin instalar nada nuevo) con paginación real, encabezado repetido, pie de página con fecha de generación y número de página, y texto seleccionable; Excel `.xlsx` real (OOXML) construido a mano y empaquetado con `fflate` (también ya era dependencia) en tres hojas — Resumen, Conceptos, Pagos — con celdas monetarias como número real con formato de moneda, no como texto; CSV con BOM UTF-8 para acentos correctos en Excel/Numbers. Ninguna exportación incluye UUID, nombres de tabla ni nombres de RPC. El modo de privacidad de la aplicación nunca alcanza a una exportación: `MoneyValue` (que sí lo respeta) solo se usa en pantalla, las exportaciones leen los importes crudos directamente.

Compartir usa la Web Share API con archivo cuando el navegador la soporta (`navigator.canShare`); si no está disponible, descarga el PDF normalmente. No se sube ningún archivo a Supabase Storage ni a ningún bucket — todo se genera y comparte localmente en el navegador. `record_person_statement_export` (ya existía, solo se conectó) audita cada exportación real (`person_statement_exported`: contact_id, periodo, formato, fecha) sin guardar los importes del documento en el evento de auditoría.

Decisión explícita sobre históricos (Fase 5C, §25 del encargo): **no se implementó selector de periodos anteriores.** `get_person_collection_period`/`get_person_statement` leen `outstanding_minor` como estado actual de cada `receivable_due_item`, no como una foto del pasado; pedir un `p_as_of_date` anterior desplaza qué corte se considera "vigente" pero no reconstruye cuánto estaba pagado en esa fecha real, porque lo pagado hoy también se refleja en fechas pasadas. Reconstruir un periodo histórico exacto necesitaría o (a) derivar el estado a partir de `receivable_due_applications`/`account_entries` filtrando por `created_at`, lo cual es posible pero no se implementó en este bloque, o (b) un snapshot inmutable guardado en el momento del cierre, que sería una fuente de verdad nueva y requiere decisión explícita del usuario antes de crearse. Por ahora el estado de persona muestra únicamente el periodo vigente; no existe un selector que simule históricos con filtros incorrectos.

Pruebas permanentes incorporadas: consolidación del estado para MSI compartido sin mostrar el importe completo de la mensualidad de tarjeta; pago parcial reduciendo periodo y deuda total en la cantidad exacta; sobrepago con MSI futuro pendiente adelantando esa deuda sin crear saldo a favor; saldo a favor real solo cuando se salda toda la deuda, sin nunca mostrar deuda negativa; rechazo de aplicar saldo a favor sin obligación elegible; dos monedas expuestas en bloques separados sin mezclarse; persona sin deuda abre su detalle sin error; aislamiento A/B de `get_person_statement`; y pruebas unitarias de los tres formatos de exportación verificando los valores financieros exactos que contienen (no solo que el archivo se genera), incluida paginación real del PDF.

Pendiente, fuera de alcance de este bloque: selector de periodos anteriores (ver decisión arriba), presupuestos, metas, reportes globales y salud financiera.

## 13. Estado después de Fase 6C

Implementado: `planned_cash_flows` (única tabla nueva, editable in-place, nunca un `financial_event`) y `get_financial_plan`, la única RPC de lectura de esta fase — `security definer stable`, parametrizada por `p_as_of_date` en cada rama, sin ninguna escritura. Todo lo demás que expone Planeación se deriva en el momento de fuentes ya existentes: `account_entries`/`goal_account_backing` para el saldo inicial, `card_statement_preview_balance`/`card_statements` para tarjetas, `get_budgets_for_period` para presupuestos, `goal_balances` más una simulación recursiva propia para metas, y `receivable_due_item_balances` para cobros de personas.

Verificado leyendo el cuerpo real de `card_statement_preview_balance` (no asumido, per instrucción explícita): ya excluye el `card_charge` de cualquier compra con un plan MSI activo y ya suma, aparte, únicamente la mensualidad cuyo `due_statement_date` coincide con el `statement_date` consultado — una sola cifra por corte no cerrado, sin duplicar nunca "compra normal + mensualidad" ni "mensualidad de este corte + mensualidad de un corte futuro". Esto simplificó la jerarquía de certeza de tarjetas de tres niveles a dos: statement cerrado (gana siempre que exista) o preview de ese corte exacto — nunca ambos.

El saldo inicial corrige explícitamente el diseño original: usa `goal_account_backing.backed_minor` por cuenta (respaldo real, ya nunca mayor que `max(saldo_real, 0)` por el invariante de 6B), no `saved_minor` nominal — así que el faltante de respaldo de una meta nunca vuelve negativa la liquidez disponible de una cuenta, solo se muestra aparte como información.

La simulación de metas (`projected_saved_minor`) vive dentro de una CTE recursiva de la misma llamada a `get_financial_plan`, sembrada con el `saved_minor` real y avanzada mes a mes sin tocar `goals` ni `goal_entries`; una meta pausada recomienda 0 sin avanzar, una archivada se excluye, y una meta sin fecha objetivo nunca tiene recomendación.

Las tres series de escenario (`base`, `planned`, `planned_with_collections`) se calculan juntas con funciones ventana sobre el neto mensual, cada una con su propio arrastre — nunca cruzadas — para que el frontend alterne entre Base/Planeado y el interruptor de cobros esperados sin una segunda consulta a Supabase.

Ruta `/planeacion` (alias `/planning`): selector de moneda (de las monedas con cuentas del usuario), horizonte de 3/6/12 meses, escenario Base/Planeado con interruptor aparte de cobros esperados, línea de tiempo mensual (saldo proyectado, o "Te faltarían aproximadamente $X" si es negativo, nunca oculto ni autocorregido), y detalle expandible por mes con lenguaje de consumidor — nunca términos internos como "preview", "backed_minor" o "planned_cash_flow" en pantalla. Gestión de flujos planeados (crear, editar, archivar, restaurar) vive en la misma página.

Pruebas permanentes incorporadas (`supabase/tests/financial_planning.test.sql`, casos A-AW): CRUD y validación de `planned_cash_flows`; aislamiento RLS; saldo inicial con respaldo real (nunca negativo por causa de una meta); jerarquía de tarjetas sin duplicar (preview antes de cerrar, statement después, nunca ambos, nunca una mensualidad aparte); presupuesto más flujo planeado categorizado sin exceder el límite; flujo sin categoría fuera de cualquier presupuesto; proyección recursiva de metas coherente y que deja de recomendar tras alcanzar el objetivo dentro de la simulación; arrastre independiente de las tres series de escenario; el interruptor de cobros esperados sin contaminar Base ni Planeado; recorte de día 31 sin arrastrarse a meses más largos; obligaciones o previews en cero sin fila visible; un flujo ya ocurrido sin volver a proyectarse; ninguna escritura al motor financiero real; y que cada agregado visible sea exactamente la suma de sus líneas.

Definición formal de `p_as_of_date` (ver DOMAIN_RULES.md §38 para el texto completo): no significa "reconstruye el saldo de las cuentas como existía ese día", significa "usa el estado financiero actualmente registrado y simula hacia adelante como si la fecha de referencia fuera `p_as_of_date`". Tres promesas exactas, ni más ni menos: (1) no hay snapshots históricos — el saldo real de las cuentas es siempre el saldo *actualmente registrado*, sin filtrar por fecha, porque Nexo no tiene ese mecanismo en ningún módulo; (2) una proyección no se promete reproducible dentro de seis meses si los datos reales cambiaron mientras tanto; (3) sí se promete determinismo estricto — mismo estado de base de datos y mismo `p_as_of_date` producen exactamente el mismo resultado (caso Z de `financial_planning.test.sql`). Esto no es una limitación nueva de 6C: es la misma característica que ya tenía el resto del dominio (5C §12 documentó la misma decisión para `get_person_collection_period`), aplicada aquí de forma consistente y explícita.

Pendiente, fuera de alcance de este bloque: patrimonio, valuaciones de inversión e indicadores de salud financiera (Fase 8); recurrencias/suscripciones completas con RRULE (movimientos recurrentes básicos llegaron en Fase 7A); conversión FX automática entre monedas dentro de una misma proyección.

## 14. Estado después de Fase 7A

Implementado: `recurring_rules` + `recurring_rule_versions` (identidad/ciclo de vida separados de los campos versionables — `update_recurring_rule` nunca reescribe una versión, siempre inserta una nueva con `effective_from_date`, protegida por una "guarda de vigencia" que impide borrar o duplicar una ocurrencia ya vencida/pendiente al editar frecuencia/día/importe/categoría/fuente). `recurring_rule_pauses` (append-only, siempre ancladas a `current_date`, nunca retroactivas). `recurring_occurrences` + `recurring_occurrence_events` (una ocurrencia solo existe al confirmar u omitir; el evento económicamente activo es una vista derivada, `recurring_occurrence_current_event`, nunca una columna sobrescrita — mismo principio que `card_statements`/`is_reversed` en `goal_entry_activity`).

`confirm_recurring_occurrence` es la pieza crítica de concurrencia: adquiere `pg_advisory_xact_lock` sobre `(rule_id, expected_date)` antes de resolver idempotencia o tocar cualquier tabla, así que dos confirmaciones concurrentes sobre el mismo slot se serializan ahí — nunca dependen de que un `unique` falle después de haber creado dinero real. El financial_event real, la fila de `recurring_occurrences` y la de `recurring_occurrence_events` se crean dentro de la misma llamada de función (la misma transacción), así que cualquier falla posterior revierte todo sin huérfanos, sin código de rollback explícito. Reconfirmar solo se permite cuando el único evento vivo de una ocurrencia ya fue revertido; con un evento activo, se rechaza.

`private.recurring_rule_occurrence_dates` es la única implementación del calendario (ocho frecuencias, sin RRULE), reutilizada tanto por `get_recurring_occurrences` (la UI) como por `get_financial_plan` (Planeación) — nunca dos cálculos distintos del mismo compromiso. El clamp de día reutiliza `card_effective_statement_date` sin lógica nueva; `biweekly` (aritmética de 14 días fija) y `semimonthly` (dos fechas de calendario) se mantienen genuinamente distintos, verificado explícitamente.

`planned_cash_flows` se acota a `one_time` en tres capas: la RPC (`create_planned_cash_flow`/`update_planned_cash_flow` rechazan cualquier otro valor), la lectura (`get_financial_plan` solo lee `one_time`), y ahora también el `CHECK` de la tabla — en una **segunda migración separada** (`20260830090000_phase_7a_lock_planned_cash_flows_one_time.sql`), aplicada después de que la primera ya migró todo lo existente ("migrar primero los datos, luego reemplazar el CHECK", nunca al revés). Auditado explícitamente: `authenticated` no tiene `GRANT` de escritura sobre esta tabla (solo `SELECT`; confirmado empíricamente — un intento directo devuelve "permission denied"), y el servicio de TypeScript solo hace `.select()` directo, todas las mutaciones pasan por RPC. El único rol que podría escribir `monthly` de nuevo es `service_role` (equivalente a acceso administrativo total, capaz de alterar cualquier constraint de todos modos) — el `CHECK` cierra ese hueco igualmente, sin debilitar la prueba de la migración: `scripts/test-db.sh` corre un checkpoint dedicado (`supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql`) justo entre las dos migraciones, en la única ventana donde una fila `monthly` genuina todavía se puede insertar, y ese archivo nunca vuelve a ejecutarse después. `private.migrate_planned_cash_flow_monthly_rows()` convierte cada fila `monthly` en su `recurring_rule` equivalente, ancla la idempotencia en `migrated_from_planned_cash_flow_id` (`unique`), y archiva — nunca borra — la fila vieja; la segunda migración la vuelve a invocar de forma defensiva antes de apretar el `CHECK`.

La integración con Planeación es un único `not exists`: la CTE `flow_occurrences` de `get_financial_plan` fusiona `planned_cash_flows` (`one_time`) con las ocurrencias derivadas de `recurring_rules` que todavía no tienen fila en `recurring_occurrences`. En cuanto se confirma o se omite, ese filtro la excluye de la derivación — si se confirmó, su efecto real ya llega por los mecanismos existentes (tarjetas, cuentas, presupuestos), sin ningún caso especial adicional.

Ruta `/recurrentes` (alias `/recurring`): "Próximos" (agrupado por fecha, con Registrar/Omitir), "Recurrentes activos", modal de creación en lenguaje de consumidor (nunca `recurrence_type`/`interval_count`/`effective_from_date` en pantalla), modal de confirmación con importe/fecha/fuente reales precargados pero editables sin afectar los próximos pagos, y detalle con historial real basado en `recurring_occurrence_activity` — nunca reconstruido regenerando la regla actual hacia atrás.

Pruebas permanentes incorporadas (`supabase/tests/recurring_transactions.test.sql` + el checkpoint `supabase/tests/_checkpoints/planned_cash_flows_prelock.test.sql`, casos A-BH): cubren cada punto del diseño aprobado, con especial atención a la atomicidad de la primera confirmación concurrente (advisory lock, nunca depender de que un `unique` falle tras crear dinero real), la trazabilidad append-only de reversión/reemplazo, la guarda de vigencia verificada letra por letra contra el ejemplo exacto de la auditoría de cierre (mensual, semimensual y quincenal), y la migración idempotente/auditable desde `planned_cash_flows` monthly con el `CHECK` ya cerrado. `supabase/diagnostics/phase_7a_pre_migration_check.sql` es un script de solo lectura, separado de las migraciones, para correr contra Supabase real antes de aplicar 7A y saber exactamente qué filas `monthly` van a convertirse.

Corrección sobre un reporte anterior: ese mismo reporte había afirmado que editar el día de corte el mismo mes en que ya venció una ocurrencia todavía no resuelta podía "mover silenciosamente" esa ocurrencia. Era una prosa incorrecta, no un límite real del código — verificado leyendo la guarda de nuevo y reproduciendo el ejemplo exacto (`renta día 1 → $12,000 pendiente el 1 → editar el 5 a día 10/$13,000`, caso BB de `recurring_transactions.test.sql`): la guarda **exige** que `effective_from_date` sea el día 1 de un mes futuro **y** que ese mes sea estrictamente posterior al mes de la última ocurrencia ya derivable bajo la versión actual (`NEXO_EFFECTIVE_FROM_MUST_BE_MONTH_START`/`NEXO_EFFECTIVE_FROM_TOO_EARLY`) — no existe ningún valor de `effective_from_date` que el usuario pueda elegir y que mueva o duplique una ocurrencia ya vencida. La corrección fue únicamente al texto del reporte, no al código.

Pendiente, fuera de alcance de esta fase (7B): detección automática de recurrencias desde histórico, ejecución automática, notificaciones, transferencias recurrentes, aportaciones recurrentes a metas, receivables recurrentes, RRULE/calendario empresarial complejo.
