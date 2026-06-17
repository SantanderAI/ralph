---
name: ralph
description: "Acciones para gestionar bucles Ralph: preparar un `plan/plan.md` con las instrucciones canónicas del bucle (`/ralph set-up`), o expandirlo a ficheros de tarea listos para el bucle (`/ralph fase0`)."
---

# Ralph

Herramientas para gestionar los bucles Ralph (`ralph-loop.sh`) sobre un repositorio: preparar el fichero `plan/plan.md` con las instrucciones canónicas del bucle, expandirlo a ficheros `plan/task/NN.md` accionables, y otras acciones futuras sobre el ciclo.

Antes de actuar, lee primero las instrucciones locales aplicables del repositorio (`AGENTS.md` y, si existe, `CLAUDE.md`) y respétalas.

**Ubicación del plan**: por defecto el plan vive en `plan/plan.md` y sus tareas en `plan/task/NN.md` desde la raíz del repositorio. Si el usuario nombra explícitamente otra ruta (otro directorio, otro nombre de fichero), usa la que indique en lugar de la por defecto. Todas las referencias a estas rutas en las acciones de esta skill son relativas a esa convención.

## Acciones

| Invocación | Acción | Cargar |
|---|---|---|
| `/ralph set-up` (o usuario pide «preparar el plan para el bucle ralph», «inserta las instrucciones de ralph», etc.) | **Set-up**: inserta al inicio de `plan/plan.md` el bloque canónico de instrucciones del bucle Ralph | `set-up.md` |
| `/ralph fase0` (o usuario pide «hacer la fase 0», «expandir el plan en tareas», «preparar las tareas del plan», etc.) | **Fase 0**: descompone `plan/plan.md` en ficheros `plan/task/NN.md` accionables, valida contexto, inserta marcas de esfuerzo y planifica los `[juez]`. Orquesta subagentes en paralelo. | `fase0.md` |

En uso normal, carga solo el fichero correspondiente (`set-up.md` o `fase0.md`) y sigue sus instrucciones. Para revisar o actualizar la propia skill, puedes leer varios.

## Detección proactiva: plan sin subtareas

Cuando inspecciones un repositorio con `plan/plan.md` (por la razón que sea: el usuario acaba de invocar `set-up`, te pide revisar el estado del bucle, o simplemente abres el fichero) y detectes que el plan **no contiene ninguna línea `- [ ]` ni `- [x]`** (es decir, tiene objetivo/contexto pero no lista de tareas accionable), **sugiere al usuario invocar `/ralph fase0`** para descomponerlo en `plan/task/NN.md`. Sin subtareas, el bucle ralph no tiene nada que ejecutar y creará `stop.md` en la primera iteración. No lances `fase0` tú sin que el usuario lo pida; solo sugiérelo.
