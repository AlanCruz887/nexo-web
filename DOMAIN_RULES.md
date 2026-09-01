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
- Los pagos parciales conservan el pendiente exacto. En Fase 5A se bloqueaba un importe superior al saldo pendiente; desde Fase 5B el excedente se conserva como saldo a favor (ver §34) en vez de rechazarse.
- Una compra distribuida con pagos aplicados no puede editarse ni revertirse con el flujo simple de 5A. Se exige un flujo futuro que reasigne o revierta los cobros sin perder trazabilidad.
- Archivar una persona impide asignarle compras nuevas, pero conserva historial, receivables y posibilidad de registrar cobros pendientes.

## 34. Periodo de cobro, saldo a favor y MSI de terceros/compartidos — Fase 5B

- "Te debe en total" y "a pagar este periodo" son proyecciones distintas y ninguna sustituye a la otra en ningún lugar de la UI, export o reporte. El total es la suma de todo lo pendiente de la persona en esa moneda; el periodo es solo lo exigible ahora (lo vencido más lo del corte/fecha relevante más próximo).
- El cronograma de cobro (`receivable_due_items`) reparte por fecha exigible el nominal que ya existe en `receivables`/`installments`; nunca crea principal nuevo. La suma de los items de una obligación es exactamente su nominal original.
- Una compra o MSI para otra persona o compartido sigue las mismas reglas de Fase 5A/4A: el impacto en cuenta o tarjeta ocurre una sola vez; `personal_amount` y las asignaciones determinan gasto personal y receivable. Un MSI compartido reparte cada mensualidad entre las personas en la misma proporción que el principal, con la última cuota de cada persona absorbiendo su propio residuo; ninguna mensualidad recrea principal ya nominal.
- Una aplicación (de pago o de saldo a favor) sobre el cronograma es una entrada firmada e inmutable. Cada aplicación mueve, en la misma transacción, la entrada agregada correspondiente en `receivable_entries` — la única fuente de verdad del saldo pendiente. El cronograma es una proyección de cuándo cobrar esa deuda, no una segunda contabilidad.
- Un pago o una aplicación de saldo a favor se reparte FIFO por fecha exigible contra **todas** las obligaciones pendientes de la persona en esa moneda, no solo las del periodo actual. Si el importe excede lo exigible ahora pero todavía queda deuda futura (por ejemplo mensualidades de un MSI activo), el excedente adelanta esas obligaciones futuras; no se convierte en saldo a favor. Solo el remanente que sobra después de saldar absolutamente todo lo pendiente se guarda como saldo a favor.
- `apply_person_credit` rechaza (`NEXO_CREDIT_WITHOUT_ELIGIBLE_OBLIGATION`) aplicar saldo a favor cuando no queda ninguna obligación pendiente a la que aplicarlo; el saldo a favor permanece disponible hasta que exista una obligación nueva.
- El saldo a favor vive en un libro propio por persona y moneda (`person_credit_entries`), desacoplado del saldo de receivables. Aplicarlo reduce lo pendiente igual que un pago, pero no crea movimiento bancario, no toca cuentas ni tarjetas, y no puede exceder ni el saldo a favor disponible ni la obligación pendiente elegible.
- La actividad de una persona incluye la aplicación de saldo a favor con su propia etiqueta ("Saldo a favor aplicado"), nunca como si fuera una compra nueva ni un pago bancario. Cada compra en esa actividad se etiqueta según su propio evento ya existente ("Compra compartida" si tiene gasto personal, "Compra para [persona]" si es 100% de la persona, "Compra a meses" si tiene un plan MSI asociado); ninguna etiqueta se infiere fuera de esos datos.
- Lo "vencido" de un periodo es el subconjunto de sus conceptos cuya fecha exigible ya pasó y que todavía tiene saldo pendiente; es parte de "a pagar este periodo", nunca una tercera cifra independiente de la deuda total o del periodo.
- Pago de persona y pago de tarjeta siguen siendo eventos distintos sin automatismo entre ellos (ver §28 y §33): un pago de persona nunca reduce saldo de tarjeta, y viceversa.
- El progreso de un plan a meses para una persona ("N de M pagadas") mide cuánto de la parte de ESA persona ya está cubierta por sus pagos o saldo a favor aplicado; es independiente de si el statement de la tarjeta ya fue pagado. Pagar el statement de la tarjeta no marca automáticamente como pagada la parte de ninguna persona, y viceversa.
- La exportación de estado de persona (PDF/Excel/CSV) no está implementada. `record_person_statement_export` solo audita la intención (persona, periodo, formato); no genera archivo.

## 35. Estado de persona y exportación — Fase 5C

- El estado de una persona (`get_person_statement`) es una lectura, no un cálculo nuevo: llama a `get_person_collection_period` para el periodo y agrega, del mismo `receivable_due_applications`, cuánto de cada pago real cayó en ese periodo, cuánto adelantó deuda futura y cuánto se volvió saldo a favor. Ningún importe se recalcula fuera de esa función.
- Un pago sobre lo exigible del periodo se explica siempre según lo que el dominio ya decidió: si todavía hay deuda futura de esa persona (por ejemplo mensualidades siguientes de un MSI), el excedente se muestra como adelantado a esa deuda, nunca como saldo a favor. Solo se llama saldo a favor lo que sobra después de saldar toda la deuda pendiente.
- El desglose "Este periodo" de un concepto de MSI muestra la parte de la persona (`amount_minor`), nunca el importe completo de la mensualidad de la tarjeta; puede mostrar también el total de la compra (`purchase_amount_minor`) como referencia, pero la cifra financiera principal de la persona sigue siendo su propia parte.
- Un estado, su pantalla y sus tres exportaciones (PDF, Excel, CSV) muestran exactamente las mismas cifras, leídas de la misma estructura (`buildStatementDocument`). Ninguna exportación redondea, recalcula ni infiere un dato que el dominio no entregó.
- Cada moneda de una persona vive en su propio bloque en pantalla y en su propia sección/fila en cada exportación. Nunca se suman monedas distintas en una sola cifra ni se aplica conversión automática.
- Una exportación real siempre muestra los importes completos, sin importar si el modo de privacidad de la aplicación está activo en pantalla; ese modo solo oculta la pantalla, nunca el archivo generado.
- Ninguna exportación incluye UUID, nombres de tabla, nombres de RPC ni metadatos internos de auditoría. Solo incluye la relación financiera entre el usuario y esa persona: nunca saldos de cuentas propias, límites de tarjeta, patrimonio ni compras de otras personas.
- `record_person_statement_export` se registra únicamente cuando una exportación se generó realmente (el archivo se produjo del lado del cliente); el evento de auditoría guarda persona, periodo y formato, nunca los importes del documento.
- Compartir un estado usa la Web Share API del navegador cuando existe soporte para compartir archivos; si no existe, se ofrece la descarga normal del mismo archivo. No se sube ningún archivo a un bucket público ni a un endpoint sin autenticación.
- El estado de persona muestra únicamente el periodo vigente. `get_person_collection_period`/`get_person_statement` leen el estado *actual* de cada obligación, no una foto histórica; por eso no existe todavía un selector de periodos anteriores (ver ARCHITECTURE.md).

## 36. Presupuestos — Fase 6A

- Un presupuesto consume únicamente `personal_amount`; nunca el `amount` total de una compra. La parte de terceros nunca consume presupuesto, sin excepción.
- El gasto presupuestado se deriva exclusivamente de dos fuentes ya existentes, nunca de una tabla de gasto nueva:
  - no-MSI: `financial_activity` (`expense`/`card_charge`/`card_refund`), excluyendo cualquier `card_charge` que pertenezca a un `installment_plans.status = 'active'`;
  - MSI: `installments` con `status = 'scheduled'` de un plan `active`, una fila por mensualidad.
- **Una mensualidad MSI pertenece al mes de `installments.due_statement_date`** — el primer día de ese mes, sin restar ni aproximar. No se usa `transaction_date` de la compra para atribuir mensualidades a un periodo; `transaction_date` solo gobierna el reconocimiento de gasto no-MSI (compra personal, compra compartida sin plan, reembolso).
- La parte personal de una mensualidad es:

  ```text
  personal_installment_minor = installments.principal_minor
    - sum(receivable_due_items.amount_minor para ese installment_id)
  ```

  Nunca un ratio nuevo (`original_amount_minor / installment_count`), nunca una tabla `installment_allocations`: es el complemento exacto del reparto a terceros que Fase 5B ya construyó y probó (`create_installment_receivable_due_items`), con el mismo residuo acumulado en la última cuota. Siempre `0 <= personal_installment_minor <= installments.principal_minor`.
- **Invariante anti doble conteo**: para una compra MSI activa, el presupuesto nunca puede mostrar a la vez el `personal_amount_minor` completo del `card_charge` de compra Y las mensualidades derivadas de sus `installments`. Una compra MSI activa siempre está representada por exactamente una de las dos fuentes (mensualidades), nunca por ambas.
- MSI histórico: solo `installments.status = 'scheduled'` (la mensualidad actual y las futuras desde que Nexo controla el plan) contribuye a presupuestos. Las cuotas `paid_before_nexo` tienen impacto presupuestario cero — nunca se reconstruye gasto personal de meses anteriores al control de Nexo, igual que nunca se reconstruye saldo de tarjeta para esas cuotas.
- Un presupuesto recurrente tiene vigencia histórica explícita: cambiar su límite nunca reescribe los meses ya resueltos con la versión anterior. Un cambio de límite crea una **nueva versión** (`effective_from_month` nuevo), nunca un `UPDATE` sobre el límite de una versión ya vigente en el pasado. Para un mes M, el límite recurrente que aplica es el de la versión con el `effective_from_month` más reciente que sea `<= M` (y cuyo `effective_to_month`, si existe, sea `>= M`).
- Una excepción de un mes específico (`period_month`) gana sobre cualquier resolución recurrente para ese mes exacto; el mes siguiente vuelve automáticamente al recurrente vigente, sin ninguna fila adicional.
- Dejar de presupuestar una categoría desde un mes en adelante se hace cerrando la vigencia de la versión recurrente actual (`effective_to_month` = el último mes en que debe seguir aplicando), nunca archivando esa fila: archivar una versión recurrente directamente borraría su validez también para los meses pasados que ya la usaron.
- Un reembolso directo (`create_card_refund`) sobre una compra que pertenece a un plan MSI **activo** se rechaza (`NEXO_REFUND_NOT_ALLOWED_FOR_ACTIVE_MSI`): un reembolso parcial no puede redistribuir un cronograma de mensualidades ya construido. La forma correcta de deshacer una compra MSI sigue siendo `reverse_installment_purchase`, que revierte el cargo completo y cancela las mensualidades restantes de forma atómica.
- Un reembolso normal (no ligado a MSI) reduce el presupuesto correspondiente por su propio `personal_amount_minor`, que en la implementación actual siempre es igual a su `amount_minor` — el reembolso mismo no prorratea según el reparto de la compra original que reembolsa.
- Una reversión (de una compra simple, de tarjeta, o de un plan MSI completo) elimina su impacto presupuestario porque el evento revertido deja de aparecer en `financial_activity`, y un plan MSI revertido deja de tener `status = 'active'`, así que sus mensualidades dejan de contribuir también.
- Categoría de una compra MSI para presupuestos: se usa `financial_events.category_id` del evento de compra, igual que para cualquier `card_charge` en `financial_activity`. Editar posteriormente la categoría de un plan MSI (`installment_plan_metadata_revisions`) no se refleja todavía en presupuestos — limitación conocida, no corregida en 6A porque tampoco está corregida para `financial_activity` en general.
- Nunca se agregan monedas distintas: cada presupuesto pertenece a una sola `currency`, y el gasto de una categoría en una moneda nunca se suma con el de otra moneda de la misma categoría.

## 37. Metas de ahorro — Fase 6B

- Una meta nunca es ingreso ni gasto. Una aportación o un retiro nunca crea `financial_events.kind in ('income','expense')`.
- El progreso de una meta (`saved_minor`) es siempre `sum(goal_entries.amount_minor)` — nunca un campo mutable. Cada aportación, retiro o reversión es una fila nueva, append-only; `goal_entries` es inmutable (mismo trigger `reject_financial_mutation` que el resto de los libros firmados).
- `goal_entries.account_id` no es informativo: identifica la cuenta real que respalda esa reserva. Una aportación virtual está limitada por `available_for_goals = saldo_real_de_la_cuenta - reservas_vigentes_contra_esa_cuenta` en el momento de reservar, verificado con el mismo bloqueo `FOR UPDATE` sobre la fila de `accounts` que ya usan `create_transaction`, `create_transfer`, `create_person_payment` y `create_card_payment` — sin mecanismo de bloqueo nuevo. Dos metas nunca pueden reservar simultáneamente el mismo saldo.
- Una aportación virtual no crea `account_entries`, no cambia el saldo real de ninguna cuenta y no cambia el patrimonio. Un retiro virtual tampoco toca `account_entries`.
- Una aportación o retiro **real** (`p_move_real_money = true`) reutiliza el motor de transferencias existente (mismo `financial_events.kind = 'transfer'`, dos `account_entries` que suman cero, mismo orden de bloqueo `ORDER BY id` entre las dos cuentas para evitar deadlocks con `create_transfer`), atómico con la fila de `goal_entries` que referencia el `financial_event_id` resultante.
- `saved_minor` (progreso registrado) nunca cambia por un gasto o retiro ajeno a la meta, aunque reduzca el saldo real de la cuenta que la respalda. `backed_minor` (cuánto de ese progreso sigue cubierto por el saldo real actual) es una cifra separada, calculada en lectura, que puede ser menor que `saved_minor` — nunca se oculta esa diferencia ni se ajusta `saved_minor` automáticamente para que coincidan.
- El respaldo (`backed_minor`) se distribuye entre las metas que comparten una cuenta por FIFO determinista, usando la antigüedad de cada reserva **todavía vigente** (`occurred_on`, `created_at`, `id`) — nunca la fecha de la primera aportación histórica de la meta contra esa cuenta. Una reserva retirada por completo y vuelta a aportar recibe una prioridad nueva, no la de la reserva antigua. Invariante permanente: `0 <= backed_minor <= saved_minor` por meta, y la suma de `backed_minor` de todas las metas que comparten una cuenta nunca excede `max(saldo_real_de_esa_cuenta, 0)`.
- Una cuenta con saldo real `<= 0` no tiene capacidad disponible para nuevas reservas. Nexo no impide que una cuenta tenga saldo negativo (ni en 6B ni antes); una meta no cambia ese comportamiento general.
- `linked_account_id` (a nivel meta) es solo la cuenta destino/origen por defecto para movimientos reales — nunca implica que todo el saldo de esa cuenta pertenece a la meta. `goal_entries.account_id` (a nivel movimiento) es la cuenta que respalda esa reserva concreta, y coincide con `linked_account_id` únicamente cuando esa fila fue una transferencia real.
- Un retiro virtual con cuenta explícita libera solo la reserva de esa cuenta. Sin cuenta explícita, libera FIFO entre las reservas vigentes de la meta (posiblemente varias filas, una por cuenta tocada), sin perder nunca la trazabilidad de qué cuenta quedó liberada.
- Una reversión es siempre append-only: inserta una fila compensatoria que conserva el `account_id` original; nunca edita ni borra. Una misma fila no puede revertirse dos veces. Una contribución no puede revertirse si un retiro posterior ya consumió parte de su reserva — evita la ambigüedad de revertir una reserva parcialmente usada. Revertir una fila con transferencia real revierte también esa transferencia, atómicamente.
- No existe `status = 'completed'`. "Meta alcanzada" es una etiqueta derivada (`saved_minor >= target_minor`), nunca almacenada; una meta puede superar el 100% sin truncarse, y deja de mostrarse como alcanzada de forma natural si un retiro posterior baja el progreso por debajo del objetivo.
- `target_minor`, `target_date`, `name`, `icon` y `linked_account_id` se editan in-place vía `update_goal` — no requieren versionado histórico como los presupuestos recurrentes, porque el historial que sí es inmutable es `goal_entries`, no el objetivo declarado.
- `meta.currency = cuenta_de_respaldo.currency = cuenta_vinculada.currency`, siempre, sin conversión automática.
- Archivar una meta (`archived_at`) conserva `goal_entries` intacto. Archivar la cuenta que respalda una aportación histórica no la elimina del detalle; sí bloquea nuevas reservas contra esa cuenta.

## 38. Planeación financiera — Fase 6C

- Planeación es una **proyección de liquidez**, nunca contabilidad. `get_financial_plan` es `stable` y de solo lectura: no crea `financial_events`, `account_entries`, `card_statements`, `installments`, `goal_entries`, `budgets` ni `receivable_entries`, en ninguna rama. La única tabla nueva de esta fase (`planned_cash_flows`) es una intención declarada por el usuario, nunca un movimiento real, y nunca se convierte en uno automáticamente.
- Toda la lógica depende de `p_as_of_date` explícito, nunca de `current_date` implícito — ni siquiera indirectamente vía una vista que sí dependa de él (`card_summaries`, `card_current_cycles` y el `recommended_monthly_minor`/`months_remaining` de `goal_balances` quedan explícitamente fuera de esta fase por esa razón; 6C recalcula esas dos cifras de metas de forma parametrizada).
- **Definición formal de `p_as_of_date` (sin ambigüedad):** `p_as_of_date` **no** significa "reconstruye el saldo de las cuentas tal como existía históricamente ese día". Significa: *usa el estado financiero actualmente registrado y simula hacia adelante como si la fecha de referencia fuera `p_as_of_date`*. De ahí se derivan tres promesas explícitas, y solo estas tres:
  1. **No prometemos snapshots históricos.** El saldo real de las cuentas (`account_entries`, sin filtrar por fecha) es siempre el saldo *actualmente registrado*, sea cual sea `p_as_of_date` — Nexo no tiene, en ningún módulo, un mecanismo de saldo reconstruido a una fecha pasada.
  2. **No prometemos reproducir dentro de seis meses una proyección antigua** si los datos reales cambiaron en el ínterin (una cuenta nueva, un gasto real, una meta archivada). Cada llamada a `get_financial_plan` refleja el estado de la base de datos en el momento en que se ejecuta, no el estado que tenía cuando se generó una proyección anterior con el mismo `p_as_of_date`.
  3. **Sí prometemos determinismo:** con el mismo estado de base de datos y el mismo `p_as_of_date`, dos llamadas consecutivas producen exactamente el mismo resultado, sin excepción (caso Z de `financial_planning.test.sql`). Todo lo demás que sí depende de `p_as_of_date` — qué corte de tarjeta es "el próximo", cuántos meses le quedan a una meta, qué ocurrencias de un `planned_cash_flow` caen dentro del horizonte — se recalcula puramente a partir de él, nunca de `current_date`.
- **Saldo inicial**: `saldo_en_cuentas` es la suma de `account_balances` de cuentas activas de esa moneda. `apartado_respaldado` es `goal_account_backing.backed_minor` agrupado por cuenta — nunca `saved_minor` nominal. `disponible_sin_comprometer = saldo_en_cuentas - apartado_respaldado`, calculado también por cuenta individual antes de sumar. Como 6B garantiza `backed_minor <= max(saldo_real, 0)` por cuenta, `disponible_sin_comprometer` de una cuenta nunca es negativo por causa de una meta — una cuenta ya sobregirada se queda sobregirada, sin que una meta lo empeore ni lo oculte. El faltante de respaldo (`saved_minor - backed_minor` por meta) se muestra aparte, informativo, y nunca resta la liquidez de nuevo ni genera una salida futura automática.
- **Tarjetas — una sola obligación por corte**: para cada `statement_date` relevante, si existe un `card_statements` cerrado se usa únicamente su `remaining_due_minor`; si no existe, se usa únicamente `card_statement_preview_balance(card_id, statement_date)`. Nunca se suman ambos, y nunca se agrega una mensualidad MSI por separado cuando ya está contenida en uno de los dos — `card_statement_preview_balance` ya excluye el `card_charge` de una compra MSI activa y ya incluye, por separado, únicamente la mensualidad cuyo `due_statement_date` coincide exactamente con ese `statement_date`; para un corte más lejano cuyo ciclo ni siquiera ha empezado a acumular, la misma función se reduce naturalmente a solo esa mensualidad conocida (el gasto no-MSI de un ciclo que no ha comenzado es, correctamente, cero — nunca se inventa gasto futuro no-MSI). La obligación de un corte se atribuye al mes de su `payment_due_date` (`card_due_date(statement_date, payment_days_after_statement)`), nunca al mes del propio `statement_date`. Un corte cerrado con `remaining_due_minor = 0`, o un preview en cero, no genera una fila visible de obligación — pero sigue sumando correctamente (cero) al total del mes.
- **`planned_cash_flows` vs. presupuestos**: `category_id` (nullable) solo tiene efecto en una salida (`amount_minor < 0`). Para esa categoría/mes: `planned_categorized = Σ|monto|` de las ocurrencias futuras categorizadas; `flexible_additional = max(available_minor - planned_categorized, 0)`, donde `available_minor` viene sin modificar de `get_budgets_for_period` (ya neto del gasto real y del MSI de ese mes — 6C nunca reconstruye `budget_period_spend`). La presión total de esa categoría es `planned_categorized + flexible_additional`, que nunca excede el límite salvo que la propia salida planeada ya lo exceda por sí sola (nunca se sobrepasa el límite por sumar el flujo planeado *encima* del disponible completo). Un flujo con `category_id is null`, o una entrada positiva (con o sin categoría), nunca participa en esta cuenta — es una línea "Planeado" independiente.
- **Metas — simulación recursiva no persistida**: `get_financial_plan` nunca escribe en `goals` ni `goal_entries`. `projected_saved_minor` arranca en el `saved_minor` real a `p_as_of_date` y, mes a mes, solo dentro de esta llamada, avanza sumando la recomendación de ese mes — nunca vuelve a leer `saved_minor` real para los meses siguientes. `months_remaining` se calcula una sola vez al inicio (misma fórmula que 6B pero parametrizada por `p_as_of_date`) y decrece un mes por iteración, con piso de 1. Una meta `paused` recomienda 0 todos los meses sin avanzar su proyección; una meta archivada se excluye por completo; una meta sin `target_date` nunca tiene recomendación; una meta cuyo `target_date` ya pasó concentra todo lo que falta en el mes actual (mismo piso de 1 mes que 6B), sin dividir entre meses artificiales.
- **Cobros de personas**: nunca se leen como ingreso. Se agrupan directamente desde `receivable_due_item_balances` (misma cifra ya neta de pagos y conciliaciones que usa el estado de cuenta por persona) por mes de `payment_due_date`, sin recorrer el RPC por-contacto uno por uno. Una compra compartida en tarjeta sigue exigiendo el monto **completo** en Obligaciones, sin importar que exista un cobro esperado paralelo — son dos pesos distintos que nunca se cancelan entre sí ni se dan por garantizados.
- **Escenarios, independientes desde el mes 0**: Base = saldo inicial + entradas planeadas − salidas planeadas − obligaciones de tarjeta (sin presupuestos ni metas). Planeado = lo mismo, además − flexible adicional de presupuestos − aportaciones recomendadas de metas. Planeado con cobros = Planeado + cobros esperados de ese mes. Las tres series arrancan del mismo saldo inicial real pero cada una arrastra **su propio** cierre como apertura del mes siguiente — el cierre de una nunca es la apertura de otra. El toggle de cobros esperados solo afecta a la serie "planeado con cobros"; nunca contamina Base ni Planeado.
- Nada se autocorrige: un cierre proyectado negativo se muestra tal cual, nunca se trunca a cero ni se oculta.
- Cada agregado de la respuesta (obligaciones de tarjeta, flexible de presupuestos, recomendación de metas, cobros esperados) viene acompañado de las líneas exactas que lo componen — el frontend nunca resta ni suma nada por su cuenta, solo muestra.

## 39. Movimientos recurrentes — Fase 7A

- Una regla recurrente es una expectativa, nunca un hecho: crearla o editarla nunca genera `financial_events`, `account_entries` ni `card_entries`. Solo `confirm_recurring_occurrence`, reutilizando el motor real (`create_transaction`/`create_card_purchase`), produce un movimiento — idéntico al que el usuario habría creado a mano.
- `planned_cash_flows` queda exclusivamente para intenciones de una sola vez desde esta fase: `create_planned_cash_flow`/`update_planned_cash_flow` rechazan cualquier valor de `recurrence` distinto de `one_time` (`NEXO_PLANNED_CASH_FLOW_RECURRENCE_DEPRECATED`), y `get_financial_plan` solo lee filas `one_time`. Toda recurrencia vive en `recurring_rules`. Nunca puede existir el mismo compromiso futuro representado simultáneamente en ambas tablas.
- **Versionado, no edición in-place**: los campos que afectan el calendario o el dinero (`amount_minor`, `category_id`, `frequency`, `day_of_month`, `day_of_month_secondary`, `account_id`/`card_id`) viven en `recurring_rule_versions`, append-only — `update_recurring_rule` siempre inserta una versión nueva con `effective_from_date`, nunca reescribe una existente. `name` y `end_date` son cosméticos y se editan in-place en `recurring_rules`. Una ocurrencia confirmada u omitida nunca vuelve a leer la regla — su propio snapshot (`expected_amount_minor`, `category_id`) es la fuente de verdad para siempre, por eso editar la regla después nunca puede reescribir su historia (a diferencia de los presupuestos de 6A, aquí no hace falta ninguna resolución "vigente para este mes" en el momento de mostrar el historial).
- **Guarda de vigencia**: `update_recurring_rule` exige que `effective_from_date` sea posterior a la última ocurrencia ya vencida/pendiente bajo la versión actual — normalizado al inicio de un mes futuro para frecuencias de familia mensual (para no producir dos ocurrencias del mismo compromiso dentro del mes de transición), o simplemente posterior a esa fecha exacta para `weekly`/`biweekly`. Es una validación de escritura (usa `current_date` real, igual que `close_card_statement`'s `NEXO_STATEMENT_NOT_DUE` — nunca `p_as_of_date`), así que nunca puede borrar ni duplicar una ocurrencia que el calendario ya había hecho derivable antes de la edición.
- **Ocurrencias derivadas vs. persistidas**: una fila en `recurring_occurrences` existe únicamente al confirmar o al omitir — todo lo demás (próxima, pendiente, vencida) se calcula en el momento vía `private.recurring_rule_occurrence_dates`, consciente de versiones y de pausas, nunca almacenado. Mismo principio que `card_statements` (no existe hasta que cierras).
- **Calendario mínimo, sin RRULE**: `weekly`/`biweekly` son aritmética de días fija (7/14) anclada en `start_date` de la regla; las frecuencias de familia mensual (`monthly`/`bimonthly`/`quarterly`/`semiannual`/`annual`/`semimonthly`) caminan mes a mes desde el mes de `start_date` al paso correspondiente (1/2/3/6/12), reutilizando `card_effective_statement_date` para el clamp de día — cero lógica de fechas nueva. `semimonthly` usa dos días de calendario fijos (`day_of_month`/`day_of_month_secondary`); usar `31` como segundo día es la forma deliberada de expresar "último día del mes" reaprovechando el mismo clamp, sin inventar un centinela. `biweekly` nunca se comporta como `semimonthly` ni viceversa — son mecanismos distintos, nunca intercambiables.
- **Pausas**: `pause_recurring_rule` siempre pausa desde `current_date` (nunca acepta una fecha pasada como parámetro) — por construcción, una ocurrencia ya vencida antes de pausar nunca puede quedar dentro del intervalo pausado. `recurring_rule_pauses` es append-only (una fila por pausa, `resumed_at` se cierra al reactivar); el generador de calendario resta todos los intervalos pausados del rango solicitado — reactivar nunca genera "atrasados" ficticios para el hueco pausado, porque ese hueco nunca se derivó en primer lugar.
- **Confirmación**: la fuente se resuelve con prioridad `fuente explícita de esta confirmación > fuente predeterminada de la versión > rechazar (NEXO_RECURRING_RULE_HAS_NO_SOURCE)`. Elegir una fuente al confirmar nunca modifica la regla — solo se guarda en el snapshot del evento (`recurring_occurrence_events.account_id`/`card_id`). Un ingreso nunca puede usar tarjeta como fuente (`NEXO_INCOME_CANNOT_USE_CARD`).
- **Atomicidad de la primera confirmación**: `confirm_recurring_occurrence` y `omit_recurring_occurrence` adquieren `pg_advisory_xact_lock(private.recurring_occurrence_lock_key(rule_id, expected_date))` como la primera instrucción de la función, antes de resolver idempotencia, antes de cualquier `select`, y antes de `create_transaction`/`create_card_purchase`/cualquier `insert` — dos confirmaciones concurrentes sobre el mismo slot se serializan ahí, nunca dependen de que un `unique` falle después de haber creado dinero real. La clave es un solo `md5` de 64 bits sobre una cadena namespaced con delimitadores de longitud fija (`'nexo.recurring_occurrence|rid|<uuid>|date|<fecha>'`), no dos `hashtext` de 32 bits combinados por separado. Todo lo demás (financial_event real, `recurring_occurrences`, `recurring_occurrence_events`) ocurre dentro de la misma llamada de función = la misma transacción: cualquier falla posterior (por ejemplo, la cuenta se archivó entre crear la regla y confirmar) revierte todo sin dejar huérfanos, sin código de rollback explícito.
- **Reversión y reemplazo, append-only**: `recurring_occurrence_events` nunca se sobrescribe. El evento económicamente activo de una ocurrencia es una vista derivada (`recurring_occurrence_current_event`, mismo patrón que `is_reversed` en `goal_entry_activity`) — el más reciente cuyo `financial_event_id` no está revertido. Reconfirmar una ocurrencia está permitido únicamente cuando su único evento vivo ya fue revertido; con un evento todavía activo, se rechaza (`NEXO_OCCURRENCE_ALREADY_CONFIRMED`) — nunca pueden coexistir dos eventos activos para la misma ocurrencia.
- **Anti-doble-conteo con Planeación, un solo interruptor**: la CTE `flow_occurrences` de `get_financial_plan` fusiona `planned_cash_flows` (`one_time`) con las ocurrencias derivadas de `recurring_rules` que **todavía no tienen fila** en `recurring_occurrences`. En cuanto una ocurrencia se confirma u omite, ese `not exists` la excluye de la derivación — si se confirmó, su efecto real ya llega por las vías existentes (`card_statement_preview_balance`/`card_statements` para tarjetas, saldo real de cuentas, `budget_period_spend` para presupuestos), sin ningún caso especial adicional.
- **Ingresos y personas/metas/transferencias**: un ingreso recurrente confirmado crea `income` real, nunca antes. Personas/receivables recurrentes y aportaciones recurrentes a metas quedan fuera de 7A explícitamente. Transferencias recurrentes también quedan fuera — Planeación agrega todas las cuentas de una moneda en un solo saldo, así que una transferencia entre dos cuentas propias no cambiaría ningún número que Planeación ya muestra hoy.

## 40. Captura rápida por Atajos — dominio y autenticación (Fase 7C-A)

**Solo dominio y SQL. Sin Edge Function, sin capa HTTP, sin UI — eso es 7C-B.**

- **El motor financiero nunca se duplicó**: `create_transaction`/`create_card_purchase` se extrajeron a `private.create_transaction_for_user(p_user_id, ...)`/`private.create_card_purchase_for_user(p_user_id, ...)` — el cuerpo es literalmente el mismo, con `command_user_id := private.require_user()` sustituido por `command_user_id := p_user_id`. Los RPC públicos quedaron como envoltorios de dos líneas (`private.require_user()` → `private.*_for_user(...)`); misma firma, mismos grants, mismo comportamiento, mismos códigos de error, misma idempotencia — verificado con el mismo `financial_planning`/`accounts_movements_rls`/`card_transactions_rls`/`budgets`/`goals`/`recurring_transactions` de siempre, sin tocar ni una aserción.
- **`shortcut_tokens`**: token personal revocable, nunca una sesión de Supabase ni `service_role` en el dispositivo. Formato `nexo_shortcut_<43 chars base64url>`, 32 bytes aleatorios generados en el servidor (`extensions.gen_random_bytes(32)`, dentro de la propia RPC de creación — nunca en el cliente). Solo se guarda `sha256(token)` (`token_hash`, `check` de 64 hex); el valor plano se devuelve una única vez en la respuesta de `create_shortcut_token` y nunca vuelve a ser recuperable — ni siquiera por `list_shortcut_tokens`, que solo expone `id/name/scopes/created_at/last_used_at/expires_at/revoked_at`. SHA-256 sin salt es correcto aquí: un input de 256 bits de entropía real ya es inmune a tablas arcoíris/precómputo, el salt solo defiende inputs adivinables como contraseñas.
- **`create_shortcut_token` deliberadamente NO usa `private.resolve_financial_command`**: ese mecanismo promete "misma clave + mismo payload → mismo resultado", la garantía correcta para dinero, pero incorrecta aquí — lo único que un reintento legítimo no puede recuperar es justamente el token plano (nunca se almacena). Forzar idempotencia aquí devolvería una ilusión de "mismo resultado" sin el secreto real, o ningún secreto en absoluto. Un doble-submit simplemente crea dos tokens, revocables sin costo — nunca un movimiento de dinero duplicado. `revoke_shortcut_token` sí es idempotente vía el mecanismo estándar (revocar es naturalmente repetible: `revoked_at = coalesce(revoked_at, now())`).
- **Scopes reales desde ya**: `shortcut:options:read`, `shortcut:transactions:write`, columna `text[]` con `check` cerrado al conjunto conocido. Todo token nuevo recibe ambos por defecto en 7C-A (no hay selector en UI todavía), pero `private.resolve_shortcut_token(token_hash, required_scope)` comprueba membresía real en cada llamada — nunca un `true` fijo esperando a que 7C-B lo active.
- **`private.resolve_shortcut_token`**: recibe únicamente el hash, jamás el token plano — el hasheo ocurre en el llamador (en 7C-B, en la Edge Function, con Web Crypto, antes de que Postgres vea nada). Verifica existencia, `revoked_at is null`, `expires_at`, y el scope, en ese orden; es una función pura sin efectos secundarios — `last_used_at` se actualiza en el llamador (`execute_shortcut_transaction`), no aquí, para que una simple resolución fallida de scope no se cuente como "uso" del token.
- **`public.execute_shortcut_transaction` es el único punto de entrada de ejecución, `service_role`-only** (revocado de `anon`/`authenticated`; ni siquiera visible para PostgREST vía `apikey` normal). Resuelve el token, y para `source_type='account'`/`'card'` llama exclusivamente a `private.create_transaction_for_user`/`private.create_card_purchase_for_user` — nunca escribe `financial_events`/`account_entries`/`card_entries` por su cuenta. El ownership de la cuenta/tarjeta se valida **dentro** de esas funciones (`where id = ... and user_id = command_user_id`), contra el `user_id` resuelto del token — no hay una comprobación de pertenencia paralela que pueda desincronizarse.
- **Idempotencia**: `shortcut_execution_id` se mapea a `p_idempotency_key = 'shortcut:' || uuid`, reutilizando `private.resolve_financial_command` sin cambios — mismo UUID + mismo payload → mismo evento devuelto; mismo UUID + payload distinto → `NEXO_IDEMPOTENCY_CONFLICT`, sin tocar el ledger.
- **Por qué `execute_shortcut_transaction` devuelve `(ok, event_id, error_code)` en vez de lanzar una excepción en el camino de rechazo de dominio**: una excepción no capturada aborta toda la transacción que envuelve la llamada RPC — en producción, la transacción implícita de una sola llamada HTTP. Si esa transacción se aborta, se pierde también la fila de auditoría de error recién insertada dentro del manejador de excepción interno, dejando la auditoría exactamente "incoherente" (el requisito explícito que esto debía evitar). Por eso solo los rechazos previos a resolver el token (source_type inválido, execution_id nulo, o el propio `resolve_shortcut_token`) siguen lanzando de forma dura — ahí no existe todavía ningún `token_id` contra el cual auditar nada. Todo lo que ocurre después de resolver el token (ownership, archivado, categoría inválida, conflicto de idempotencia) se captura, se audita, y se **retorna** como `ok=false`, nunca se relanza.
- **`private.shortcut_token_usage`**: auditoría separada de `financial_commands` a propósito — nunca se le mete metadata de Atajos al payload que `resolve_financial_command` compara, porque cambiaría la semántica de idempotencia del motor real. A diferencia de `audit_events` (solo-inserción), esta tabla se actualiza por `upsert` sobre `unique(token_id, shortcut_execution_id)`: un reintento correctivo (falla → éxito) corrige la fila existente, nunca crea una segunda; y una fila que ya dice `success` nunca se degrada a `error` por un reintento con payload distinto (ese reintento es rechazado, pero el hecho de que la ejecución original sí tuvo éxito no se borra).
- **Rate limiting**: `private.shortcut_rate_limit_windows` + `private.check_shortcut_rate_limit(bucket_key, limit)` — ventana fija por minuto, incremento atómico vía `insert ... on conflict do update ... returning`, sin memoria de proceso ni Deno KV. Desde 7C-B está conectado: `execute_shortcut_transaction` y `get_shortcut_transaction_context` comparten el bucket `'tx:' || token_id` (30/min); `get_shortcut_options` usa su propio bucket `'options:' || token_id` (30/min), separado a propósito para que una ráfaga de lecturas nunca consuma el presupuesto de escrituras ni viceversa. Ver también §41 para el bucket de tokens inválidos, que vive del lado de la Edge Function.
- **Revocación**: nunca borra ni altera `financial_events`/`account_entries`/`card_entries`/`recurring_occurrence_events` ya creados por ese token — solo cierra `revoked_at`, y toda llamada futura con ese hash falla con `NEXO_SHORTCUT_TOKEN_REVOKED` antes de tocar cualquier dato financiero.

## 41. Capa HTTP de Atajos — Edge Functions (Fase 7C-B)

**Flujo exacto**: Atajo de iPhone → HTTPS → Edge Function (Deno) → SHA-256 del token dentro de la función → RPC estrecha `service_role`-only (nunca una tabla financiera directa) → `private.*_for_user` (el mismo motor que usa la app web) → respuesta JSON humana. **Sin JWT de impersonación en ningún punto** — decisión ya cerrada y auditada antes de 7C-A; esta fase la respeta sin reabrirla.

- **Postgres nunca recibe el token en texto plano.** `supabase/functions/_shared/auth.ts` extrae el header `Authorization: Bearer nexo_shortcut_...`, valida su formato, y calcula `sha256` con `crypto.subtle.digest` (Web Crypto nativo de Deno) antes de que cualquier valor cruce la red hacia Postgres. Ni el token ni el header `Authorization` completo se registran nunca — `_shared/errors.ts#logSafeError` solo recibe el mensaje de error, jamás el request.
- **`service_role` vive únicamente como variable de entorno de la Edge Function** (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`, provistas automáticamente por la plataforma) — `supabase/functions/_shared/supabase-admin.ts` es el único archivo que las lee. La Edge Function nunca hace `select`/`insert` directo sobre `accounts`/`credit_cards`/`financial_events`/`account_entries`/`card_entries`: llama exclusivamente `get_shortcut_options`, `get_shortcut_transaction_context`, `execute_shortcut_transaction` y `check_shortcut_abuse_bucket` — las cuatro RPC `service_role`-only creadas para esto.
- **`get_shortcut_transaction_context(token_hash, source_type, source_id)`** resuelve en una sola llamada la moneda real de la fuente (nunca la que mande el teléfono) y el `timezone` del perfil del usuario — evita que la Edge Function necesite dos round-trips o, peor, que dependa de `get_shortcut_options` (que exige el scope `options:read`) para una operación que solo debería requerir `transactions:write`. Comparte el bucket de rate limit `'tx:'` con `execute_shortcut_transaction`, a propósito: una ejecución real siempre llama ambas exactamente una vez.
- **Conversión de dinero**: una sola implementación. `src/lib/money-core.ts` (cero imports, cero dependencia de Vite/React) se importa sin copiar desde `supabase/functions/_shared/money.ts` vía ruta relativa (`../../../src/lib/money-core.ts`) — verificado empíricamente con `deno check` y `deno eval` ejecutando el parser real contra "450.50" → `45050n`. La escala de decimales por moneda (`currencyMinorUnits`) se resuelve con la moneda que devuelve `get_shortcut_transaction_context`, nunca con una enviada por el cliente.
- **Fecha/hora**: `transaction_date` explícita se usa tal cual tras validar formato y calendario real (`_shared/date.ts#isValidDateString`, rechaza p. ej. `2026-02-30`). Si se omite, `_shared/date.ts#resolveLocalDate(timezone)` calcula "hoy" con `Intl.DateTimeFormat("en-CA", { timeZone })` — nunca `new Date().toISOString().slice(0,10)` (siempre UTC, verificado que produce el día equivocado cerca de medianoche para cualquier usuario no-UTC).
- **`execute_shortcut_transaction` devuelve `(ok, event_id, error_code)`, nunca lanza, para cualquier rechazo posterior a resolver el token** (decisión de 7C-A, respetada aquí): la Edge Function traduce ese resultado — o el error de PostgREST si la RPC sí lanzó antes de resolver el token — a un código HTTP y un mensaje humano vía `_shared/errors.ts#classifyError`, con un mapa explícito NEXO_* → status. Ningún 500 devuelve SQL, stack ni el mensaje interno real (ese se registra solo del lado del servidor con `logSafeError`).
- **Rate limiting de tokens inválidos**: sin `token_id` resuelto, no hay bucket por token posible. `_shared/rate-limit.ts#resolveAbuseBucketKey` usa `cf-connecting-ip` — el único header que Cloudflare (la capa que efectivamente pone en frente Supabase Edge Functions) fija por sí mismo y que un cliente no puede sobrescribir — nunca `x-forwarded-for` (spoofeable por el cliente: se puede anteponer cualquier valor). Cuando ese header no está presente (por ejemplo, en desarrollo local sin Cloudflare de por medio) se usa un único bucket global de reserva, documentado explícitamente como limitación real: throttling agregado de todos los intentos inválidos cuando no hay señal de origen confiable, nunca una simulación de aislar clientes que en realidad no se pueden distinguir.
- **Verificación real, no solo compilación**: `scripts/test-shortcut-concurrency.sh` lanza dos procesos `psql` genuinamente concurrentes contra `execute_shortcut_transaction` con el mismo `shortcut_execution_id` — 30/30 intentos produjeron exactamente un `financial_event`. `scripts/test-shortcut-http-local.sh` levanta Postgres + PostgREST real + un proxy mínimo `/rest/v1` + los archivos reales de `supabase/functions/*/index.ts` corridos con `deno run`, y les hace peticiones `curl` reales (200/401/404/405/409/400, conversión de moneda verificada contra la fila real de `account_entries`). Ninguno de los dos depende de Supabase real ni de Docker.
