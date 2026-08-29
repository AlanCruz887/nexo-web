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

## Acciones

- `Registrar compra`, `Registrar pago`, `Registrar reembolso` y `Confirmar transferencia` crean operaciones.
- `Guardar cambios` modifica información existente.
- `Cerrar estado` crea el estado correspondiente al corte vencido.
- `Revertir movimiento` cancela una operación conservando evidencia.
- `Archivar` retira un elemento de los flujos nuevos sin borrar su historia.

## Reglas editoriales

- No mostrar `baseline`, `RPC`, `projection`, `financial_event`, `allocation`, `effect_scope`, `minor units`, `idempotency` ni nombres de columnas.
- No llamar ingreso a un reembolso ni gasto a un pago de tarjeta.
- No llamar “pago de este estado” al saldo utilizado total.
- Usar “estimado” para el próximo estado mientras el corte siga abierto.
- Las confirmaciones explican la consecuencia para saldos e historial, no el mecanismo interno.
