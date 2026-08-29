# Nexo — Plan de implementación por fases

## 1. Principio de ejecución

Cada fase termina con software verificable y documentación actualizada. No se inicia la siguiente si fallan invariantes financieras, aislamiento RLS o reconstrucción de saldos. Las fases agregan capacidades sobre el mismo núcleo; no crean modelos paralelos para cuentas, tarjetas, personas o reportes.

Estado actual: **Fase 5B completada salvo exportación: cronograma de cobro por periodo, saldo a favor y MSI de terceros/compartidos con UI de Personas terminada. Exportación (PDF/Excel/CSV) queda como último subbloque, pendiente de validación manual del resto.**

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

### Fase 4 — Personas, compras compartidas y receivables — Completada (incluye 5B, salvo exportación)

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

### Fase 6 — Presupuestos, recurrencias y suscripciones

Objetivo: convertir datos confiables en control del gasto y automatización predecible.

Alcance:

- presupuestos por periodo/categoría;
- consumo por `personal_amount`;
- recurrencias en todas las frecuencias contratadas;
- suscripciones y ocurrencias vinculadas;
- reglas automáticas básicas con preview.

Verificación:

- porciones de terceros no consumen presupuesto;
- ocurrencias no se duplican;
- desactivar una regla no borra historial;
- preview y aplicación producen el mismo resultado validado.

### Fase 7 — Conciliación e importaciones

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

### Fase 8 — Planificación, forecast, patrimonio y salud

Objetivo: proyectar el futuro y evaluar posición personal a partir de hechos verificados.

Alcance:

- planeado frente a realizado;
- forecast de liquidez, tarjetas, cuotas y cobros;
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
27. aplicar saldo a favor sin ninguna obligación pendiente elegible se rechaza en vez de crear un movimiento sin destino.

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
