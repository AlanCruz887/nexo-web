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

La clave se identifica de forma única por `(user_id, command_type, idempotency_key)`. El mismo reintento con el mismo payload devuelve el resultado original; reutilizar la clave con un payload diferente falla. Los estados `in_progress`, `completed` y `failed_retryable` impiden carreras y permiten recuperación controlada.

## 25. Fechas de compra e importación

- En el MVP, `transaction_date` es la única fuente de verdad para ciclos, presupuestos, cash flow y reportes por fecha.
- El modelo queda preparado para `purchase_date` y `posted_date`, ambas opcionales. No se inventa ninguna de ellas.
- Una importación futura puede usar `posted_date` para asignar statement únicamente cuando el proveedor bancario la proporcione y declare que esa fecha gobierna el corte.
- Cambiar la fecha que determina un statement requiere una regla versionada y una migración explícita de dominio; nunca cambia silenciosamente la semántica histórica.
