# Acción: Set-up del plan

Inserta al inicio del fichero `plan/plan.md` del repositorio el bloque canónico de **«Instrucciones de bucle (ralph)»** que el `ralph-loop.sh` espera encontrar. La acción es **idempotente**: si el bloque ya existe (encabezado `## Instrucciones de bucle (ralph)`), no duplica ni reescribe nada.

## Cuándo

- El usuario invoca `/ralph set-up` o pide explícitamente preparar el plan para el bucle Ralph.
- Se está creando un nuevo `plan/plan.md` y todavía no tiene las instrucciones del bucle.
- Un `plan/plan.md` existente carece de la sección y se quiere homogeneizar con el resto de planes.

## Procedimiento

1. **Localiza el fichero**: el destino por defecto es `plan/plan.md` desde la raíz del repositorio. Si el usuario indica otra ruta, úsala. Si el fichero no existe, créalo con un encabezado mínimo `# Plan` y continúa.
2. **Detecta duplicados**: lee el fichero y busca un encabezado `## Instrucciones de bucle (ralph)`. Si **ya existe**, no toques nada y reporta en la conversación que el plan ya estaba preparado.
3. **Decide el punto de inserción**:
   - Si el fichero empieza con un encabezado `# …` (H1), inserta el bloque **inmediatamente después** del H1 (y de la línea en blanco que lo sigue, si la hay).
   - Si no hay H1, inserta el bloque al **inicio** del fichero.
   - El bloque va siempre **antes** de cualquier sección `## Objetivo`, `## Contexto`, `## Tareas`, etc.
4. **Inserta el bloque** literal de abajo, respetando el formato exacto (saltos de línea, comillas, negritas).
5. **Confirma en la conversación**: di si se insertó o si ya estaba, y en qué fichero.
6. **Comprueba si el plan tiene subtareas**: después de la inserción, busca en `plan/plan.md` cualquier línea con `- [ ]` o `- [x]`. Si **no hay ninguna** (el plan tiene objetivo/contexto pero no lista de tareas accionable), sugiere al usuario ejecutar `/ralph fase0` para descomponer el plan en ficheros `plan/task/NN.md` antes de arrancar el bucle. Mensaje sugerido: «El plan no contiene subtareas marcables; invoca `/ralph fase0` para expandirlo en `plan/task/NN.md` accionables, o añádelas a mano si prefieres.» No ejecutes `fase0` tú; solo sugiere.

## Bloque canónico a insertar

```markdown
## Instrucciones de bucle (ralph)

Cada iteración ejecuta **una sola** acción y termina. No encadenes tareas.

1. **Localizar la siguiente subtarea**:
   - Recorre `plan.md` de arriba a abajo y encuentra el primer `[ ]`.
   - Si la línea enlaza a un fichero `task/NN.md`, abre el fichero y repite la búsqueda recursivamente dentro de él hasta llegar a una subtarea `[ ]` hoja (sin enlace).
   - Si no encuentras ningún `[ ]` en ninguna parte → **crea `plan/stop.md`** con una nota breve ("plan completo, sin subtareas pendientes") y **para**. El fichero `stop.md` es la señal que `ralph-loop.sh` usa para detenerse; sin él el bucle sigue iterando aunque no haya trabajo.
2. **Ejecutar esa única subtarea**:
   - Subtarea normal: realízala y márcala `[x]`.
   - Subtarea `[juez]`: invoca la skill `juez` sobre el repositorio pasándole las instrucciones del fichero `task/NN.md` correspondiente. La skill juzgará la evidencia y actualizará el fichero.
   - Si la subtarea consiste en **añadir** nuevas subtareas o crear un nuevo `task/NN.md`: añádelas y **no las ejecutes**; crear tareas cuenta como la acción única de la iteración.
   - **Excepción**: si al inspeccionar la subtarea descubres que el trabajo **ya está hecho** (el código/artefacto/condición existe sin necesidad de cambios), márcala `[x]` y **continúa con la siguiente subtarea en la misma iteración**. Marcar tareas ya completadas no cuenta como la acción única del bucle; solo el trabajo real (implementar, crear tareas, invocar a la juez) consume la iteración.
3. **Propagar hacia arriba**:
   - Tras marcar una subtarea, si **todas** las subtareas del `task/NN.md` están `[x]`, marca también la entrada correspondiente en `plan.md` como `[x]`.
4. **Parar**. No busques la siguiente subtarea, no encadenes iteraciones.
```

## Reglas duras

- **Idempotente**: no insertes el bloque dos veces. Si el encabezado `## Instrucciones de bucle (ralph)` ya está presente, no edites el fichero.
- **No reescribes contenido existente**: solo insertas el bloque. No tocas el resto del plan (objetivo, decisiones, lista de tareas, etc.).
- **No ejecutas el bucle**: esta acción solo prepara el fichero. No interpreta tareas, no llama a la juez, no crea `stop.md`.
- **No creas ficheros bajo `plan/task/`**: solo toca `plan/plan.md` (creándolo si no existe).
