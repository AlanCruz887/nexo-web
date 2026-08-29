# Nexo — Especificación de producto

## 1. Propósito

Nexo es una aplicación financiera personal para entender y operar, desde una sola experiencia, el dinero disponible, el crédito utilizado, los compromisos de pago, el gasto verdaderamente personal y el dinero que otras personas deben al usuario.

La diferencia central del producto es que una compra no se interpreta automáticamente como gasto personal. Nexo separa siempre:

- el importe financiero total que afectó una cuenta o tarjeta;
- la parte que corresponde al usuario (`personal_amount`);
- la parte que se convierte en cuenta por cobrar a terceros.

Esta especificación es el contrato funcional de referencia. Las fases posteriores deben conservar sus conceptos e invariantes, aunque la interfaz o la implementación interna evolucionen.

## 2. Principios de producto

1. **Verdad financiera antes que conveniencia visual.** Un mismo evento no puede producir cifras contradictorias en saldos, presupuestos, patrimonio o reportes.
2. **Tarjetas y cuentas son dominios distintos.** Las cuentas representan activos; las tarjetas representan pasivos/líneas de crédito con ciclos, cortes y fechas límite.
3. **Una sola captura, efectos coordinados.** Compras compartidas, pagos, transferencias, MSI y reversiones se registran de forma atómica.
4. **No ocultar diferencias.** La conciliación muestra discrepancias; nunca crea ajustes silenciosos.
5. **Historial preservado.** Los eventos financieros se revierten y las entidades con historial se archivan.
6. **Información progresiva.** La vista cotidiana es simple; el desglose y la auditoría permiten explicar cada cifra.
7. **Privacidad visible.** Ocultar cantidades funciona de forma global y consistente.
8. **Experiencia premium.** Nexo debe sentirse minimalista, rápida y propia de una fintech, no como un panel administrativo.

## 3. Alcance funcional completo

### 3.1 Acceso, perfil y preferencias

- Autenticación segura mediante Supabase Auth.
- Perfil financiero aislado por usuario.
- Preferencias de `base_currency`, locale, zona horaria, formato de fecha y tema.
- Control global para ocultar cantidades en toda la aplicación.
- Instalación como PWA en iPhone, Android y escritorio.

### 3.2 Cuentas

Tipos soportados:

- checking;
- savings;
- cash;
- debit;
- investment.

Cada cuenta tiene moneda propia y mantiene su saldo, movimientos, conciliaciones e historial. Puede archivarse, pero no eliminarse si participa en eventos financieros. El MVP presenta monedas distintas por separado y no realiza conversión automática.

### 3.3 Tarjetas de crédito

Una tarjeta conserva, al menos:

- emisor y nombre/producto;
- límite de crédito;
- moneda;
- día de corte;
- días entre corte y fecha límite;
- política y saldo inicial;
- estados de cuenta;
- compras, reembolsos, pagos y MSI.

Las vistas deben distinguir con claridad:

- **saldo utilizado:** todo el crédito ocupado;
- **pago actual:** saldo pendiente del último estado de cuenta cerrado;
- **acumulado del ciclo:** cargos netos acumulados en el ciclo abierto; no es todavía un pago requerido.

Al agregar una tarjeta existente, el usuario elige desde cuándo controlarla:

- `current_bank_balance`;
- `after_last_statement`;
- `specific_date`.

La política crea un baseline explícito para no duplicar deuda histórica.

### 3.4 Movimientos

Nexo soporta, como mínimo:

- ingresos y gastos personales;
- compras personales, para terceros y compartidas;
- transferencias entre cuentas;
- pagos de tarjeta;
- pagos recibidos de personas;
- reembolsos;
- ajustes explícitos y conciliables;
- cargos recurrentes y suscripciones;
- MSI nuevos e históricos.

Cada fila muestra descripción, importe, cuenta o tarjeta, persona cuando aplique, MSI cuando aplique y método de pago. El contexto de creación puede preseleccionar una cuenta, tarjeta o persona, pero nunca cambia el resultado financiero.

### 3.5 Personas y cuentas por cobrar

- Una compra puede asignarse a una o varias personas y conservar una parte personal.
- Una persona puede tener obligaciones en varias tarjetas y compras sin tarjeta.
- Se soportan pagos parciales, completos, adelantados y sobrepagos. Una cuota parcial permanece abierta hasta llegar a saldo cero.
- La asignación predeterminada de un pago es: vencidos más antiguos, cuota actual, cuotas futuras del mismo receivable/plan y después saldo a favor (`credit_balance`).
- Un pago recibido aumenta la cuenta receptora y reduce la cuenta por cobrar; no es ingreso.
- El saldo a favor nunca se pierde ni es ingreso; queda disponible para obligaciones posteriores o una devolución explícita.
- El estado de cuenta compartible de una persona responde únicamente cuánto paga ahora, antes de cuándo y por qué conceptos.

El periodo de cobro de una persona usa las tarjetas relevantes para sus obligaciones:

- inicio: fecha de corte relevante más temprana;
- fin: fecha límite relevante más tardía.

### 3.6 Meses sin intereses (MSI)

Plazos estándar: 3, 6, 9, 12, 18 y 24, además de un plazo personalizado.

Modos:

- **Nuevo:** Nexo crea el plan completo desde la compra.
- **Ya iniciado:** se captura importe original, tarjeta, total de mensualidades, mensualidad real, mensualidad actual, mensualidades pagadas, saldo pendiente, fecha original, próxima cuota y persona si aplica.

Si el plan importado va en la mensualidad 5 de 12, las cuotas 1 a 4 quedan registradas como pagadas antes de importar, la 5 como actual/pendiente según fecha y las 6 a 12 como futuras. Nexo conserva un importe real pagado reportado aunque difiera del cálculo teórico. Si el saldo pendiente ya estaba incluido en el baseline de la tarjeta, el impacto adicional es cero; en caso contrario, solo se agrega el principal pendiente.

`installment_amount` conserva la mensualidad real informada por el banco. No se asume que toda cuota sea exactamente `original_amount / installment_count`; la última puede absorber el residuo para cerrar el principal exacto.

Una compra MSI nueva utiliza la línea por el principal completo desde la compra. El saldo utilizado incluye el principal pendiente total, mientras el statement solo incorpora las mensualidades de ese corte.

Los MSI pueden ser personales, para otra persona o compartidos.

### 3.7 Estados de cuenta y ciclos

- Los ciclos se calculan como intervalos semiabiertos: inicio inclusivo, corte exclusivo.
- Una compra realizada el día de corte pertenece al ciclo siguiente.
- Si el día 29, 30 o 31 no existe en un mes, el corte efectivo es el último día válido de ese mes y ese día efectivo sigue perteneciendo al ciclo siguiente.
- La fecha límite se deriva de `statement_date + payment_days_after_statement`.
- Un statement cerrado es la fuente de verdad de `statement_balance`, `payment_to_avoid_interest`, `minimum_payment`, `amount_paid`, `remaining_due` y `payment_due_date`.
- “Cerrar estado” propone el corte vencido pendiente más antiguo desde el inicio de control. Nunca propone ni permite cerrar anticipadamente el ciclo abierto.
- El saldo del statement se obtiene de la actividad de su periodo y de la contribución inicial aplicable; no es sinónimo del saldo utilizado total de la tarjeta.
- Un pago sin deuda cerrada pendiente se presenta como “Pago anticipado” y se asocia visualmente al próximo corte del ciclo, sin crear una relación con un statement inexistente.
- La vista por estado separa compras, reembolsos, compras netas, pagos anticipados e impacto neto. La métrica principal se presenta como “Compras netas del ciclo”, no como saldo utilizado.
- Si el banco no proporcionó pago mínimo, la interfaz muestra “No registrado”.
- El pago de tarjeta reduce el activo bancario y el pasivo de tarjeta; no es gasto.
- Un pago anterior al baseline puede conservarse como evidencia histórica sin volver a reducir el saldo Nexo.

### 3.8 Categorías y presupuestos

- Categorías para ingresos y gastos, con archivado y jerarquía futura compatible.
- Los presupuestos consumen únicamente `personal_amount`.
- Los reportes por categoría usan gasto personal, no el importe financiado para terceros.
- Presupuestos por periodo, categoría y, en fases posteriores, agrupaciones configurables.

### 3.9 Suscripciones, recurrencia y planificación

Frecuencias soportadas:

- semanal;
- quincenal;
- mensual;
- trimestral;
- semestral;
- anual.

Las reglas recurrentes generan ocurrencias identificables, no duplicadas. La planificación y el forecast distinguen eventos planeados de eventos realizados y permiten proyectar liquidez, obligaciones de tarjeta, MSI, cobros y ahorro.

### 3.10 Patrimonio y salud financiera

El patrimonio mide la situación económica personal. Por moneda suma activos líquidos y receivables nominales, y resta tarjetas, saldos a favor de personas y otros pasivos. Mover valor de cuenta por cobrar a banco no crea riqueza ni ingreso. El MVP no descuenta receivables por riesgo o valor presente; la salud financiera puede evaluar exposición y antigüedad por separado.

La salud financiera utiliza, como dimensiones separadas:

- ingreso personal;
- gasto personal;
- deuda y utilización de crédito;
- liquidez;
- cuentas por cobrar y riesgo de cobro;
- ahorro.

Una compra para un tercero no aumenta gasto personal, pero sí puede afectar utilización, liquidez y riesgo de cobro.

### 3.11 Reportes

Agrupaciones previstas:

- por cuenta;
- por tarjeta, emisor y producto;
- por categoría;
- por persona;
- por periodo.

Comparativas de tarjeta:

- saldo utilizado;
- importe en MSI;
- pago por corte;
- gasto personal;
- compras para terceros;
- utilización.

Toda métrica debe poder navegar a su desglose de origen.

Dashboard, presupuestos, categorías, comparaciones mensuales, salud financiera y tasa de ahorro usan `personal_amount` como gasto personal. Cash flow puede mostrar el importe financiero total que entró o salió de cuentas, manteniendo separada su clasificación económica.

### 3.12 Conciliación y explicación de saldos

La conciliación muestra:

- saldo informado por el banco;
- saldo comparable;
- saldo calculado por Nexo;
- diferencia.

El saldo utilizado de una tarjeta debe reconstruirse fila por fila como:

`baseline + movimientos nuevos + MSI importados no incluidos - pagos - reembolsos = saldo utilizado`

Nexo nunca crea un ajuste automático para llevar la diferencia a cero.

### 3.13 Importación, exportación y recibos

Importación mediante staging:

1. subir;
2. mapear columnas;
3. previsualizar;
4. detectar duplicados;
5. categorizar;
6. confirmar.

La confirmación es el único paso que genera eventos financieros productivos.

Exportaciones PDF, Excel y CSV para tarjetas, cortes, personas, movimientos y reportes. Los recibos se almacenan de forma privada y solo son accesibles por su propietario mediante autorización de corta duración.

### 3.14 Reglas automáticas

- Reglas deterministas para categorizar, asociar personas y normalizar descripciones.
- Vista previa antes de aplicar cambios en lote.
- Prioridad explícita, historial y posibilidad de desactivar.
- Ninguna regla puede saltarse las validaciones financieras ni la atomicidad.

### 3.15 Archivado, reversión y auditoría

- Cuentas, tarjetas, categorías y personas con historial se archivan.
- Las entidades archivadas no aparecen en selectores normales ni aceptan nuevos movimientos, pero preservan su historial.
- En Movimientos, `Origen` separa Todos/Cuentas/Tarjetas. Solo Cuentas o Tarjetas muestran un selector contextual; archivadas requieren la opción explícita “Incluir archivadas”.
- La configuración de tarjeta muestra “Controlada en Nexo desde”. Una compra anterior se rechaza con esa fecha real para evitar duplicar el saldo inicial; no existe conversión silenciosa a historial sin impacto.
- Los eventos financieros asentados se revierten con un evento compensatorio; no se eliminan.
- La auditoría registra `created`, `edited`, `reverted`, `archived` y `restored`.
- Los registros de auditoría no son editables desde el frontend.

## 4. Experiencia y navegación

### 4.1 Estructura de alto nivel

- Inicio: posición financiera y pendientes inmediatos.
- Movimientos: actividad unificada con filtros y desglose; la UI usa Compra, Pago, Transferencia, MSI, Cobro, Reembolso y no expone terminología de libro contable.
- Cuentas: activos y conciliación.
- Tarjetas: crédito, cortes, pago actual, acumulado del ciclo y MSI.
- Personas: cuentas por cobrar, cobros y estado compartible.
- Plan: presupuestos, recurrencias, suscripciones y forecast.
- Reportes: análisis y patrimonio.
- Configuración: preferencias, privacidad, importación/exportación y archivo.

### 4.2 Patrones de interacción

- Navegación contextual con valores preseleccionados.
- Formularios validados y con vista previa de efectos financieros.
- Drawers y bottom sheets para flujos breves, especialmente en móvil.
- Animaciones sutiles en transiciones, listas, balances, progreso y tarjetas.
- Respeto obligatorio de `prefers-reduced-motion`.
- Estado vacío, carga, error y reintento definidos para cada vista remota.

## 5. Requisitos no funcionales

- TypeScript estricto y validación compartida con Zod.
- Accesibilidad de teclado, foco visible, contraste suficiente y etiquetas semánticas.
- Diseño responsive desde móvil.
- Cálculos monetarios sin coma flotante binaria.
- `transaction_date` como fuente temporal del MVP; `purchase_date` y `posted_date` quedan opcionales y nunca se inventan.
- Operaciones financieras complejas atómicas e idempotentes.
- RLS en toda tabla de usuario y Storage privado.
- Ninguna clave de servicio en el cliente.
- Trazabilidad desde métricas hasta eventos y auditoría.
- Pruebas de invariantes, límites de ciclo y autorización antes de cada fase.

## 6. Criterios globales de aceptación

Nexo cumple su contrato cuando:

1. una compra compartida conserva `amount = personal_amount + receivables`;
2. pagos de terceros, pagos de tarjeta y transferencias no aparecen como ingreso o gasto;
3. una compra del día de corte pertenece al ciclo siguiente;
4. saldo utilizado, pago actual y acumulado del ciclo pueden diferir y explicarse;
5. un MSI histórico nunca duplica principal incluido en el baseline;
6. presupuestos y reportes personales usan `personal_amount`;
7. patrimonio no cambia al cobrar una cuenta por cobrar, salvo diferencias explícitas;
8. toda operación compuesta termina completa o no deja cambios;
9. un usuario nunca puede leer o mutar datos de otro;
10. toda cifra agregada permite llegar a sus componentes;
11. un pago parcial conserva el pendiente exacto y un sobrepago conserva saldo a favor;
12. un MSI nuevo ocupa línea por todo su principal pendiente, pero el statement exige solo cuotas del ciclo;
13. distintas monedas se muestran separadas salvo que exista FX explícito;
14. la reversión restaura todas las proyecciones sin borrar el evento original.

## 7. Estado de implementación

Las Fases 1, 2, 3A, 3B, 4A, 4B, 5A, 5B y 5C implementan el fundamento técnico, Auth, perfil, monedas, cuentas, movimientos, tarjetas, MSI personales y de terceros/compartidos, y personas con cuentas por cobrar, periodo de cobro consolidado, saldo a favor y estado de persona exportable. Los saldos y métricas consumen proyecciones compartidas; la UI nunca edita un saldo calculado.

Las rutas productivas actuales incluyen `/cards` y `/cards/:id` junto con sus alias `/tarjetas`, además de las rutas de cuentas, movimientos, configuración y Auth. Tarjetas y cuentas mantienen ledgers distintos. Compras, pagos y reembolsos aparecen en una actividad global unificada sin perder su origen.

Continúan como contrato de diseño futuro, sin implementación parcial: selector de periodos anteriores del estado de persona, presupuestos, planificación, salud, reportes globales, conciliación e importaciones bancarias.

En Fase 5A, Personas muestra saldos separados por moneda, compras asignadas y pagos. Una compra desde cuenta o tarjeta puede ser personal, para otra persona o compartida entre varias; la distribución debe cerrar exactamente contra el total. Registrar un pago exige una cuenta en la misma moneda, admite parcialidad, aplica primero a la deuda más antigua y nunca se presenta como ingreso.

En Fase 5B, Personas distingue siempre "a pagar este periodo" de "te debe en total": el detalle de cada persona muestra primero cuánto toca pagar ahora, la fecha límite, lo que falta y lo vencido si lo hay, y solo después, con menor jerarquía, la deuda total y lo pagado en el periodo. "Este periodo" lista cada concepto exigible (compra o mensualidad de un MSI) con su importe; "Compras a meses" muestra, por cada MSI de la persona, cuánto te debe en total de ese plan, la mensualidad y el importe de este periodo, el próximo corte y cuántas mensualidades ya están cubiertas. Un MSI puede asignarse por completo a otra persona o repartirse entre varias, con el mismo principio de "Nueva compra" de Fase 4A; la parte de cada persona en un MSI compartido se reparte en la misma proporción que el principal. Un sobrepago ya no se bloquea: cualquier excedente sobre lo exigible primero adelanta la deuda futura de esa persona (por ejemplo mensualidades siguientes de un MSI activo); solo se convierte en saldo a favor cuando ya no queda nada pendiente por cubrir. La persona puede aplicar su saldo a favor a una obligación pendiente desde su propia página, viendo antes el saldo disponible, cuánto se aplicará y qué queda pendiente después; aplicar saldo a favor no crea ningún movimiento bancario ni de tarjeta, y se rechaza si no hay ninguna obligación a la que aplicarlo. Registrar un pago muestra antes de confirmar si quedará parcial, completo, completo con adelanto de deuda futura, o con saldo a favor real. La actividad de cada persona distingue compra compartida, compra para esa persona, compra a meses, pago recibido y saldo a favor aplicado, sin listar cada mensualidad futura como si fuera un movimiento ya ocurrido. La lista de Personas resume, por persona, lo mismo que su detalle: te debe en total, a pagar este periodo y, si existe, saldo a favor.

En Fase 4A, “Nueva compra” permite exhibición única o MSI de 2 a 60 meses, con opciones comunes 3/6/9/12/18/24. La UI presenta el cargo completo una vez en Movimientos, el plan y su progreso en la tarjeta, y cada mensualidad dentro del statement proyectado correspondiente. El detalle permite modificar solo metadata y ofrece una reversión MSI dedicada; los reembolsos vinculados quedan restringidos hasta aprobar su redistribución.

El selector principal muestra únicamente 3/6/9/12/18/24 y “Personalizado”; el campo numérico de 2 a 60 aparece solo para esta última opción. El cronograma usa estados futura, pendiente, pagada y revertida. Un pago parcial del statement no marca una mensualidad como pagada; el progreso avanza al quedar cubierto el statement completo, sin crear un segundo movimiento financiero.

En Fase 4B, “Agregar MSI existente” es un flujo separado que deriva las cuotas pagadas antes de Nexo desde la mensualidad actual. Conserva mensualidad bancaria, dinero reportado pagado y principal amortizado como datos distintos. Si el principal pendiente ya estaba incluido en el saldo inicial su impacto adicional es cero; de lo contrario agrega únicamente ese pendiente. La importación no crea compras, pagos ni gasto personal retroactivos. Las cuotas futuras se integran con los statements proyectados y solo avanzan mediante pagos reales de tarjeta.

En Fase 5C, cada persona tiene un “Ver estado” dedicado en `/personas/:id/estado`: un documento limpio, no una pantalla administrativa. Muestra, siempre por separado, cuánto le corresponde pagar este periodo, la fecha límite, cuánto está vencido si aplica, cuánto debe en total y cuánto tiene de saldo a favor si aplica; el desglose “Este periodo” explica cada compra o mensualidad detrás de esa cifra, y “Pagos recibidos” muestra cada pago con cuánto cubrió el periodo, cuánto adelantó deuda futura y cuánto generó de saldo a favor — exactamente lo que decidió el dominio, nunca una resta hecha en la pantalla. El estado ofrece “Exportar” (PDF, Excel o CSV, en un menú, no tres botones) y “Compartir” (usa la función nativa del navegador cuando existe; si no, descarga el archivo). Los tres formatos muestran las mismas cifras que la pantalla, sin IDs ni nombres técnicos, y sin mezclar monedas. Los importes de una exportación siempre se ven completos aunque el modo de privacidad esté activo en pantalla. Imprimir desde el navegador oculta la barra lateral y las acciones, dejando solo el documento. El estado de persona solo cubre el periodo vigente; no existe todavía un selector de periodos anteriores (ver ARCHITECTURE.md y PLAN.md §12 para la razón).
