# Acción: Desatascar el bucle (`[juez desatascar]`)

Se dispara cuando un bloque acumula rechazos (al quinto, `juzgar.md` inserta una subtarea `[juez desatascar]` antes del `[juez]`). Su misión: averiguar **por qué el bloque se atasca** y, si el bucle persigue un criterio **inalcanzable tal como está planteado** (arnés que mide lo que no debe, criterio contradictorio, capacidad ausente…), documentar el problema y su solución en el fichero de tarea e insertar una subtarea de **implementación del arreglo** antes del `[juez]`. **No implementa**: solo diagnostica, documenta e inserta la tarea.

Es distinta de `auditar.md`: aquélla audita el plan global en solo lectura bajo invocación del usuario; ésta es automática, se centra en **un bloque atascado** concreto y **sí edita** el fichero de tarea de ese bloque.

## Cuándo

Hay una subtarea `[juez desatascar]` pendiente `[ ]` (es el primer `[ ]` del fichero, justo antes de un `[juez]`). Es la acción de mayor prioridad entre las automáticas: diagnostica antes de seguir juzgando.

## Entradas

1. **`plan/plan.md`**: el Objetivo y la posición del bloque en el plan.
2. **El `plan/task/NN.md` del bloque**: el `[juez]` atascado, su Alcance, sus **Criterios de aceptación** y **Evidencias requeridas**, y el historial de rechazos (sufijos `— rechazado por juez (intento N): …`). Lee la razón repetida: si es la misma una y otra vez, es señal fuerte de criterio mal planteado.
3. **`.ralph/logs/`** (vía **subagentes**, ver abajo): qué falla **de verdad** en cada iteración (error exacto, señal, comando que peta), y si el patrón se repite idéntico.
4. **El código de la evidencia / arnés** que la juez ejecuta (el comando de "Evidencias requeridas", el script de `[crear evidencia]`, etc.): aquí suele estar la raíz. Léelo en solo lectura.

## Procedimiento

1. **Reúne el contexto sin saturarte**: lee `plan/plan.md`, el fichero de tarea del bloque y el código del arnés/evidencia. **No** vuelques los logs enteros en tu contexto.
2. **Delega los logs en subagentes**: lanza uno o varios subagentes que recorran `.ralph/logs/` (del más reciente al más antiguo) y devuelvan **solo la conclusión destilada**, no el log crudo:
   - el comando de evidencia que falla y su **código/seña de salida exacta** (p. ej. `exit -11` = SIGSEGV, `exit 137` = OOM-kill, traceback de `MemoryError`, assertion concreta…),
   - si el fallo es **idéntico** entre iteraciones (mismo error, misma línea) pese a que el implementador cambió el código → fortísima señal de que el problema no está donde se rechaza,
   - cualquier pista de que el arnés mide algo distinto del criterio.
   Si hay varios tramos de log, reparte el trabajo entre subagentes y consolida tú las conclusiones.
3. **Diagnostica la causa raíz** cruzando el criterio, el arnés y la señal de fallo real. Responde a una pregunta binaria: **¿el criterio es alcanzable tal como está planteado y evaluado?**
   - **Inalcanzable / mal planteado** si, por ejemplo: el arnés mide una magnitud distinta de la del criterio (caso típico: limitar espacio de direcciones virtual con `RLIMIT_AS` para comprobar un tope de RSS → SIGSEGV de motores como DuckDB/Arrow, que no es un OOM); el criterio se contradice; exige una capacidad/recurso que no existe; la evidencia falla siempre por el mismo motivo ajeno a lo que el implementador toca.
   - **Alcanzable** si el criterio y el arnés son correctos y el fallo es atribuible a la implementación, que simplemente aún no cumple.
4. **Actúa según el diagnóstico** (ver abajo). En ambos casos, **marca la subtarea `[juez desatascar]` como `[x]`** y detén el bucle.

## Acción según diagnóstico

### A — Criterio inalcanzable tal como está (hay un imposible que arreglar)

1. **Escribe un bloque de diagnóstico** en el fichero de tarea del bloque, con un encabezado claro, p. ej. `## Diagnóstico de bucle (juez desatascar) — <bloque>`. A diferencia del feedback de una línea de `juzgar.md`, este bloque **sí** es detallado y técnico. Contiene:
   - **Problema**: la causa raíz, anclada en la evidencia concreta (la seña de salida real, por qué el arnés/criterio no puede cumplirse, qué se está midiendo mal). Explica por qué los rechazos previos eran espurios si lo eran.
   - **Solución**: el arreglo concreto y accionable (qué cambiar y dónde: el arnés, el criterio, la evidencia o el código de producción), suficiente para que el implementador lo aplique sin volver a investigar.
2. **Inserta una subtarea de implementación** del arreglo, inmediatamente **antes** de la subtarea `[juez]` del bloque (y antes de cualquier `[crear evidencia]`/`[preparación entorno]` si el arreglo es prerrequisito de ellos), referida al bloque de diagnóstico. Es una subtarea normal `[ ]` que ejecutará el implementador en la siguiente iteración. Formato:
   ```
   - [ ] aplicar el arreglo descrito en «Diagnóstico de bucle (juez desatascar)»: <resumen de una línea del cambio>
   ```
3. **Si el arreglo invalida un criterio o evidencia mal planteados**, ajústalos en la propia subtarea `[juez]` para que midan la propiedad correcta (esta acción **sí** puede editar el criterio/evidencia del `[juez]` del bloque atascado; es la excepción a la regla general de no tocar las `[juez]`). No inventes criterios nuevos no relacionados.
4. **No desmarques** la(s) subtarea(s) de implementación originales si su rechazo era espurio (no eran el problema): déjalas `[x]` con su sufijo de historial. Lo que falta es el arreglo recién insertado.
5. Marca `[juez desatascar]` como `[x]`, resume en la conversación el problema y la solución, y **detén el bucle**.

### B — Criterio alcanzable (no hay imposible; sigue el ciclo normal)

1. **No** escribas bloque de diagnóstico ni insertes tarea de arreglo: el problema es la implementación, que debe seguir reintentándose.
2. Para que el ciclo normal continúe (en el quinto rechazo `juzgar.md` dejó la implementación en `[x]` sin desmarcar), **desmarca** ahora la(s) subtarea(s) de implementación del Alcance a `[ ]`, **conservando** su sufijo `— rechazado por juez (intento 5): …` como historial. Así la siguiente iteración la re-implementa y la juez retomará la cuenta hacia el umbral de 10.
3. Marca `[juez desatascar]` como `[x]`, deja en la conversación una línea explicando por qué el criterio sí es alcanzable, y **detén el bucle**.

> En el caso B, los siguientes rechazos (intentos 6→10) los gestiona `juzgar.md` por la rama de "Re-rechazo por debajo del umbral", **sin** volver a insertar otro desatascado (ya existe un `[juez desatascar]` para este bloque), hasta el décimo, que emite `stop.md` como siempre.

### Si no puedes decidir con confianza

Si tras revisar no tienes evidencia suficiente para afirmar que el criterio es inalcanzable, trátalo como **caso B** (no fabriques un arreglo dudoso): es más seguro dejar que el ciclo siga y, llegado el caso, que el décimo rechazo fuerce intervención humana vía `stop.md`.

## Reglas duras

- **No implementa código**: ni de producto ni del arnés. Solo escribe el bloque de diagnóstico, inserta la subtarea de implementación y, en su caso, ajusta el criterio/evidencia del `[juez]` atascado. El arreglo lo aplica el implementador después.
- **Edita solo el fichero de tarea del bloque** (`plan/task/NN.md`): el bloque de diagnóstico, la subtarea de arreglo, el estado de `[juez desatascar]` y, en el caso A, el criterio/evidencia del `[juez]` afectado. No toca `plan/plan.md` ni otros ficheros de tarea.
- **Logs vía subagentes**: nunca cargues los `.ralph/logs/` enteros en tu propio contexto; delega y consolida conclusiones.
- **Todo apoyado en evidencia**: cada afirmación del diagnóstico se ancla en algo leído (seña de salida, línea de log, código del arnés). "Creo que es el arnés" no basta sin la observación que lo respalde.
- **Un solo desatascado por bloque**: tras marcar `[juez desatascar]` como `[x]`, no se inserta otro para el mismo `[juez]`.
