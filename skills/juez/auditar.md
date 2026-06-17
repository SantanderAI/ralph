# Acción: Auditar el enfoque

Esta acción **no juzga la evidencia de un bloque** ni **verifica cobertura de checkpoints**. Es una revisión **holística y de solo lectura** del avance del bucle autónomo (ralph) y del plan global: comprueba si el enfoque actual va camino de cumplir el **Objetivo** y, si no, propone cambios. Su producto es un **informe razonado en la conversación**; **no edita** `plan/plan.md`, ni los `plan/task/*.md`, ni `stop.md`.

## Cuándo

Solo bajo invocación **explícita** del usuario (`/juez auditar`). No entra en el ruteo automático de apertura de `plan/task/*.md`: las acciones automáticas siguen siendo planear, juzgar y desatascar.

## Entradas (todas de solo lectura)

1. **`plan/plan.md`**: el **Objetivo**, las decisiones tomadas, la lista de tareas y su estado. Determina cuáles están `[x]`, cuál es la siguiente `[ ]` y **si la última tarea está marcada** (señal de plan completo).
2. **`plan/task/*.md`**: estado detallado de subtareas. Presta atención a:
   - sufijos `— rechazado por juez (intento N): …` (fricción; N creciente = reincidencia, y N cercano a 10 = a punto de romper el bucle),
   - subtareas `[juez]` sin marcar (bloque no verificado todavía).
3. **`.ralph/logs/`**: logs de las iteraciones del bucle. Léelos **del más reciente al más antiguo** para reconstruir qué ha intentado el bucle, dónde se atasca, qué errores se repiten y si avanza o gira en círculos.
4. **`stop.md`** (si existe, en el directorio de `plan/task/`): señal de que el bucle se detuvo. Su contenido resume la causa del bloqueo y es el **mejor punto de partida** para evaluar si el enfoque actual es el correcto. Su ausencia no exime de evaluar.

## Procedimiento

1. **Fijar el objetivo**: extrae de `plan/plan.md` el Objetivo y las decisiones tomadas. Todo lo demás se evalúa contra esto.
2. **Estado del plan**: determina qué tareas están completas, cuál es la actual y si la última está marcada. Si todo está `[x]`, el plan está completo: dilo y limita la evaluación a si el Objetivo se ha cumplido **de verdad** (con evidencia), no solo a que las casillas estén marcadas.
3. **Reconstruir la trayectoria**: lee `.ralph/logs/` (del más reciente al más antiguo) y, si existe, `stop.md`. Cruza lo que ves en los logs con el estado de los `plan/task/*.md`.
4. **Diagnóstico**: responde a una pregunta única — *¿el enfoque actual lleva al Objetivo?* Identifica la **causa raíz** cuando la respuesta es no, anclada en evidencia concreta.
5. **Propuesta**: redacta cambios concretos y razonados al plan para alcanzar el Objetivo. **No los apliques**.

## Síntomas a buscar (bucle atascado o enfoque equivocado)

- Una misma subtarea **re-rechazada** (el sufijo `— rechazado por juez` reaparece tras haberse re-marcado `[x]`, o se emitió `stop.md`) → criterio inalcanzable, mal planteado, o feedback que no resuelve la causa.
- **`stop.md` presente** → el bucle ya se rompió a propósito; lee por qué.
- **Iteraciones consecutivas sin progreso**: nada nuevo se marca `[x]` entre iteraciones.
- **Errores repetidos** en logs: fallo de compilación, tests rojos, herramienta ausente, servicio caído.
- El bucle **marca tareas como hechas sin evidencia** o saltándose subtareas `[juez]`.
- Tareas que dependen de un **prerrequisito inexistente** o en **orden incorrecto**.
- **Descomposición desalineada** con el Objetivo: tareas que no acercan al objetivo, o falta una imprescindible.

## Salida (informe en la conversación)

No editas `plan/plan.md`, ni los `plan/task/*.md`, ni `stop.md`. Emites un informe estructurado y breve:

1. **Estado**: progreso (n.º de tareas hechas / total), tarea actual, si está bloqueado y desde cuándo.
2. **Diagnóstico**: causa raíz por la que el enfoque actual **sí o no** llega al Objetivo, apoyada en evidencia concreta (línea de log, sufijo de rechazo, contenido de `stop.md`).
3. **Propuesta de cambios**: lista **priorizada** y concreta de cambios al plan para alcanzar el Objetivo — reordenar, dividir, añadir, eliminar o reescribir tareas; ajustar criterios de aceptación; revisar alguna de las decisiones tomadas. Cada cambio acompañado de su porqué.
4. **Recomendación**: una de tres — *continuar tal cual*, *replantear el plan según la propuesta*, o *requiere intervención/decisión humana*.

## Reglas duras

- **Solo lectura sobre el plan**: esta acción nunca edita `plan/plan.md`, `plan/task/*.md` ni `stop.md`. Su producto es una propuesta; la decisión de aplicarla es humana.
- **No implementa código**: ni de la aplicación ni para "arreglar" el bucle.
- **No es juzgar ni planear**: no juzga la evidencia de un bloque concreto (eso es `juzgar.md`) ni inserta subtareas `[juez]` (eso es `planear.md`). Audita el **enfoque global**.
- **Todo apoyado en evidencia**: cada afirmación del diagnóstico se ancla en algo leído. "Parece que no avanza" no basta sin la observación que lo respalde.
- **Propón, no apliques**: las propuestas deben ser accionables, pero su ejecución queda fuera de esta acción.
