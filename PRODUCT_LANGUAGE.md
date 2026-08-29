# Lenguaje de producto de Nexo

Este documento define las palabras visibles en la interfaz. Los nombres internos de tablas, funciones y campos permanecen en la arquitectura y nunca se trasladan literalmente a la experiencia.

## Voz

Nexo habla de forma clara, tranquila, profesional y directa. Una etiqueta breve presenta el concepto; el valor recibe la mayor jerarquía; la explicación aparece bajo demanda cuando hace falta.

## Diccionario

| Concepto de producto | Uso visible | No usar en la UI |
|---|---|---|
| Estado de cuenta | Documento cerrado por el banco para un periodo | snapshot |
| Periodo actual | Tiempo entre el último corte y el próximo | ciclo abierto |
| Corte | Día en que termina el periodo de la tarjeta | cycle end |
| Fecha límite | Día máximo de pago del estado | payment due date |
| Saldo utilizado | Todo el crédito que la tarjeta ocupa hoy | pasivo total, used balance |
| Pago de este estado | Lo que falta pagar del último estado cerrado | pago actual, remaining due |
| Próximo estado | Total estimado hasta ahora para el siguiente corte | acumulado, proyección, compras netas del ciclo |
| Disponible | Crédito que todavía puede utilizarse | limit minus used |
| Total del estado | Importe con el que cerró el estado de cuenta | statement balance, saldo preliminar |
| Pagaste | Pagos aplicados al estado | amount paid |
| Falta por pagar | Importe aún pendiente del estado | remaining due |
| Pago anticipado | Parte de un pago que aún no corresponde a un estado cerrado | sin estado asignado |
| Reembolso | Devolución que reduce saldo y gasto; no es ingreso | ingreso por devolución |
| Revertir | Cancelar de forma segura y restaurar saldos conservando historial | borrar evento, compensar entradas |
| MSI existente | Plan que ya existía cuando la persona comenzó a usar Nexo | MSI histórico como explicación principal |
| Te falta pagar | Principal pendiente del plan, en resúmenes | principal restante |
| Mensualidad de este periodo | Primera mensualidad pendiente cuando pertenece al corte actual | próxima mensualidad |
| Próxima mensualidad | Primera mensualidad pendiente únicamente cuando pertenece a un corte futuro | mensualidad actual |
| Principal pendiente | Parte del importe original aún no amortizada, solo en detalle avanzado | remaining principal |
| Ya incluido en el saldo | La deuda del MSI ya formaba parte del saldo registrado al iniciar | included in opening balance |
| Inicio del seguimiento | Fecha desde la que Nexo administra la tarjeta | baseline |
| Moneda principal | Moneda usada en los resúmenes personales | moneda base, base currency |
| Te debe | Saldo nominal pendiente de una persona | receivable balance |
| Pago recibido | Cobro que mueve valor de cuenta por cobrar a cuenta bancaria | ingreso |
| Tu parte | Parte personal de una compra compartida | personal_amount |
| Parte de otra persona | Importe que crea dinero por cobrar | allocation |
| A pagar este periodo | Lo exigible ahora de una persona: vencido más el corte/fecha más próxima | due item, cronograma |
| Te debe en total | Toda la deuda pendiente de la persona, no solo la de este periodo | total_outstanding_minor |
| Falta | Lo que sigue pendiente de este periodo tras pagos y saldo a favor aplicado | remaining_minor |
| Pagado | Lo ya cubierto de este periodo, por pago o por saldo a favor aplicado | paid_minor |
| Este periodo | Lista de compras y mensualidades exigibles ahora | concepts, due items |
| Mensualidad | Una cuota de un plan a meses | installment |
| Compras a meses | Los MSI activos de una persona con su avance | installment plans, planes a meses |
| Vencido | Parte de lo exigible del periodo cuya fecha ya pasó | overdue, past due |
| Adelantado | Parte de un pago que cubrió obligaciones futuras además del periodo actual | advanced, applied to future |
| Compra compartida | Compra con parte personal y parte de una o más personas | shared purchase |
| Compra a meses | Compra o MSI que aparece en el plan a meses de la persona | installment purchase |
| Te queda por pagar | Lo pendiente de un plan a meses después del periodo actual | remaining principal |
| Saldo a favor | Dinero ya recibido de una persona que aún no se aplicó a una compra o mensualidad | credit balance, credit entry |
| Aplicar saldo a favor | Usar saldo a favor existente para reducir una obligación, sin mover dinero de nuevo | apply credit |
| Saldo a favor aplicado | Movimiento en la actividad cuando se usó saldo a favor en vez de un pago nuevo | credit_applied |
| Compra | Un cargo asignado a la persona, sea único o parte de un plan a meses | purchase, charge |

## Acciones

- `Registrar compra`, `Registrar pago`, `Registrar reembolso` y `Confirmar transferencia` crean operaciones.
- `Guardar cambios` modifica información existente.
- `Cerrar estado` crea el estado correspondiente al corte vencido.
- `Revertir movimiento` cancela una operación conservando evidencia.
- `Archivar` retira un elemento de los flujos nuevos sin borrar su historia.

## Reglas editoriales

- No mostrar `baseline`, `RPC`, `projection`, `financial_event`, `allocation`, `effect_scope`, `minor units`, `idempotency` ni nombres de columnas.
- No mostrar tampoco `receivable`, `due item`, `credit entry`, `ledger`, `principal`, `period engine` ni `installment allocation`: en Personas se dice “te debe”, “a pagar este periodo”, “falta”, “saldo a favor” y “mensualidad”.
- No llamar ingreso a un reembolso ni gasto a un pago de tarjeta.
- No llamar “pago de este estado” al saldo utilizado total.
- No llamar “te debe en total” a lo exigible del periodo, ni al revés: son dos cifras distintas y ambas se muestran, con “a pagar este periodo” siempre con mayor jerarquía visual.
- Usar “estimado” para el próximo estado mientras el corte siga abierto.
- Aplicar saldo a favor se explica como usar dinero ya recibido, nunca como un pago o movimiento bancario nuevo.
- Un pago mayor a lo exigible del periodo no se llama "saldo a favor" si todavía hay deuda futura de esa persona: se explica como "adelantado". Solo se llama saldo a favor cuando ya no queda nada pendiente.
- Las confirmaciones explican la consecuencia para saldos e historial, no el mecanismo interno.
