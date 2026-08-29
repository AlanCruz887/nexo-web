# Nexo — Reglas financieras inquebrantables

Este documento contiene únicamente invariantes financieras. Si una implementación, interfaz, importación o automatización contradice una regla de este archivo, la implementación es incorrecta.

## 1. Convenciones monetarias

- `amount` es el importe financiero total del evento.
- `personal_amount` es únicamente la parte económica atribuible al usuario.
- Todo importe monetario persistido usa `bigint` en unidades menores y una moneda ISO 4217 explícita. La escala de la moneda determina cómo se presenta y valida; nunca se usa `float` ni coma flotante binaria.
- Cada cuenta y tarjeta tiene `currency`; el perfil tiene `base_currency`.
- El MVP no convierte monedas automáticamente. No se agregan monedas diferentes sin una tasa de cambio explícita, fechada y con procedencia.
- Cuando existan varias monedas, patrimonio y reportes muestran totales separados por moneda. `base_currency` es preferencia de presentación, no autorización para inventar FX.
- El invariante de asignación aplica únicamente a eventos de compra: `purchase_amount = personal_amount + suma(third_party_allocations)`.
- No se aplica directamente a pagos de tarjeta, transferencias, cobros, reembolsos, ajustes ni opening balances.
- Los importes de una compra y sus asignaciones no pueden ser negativos. Reembolsos y reversiones son eventos tipados, no compras con signos ambiguos.
- Cuando sea necesario derivar cuotas iguales, se redondea a la unidad menor mediante `round half up`; las primeras `n - 1` usan ese importe y la última cuota es el residuo exacto necesario para que la suma sea igual al principal. Si el banco informa una mensualidad real, prevalece `installment_amount` y la última cuota puede ajustarse para cerrar el principal exacto.

## 2. Compra personal

Para una compra completamente personal:

```text
amount = total
personal_amount = total
receivable = 0
```

Impacta el medio de pago por el total y el gasto/presupuesto personal por `personal_amount`.

## 3. Compra para otra persona

Para una compra 100 % de un tercero:

```text
amount = total
personal_amount = 0
receivable de la persona = total
```

La obligación con la cuenta o tarjeta aumenta por el total. El gasto personal no aumenta.

## 4. Compra compartida

Para una compra de 10,000 donde 3,000 corresponden al usuario y 7,000 a Carlos:

```text
amount = 10,000
personal_amount = 3,000
receivable Carlos = 7,000
```

La suma de todas las partes debe igualar exactamente el total antes de confirmar la operación.

La igualdad de asignaciones es específica del agregado compra. Ejemplos definitivos:

```text
Compra personal:
1,000 = 1,000 personal + 0 terceros

Compra para Carlos:
10,000 = 0 personal + 10,000 Carlos

Compra compartida:
10,000 = 3,000 personal + 7,000 Carlos
```

## 5. Flujo de efectivo e ingreso/gasto

- Un ingreso aumenta una cuenta y el ingreso personal.
- Un gasto pagado desde una cuenta reduce la cuenta y aumenta el gasto personal solo por `personal_amount`.
- Una compra con tarjeta aumenta el pasivo de tarjeta por `amount`; el gasto personal solo aumenta por `personal_amount`.
- Un pago recibido de una persona aumenta la cuenta receptora y reduce su cuenta por cobrar; no es ingreso.
- Un pago de tarjeta reduce la cuenta pagadora y el pasivo de tarjeta; no es gasto.
- Una transferencia reduce una cuenta y aumenta otra por el mismo valor; no es ingreso ni gasto.
- En el MVP, una transferencia directa requiere la misma moneda en origen y destino. Mover valor entre monedas requiere en el futuro una operación FX explícita, no una transferencia con conversión implícita.
- Un retiro o depósito entre efectivo y banco es una transferencia si ambos pertenecen al usuario.
- Los movimientos internos no consumen presupuesto.
- Para métricas personales, `personal_expense = personal_amount`. Esta regla aplica al dashboard, presupuestos, categorías, comparaciones mensuales, salud financiera y tasa de ahorro.
- El cash flow observa entradas y salidas financieras por el importe total que afectó cuentas, sin reclasificar transferencias, cobros o pagos de tarjeta como ingreso/gasto personal.
- En el MVP, el gasto personal de una compra MSI se reconoce una sola vez en `transaction_date` por su `personal_amount`; las mensualidades no vuelven a crear gasto.

## 6. Cuentas por cobrar

- Una asignación a tercero crea una cuenta por cobrar por el importe exacto asignado.
- Saldo por cobrar = principal creado - pagos aplicados - reembolsos/condonaciones explícitas - reversiones.
- El saldo por cobrar nunca puede quedar por debajo de cero por una asignación de pago normal.
- Un cobro debe estar vinculado a la cuenta que recibió el dinero.
- Los pagos pueden ser parciales, completos o adelantados. Un pago parcial reduce el pendiente exacto; una cuota solo cambia a `paid` cuando su pendiente llega a cero.
- La aplicación predeterminada es: vencidos más antiguos, cuota actual, futuras cuotas del mismo receivable/plan y, si aún sobra, saldo a favor de la persona. Cualquier aplicación manual debe ser explícita y auditable.
- Ningún excedente se pierde. `credit_balance` es el saldo a favor nominal de una persona, derivado de entradas de crédito inmutables. Representa un pasivo del usuario frente a esa persona, no ingreso.
- Aplicar posteriormente `credit_balance` a un receivable reduce simultáneamente el saldo a favor y la cuenta por cobrar, sin nuevo flujo bancario ni ingreso.
- Cobrar principal sustituye un activo por cobrar por un activo líquido y, por sí solo, no cambia el patrimonio.
- Una diferencia entre lo debido y lo recibido requiere un concepto explícito; no puede convertirse silenciosamente en ingreso, gasto o ajuste.

## 7. Tarjetas frente a cuentas

- Una cuenta es un activo del usuario; una tarjeta es un pasivo/línea de crédito.
- Una tarjeta nunca se modela como cuenta bancaria genérica.
- El límite de crédito no es saldo ni patrimonio.
- Saldo utilizado, crédito disponible, pago actual y acumulado del ciclo son métricas distintas.
- `crédito disponible = límite de crédito - saldo utilizado`, sujeto a cargos pendientes y reglas informativas del emisor.
- Un pago a tarjeta requiere una cuenta de origen y no modifica el gasto histórico de las compras pagadas.

## 8. Regla de corte

Cada ciclo es un intervalo semiabierto:

```text
cycle_start <= transaction_date < statement_date
```

Con día de corte 13:

```text
corte 13 agosto:
13 julio <= transaction_date < 13 agosto
```

Por tanto:

```text
12 agosto -> corte 13 agosto
13 agosto -> corte 13 septiembre
```

El límite superior siempre es exclusivo. La pertenencia se calcula con `transaction_date`, la fecha financiera local del MVP, no comparando timestamps UTC de forma accidental.

Si `statement_day` no existe en un mes, `statement_date` es el último día válido de ese mes. Ejemplos:

```text
statement_day = 31
abril -> 30 abril
febrero 2028 -> 29 febrero
```

El día de corte efectivo pertenece al siguiente ciclo. Con corte efectivo 30 de abril, una compra del 29 entra al corte del 30 y una compra del 30 entra al siguiente corte. Esta semántica solo puede cambiar mediante una migración explícita de dominio y datos.

## 9. Fecha límite

```text
due_date = statement_date + payment_days_after_statement
```

No se usa un día fijo mensual como fuente de verdad. En ausencia de una regla explícita del emisor, la suma es en días calendario y no se ajusta silenciosamente por fines de semana o festivos.

## 10. Statements

- Un estado de cuenta representa un ciclo concreto y no se confunde con el saldo total de tarjeta.
- Un statement cerrado es la fuente de verdad de `statement_balance`, `payment_to_avoid_interest`, `minimum_payment`, `amount_paid`, `remaining_due` y `payment_due_date`.
- `pago actual` es `remaining_due` del último statement cerrado aplicable.
- El ciclo abierto se presenta como `acumulado del ciclo`, nunca como pago requerido ni pago actual.
- `saldo utilizado` incluye todo el crédito ocupado, esté o no cortado.
- Un pago se asigna de forma explícita al saldo de uno o más statements o queda como crédito no asignado; nunca se cuenta dos veces.
- Cerrar un statement fija su periodo, fecha de corte, fecha límite y componentes. Correcciones posteriores se hacen mediante reversión/reclasificación auditable, no reescribiendo el pasado sin rastro.

## 11. MSI nuevos

- Un plan MSI conserva importe original, plazo, `installment_amount` real cuando se conozca, calendario, principal asignado y relación con la compra. No se asume siempre `original_amount / installment_count`.
- La suma de las mensualidades debe igualar el principal del plan. El redondeo sigue la regla de unidades menores de la sección 1 y la última cuota absorbe el residuo exacto.
- El plan no crea gasto repetido cada mes: el reconocimiento del gasto personal ocurre una sola vez según la política de reporte; las cuotas representan vencimiento/pago del pasivo.
- Una cuota no puede pagarse por encima de su saldo pendiente salvo que el excedente se aplique explícitamente a otras cuotas.
- Una compra MSI nueva utiliza la línea de crédito por el principal completo desde `transaction_date`. El saldo utilizado incluye todo el principal pendiente, mientras el statement incluye únicamente las cuotas que pertenecen a ese corte.
- El principal de una compra MSI nueva impacta la tarjeta exactamente una vez, mediante el evento de compra. `installment_plan` e `installments` distribuyen esa obligación entre statements, pero su impacto adicional en principal es cero.
- Nunca puede coexistir el cargo de compra y una segunda entrada del mismo principal generada por el plan. Para una compra nueva de 24,000 a 12 MSI: la tarjeta aumenta 24,000 al comprar; las cuotas de 2,000 organizan statements y no vuelven a sumar 24,000.

## 12. MSI históricos

Al importar un plan ya iniciado se conservan:

- importe original;
- total de mensualidades;
- mensualidad real;
- mensualidad actual;
- mensualidades ya pagadas;
- saldo pendiente;
- fecha original y próxima cuota.
- importe total pagado real reportado, cuando el usuario lo proporcione, aunque difiera del cálculo teórico.

Si el plan va en la cuota 5 de 12, las cuotas 1, 2, 3 y 4 quedan como `paid_before_import`, la 5 como actual/pendiente según fecha y las 6 a 12 como futuras. Las cuotas importadas mantienen trazabilidad, pero no crean pagos bancarios históricos ficticios.

El importe pagado real reportado se conserva como evidencia independiente del principal pagado. El principal pagado usado para saldos debe reconciliarse con el importe original y el `remaining_principal`; diferencias por cargos, redondeos o información del banco no se descartan ni se convierten automáticamente en principal.

Siempre debe cumplirse:

```text
remaining_principal = original_principal - principal_paid
remaining_principal = suma(saldo pendiente de cuotas no pagadas)
```

## 13. MSI y baseline

- Si un MSI histórico está incluido en el saldo inicial: `included_in_opening_balance = true` y su impacto adicional en tarjeta es cero.
- Si no está incluido, el impacto adicional es `remaining_principal`.
- Nunca se agrega el importe original completo cuando ya existen cuotas pagadas.
- Cambiar esta marca después de asentar el plan requiere una reclasificación o reversión auditable para evitar duplicidad.
- Estas igualdades son invariantes permanentes y deben probarse tanto para importación inicial como para reintentos y reversiones.
- La regla unificada de impacto es:

```text
MSI nuevo:
card principal impact = purchase event
installment plan additional impact = 0

MSI histórico incluido en opening balance:
additional impact = 0

MSI histórico no incluido en opening balance:
additional impact = remaining_principal
```

- Nunca se permite `purchase charge + same installment principal`, porque duplicaría el saldo utilizado.

## 14. Personas y MSI

Un MSI puede ser personal, de un tercero o compartido. Para una compra de 24,000 totalmente para Carlos a 12 MSI:

```text
card obligation = 24,000
personal expense = 0
receivable Carlos = 24,000
installment principal = 24,000
```

- La porción de cada persona se distribuye en cuotas sin perder la igualdad con el principal asignado.
- Pagar una cuota de una persona reduce tanto su cuenta por cobrar como la obligación cobrable correspondiente, y aumenta la cuenta receptora.
- El cobro no reduce por sí mismo el pasivo de tarjeta; solo un pago de tarjeta lo hace.

## 15. Periodo y estado de cobro de una persona

Para las obligaciones exigibles de una persona en varias tarjetas:

```text
period_start = fecha de corte relevante más temprana
period_end = fecha límite relevante más tardía
```

Solo participan tarjetas donde la persona tenga obligaciones en el periodo. El documento compartible muestra únicamente cuotas del periodo, compras de contado exigibles, pagos aplicados y pendiente del periodo. No muestra siguientes periodos, todas las cuotas futuras ni deuda futura total. Esa información puede existir solo en la vista interna de Nexo.

## 16. Baseline de tarjeta

- El baseline representa deuda existente antes del punto desde el cual Nexo controla movimientos detallados.
- Su política financiera obligatoria es una de: `current_bank_balance`, `after_last_statement` o `specific_date`.
- Tiene fecha efectiva, importe y evidencia/origen explícitos.
- Los movimientos incluidos en el baseline no vuelven a incrementar el saldo.
- Un MSI importado incluido en baseline aporta cero adicional.
- Los eventos anteriores al baseline pueden conservarse como historia con efecto `historical_non_impacting`; no generan entradas que vuelvan a modificar el saldo inicial.
- Un pago de tarjeta de un periodo anterior, ya excluido del baseline, no reduce nuevamente el saldo Nexo. Puede registrarse como evidencia `historical_non_impacting`.

El saldo debe poder reconstruirse como:

```text
baseline
+ cargos nuevos
+ principal pendiente de MSI importados no incluidos
- pagos de tarjeta
- reembolsos/créditos
+/- reversiones y ajustes explícitos
= saldo utilizado
```

## 17. Patrimonio

- Patrimonio personal por moneda = activos líquidos + receivables nominales - pasivos de tarjeta - saldos a favor de personas y otros pasivos propios.
- El límite de crédito no forma parte del patrimonio.
- Cobrar a un tercero mueve valor de receivable a banco y no cambia el patrimonio.
- Una compra completamente para un tercero crea simultáneamente obligación financiera y cuenta por cobrar equivalentes; no es gasto personal ni riqueza nueva.
- Condonaciones, incobrables, comisiones o diferencias sí pueden afectar patrimonio, pero requieren un evento y categoría explícitos.
- Las cuentas de inversión necesitan una valuación fechada; no se inventa rendimiento a partir de flujos.
- Para el MVP, `receivable value = outstanding nominal amount`; no se aplican descuentos por riesgo, probabilidad de impago ni valor presente.
- No se suman patrimonios de distintas monedas sin FX explícito. En ausencia de FX se presentan totales separados.

## 18. Presupuestos y categorías

- Un presupuesto de gasto consume únicamente `personal_amount`.
- Las porciones de terceros no consumen presupuesto.
- Los pagos de tarjeta, cobros de personas y transferencias no consumen presupuesto.
- Reportes por categoría de gasto usan la categoría y el `personal_amount` de la compra original.
- Reembolsos personales reducen el gasto/presupuesto de forma explícita y conservan vínculo con el origen cuando sea posible.

## 19. Salud financiera

- Gasto personal e ingreso personal se calculan solo con eventos clasificados como tales.
- Compras para terceros no aumentan gasto personal.
- Sí pueden aumentar utilización de tarjeta, reducir liquidez o elevar riesgo de cobro.
- Receivables no se presentan como efectivo disponible.
- La exposición y antigüedad de receivables pueden reducir un indicador de salud como factor de riesgo separado, sin cambiar su valuación nominal en patrimonio.
- Un indicador compuesto debe exponer sus componentes y periodo; no puede ocultar deuda o compensarla silenciosamente con crédito disponible.

## 20. Conciliación

- La conciliación compara saldos en la misma fecha, moneda y alcance.
- Debe mostrar saldo del banco, saldo comparable, saldo Nexo y diferencia.
- Una diferencia no genera ajustes automáticos.
- Resolver una diferencia requiere vincular, importar, corregir, revertir o crear un ajuste explícito y auditable.
- Conciliar no modifica la naturaleza ingreso/gasto de los eventos.

## 21. Recurrentes y forecast

- Una regla recurrente no es un movimiento realizado.
- Cada ocurrencia confirmada se registra una sola vez y conserva vínculo con su regla.
- El forecast separa valores planeados y realizados.
- Proyecciones no alteran saldos reales, patrimonio real ni presupuesto ejecutado.

## 22. Importaciones

- Las filas en staging no afectan saldos.
- Solo la confirmación atómica crea eventos productivos.
- La detección de duplicados debe considerar fuente, cuenta/tarjeta, fecha, importe, descripción normalizada e identificador externo cuando exista.
- Una coincidencia sugerida nunca se inserta ni descarta sin quedar resuelta en la revisión.
- Reimportar el mismo lote no puede duplicar eventos confirmados.

## 23. Reversión, edición y auditoría

- Un evento financiero asentado no se elimina.
- Revertir crea efectos iguales y opuestos, vinculados al evento original, y restaura todas las proyecciones afectadas sin borrar historia.
- Un evento solo puede tener una reversión efectiva; reintentos deben ser idempotentes.
- Editar un hecho financiero material se implementa como reversión más reemplazo o como versión equivalente con trazabilidad completa.
- La auditoría no altera saldos y no puede editarse desde el cliente.

## 24. Atomicidad e idempotencia

Son operaciones indivisibles:

- compras para terceros o compartidas;
- creación/importación de MSI;
- cobros y asignación de pagos de personas;
- pagos de tarjeta;
- transferencias;
- reversiones;
- confirmación de importaciones.

O se registran todos sus efectos, o no se registra ninguno. Cada comando acepta una clave idempotente por usuario para que un reintento no duplique dinero.

La clave se identifica de forma única por `(user_id, idempotency_key)`. El registro conserva además `command_type`, payload canónico y resultado. El mismo reintento con el mismo comando y payload devuelve el resultado original; reutilizar la clave para otro comando o payload falla. La inserción única participa en la misma transacción PostgreSQL que el evento: competidores esperan el resultado confirmado y una ejecución fallida revierte también la reserva.

## 25. Cuentas y movimientos base

- El saldo de una cuenta es `sum(account_entries.amount_minor)` para esa cuenta. El saldo inicial se materializa una sola vez como evento `opening` y entrada firmada; `accounts.opening_balance_minor` conserva el baseline declarado, pero no existe un `current_balance` editable.
- Un ingreso personal verdadero crea una entrada positiva y se clasifica como `income`. Transferencias, cobros futuros de personas, reembolsos y pagos de tarjeta no reutilizan esa clasificación.
- En Fase 2, un gasto simple cumple `personal_amount_minor = amount_minor`; la futura división con terceros se aplicará únicamente al agregado compra.
- Una transferencia entre cuentas genera dos entradas bajo un solo evento: salida negativa y entrada positiva por el mismo importe y moneda. Su suma global es cero y no aumenta ingreso, gasto personal ni presupuesto.
- Sin FX explícito, origen y destino de una transferencia deben tener la misma moneda.
- Archivar una cuenta la excluye de nuevos movimientos y selectores normales, pero no elimina su saldo, sus entradas ni su actividad histórica. Restaurarla solo vuelve a habilitarla; no recrea el opening balance ni modifica entradas existentes.
- Los eventos y entradas asentados son inmutables. Editar un movimiento simple crea reversión más reemplazo; eliminarlo registra la acción de producto `transaction_deleted`, pero materializa una reversión; revertir una transferencia crea entradas opuestas para ambos lados. Editar notas de transferencia agrega una nota versionada sin cambiar principal ni cuentas.
- Duplicar un movimiento crea únicamente un borrador con importe, cuenta, categoría y descripción precargados y fecha de hoy. No produce evento ni entrada hasta que el usuario confirma.
- Fuentes de verdad de Fase 2: saldo = `account_balances`; actividad vigente = `account_activity`; gasto personal = `personal_amount_minor` de gastos vigentes; ingreso = importe de eventos `income` vigentes; cash flow = entradas firmadas de cuenta por fecha. La UI consume estos contratos y no redefine clasificaciones financieras.

## 26. Fechas de compra e importación

- En el MVP, `transaction_date` es la única fuente de verdad para ciclos, presupuestos, cash flow y reportes por fecha.
- El modelo queda preparado para `purchase_date` y `posted_date`, ambas opcionales. No se inventa ninguna de ellas.
- Una importación futura puede usar `posted_date` para asignar statement únicamente cuando el proveedor bancario la proporcione y declare que esa fecha gobierna el corte.
- Cambiar la fecha que determina un statement requiere una regla versionada y una migración explícita de dominio; nunca cambia silenciosamente la semántica histórica.

## 27. Implementación de tarjetas en Fase 3A

- `card_baselines.baseline_balance_minor` es el punto inicial comparable. En `after_last_statement` equivale a saldo bancario reportado menos el statement excluido.
- `card_entries.amount_minor` es firmado: cargos aumentan pasivo; pagos y refunds lo reducen. Solo `effect_scope = impacting` modifica saldo utilizado; `historical_non_impacting` conserva evidencia sin reaplicar saldo.
- El ciclo abierto no se persiste como deuda requerida. `card_current_cycles` lo deriva con `cycle_start <= transaction_date < statement_date`.
- Un statement cerrado captura el saldo utilizado al corte. Deuda anterior no pagada sigue dentro del ledger y, por tanto, se traslada al snapshot siguiente; cerrar no borra ni liquida deuda.
- Estado persistido: `closed` mientras `remaining_due > 0`, `paid` cuando llega a cero. `open` está reservado por el contrato, pero el ciclo abierto actual es una proyección.
- Sobrepago puede producir saldo utilizado negativo y disponible superior al límite. Fase 3A lo muestra sin inventar una clasificación; su aplicación operativa queda para la fase de pagos.
- La automatización futura podrá invocar el mismo RPC idempotente de cierre. Fase 3A no incluye cron ni Edge Function.

## 28. Operaciones de tarjeta en Fase 3B

- Una compra simple crea un evento `card_charge` con `personal_amount_minor = amount_minor` y una entrada positiva de tarjeta. No crea entrada bancaria.
- La fecha de statement se obtiene exclusivamente con `card_statement_for_date(transaction_date, statement_day)`. Editar fecha o tarjeta revierte y reemplaza el evento, por lo que el ciclo se recalcula en backend.
- Una operación impactante requiere `transaction_date >= card_baselines.baseline_date`. Antes de esa fecha podría duplicar deuda incluida en el saldo inicial y se rechaza. La UI lo explica como “Controlada en Nexo desde”, sin exponer jerga de baseline.
- Fase 3B no ofrece todavía “Registrar solo como historial”: aunque el ledger conoce `historical_non_impacting`, no se convierte una compra normal a histórica de forma implícita ni se expone un flujo incompleto.
- Una compra o reembolso cuyo statement correspondiente ya está cerrado no se edita ni revierte silenciosamente. Se exige una corrección/reembolso posterior que preserve el snapshot.
- Un pago crea, atómicamente, una entrada negativa en la cuenta origen y otra negativa en la tarjeta. `personal_amount_minor = 0`; no es ingreso ni gasto.
- Los pagos se asignan primero a statements pendientes por `payment_due_date` y luego `statement_date`, del más antiguo al más reciente. Cada aplicación es una entrada firmada e inmutable.
- Revertir un pago restaura cuenta, saldo de tarjeta y cada `remaining_due` afectado en la misma transacción.
- El importe de pago que excede todos los statements pendientes no se pierde: queda como crédito no asignado y puede producir saldo utilizado negativo/disponible superior al límite.
- Un reembolso crea `card_refund`, una entrada negativa de tarjeta y reduce gasto personal neto por su `personal_amount_minor`; nunca crea un evento `income`.
- Los reembolsos vinculados acumulados no pueden exceder la compra original. Un reembolso sin vínculo explícito sigue siendo un crédito auditable de tarjeta.
- Saldo utilizado sigue siendo una sola fórmula: baseline + compras impactantes - pagos - reembolsos +/- reversiones y ajustes.
- `financial_activity` es la fuente compartida del timeline global. Mantiene `source_type`, cuenta/tarjeta, categoría, importe firmado y contexto; ninguna pantalla reclasifica pagos como gasto.
- El filtro Origen tiene tres estados exclusivos: Todos, Cuentas y Tarjetas. El selector contextual solo existe para Cuentas o Tarjetas; cambiar de origen limpia el identificador incompatible.
- Instrumentos archivados permanecen en el timeline histórico, pero no aparecen en selectores operativos. Un control explícito “Incluir archivadas” puede incorporarlos a filtros históricos, agrupados y etiquetados.

## 29. Cierre cronológico de estados

- El cierre normal selecciona siempre el corte vencido más antiguo que todavía no tenga statement, comenzando después de `card_baselines.baseline_date`.
- Un corte solo es elegible cuando su fecha efectiva es menor o igual a la fecha actual. El ciclo abierto nunca puede cerrarse anticipadamente mediante el flujo normal.
- Cerrar un statement habilita cronológicamente el siguiente corte vencido; no se permiten huecos ni cierres fuera de orden.
- `statement_balance_minor` no usa el saldo utilizado total de la tarjeta. Se calcula con la contribución del baseline únicamente cuando el baseline pertenece a ese primer ciclo, más cargos, reembolsos y ajustes impactantes del intervalo semiabierto `[cycle_start, statement_date)`.
- Pagos de tarjeta no forman parte del acumulado de compras del ciclo. La deuda no pagada de un statement anterior permanece en el `remaining_due_minor` de ese statement y no se duplica como principal dentro del statement siguiente.
- Movimientos revertidos no participan en el saldo preliminar ni en el snapshot cerrado.

## 30. Pagos anticipados de tarjeta

- Para cada pago, `applied_amount_minor` es la suma realmente asignada a statements cerrados y `advance_amount_minor = payment_amount_minor - applied_amount_minor`.
- Si no existe deuda cerrada pendiente, el pago completo es anticipado. Si solo una parte cubre deuda cerrada, únicamente el excedente es anticipado.
- Mientras el statement futuro no exista, el pago anticipado no tiene `statement_id`. Su asociación visual se deriva de `transaction_date` con el motor central y apunta al ciclo abierto/próxima fecha de corte.
- Compras netas del ciclo = compras − reembolsos. Los pagos anticipados se muestran separados y no reducen esta métrica.
- Impacto neto del ciclo = compras − reembolsos − pagos anticipados. El saldo utilizado sigue siendo la proyección global del ledger, no esta métrica visual.
- Al cerrar el ciclo, el RPC asigna los anticipos disponibles del periodo al nuevo statement sin crear eventos ni entradas financieras adicionales. El statement conserva `statement_balance`, `amount_paid` y `remaining_due` por separado.
- Un `minimum_payment_minor` no proporcionado permanece `NULL` y se muestra como “No registrado”; nunca se sustituye automáticamente por el saldo completo.

## 31. Compras nuevas a MSI — Fase 4A

- Una compra nueva a MSI crea exactamente un evento `card_charge` y una entrada impactante por el principal completo. `installment_plans` e `installments` tienen impacto adicional de tarjeta igual a cero.
- El gasto personal se reconoce una sola vez en la compra por `personal_amount_minor = original_amount_minor`; una mensualidad no vuelve a crear gasto.
- La primera mensualidad pertenece al primer statement que contiene `transaction_date`, calculado por `card_statement_for_date`. El día efectivo de corte comienza el siguiente statement.
- Las mensualidades siguientes avanzan por meses calendario y cada fecha usa `card_effective_statement_date`, incluida la regla de último día válido para cortes 29–31.
- El importe regular se calcula con división entera en unidades menores o conserva la mensualidad real ingresada. La última mensualidad absorbe el residuo y la suma es exactamente el principal; ninguna cuota puede ser cero o negativa.
- Los statements futuros no se crean por anticipado. `due_statement_date` es una proyección; al cerrar un statement, su balance incluye la mensualidad programada y excluye el cargo principal MSI completo.
- El progreso no avanza por fecha. Una mensualidad se considera pagada únicamente cuando su statement existe y queda `paid` mediante pagos normales de tarjeta.
- Un pago parcial que deja `remaining_due_minor > 0` no cubre ninguna mensualidad MSI del statement para efectos de progreso. Cuando los pagos reales llevan el statement completo a `remaining_due_minor = 0`, sus mensualidades pasan a pagadas. No existe un comando ni un evento “pagar mensualidad”.
- Estados visibles del cronograma: `futura` cuando el statement aún no existe, `pendiente` cuando existe y conserva saldo, `pagada` cuando el statement quedó cubierto y `revertida` cuando se revirtió el plan. Los nombres internos de persistencia no se exponen.
- El saldo utilizado sigue derivándose del baseline y las entradas impactantes. No suma `remaining_principal` del plan porque ese principal ya vive en el cargo original.
- Solo descripción, categoría y notas se editan mediante revisiones de metadata. Principal, tarjeta, fecha y plazo son inmutables; cambiarlos exige reversión y una compra nueva.
- La reversión MSI es dedicada y atómica: crea la entrada opuesta al cargo completo, marca el plan `reversed` y cancela sus mensualidades futuras. Si existe un statement relacionado ya cerrado, se bloquea para exigir una corrección explícita.
- Fase 4A bloquea reembolsos vinculados a MSI. No redistribuye mensualidades sin una política de dominio aprobada.
- MSI de terceros y compras compartidas permanecen fuera de alcance hasta fases autorizadas.

## 32. MSI ya empezados / históricos — Fase 4B

- Un plan importado se identifica con `origin = historical`. No crea compras, pagos bancarios ni gasto personal retroactivos; su evento de importación usa `personal_amount_minor = 0`.
- Si el usuario indica que va en la mensualidad `X`, se deriva `paid_before_nexo_count = X - 1`. Esas cuotas se conservan como `paid_before_nexo`; la cuota `X` queda pendiente o futura según su statement y las posteriores quedan futuras.
- `remaining_principal_minor = original_amount_minor - principal_paid_before_nexo_minor`. Nunca se deriva como mensualidades restantes por mensualidad reportada.
- `reported_paid_amount_minor` conserva el dinero real reportado por el banco y puede diferir de `principal_paid_before_nexo_minor`; ambos datos son independientes.
- La mensualidad reportada se conserva en `reported_amount_minor`. El principal asignado a las cuotas usa unidades menores exactas y ajusta la última para cerrar el principal sin alterar el valor reportado.
- Si `included_in_opening_balance = true`, el principal pendiente ya vive en el baseline y el efecto adicional es cero. Si es `false`, se crea una sola entrada impactante por el principal pendiente. Nunca se agrega el importe original completo ni se vuelve a sumar cada mensualidad.
- El statement proyectado incorpora la mensualidad reportada correspondiente. Para un plan incluido en el saldo inicial, su integración con el primer statement administrado sustituye esa porción del baseline por la mensualidad exigible, sin duplicar principal ni producir un segundo impacto en saldo utilizado.
- Las mensualidades pagadas antes de Nexo no avanzan por movimientos ficticios. Desde la importación, el progreso de las cuotas actuales y futuras depende exclusivamente de que el statement real quede completamente cubierto; un pago parcial no marca la cuota como pagada.
- Solo descripción, categoría y notas admiten edición directa auditable. Corregir importe, plazo, avance, principal pagado o inclusión en saldo inicial exige revertir la importación y crear una nueva.
- Revertir un MSI histórico cancela su cronograma y revierte únicamente su impacto adicional: cero si estaba incluido en el saldo inicial o el principal pendiente si no estaba incluido. El baseline nunca se reescribe.

## 33. Personas y receivables — Fase 5A

- Solo una compra distribuida cumple `purchase_amount = personal_amount + sum(third_party_allocations)`. La regla no se aplica globalmente a pagos, cobros, transferencias, reembolsos, ajustes ni saldos iniciales.
- Una compra puede tener cero, una o varias asignaciones a personas. La cuenta o tarjeta recibe el impacto completo una sola vez; las asignaciones no duplican el movimiento financiero.
- `personal_amount` es la única parte que alimenta gasto personal. Cada asignación crea un receivable nominal en la moneda de la fuente financiera.
- El pendiente se deriva de entradas inmutables: cargo positivo, pago negativo y reversión compensatoria. No se edita como saldo almacenado.
- Un pago de persona aumenta la cuenta receptora y reduce receivables en la misma moneda, del más antiguo al más reciente. No es ingreso, gasto ni cambia patrimonio: banco `+X`, receivable `-X`.
- Los pagos parciales conservan el pendiente exacto. En Fase 5A se bloquea un importe superior al saldo pendiente; `credit_balance` se implementará únicamente en una fase posterior.
- Una compra distribuida con pagos aplicados no puede editarse ni revertirse con el flujo simple de 5A. Se exige un flujo futuro que reasigne o revierta los cobros sin perder trazabilidad.
- Archivar una persona impide asignarle compras nuevas, pero conserva historial, receivables y posibilidad de registrar cobros pendientes.
