# Propuesta v2 de las tareas de correo

Fecha: 3 de octubre de 2026. Base: la prueba de Seguimientos de las 10:13 UTC (2,12 $) y una tarea mínima de control.

## Qué se midió

**Seguimientos, prueba de hoy (Sonnet 5): 2,12 $, 9 min, 37 turnos.**

| Concepto | Dato |
|---|---|
| Arranque fijo de cada ejecución | 110.000 tokens (≈ 0,9 $ de los 2,12 $, un 42 %) |
| Resultados de Outlook | 78.000 tokens |
| de ellos, listado de 137 correos enviados (6 páginas de 25) | 55.000 tokens (70 %) |
| de ellos, 22 comprobaciones de respuesta (≈ 4,5 KB cada una) | 23.000 tokens |
| Razonamiento interno | 46.000 tokens (≈ 0,46 $) |
| Seguimientos encontrados | 12 |

**Tarea mínima de control (Haiku, sin conectores, «responde OK»): arranque de 32.335 tokens, 0,016 $.**
La misma clase de tarea con tus conectores arrancó con ≈ 75.000 (Haiku) y 110.000 (Sonnet).
Es decir, entre 40.000 y 75.000 tokens de cada arranque dependen de los conectores y del entorno de Cowork.

## Por qué costaba tanto

La ventana era de 45 días y se repetía cada día: el 90 % de lo que se revisaba hoy ya se revisó ayer.
La versión del 3-oct ya usaba una ventana de hace 6 a hace 3 días, pero eso son 3 días de correo (137 correos) para que cada día entre solo uno nuevo.

## Diseño propuesto (Seguimientos)

- **Una sola tarea, un solo trabajo.** Partirla en varias no ahorra nada: cada tarea paga su arranque fijo.
- **Ventana de 24 horas, solo de lunes a viernes:** de martes a viernes, los correos enviados entre hace 96 y hace 72 horas; el lunes, entre hace 144 y hace 72 horas (de martes a viernes de la semana anterior). Así cada correo se revisa exactamente una vez, sin huecos ni solapes, aunque no corra en fin de semana. El lunes cuesta unas 3 veces más (más páginas de listado).
- **≈ 34 correos al día en vez de 137:** 2 páginas de listado en vez de 6.
- **Una consulta a la base de datos.** Las claves (`pendiente`, `seguimiento`, `alta`) están fijas. Un único INSERT con `ON CONFLICT DO NOTHING`. El límite de acciones gratuitas de Lovable no vuelve a ser un problema.
- **Topes duros:** 12 llamadas a Outlook, 15 comprobaciones de respuesta, 2 consultas a la base de datos.
- **Modelo:** Haiku 4.5. Si en una semana comete errores al juzgar qué es una petición, pasar a Sonnet 5.

### Coste estimado por ejecución

| | Con los conectores de hoy | Con solo 2 conectores |
|---|---|---|
| Haiku 4.5 | ≈ 0,35–0,40 $ | ≈ 0,25 $ |
| Sonnet 5 | ≈ 1,00 $ | ≈ 0,60 $ |

Al mes (30 días): Haiku ≈ 8–12 $, Sonnet ≈ 18–32 $. Antes: más de 550 $.

## Prompt propuesto

```
Eres el asistente de Miguel Millera (mmillera@allsunhotels.com), Director F&B Corporativo de allsun Hotels. Tarea diaria, BARATA y simple: encuentra correos en los que Miguel pidió algo y nadie ha contestado, y créalos como tareas de seguimiento.

REGLAS DE COSTE (obligatorias)
- Trabaja tú solo: no uses la herramienta Agent ni escribas scripts para copiar datos.
- No razones largo: decide cada correo en una línea.
- Máximo 12 llamadas a Outlook y 2 consultas a la base de datos. Si llegas al tope, para, inserta lo ya confirmado e indícalo.

PASO 1 — Listar. Con outlook_email_search sobre la carpeta de enviados de mmillera@allsunhotels.com, trae los correos con sentDateTime entre hace 96 horas y hace 72 horas (afterDateTime = hace 96 h; si la herramienta no admite límite superior, descarta tú los posteriores a hace 72 h). limit 25, y pide la página siguiente (offset 25, 50) solo si la respuesta trae nextOffset y sigue habiendo correos dentro de la ventana. Máximo 3 páginas. De cada correo apunta solo: internetMessageId, webLink, sentDateTime, destinatario principal, asunto y el campo summary.

PASO 2 — Filtrar sin abrir cuerpos. Quédate con los que piden algo claro a otra persona: información, acción, confirmación, decisión, presupuesto, plazo. Descarta acuses de recibo, agradecimientos, confirmaciones de reunión, reenvíos informativos, respuestas que cierran el tema y mensajes a listas de distribución. Máximo 15 candidatos: si hay más, quédate con los 15 más claros e indícalo.

PASO 3 — ¿Contestaron? Para cada candidato, UNA búsqueda: outlook_email_search con el asunto sin prefijos RE:/RV:/FW:, afterDateTime = fecha de envío, limit 3. Si hay un correo posterior del destinatario o de su buzón en ese hilo, está contestado: descártalo. Si no hay nada, es un seguimiento. Si dudas, créalo.

PASO 4 — Insertar. Con query_database de Lovable (project_id "10feea1a-0991-445b-bf44-934855fbfab7"), UN solo INSERT en public.tasks con todas las filas y ON CONFLICT DO NOTHING, con:
- created_by '4f4895a6-b3b6-4b90-ac41-94d6b1c0740e', assigned_to '{}'
- status_key 'pendiente', type_key 'seguimiento', priority_key 'alta'
- waiting_on: nombre de la persona a la que se espera (nunca vacío)
- title: empieza por verbo y nombra a la persona y el asunto; no copies el asunto tal cual
- meta: 'Seguimiento · esperando a <nombre> · enviado el <d mmm> · <N> días sin respuesta'
- outlook_source: internetMessageId completo con sus ángulos; outlook_link: webLink tal cual; origin_date: fecha de envío
- department_id según contenido o NULL: Bares 3ecb5181-c541-4e64-9952-b45e5f82029a · Cocina 90cd0d17-9a17-494d-932f-9b2cee0f8843 · Grecia 168925b2-3bc9-4e11-b29c-526d6a63bc1a · Canarias bb1a50e0-aaf8-4fcd-982a-daf1ad4fb6d0 · Marketing 7f654fda-1f76-4b3f-abf2-c458a7754c29 · Asesores 076b959a-d4ba-4b26-9a9e-ece2081bcc18 · Reposiciones ec431309-103c-4691-8040-71b91a24eeab · Personal a38f8c4d-39a7-4547-bcb6-107fe93faf60
Solo si el INSERT falla por una clave foránea, haz UNA consulta a task_types/task_priorities y reintenta una vez. Si falla por el límite de la base de datos, no insistas: da el error literal y la lista de seguimientos para insertarlos después.

PASO 5 — Resumen breve en español: correos enviados revisados, seguimientos creados (persona · asunto · días sin respuesta, uno por línea), y una frase con los dudosos descartados. Si no hay ninguno, dilo en una frase. Esta tarea solo lee correo: nunca envía, responde ni modifica nada en el buzón.
```

Horario aplicado: de lunes a viernes, 07:52 hora de Madrid (`CRON_TZ=Europe/Madrid 52 7 * * 1-5`). Sincronizar Outlook: lunes a viernes, 06:52 (`CRON_TZ=Europe/Madrid 52 6 * * 1-5`).

Nota: el prompt aplicado en la tarea incluye la regla del lunes y topes mayores ese día (20 llamadas a Outlook, 5 páginas, 25 candidatos). El texto del bloque anterior es la versión previa de 24 h diarias.

## Qué no se puede hacer desde Claude Code

- Una tarea creada con la herramienta de Claude Code **nace sin ningún conector** y corre en otro entorno, así que no puede leer Outlook ni escribir en Lovable. Una tarea nueva con conectores solo se puede crear desde claude.ai (Routines) o desde un chat de Cowork.
- Las tareas existentes se pueden retocar (prompt, modelo, horario) con la herramienta, pero no sus conectores.

## Versión 3 del prompt de Seguimientos (3-oct, aplicada)

Cambios respecto a la versión anterior:
- Lista cerrada de herramientas: solo `outlook_email_search` y `query_database`; no abre cuerpos de correo ni usa otras herramientas.
- Listado con `folderName "Sent Items"` y `afterDateTime`/`beforeDateTime` exactos (ya no descarta a mano los correos fuera de ventana).
- Comprobación de respuesta más estricta: busca por asunto **y** por remitente (el destinatario original); un correo de la misma persona sobre otro asunto no cuenta como respuesta. Motivo: en la prueba del 3-oct la versión anterior citó como respuesta un correo de Inma sobre otro tema.
- Si no hay seguimientos, no hace ninguna consulta a la base de datos (0 en vez de 1).
- Los candidatos con duda sobre si son una petición se descartan; los que tienen duda sobre si contestaron se crean.
- Sigue con Haiku 4.5, de lunes a viernes a las 07:05 (Madrid).
