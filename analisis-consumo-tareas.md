# Consumo de tokens en las tareas programadas: análisis y optimización

> **Nota (3-oct, tarde):** este documento es el análisis de partida. La configuración final y las mediciones posteriores están en `propuesta-tareas-v2.md`. En particular: las tareas de correo corren solo de lunes a viernes, Seguimientos revisa una ventana de 24 h (72 h el lunes) y usa Haiku 4.5, y la limpieza de conectores se hizo en la cuenta, no en cada tarea.


Fecha del análisis: sábado 3 de octubre de 2026. Fuente: `list_triggers`, `get_session` y los eventos de cada ejecución. Los costes son el `total_cost_usd` que registra cada sesión, a precio de lista.

## 1. Qué se ha gastado hoy

| Hora (UTC) | Tarea | Modelo | Duración | Coste | Resultado |
|---|---|---|---|---|---|
| 05:09 | Sincronizar tareas desde Outlook | **Opus 5** | 2 min | **2,90 $** | OK, **0 tareas nuevas** |
| 06:15 | Seguimientos: correos enviados sin respuesta | Sonnet 5 | **77 min** | **18,59 $** | **FALLIDA**: agotó el límite de 5 h, sin crear nada ni informar |
| 07:18 | Radar F&B semanal (sábado) | Sonnet 5 (+ Haiku) | 8 min | 2,32 $ | OK, 4 hallazgos y correo enviado |
| | **Total hoy** | | | **≈ 23,8 $** | |

Las tres tareas comparten la misma ventana de 5 horas (05:10 a 10:10 UTC). La de Outlook la abrió, Seguimientos la llenó (estado `rejected`, «You've hit your session limit · resets 10:10am») y el Radar terminó en `allowed_warning`. **Seguimientos se llevó el 78 % del gasto del día y no entregó nada.**

## 2. Por qué Seguimientos costó 18,59 $

Desglose aproximado (Sonnet 5: 2 $/M de entrada, 10 $/M de salida, lectura de caché 0,1×, escritura de caché a 5 min 1,25×):

| Concepto | Tokens | Coste aprox. | % |
|---|---|---|---|
| Escritura de caché | 3,97 M | ~9,9 $ | 53 % |
| Salida (208 k de ellos, *thinking*) | 487 k | ~4,9 $ | 26 % |
| Lectura de caché | 10,3 M | ~2,1 $ | 11 % |
| Entrada sin caché | 812 k | ~1,6 $ | 9 % |

Causas, de mayor a menor peso:

1. **Ventana de 45 días cada día.** El prompt pide revisar todo lo enviado entre hace 3 y 45 días. Hoy eso dio **258 correos candidatos** con **77 destinatarios distintos**, de los cuales 242 quedaban «por verificar». Mañana volverá a verificar casi los mismos 242. Es un trabajo de 45 días que se repite entero a diario.
2. **Una búsqueda pesada por destinatario.** Para comprobar si alguien contestó, hace `outlook_email_search(sender=X, afterDateTime=…, limit 25)`. Cada respuesta pesa **~35 KB (~10 k tokens)** porque trae 25 correos con su cuerpo. 77 destinatarios × 10 k ≈ 770 k tokens de resultados, que luego se arrastran en el contexto de cada turno.
3. **Búsquedas repetidas.** El mismo bloque de búsquedas (mismos remitentes, mismas fechas y mismos tamaños de respuesta) se lanzó dos veces, a las 07:09 y a las 07:12, y otra vez a las 07:20 y a las 07:23. El agente perdió el hilo y rehízo el trabajo.
4. **Delegó todo en un subagente.** El agente principal creó un subagente `general-purpose` que hizo todo el trabajo. Los subagentes usan una caché de 5 minutos. En las pausas largas (07:03→07:08 y 07:12→07:18, mientras escribía scripts) la caché caducaba y había que volver a escribir el contexto entero. De ahí los 3,97 M tokens de escritura de caché.
5. **Copió los datos a mano en scripts de Python.** Escribía ficheros como `replies_batch1.py` con listas de asuntos y fechas pegados del resultado de las búsquedas. Eso son tokens de salida, los más caros, gastados en transcribir. Además hubo 208 k tokens de razonamiento (*thinking*).
6. **El prompt empuja a la exhaustividad**: «cualquier destinatario, nunca limites…» y «mejor crearlo que perderlo». Sin topes de llamadas ni de tiempo.

## 3. Las otras tareas activas

### Sincronizar tareas desde Outlook (diaria 05:00 UTC) — 2,90 $/día ≈ 87 $/mes
- Usa **Opus 5**, el modelo más caro, para un trabajo mecánico: leer correos con bandera, comparar sus ID con la base de datos e insertar las tareas nuevas. Hoy no encontró nada nuevo.
- Hizo 18 turnos con un contexto de partida de **~102 k tokens** (`first_request_input_tokens`). Por eso hay 2,85 M tokens de lectura de caché en solo 2 minutos.
- Comparación: la antigua sincronización con **Haiku 4.5** costaba entre **0,17 $ y 0,54 $** por ejecución.

### Radar F&B semanal (sábado 07:00 UTC) — 2,32 $/semana ≈ 10 $/mes
- Coste razonable. Aun así hizo 92 turnos, el contexto llegó a 245 k y partía de ~115 k tokens.
- Detalle a revisar: el resumen dice que la semana 41 «ya tenía 6 hallazgos» antes de esta ejecución. Conviene comprobar si el Radar se lanzó dos veces esta semana, a mano o por un reintento.

### Coste fijo común: el arranque de ~100–115 k tokens
Todas las rutinas llevan conectados entre 11 y 15 conectores (Canva, Higgsfield, Gamma, Clay, SlidesGPT, Read_AI, Goodnotes, Supabase…), aunque solo usan uno o dos. Cada turno vuelve a leer ese prefijo. Ese contexto de partida incluye el prompt del sistema, la lista de skills y las herramientas. Los conectores no son el único componente, pero sí el que se puede recortar.

| Tarea | Conectores que necesita de verdad |
|---|---|
| Sincronizar Outlook | Microsoft_365, Lovable |
| Seguimientos | Microsoft_365, Lovable |
| Radar F&B | Gmail (el panel se lee con ArtifactData, que es una herramienta de la sesión, no un conector) |

### Rutinas desactivadas (hoy no gastan)
Sincronización Completa (Haiku), Sincronización 10 AM y 19:00, Resúmenes 10 AM y 19:00, y las rutinas de un solo uso de Lovable, ya ejecutadas. Se pueden borrar para tener la lista limpia.

## 4. Proyección mensual

| Tarea | Ahora | Optimizada (estimación) |
|---|---|---|
| Seguimientos (diaria) | 18 $+/día → **> 500 $/mes**, y además bloquea el resto | 0,3–0,8 $/día → **10–25 $/mes** |
| Sincronizar Outlook (diaria) | 2,90 $/día → **~87 $/mes** | 0,15–0,40 $/día → **5–12 $/mes** |
| Radar F&B (semanal) | 2,32 $ → **~10 $/mes** | ~1,2–1,6 $ → **5–7 $/mes** |
| **Total** | **~600 $/mes** | **~20–45 $/mes** |

## 5. Optimizaciones, de mayor a menor impacto

1. **Seguimientos: hacerlo incremental.** Cada día, revisar solo lo enviado **entre hace 3 y hace 6 días**, en lugar de 3 a 45. Los dos días de solape cubren un día en que la rutina falle, y los duplicados ya los frena el índice único de `outlook_source`. Si se quiere una red de seguridad, añadir una pasada semanal de 3 a 21 días.
2. **Seguimientos: comprobar la respuesta por hilo y no por remitente.** Una búsqueda acotada por asunto del hilo, posterior a la fecha de envío y con `limit 5`, en lugar de traer los últimos 25 correos de cada persona.
3. **Prohibir subagentes y la transcripción a scripts.** Procesar en lotes cortos y quedarse solo con los campos necesarios: `internetMessageId`, `webLink`, fecha, destinatario y asunto.
4. **Poner topes explícitos**: un máximo de llamadas a Outlook por ejecución. Si se alcanza, parar e informar de lo hecho, en lugar de seguir hasta agotar el límite.
5. **Sincronizar Outlook: pasar de Opus 5 a Haiku 4.5.** Es una tarea mecánica, con reglas claras. Si se notan fallos de criterio al descartar «ruido», usar Sonnet 5, que sigue costando unas 3 veces menos.
6. **Sincronizar Outlook: cortar la paginación por fecha.** Los resultados ya vienen de más reciente a más antiguo. En cuanto una página llega a correos de más de 45 días, parar. Hoy bastaba con 1 o 2 páginas.
7. **Quitar en cada rutina los conectores que no usa** (ver tabla de arriba). `update_trigger` no permite cambiar los conectores, así que hay que hacerlo desde la configuración de la rutina en claude.ai o recreándola con `create_trigger`, y recrearla pierde el historial.
8. **Radar: acotar la investigación.** Máximo 12 páginas abiertas y parar al llegar a 6 hallazgos válidos. Sigue en Sonnet 5, porque aquí el criterio importa.
9. **Separar los horarios** para que no caigan todas en la misma ventana de 5 horas, o al menos dejar Seguimientos para el final. Con los arreglos anteriores esto deja de ser crítico.
10. **Valorar ejecutar Seguimientos y Outlook solo de lunes a viernes** (`0 5 * * 1-5`, `0 6 * * 1-5`). En fin de semana apenas hay correo nuevo y se ahorra un 28 %.

## 6. Prompts propuestos

### 6.1 Seguimientos (Sonnet 5, L–V)

```
Eres el asistente de Miguel Millera (mmillera@allsunhotels.com), Director F&B Corporativo en allsun Hotels. Tarea diaria y BARATA: detecta correos en los que Miguel pidió algo y no le han contestado, y créalos como tareas de seguimiento. Trabaja tú solo, sin subagentes (no uses la herramienta Agent) y sin escribir scripts que copien datos de los resultados. Termina con un resumen breve en español.

LÍMITES: como máximo 30 llamadas a Outlook en total. Si llegas al tope, para, inserta lo ya confirmado e indícalo en el resumen.

PASO 1 — Ya importados. Con query_database de Lovable (project_id "10feea1a-0991-445b-bf44-934855fbfab7"):
SELECT outlook_source FROM public.tasks WHERE outlook_source IS NOT NULL AND origin_date >= now() - interval '10 days';
Y una sola vez: SELECT key, name FROM public.task_types; SELECT key, name FROM public.task_priorities; (usa la clave de "Seguimiento" y la de "Alta").

PASO 2 — Candidatos. Con outlook_email_search busca en "Sent Items" los correos que Miguel envió entre hace 6 días y hace 3 días (solo esa ventana). De cada uno quédate SOLO con: internetMessageId, webLink, sentDateTime, destinatario principal, asunto y la primera frase útil. Descarta los ya importados (PASO 1), los acuses de recibo, agradecimientos, confirmaciones de reunión y respuestas que cierran tema. Quédate con los que piden información, acción, confirmación o decisión a otra persona, sea quien sea.

PASO 3 — ¿Contestaron? Para cada candidato haz UNA búsqueda acotada: query con el asunto sin "RE:/RV:/FW:", afterDateTime = fecha de envío, limit 5. Si aparece un correo de ese destinatario (o de su buzón) posterior, está contestado. Si no aparece nada, es un seguimiento.

PASO 4 — Insertar cada seguimiento nuevo en public.tasks con: created_by '4f4895a6-b3b6-4b90-ac41-94d6b1c0740e', assigned_to '{}', status_key 'pendiente', type_key = clave de Seguimiento, priority_key = clave de Alta, waiting_on = nombre de la persona (nunca vacío), title accionable que empiece por verbo y nombre a la persona y el asunto, meta 'Seguimiento · esperando a <nombre> · enviado el <d mmm> · <N> días sin respuesta', outlook_source = internetMessageId completo, outlook_link = webLink tal cual, origin_date = fecha de envío, department_id según contenido o NULL (Bares 3ecb5181-c541-4e64-9952-b45e5f82029a · Cocina 90cd0d17-9a17-494d-932f-9b2cee0f8843 · Grecia 168925b2-3bc9-4e11-b29c-526d6a63bc1a · Canarias bb1a50e0-aaf8-4fcd-982a-daf1ad4fb6d0 · Marketing 7f654fda-1f76-4b3f-abf2-c458a7754c29 · Asesores 076b959a-d4ba-4b26-9a9e-ece2081bcc18 · Reposiciones ec431309-103c-4691-8040-71b91a24eeab · Personal a38f8c4d-39a7-4547-bcb6-107fe93faf60). Un único INSERT con todas las filas, terminado en ON CONFLICT DO NOTHING.

PASO 5 — Resumen: cuántos correos enviados revisaste, cuántos seguimientos creaste (uno por línea: persona · asunto · días), y si descartaste alguno dudoso, en una frase. Si no hay ninguno, dilo en una frase. Solo lees correo: nunca envías ni modificas nada en el buzón.
```

### 6.2 Sincronizar tareas desde Outlook (Haiku 4.5, L–V)

```
Sincroniza los correos con bandera de Outlook (mmillera@allsunhotels.com) hacia el tablero de Miguel Millera. Trabaja tú solo, sin subagentes, y termina con un resumen breve en español.

PASO 1 — Ya importados (Lovable query_database, project_id "10feea1a-0991-445b-bf44-934855fbfab7"):
SELECT outlook_source FROM public.tasks WHERE outlook_source IS NOT NULL;

PASO 2 — outlook_email_search con query "isflagged:true", limit 25, offset 0. Vienen de más reciente a más antiguo. Pide la página siguiente (offset 25, 50…) SOLO si el último correo de la página sigue dentro de los últimos 45 días. Máximo 4 llamadas. Quédate con internetMessageId, webLink, receivedDateTime, remitente y asunto.

PASO 3 — Filtra: últimos 45 días, no importados, sin remitentes automáticos (noreply@, tickets@, viajeselcorteingles, kiwi.com, eurowings), sin confirmaciones de reserva, billetes, recibos ni avisos de archivos compartidos. Abre con read_resource solo los que queden y tengan dudas.

PASO 4 — Inserta las nuevas en public.tasks en un único INSERT … ON CONFLICT DO NOTHING con: created_by '4f4895a6-b3b6-4b90-ac41-94d6b1c0740e', assigned_to '{}', status_key 'pendiente', priority_key 'alta', type_key 'operacional' (o 'seguimiento' + waiting_on si Miguel espera a un tercero), title accionable que empiece por verbo, meta 'Outlook · <remitente> · <d mmm>', outlook_source = internetMessageId, outlook_link = webLink tal cual, origin_date = fecha de recepción, department_id según contenido o NULL (mismos IDs de siempre: Bares 3ecb5181-c541-4e64-9952-b45e5f82029a · Cocina 90cd0d17-9a17-494d-932f-9b2cee0f8843 · Grecia 168925b2-3bc9-4e11-b29c-526d6a63bc1a · Canarias bb1a50e0-aaf8-4fcd-982a-daf1ad4fb6d0 · Marketing 7f654fda-1f76-4b3f-abf2-c458a7754c29 · Asesores 076b959a-d4ba-4b26-9a9e-ece2081bcc18 · Reposiciones ec431309-103c-4691-8040-71b91a24eeab · Personal a38f8c4d-39a7-4547-bcb6-107fe93faf60). Si el INSERT falla por nombre de columna, consulta information_schema.columns y reintenta una vez.

PASO 5 — Resumen: correos revisados, tareas nuevas (una por línea). Si no hay ninguna, una sola frase. Si falla algo, el error literal.
```

### 6.3 Radar F&B (Sonnet 5, sin cambios de fondo)
Mantener el prompt actual y añadir al final del PASO 2:

```
Topes de coste: abre como máximo 12 páginas en total y para en cuanto tengas 6 hallazgos válidos (o menos si ya hay 6 o más para esa semana en `hallazgos`: en ese caso, no añadas más y salta al PASO 3). No uses subagentes.
```

## 7. Cómo aplicarlo

- **Modelo, prompt y cron**: se cambian con `update_trigger` sin perder el historial. Lo puede hacer Claude con tu confirmación.
- **Conectores**: desde la configuración de cada rutina en claude.ai. `update_trigger` no permite cambiarlos.
- **Antes de aplicarlo a diario**: lanzar una vez cada rutina nueva con `fire_trigger` y comprobar el coste en `get_session` (campo `usage.cost_usd`).
