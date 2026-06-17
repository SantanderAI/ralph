# Acción: Review — curar las skills locales del proyecto

Tras completar el trabajo de una tarea, das un paso atrás y curas el conjunto de **skills locales** del proyecto (en `skills/`, al nivel de `plan/`) para que las próximas iteraciones del bucle planifiquen y ejecuten con menos palos de ciego. Lees el **plan y los logs** —como hace la review de la juez, pero con otro objetivo— y, en la misma pasada, **creas, extiendes o borras** esas skills.

A diferencia de la juez, que verifica con evidencia reproducible que **un bloque concreto** se hizo bien, el maestro no juzga ese bloque: destila el **aprendizaje acumulado** (metodologías que funcionaron, pitfalls repetidos, decisiones tomadas, conocimiento que ha caducado) en skills reutilizables.

## Cuándo

- **Cierre de cada tarea**: `fase0` inserta `/maestro review` como **última subtarea** de cada `plan/task/NN.md`. Al llegar a ella, el bucle invoca esta acción sobre el trabajo completado de esa tarea.
- **Invocación manual**: también puede lanzarse con `/maestro review` al margen del bucle. En ambos casos el comportamiento es el mismo y **plenamente autónomo**.

La review es **autónoma de principio a fin**: no pregunta al usuario, no espera aprobación ni confirmación, no deja decisiones pendientes de un humano. Diagnostica, decide y aplica los cambios sobre las skills locales con los criterios de abajo. Corre dentro del bucle `ralph` sin nadie delante.

Si no existe un workspace con `plan/` real sobre el que operar (p. ej. solo se está manteniendo esta skill), **no actúes**.

## Entradas (todas de solo lectura para el diagnóstico)

1. **`plan/plan.md`**: el **Objetivo**, las decisiones tomadas y el estado de las tareas. Fija contra qué se evalúa todo lo demás y revela decisiones locales que merecen convertirse en skill.
2. **`plan/task/*.md`**: qué se hizo y con cuánta fricción. Presta atención a los sufijos `— rechazado por juez (intento N): …` (un mismo tipo de criterio rechazado una y otra vez es un pitfall candidato) y a tareas que han quedado **obsoletas** (su tecnología o enfoque ya no aplican).
3. **`.ralph/logs/`**: logs de las iteraciones, leídos **del más reciente al más antiguo**. Aquí se ve dónde el bucle dio palos de ciego, qué errores se repitieron, qué callejones sin salida recorrió y qué descubrimiento le costó varios intentos.
4. **`skills/` (al nivel de `plan/`)**: las skills locales que **ya existen**. Imprescindible para saber qué está cubierto (extender, no duplicar) y qué ha quedado obsoleto (borrar).
5. **`AGENTS.md` / `CLAUDE.md`**: conocimiento ya documentado que **no** debes duplicar en una skill.

## Procedimiento (orquestado con subagentes)

La review **diagnostica con subagentes** y **construye el resultado con subagentes**, vía la herramienta `Task`/`Agent` de la sesión actual. Tú orquestas y decides; los subagentes recolectan y aplican.

### Paso 1 — Diagnóstico en paralelo

Lanza, **en paralelo**, varios subagentes de solo lectura, cada uno con un ángulo distinto y un encargo autónomo (pásale en su prompt las rutas, qué buscar y el formato de salida; no asumas que ve esta conversación). Reparto canónico:

- **Agente LOGS**: barre `.ralph/logs/` del más reciente al más antiguo y devuelve una lista de hallazgos: errores recurrentes, callejones sin salida, descubrimientos que costaron varios intentos. Cada hallazgo anclado en la línea o iteración concreta donde aparece.
- **Agente PLAN**: lee `plan/plan.md` y `plan/task/*.md` y devuelve: patrones de rechazo de la juez (mismo criterio reincidente), decisiones locales tomadas dignas de skill, y tareas/enfoques que han quedado obsoletos.
- **Agente INVENTARIO**: lista las skills locales existentes en `skills/` con su `description` y tipo, para saber la cobertura actual.

Cada subagente devuelve una **lista estructurada de hallazgos**, cada uno con su evidencia (línea de log, sufijo de rechazo, decisión del plan).

### Paso 2 — Síntesis (la haces tú, sin spawn)

Funde los hallazgos en una lista **deduplicada** de cambios candidatos, cada uno clasificado como **crear**, **extender** o **borrar** una skill local, y cada uno filtrado por:

- ¿Está **ya cubierto** por `AGENTS.md`, `CLAUDE.md` o una skill existente? → si sí, es **extender**, no crear; si ya está completo, descártalo.
- ¿Es **conocimiento durable y reutilizable** o un apunte efímero de esta iteración? → si es efímero, descártalo.
- ¿Tiene **evidencia concreta** que lo respalde? → si no, descártalo.

Decide los criterios por tipo:

- **Crear**: ha emergido una metodología no obvia que funcionó, un pitfall pisado repetidamente (con síntoma observable), o una decisión local que futuras iteraciones deben respetar, y **nada lo cubre todavía**.
- **Extender**: el conocimiento encaja en una skill existente (incluida `planificar` si lo aprendido afecta a cómo se desgranan las tareas) → enriquécela en vez de duplicar.
- **Borrar**: una skill ha quedado **genuinamente obsoleta** o **contradicha** por una decisión más reciente (p. ej. una skill de entorno Python tras migrar a Go). Ante la duda, **conserva** y anota la posible caducidad en su cuerpo en vez de borrar.

### Paso 3 — Construcción con subagentes

Para cada cambio aprobado, spawnea un subagente **constructor** (en paralelo entre skills distintas) que aplique el cambio sobre el fichero `skills/<nombre>/SKILL.md` correspondiente, respetando el formato de skill local (frontmatter `name` + `description` + `metadata.tipo`, cuerpo conciso de una sola preocupación). El encargo de cada constructor debe incluir: la ruta exacta del fichero, si es crear/extender/borrar, el conocimiento concreto a plasmar y su evidencia, y la regla de no duplicar lo ya cubierto. Para un borrado, el subagente elimina el directorio `skills/<nombre>/` de esa skill.

### Paso 4 — Informe en la conversación

Reporta brevemente: qué skills se **crearon**, **extendieron** o **borraron**, y el porqué (anclado en la evidencia) de cada una. Si no procedía ningún cambio, dilo explícitamente: una review sin cambios es un resultado válido, no un fallo.

## Reglas duras

- **No implementa código de producto** ni toca `plan/plan.md` ni `plan/task/*.md` (subtareas, checkpoints `[juez]`, sufijos de rechazo). El maestro solo escribe sobre las skills locales en `skills/`.
- **No duplica**: si `AGENTS.md`, `CLAUDE.md` o una skill local ya recogen el conocimiento, extiende lo existente; nunca crees un duplicado.
- **Evidencia obligatoria**: cada skill creada o borrada se ancla en algo concreto leído. Sin evidencia, no se actúa.
- **Borrado conservador**: solo se borra lo obsoleto o contradicho con evidencia; ante la duda, conservar.
- **Una preocupación por skill**: si un hallazgo mezcla dos conocimientos distintos, son dos skills (o dos secciones), no un cajón de sastre.
- **Autonomía de los subagentes**: cada uno recibe en su prompt todo lo que necesita (rutas, qué buscar/escribir, formato, reglas). No serialices lo que puede ir en paralelo ni paralelices lo que depende de la síntesis.
