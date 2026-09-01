-- Diagnóstico de solo lectura para Fase 7A. Ejecutar en el SQL Editor de
-- tu Supabase real ANTES de aplicar 20260830080000_phase_7a_recurring_
-- transactions.sql, para saber exactamente qué va a convertirse.
--
-- No modifica ningún dato. No crea nada. Solo SELECT. Seguro de correr
-- las veces que quieras, en cualquier momento.
--
-- Ejecuta cada bloque por separado, o todo el archivo de una vez -- cada
-- SELECT es independiente.

-- 1) Resumen general: cuántas filas hay en planned_cash_flows y cómo se
--    reparten por recurrencia y estado de archivado.
select
  count(*) as total_planned_cash_flows,
  count(*) filter (where recurrence = 'one_time') as one_time_total,
  count(*) filter (where recurrence = 'monthly' and archived_at is null) as monthly_activos,
  count(*) filter (where recurrence = 'monthly' and archived_at is not null) as monthly_archivados
from public.planned_cash_flows;

-- 2) Lista exacta de lo que la migración va a convertir: cada fila
--    monthly ACTIVA (archived_at is null) -- exactamente las que
--    private.migrate_planned_cash_flow_monthly_rows() tomará.
select
  id,
  user_id,
  name,
  currency,
  amount_minor,
  (amount_minor::numeric / 100) as amount_display,
  case when amount_minor > 0 then 'income' else 'expense' end as direccion_resultante,
  category_id,
  start_date,
  end_date,
  created_at
from public.planned_cash_flows
where recurrence = 'monthly' and archived_at is null
order by user_id, start_date;

-- 3) Lo que la migración NUNCA toca, para contraste: filas one_time
--    (permanecen intactas) y filas monthly ya archivadas (permanecen
--    archivadas, no se re-procesan).
select
  id, user_id, name, currency, amount_minor, recurrence, archived_at, start_date
from public.planned_cash_flows
where recurrence = 'one_time' or (recurrence = 'monthly' and archived_at is not null)
order by recurrence, user_id, start_date;

-- 4) Verificación cruzada: total de filas debe ser exactamente la suma de
--    las tres categorías anteriores (ninguna fila queda fuera de este
--    diagnóstico). Debe devolver una sola fila con should_be_zero = 0.
select
  (select count(*) from public.planned_cash_flows) -
  (
    (select count(*) filter (where recurrence = 'one_time') from public.planned_cash_flows) +
    (select count(*) filter (where recurrence = 'monthly' and archived_at is null) from public.planned_cash_flows) +
    (select count(*) filter (where recurrence = 'monthly' and archived_at is not null) from public.planned_cash_flows)
  ) as should_be_zero;
