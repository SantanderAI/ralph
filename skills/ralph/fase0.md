# Acción: Fase 0 — expandir el plan en ficheros de tarea accionables

Descompone el `plan/plan.md` del repositorio en N ficheros `plan/task/NN.md`, uno por cada tarea descrita en el plan, dejándolos listos para que el bucle `ralph-loop.sh` los recorra sin requerir intervención humana. La acción **orquesta subagentes en paralelo** (vía la herramienta `Task`/`Agent` de la sesión actual): un agente por acción y por fichero.

## Cuándo

- El usuario invoca `/ralph fase0` o pide explícitamente «hacer la fase 0», «expandir el plan en tareas», «preparar las tareas del plan».
- Existe ya un `plan/plan.md` con el bloque de instrucciones del bucle (puesto por `/ralph set-up`) y una sección de objetivo + lista de tareas de alto nivel.

## Precondición dura: el plan debe existir

1. Localiza `plan/plan.md` (o la ruta que el usuario haya indicado).
2. Si **no existe**, **aborta** sin hacer nada más. Reporta literalmente en la conversación:

   > No puedo ejecutar `/ralph fase0`: no existe `plan/plan.md`. No se puede hacer una fase 0 sobre un plan inexistente. Crea el plan primero (puedes invocar `/ralph set-up` para inicializarlo con la cabecera canónica del bucle) y vuelve a llamarme.

   No crees el plan tú. No infieras tareas. No continúes con ningún otro paso.

3. Si existe pero no tiene el bloque `## Instrucciones de bucle (ralph)`, **no abortes**: el primer subagente del flujo (Agente S, ver Paso 1a) se encargará de insertar la cabecera canónica invocando la acción `set-up` de esta misma skill antes de continuar con el breakdown.

## Visión general del flujo

```
plan/plan.md (existe)
      │
      ▼
  ┌─────────────────────────┐
  │ Agente S: SET-UP         │   1 subagente único, SOLO si falta la cabecera
  │  inserta el bloque       │   `## Instrucciones de bucle (ralph)` invocando
  │  canónico del bucle      │   la acción `set-up` de esta skill.
  └─────────────────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │ Agente A: BREAKDOWN     │   1 subagente único
  │  consulta `planificar`  │   → si existe skills/planificar/SKILL.md, sigue su
  │  (si existe), lee plan,  │     metodología de troceado para este proyecto
  │  genera plan/task/NN.md  │   → crea plan/task/NN.md vacíos-pero-estructurados
  │                          │   → añade enlaces `- [ ] [N. titulo](task/NN.md)` en plan.md
  └─────────────────────────┘
              │
              ▼
  Para cada plan/task/NN.md, en paralelo entre ficheros, secuencial dentro:
  ┌─────────────────────────┐
  │ Agente B: CONTEXTO       │   valida que los enlaces y supuestos del task
  │  (1 por fichero)         │   siguen vigentes contra el estado actual del repo,
  │                          │   y actualiza el task si algo ha cambiado.
  └─────────────────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │ Agente C: ESFUERZO       │   intercala subtareas de cambio de capacidad
  │  (1 por fichero)         │   (`[esfuerzo low|med|high]`) según la naturaleza
  │                          │   de cada bloque.
  └─────────────────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │ Agente D: JUEZ-PLANEAR   │   invoca la skill `juez` (acción planear) sobre
  │  (1 por fichero)         │   el task para insertar los `[juez]` y
  │                          │   `[crear evidencia]` que falten.
  └─────────────────────────┘
```

Los agentes B, C y D corren **secuenciales dentro de un mismo fichero** (cada uno depende del resultado del anterior) pero **en paralelo entre ficheros**: lanza todos los pipelines B→C→D a la vez, uno por task generado.

## Procedimiento

### Paso 0 — Verificar precondiciones

- `plan/plan.md` existe (si no, aborta como arriba).
- `plan/task/` no existe o está vacío. Si ya contiene `NN.md`, **no sobrescribas**: pregunta al usuario si quiere descartar y re-generar, o si prefiere abortar. Sin respuesta clara, aborta.
- Lee `AGENTS.md` y `CLAUDE.md` del repo si existen y respétalos (rutas, comandos, convenciones).
- Comprueba si `plan/plan.md` contiene el encabezado `## Instrucciones de bucle (ralph)`. Si **no** está presente, ejecuta primero el Paso 1a (Agente S). Si **ya** está, sáltatelo y ve directo al Paso 1.

### Paso 1a — Agente S: set-up (solo si falta la cabecera del bucle)

Spawnea **un** subagente con el siguiente encargo:

> Ejecuta la acción `set-up` de la skill `ralph` (equivalente a `/ralph set-up`) sobre `plan/plan.md` del repositorio. Esa acción inserta el bloque canónico `## Instrucciones de bucle (ralph)` siguiendo las reglas duras descritas en `skills/ralph/set-up.md` (idempotente, sin reescribir contenido existente, sin crear ficheros bajo `plan/task/`, sin ejecutar el bucle). No hagas nada más: no descompongas tareas, no toques otros ficheros, no sugieras `/ralph fase0` al usuario (ya estamos dentro de fase0). Salida esperada: `plan/plan.md` con la cabecera canónica del bucle insertada en el lugar correcto.

Espera a que S termine y verifica que el bloque `## Instrucciones de bucle (ralph)` quedó insertado antes de continuar con el Paso 1. Si tras S la cabecera sigue faltando, aborta y reporta al usuario qué ha fallado.

### Paso 1 — Agente A: breakdown del plan

Spawnea **un** subagente con el siguiente encargo (resumen; adáptalo a la herramienta `Task`/`Agent` que tengas disponible):

> Antes de descomponer, comprueba si existe la skill local `planificar` en `skills/planificar/SKILL.md` (en `skills/`, al mismo nivel que `plan/`, en la raíz del workspace). Si existe, **léela y sigue su metodología y sus criterios** para trocear el objetivo —granularidad, prerrequisitos, orden de las tareas y convenciones de este proyecto—: es el conocimiento de planificación que el maestro ha acumulado para este repositorio. Si no existe, descompón con tu criterio habitual. La skill `planificar` se consulta **solo y exclusivamente** en esta fase 0; no la invoques en ningún otro momento del bucle.
>
> Lee `plan/plan.md`. Identifica cada tarea descrita (las que el usuario quiere ejecutar, no la cabecera de instrucciones ni meta-secciones). Por cada una, crea `plan/task/NN.md` con `NN` empezando en `00` y la siguiente estructura mínima:
>
> ```markdown
> # Tarea NN — <título conciso>
>
> ## Objetivo
> <una o dos frases que digan qué condición queda satisfecha al terminar>
>
> ## Contexto enlazado
> <enlaces a ficheros del repo, documentos, otros tasks, decisiones previas relevantes>
>
> ## Restricciones
> - <reglas duras a respetar: rutas, librerías prohibidas, compatibilidad, etc.>
>
> ## Happy path (ejemplo pequeño)
> <descripción breve y concreta de cómo se vería el sistema funcionando tras la tarea; sin código>
>
> ## Subtareas
> - [ ] <primera subtarea concreta>
> - [ ] <…>
> - [ ] Invocar la acción `review` de la skill `maestro` (`/maestro review`) sobre el trabajo completado de esta tarea, y resolver lo que indique antes de darla por terminada.
> ```
>
> Reglas duras:
> - **Sin código** en los task. Ni snippets, ni diffs, ni comandos largos. Referencias por ruta + descripción.
> - Las subtareas deben ser **acciones concretas y verificables**, nunca cualitativas: ❌ «comprobar calidad», ✅ «asegurar que el endpoint `/healthz` responde 200 en < 300 ms bajo el script `scripts/load_healthz.sh`».
> - Las subtareas **no pueden requerir intervención humana** de ningún tipo (no «pedir credenciales al usuario», no «esperar aprobación», no «abrir un PR y esperar review»). Si una acción requiere algo del exterior, modélala como precondición a obtener automáticamente o márcala fuera de alcance.
> - La **primera subtarea** de cada task debe ser literalmente: `- [ ] Validar contra el estado actual del repo que el contexto enlazado de este fichero sigue actualizado y es relevante; si no, actualizar las secciones afectadas antes de continuar.` (el Agente B la dejará lista, el bucle ralph la ejecutará en su primera iteración como parte del trabajo real).
> - La **última subtarea** de cada task debe ser literalmente: `- [ ] Invocar la acción `review` de la skill `maestro` (`/maestro review`) sobre el trabajo completado de esta tarea, y resolver lo que indique antes de darla por terminada.` Es el cierre de revisión global del task y va **al final del listado**, después de todas las subtareas de implementación y de sus checkpoints de juez.
> - Después, edita `plan/plan.md` para sustituir o complementar la lista de tareas de alto nivel con entradas `- [ ] [NN. <título>](task/NN.md)`, respetando el orden del plan original y sin tocar el bloque `## Instrucciones de bucle (ralph)` ni secciones ya marcadas `[x]`.

Espera a que A termine antes de continuar.

### Paso 2 — Pipelines B→C→D por fichero, en paralelo entre ficheros

Lista los `plan/task/NN.md` recién creados. Por **cada** fichero, lanza en paralelo un pipeline que ejecute B, C y D **en orden** (C necesita la salida de B; D necesita la salida de C).

#### Agente B (uno por fichero) — Validación de contexto

Encargo al subagente:

> Para `plan/task/NN.md`: comprueba que cada referencia de la sección **Contexto enlazado** sigue siendo válida y relevante contra el estado **actual** del repositorio (rutas existen, decisiones previas siguen vigentes, fases anteriores no han invalidado los supuestos). Si algo ha cambiado, actualiza el fichero (contexto, restricciones, happy path, subtareas) para reflejar el nuevo estado. No toques otros ficheros. No ejecutes el plan; solo prepara el task. Salida: el fichero queda con el contexto coherente con el repo de hoy.

#### Agente C (uno por fichero) — Intercalado de esfuerzo

Encargo al subagente:

> Para `plan/task/NN.md`: intercala subtareas que **cambien la capacidad del modelo** que usa el bucle ralph, de modo que cada bloque de trabajo use el modelo más pequeño posible.
>
> **Regla crítica de formato — las marcas de esfuerzo son SUBTAREAS INDEPENDIENTES**, no etiquetas sobre una subtarea de contenido. Cada cambio de esfuerzo ocupa su **propio bullet**, cuya única acción es editar `.ralph/.env`. El bucle ralph recarga `.ralph/.env` **al inicio de la siguiente iteración**, así que la subtarea que se beneficia del nuevo modelo es la **inmediatamente posterior** al bullet de cambio. Si pegas `[esfuerzo high]` como prefijo de una subtarea con trabajo real (p. ej. `- [ ] [esfuerzo high] Implementar parser`), esa misma subtarea se ejecutará **con el modelo viejo** y el nuevo modelo solo entrará en la siguiente — lo contrario de lo que querías. **Nunca** uses `[esfuerzo X]` como tag inline sobre una subtarea de contenido.
>
> Formato exacto (un bullet por cambio, sin trabajo extra en la línea):
>
> ```
> - [ ] [esfuerzo low] Configurar capacidad baja: sustituir la línea `RALPH_MODEL_CAPABILITY=...` de `.ralph/.env` por `RALPH_MODEL_CAPABILITY=low`.
> - [ ] [esfuerzo med] Configurar capacidad media: sustituir la línea `RALPH_MODEL_CAPABILITY=...` de `.ralph/.env` por `RALPH_MODEL_CAPABILITY=med`.
> - [ ] [esfuerzo high] Configurar capacidad alta: sustituir la línea `RALPH_MODEL_CAPABILITY=...` de `.ralph/.env` por `RALPH_MODEL_CAPABILITY=high`.
> ```
>
> Colocación: el bullet de cambio va **inmediatamente antes** de la subtarea que debe ejecutarse con el nuevo modelo (esa siguiente subtarea es la primera que se beneficia). La aproximación canónica:
>
> 1. `[esfuerzo low]` justo antes de subtareas de **scaffold / boilerplate / cambios mecánicos**.
> 2. `[esfuerzo med]` justo antes de **diseñar tests** o **implementar funcionalidad de complejidad normal**.
> 3. `[esfuerzo high]` justo antes de **bloques de razonamiento difícil** y justo antes de **los `[juez]`** que recogen evidencia.
>
> Aplica esta plantilla con criterio: si la tarea es enteramente mecánica, basta con un `low` al inicio y subir solo justo antes del `[juez]`. Si toda ella es razonamiento, empieza ya en `med` o `high`. No emitas un cambio de esfuerzo redundante (no repitas `[esfuerzo med]` si la subtarea anterior ya lo dejó en `med`).

#### Agente D (uno por fichero) — Planificación de juez

Encargo al subagente:

> Para `plan/task/NN.md`: invoca la skill `juez` en modo planear (`/juez planear` o equivalente: «planear los `[juez]` y `[crear evidencia]` que falten en este fichero»). El objetivo es asegurar que cada subtarea o bloque de implementación termine con un `[juez]` que recoja evidencia reproducible, y que ese `[juez]` esté precedido por la subtarea `[crear evidencia]` correspondiente cuando proceda. No implementes ningún código de producto: solo planifica los checkpoints. Respeta el formato y las reglas duras de la skill `juez` (una línea por feedback, sin código en la task, evidencia determinista). **No toques la última subtarea** (la invocación de `/maestro review`): debe seguir siendo la última línea del listado; coloca tus checkpoints `[juez]` y `[crear evidencia]` **antes** de ella, nunca después.

### Paso 3 — Sanity check final (lo haces tú, sin spawn)

Tras volver todos los pipelines:

1. Recorre cada `plan/task/NN.md` y verifica:
   - Tiene las secciones `Objetivo`, `Contexto enlazado`, `Restricciones`, `Happy path`, `Subtareas`.
   - Su primera subtarea es la de validación de contexto.
   - Su **última** subtarea es la invocación de `/maestro review` (acción `review` de la skill `maestro`), sin nada después de ella.
   - No contiene bloques de código (` ``` `).
   - Tiene al menos un `[juez]` y, si los `[juez]` requieren artefacto reproducible, su `[crear evidencia]` antes.
   - Hay al menos una marca `[esfuerzo …]` (o se justifica en la conversación por qué no aplica a este task). Cada `[esfuerzo …]` está en **su propio bullet**, sin trabajo de producto en la misma línea (solo la edición de `.ralph/.env`). Si encuentras `[esfuerzo X]` como prefijo de una subtarea con otra acción, recházalo y pide al agente C que lo separe en dos bullets (el cambio de esfuerzo, y debajo la subtarea de contenido que se beneficia).
   - Ninguna subtarea requiere intervención humana (busca patrones como «pedir», «confirmar con», «esperar aprobación», «manualmente»). Si encuentras alguna, repórtalo al usuario; no la edites tú a la fuerza.
2. Verifica que `plan/plan.md` enlaza a todos los `task/NN.md` generados, en orden, y que no se ha tocado el bloque `## Instrucciones de bucle (ralph)` ni las entradas `[x]` previas.
3. Reporta al usuario: nº de tasks generados, ruta de cada uno, y cualquier incidencia detectada en el sanity check.

## Reglas duras

- **Sin plan, sin fase 0**. Si no existe `plan/plan.md`, aborta con el mensaje del Paso 0. No crees el plan, no lo infieras.
- **`planificar` es opcional y exclusiva de fase 0**. Si existe `skills/planificar/SKILL.md`, el Agente A sigue su metodología al descomponer; si no, descompone con criterio propio (su ausencia nunca aborta). Esta skill se consulta solo aquí, nunca en la ejecución del bucle.
- **Un agente por acción y por fichero** (excepto el breakdown inicial, que es un único agente sobre el plan completo). No serialices lo paralelo, no paralelices lo secuencial dentro de un mismo fichero.
- **Cada agente debe poder operar autónomamente**: pásale en su prompt la ruta del fichero a tocar, las reglas duras aplicables, y la salida esperada. No asumas que ve el resto de la conversación.
- **No ejecutes el bucle**: esta acción solo prepara el plan y sus tasks. No invoca a `ralph-loop.sh`, no resuelve subtareas, no llama a la juez para juzgar evidencia (solo para planear los checkpoints en el Agente D).
- **No toques las instrucciones del bucle** ni las entradas ya `[x]` del plan.
- **No crees ficheros fuera de `plan/`**. Si el breakdown requiere artefactos auxiliares, modélalos como subtareas dentro del task correspondiente.
- **Sin código en los task**: si un subagente devuelve un task con snippets, recházalo y vuelve a pedirlo sin código.
