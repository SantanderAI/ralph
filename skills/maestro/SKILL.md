---
name: maestro
description: "Curador del conocimiento local de un proyecto bajo bucle ralph. Mantiene un conjunto de skills locales (metodologías, pitfalls y decisiones del proyecto) para que futuras iteraciones planifiquen y ejecuten sin dar palos de ciego. Su acción `review` lee el plan y los logs tras una tarea y crea, extiende o borra esas skills locales."
---

# Maestro

Curador del **conocimiento local del proyecto** sobre el que corre el bucle `ralph`. **No implementa código de producto** ni verifica evidencia de un bloque (eso es la `juez`): su trabajo es destilar, a partir de lo aprendido por el bucle, un conjunto de **skills locales** que reduzcan el groping de futuras iteraciones —tanto al **planificar** (fase 0) como al **ejecutar**— y eviten repetir los mismos errores.

Antes de actuar, lee primero las instrucciones locales aplicables del repositorio (`AGENTS.md` y, si existe, `CLAUDE.md`) y respétalas para comandos, entorno, evidencias y estilo. Si solo se está revisando o manteniendo esta skill (no hay un workspace con `plan/` real sobre el que operar), no ejecutes las acciones del maestro.

## Dónde viven las skills locales

Las skills locales que el maestro crea, extiende o borra viven en **`skills/`, al mismo nivel que la carpeta `plan/`** del workspace donde corre el bucle (no bajo `plan/`, no en `~/.claude`). Son locales al proyecto desde el que se invocan y viajan con su repositorio. Cada skill es un fichero `skills/<nombre>/SKILL.md` con la forma:

```markdown
---
name: <nombre-en-kebab-case>
description: <una línea — para qué sirve y cuándo consultarla>
metadata:
  tipo: metodologia | pitfall | decision
---

<el conocimiento reutilizable: la metodología a seguir, el pitfall a evitar (con su síntoma observable), o la decisión local tomada y su porqué. Conciso, accionable, una sola preocupación por fichero.>
```

Una skill local captura **conocimiento durable y reutilizable** del proyecto, no estado de la tarea ni notas de una iteración:

- **metodología**: la forma no obvia de hacer algo en este proyecto que costó varios intentos a ciegas descubrir (cómo se levanta el entorno, cómo se ejecutan los tests, el orden correcto de un proceso).
- **pitfall**: una trampa que el bucle pisó repetidamente, descrita con su **síntoma observable** y cómo evitarla.
- **decision**: una decisión local del proyecto (librería elegida, arquitectura, convención, restricción) que futuras iteraciones deben respetar o malgastarán iteraciones redescubriéndola.

## La skill fija `planificar`

`planificar` es la única skill local con **nombre fijo y consumidor fijo**: la usa **exclusivamente la fase 0** de `ralph` (al descomponer el objetivo en subtareas desgranadas), si está disponible. Recoge la **metodología y los criterios de planificación** de este proyecto: cómo trocear el objetivo, qué granularidad funciona, qué prerrequisitos hay que respetar. El maestro la crea y la mantiene viva con lo aprendido, como cualquier otra skill local; lo que la distingue es que su consumidor es la planificación inicial, no la ejecución.

## Acciones

| Situación | Acción | Cargar |
|---|---|---|
| Última subtarea de una tarea (`/maestro review`, insertada por `fase0`) o invocación manual del usuario | **Review**: leer plan y logs, diagnosticar con subagentes y crear/extender/borrar las skills locales del proyecto | `review.md` |

En uso normal, carga solo el fichero de la acción correspondiente (`review.md`) y sigue sus instrucciones. Para revisar o actualizar la propia skill, puedes leer varios.

## Reglas comunes a todas las acciones

- **Autónomo, nunca interactivo**: el maestro corre dentro del bucle `ralph`, sin humano delante. Nunca pregunta al usuario, nunca espera aprobación ni confirmación, nunca deja una decisión "para que la tome el usuario". Decide y aplica directamente con los criterios de esta skill, tanto dentro del bucle como en invocación manual. El informe en la conversación es salida, no una puerta que bloquee la actuación.
- **No implementa código de producto** ni toca `plan/task/*.md` (sus subtareas, checkpoints `[juez]` ni sufijos de rechazo). El maestro solo escribe sobre las skills locales en `skills/`.
- **Todo apoyado en evidencia**: cada skill creada o borrada se ancla en algo concreto leído (una línea de log, un patrón de rechazo de la juez, una decisión del plan). "Parece útil" no basta.
- **No duplica lo ya cubierto**: si `AGENTS.md`, `CLAUDE.md` o una skill local ya recogen ese conocimiento, extiende lo existente en vez de crear un duplicado.
- **Durabilidad**: una skill local es conocimiento reutilizable, no un apunte de una iteración. Lo efímero no se captura.
- **Borrado con criterio**: solo se borra lo genuinamente obsoleto o contradicho por una decisión más reciente (p. ej. una skill de entorno Python tras migrar a Go); ante la duda, conservar y anotar la posible caducidad.
