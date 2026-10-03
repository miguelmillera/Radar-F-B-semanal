-- Task Harmony (Lovable, project 10feea1a-0991-445b-bf44-934855fbfab7)
-- Arreglo de la puntuación de productividad. Aplicado a mano con query_database,
-- fuera de las migraciones de drizzle. Fecha: 2026-10-03.
--
-- Causa: el disparador trg_registrar_evento_tarea era "BEFORE UPDATE OF status".
-- Desde el 19-sep la app solo actualiza status_key; el disparador a_sincronizar_status_tarea
-- copia el valor a status, pero un disparador "UPDATE OF <columna>" solo salta si la
-- columna aparece en el SET de la sentencia, así que no se registraba ningún evento.

BEGIN;

-- 1) El disparador de puntos salta también cuando cambia status_key.
DROP TRIGGER IF EXISTS trg_registrar_evento_tarea ON public.tasks;
CREATE TRIGGER trg_registrar_evento_tarea
  BEFORE UPDATE OF status, status_key ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_tarea();

-- 2) Que borrar una tarea no borre los puntos ganados con ella.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.task_events'::regclass AND contype = 'f'
      AND confrelid = 'public.tasks'::regclass AND confdeltype <> 'n'
  LOOP
    EXECUTE format('ALTER TABLE public.task_events DROP CONSTRAINT %I', r.conname);
    ALTER TABLE public.task_events ALTER COLUMN task_id DROP NOT NULL;
    ALTER TABLE public.task_events
      ADD CONSTRAINT task_events_task_id_fkey FOREIGN KEY (task_id)
      REFERENCES public.tasks(id) ON DELETE SET NULL;
  END LOOP;
END $$;

-- 3) Histórico diario consultable (hora de Madrid).
CREATE OR REPLACE VIEW public.productividad_diaria WITH (security_invoker = on) AS
SELECT user_id,
       (occurred_at AT TIME ZONE 'Europe/Madrid')::date AS dia,
       SUM(points)::int                                  AS puntos,
       COUNT(*) FILTER (WHERE kind = 'cierre')           AS cierres,
       COUNT(*) FILTER (WHERE kind = 'arranque')         AS arranques,
       COUNT(*) FILTER (WHERE kind = 'reapertura')       AS reaperturas
FROM public.task_events
GROUP BY 1, 2;
GRANT SELECT ON public.productividad_diaria TO authenticated;

-- 4) Recuperación de lo no registrado entre el 19-sep y hoy, todo en un único día
--    (viernes 2-oct-2026, 12:00 Madrid) para no mezclarlo con la actividad real de hoy.
--    Misma fórmula que registrar_evento_tarea. Fecha de cierre real desconocida:
--    se usa updated_at como aproximación para la rapidez.

-- 4a) Cierres: tareas en estado de cierre sin ningún evento 'cierre'.
INSERT INTO public.task_events (task_id, user_id, kind, from_status, to_status, points, days_open, occurred_at)
SELECT t.id, t.created_by, 'cierre', NULL, t.status_key,
       ROUND(
         (CASE t.priority_key WHEN 'critica' THEN 5 WHEN 'alta' THEN 3 ELSE 2 END)
       * (CASE WHEN t.waiting_on IS NOT NULL AND btrim(t.waiting_on) <> '' THEN 1.3
               WHEN t.outlook_source IS NOT NULL THEN 1.2 ELSE 1.0 END)
       * (CASE WHEN d.dias <= 3 THEN 1.5 WHEN d.dias <= 7 THEN 1.25 WHEN d.dias <= 14 THEN 1.0
               WHEN d.dias <= 30 THEN 0.85 ELSE 0.7 END)
       )::int + CASE WHEN d.dias > 21 THEN 4 ELSE 0 END,
       d.dias,
       timestamp '2026-10-02 12:00' AT TIME ZONE 'Europe/Madrid'
FROM public.tasks t
JOIN public.task_statuses s ON s.key = t.status_key AND s.is_closed
CROSS JOIN LATERAL (
  SELECT GREATEST(0, t.updated_at::date - COALESCE(t.origin_date, t.created_at::date)) AS dias
) d
WHERE NOT EXISTS (SELECT 1 FROM public.task_events e WHERE e.task_id = t.id AND e.kind = 'cierre');

-- 4b) Arranques: tareas en curso sin evento 'arranque' (1 punto cada una).
INSERT INTO public.task_events (task_id, user_id, kind, from_status, to_status, points, days_open, occurred_at)
SELECT t.id, t.created_by, 'arranque', 'pendiente', t.status_key, 1,
       GREATEST(0, CURRENT_DATE - COALESCE(t.origin_date, t.created_at::date)),
       timestamp '2026-10-02 12:00' AT TIME ZONE 'Europe/Madrid'
FROM public.tasks t
WHERE t.status_key = 'proceso'
  AND NOT EXISTS (SELECT 1 FROM public.task_events e WHERE e.task_id = t.id AND e.kind = 'arranque');

COMMIT;
