# Acción: Juzgar evidencia

Verificas con evidencias reproducibles que un bloque previo de implementación se ha llevado a cabo correctamente, antes de continuar con el siguiente bloque.

## Alcance de una sola invocación

La validación es **incremental: un bloque por invocación**. Cada vez que se ejecuta la juez:

1. Localiza el **primer** checkpoint `[juez]` (el más temprano en el orden del fichero) que esté pendiente `[ ]` y cuyas subtareas de implementación de su Alcance estén todas marcadas `[x]`. Ese, y solo ese, es el bloque a juzgar en esta invocación.
2. Recolecta su evidencia, re-ejecuta la suite de evidencias persistente acumulada como gate de regresión (ver "Suite de evidencias persistente y regresiones") y toma **una** acción (positivo / negativo / no evaluable).
3. **Se detiene**, gane o pierda. Si quedan más `[juez]` pendientes detrás, los juzgarán las **siguientes** invocaciones, uno por iteración.

**Nunca encadenes varios bloques en una misma invocación.** Aunque haya tres bloques `[x]` con sus tres `[juez]` pendientes apilados, esta invocación valida el primero y para; la siguiente valida el segundo (re-ejecutando la suite del primero como regresión); la tercera valida el tercero (con la suite de los dos anteriores como regresión). Intentar recolectar la evidencia de todos a la vez es lo que bloquea a la juez.

## Entradas

Cada subtarea `[juez]` del fichero `plan/task/*.md` indica:

1. **Alcance**: qué subtarea(s) de implementación inmediatamente anteriores del mismo fichero se están verificando.
2. **Criterios de aceptación**: lista cerrada de condiciones objetivas que deben cumplirse.
3. **Evidencias requeridas**: lista cerrada de artefactos a producir (comandos a ejecutar con su salida, rutas de ficheros a inspeccionar, fragmentos a leer, peticiones HTTP a emitir, etc.).

## Procedimiento

Para cada criterio de aceptación:

1. **Recolección**: ejecuta los comandos o lee los ficheros indicados en "Evidencias requeridas". Captura la salida tal cual.
2. **Comparación**: contrasta la evidencia con el criterio de forma literal (existencia de fichero, código de salida 0, cadena exacta, número de filas, etc.), no interpretativa.
3. **Decisión**: hay tres resultados posibles, mutuamente excluyentes:
   - **Positivo**: se ha podido recolectar la evidencia y todos los criterios pasan.
   - **Negativo**: se ha podido recolectar la evidencia y algún criterio falla.
   - **No evaluable**: no se ha podido recolectar la evidencia (ver sección "Imposibilidad de emitir evidencia").

## Acción según resultado

La juez **no emite veredicto en la conversación**. Actúa directamente sobre el fichero `plan/task/*.md`. Los tres flujos son distintos:

- **Positivo** (evidencia recolectada, todos los criterios pasan): marca la subtarea `[juez]` como `[x]`. Las subtareas previas permanecen `[x]`. **Restaura el esfuerzo del modelo a medio** editando `.ralph/.env` (ver «Escalado de esfuerzo del modelo»). **Detén la iteración aquí**: si quedan otros `[juez]` pendientes, los juzgará la siguiente invocación (un bloque por iteración). No avances al siguiente bloque dentro de esta misma ejecución.
- **Negativo** (evidencia recolectada, algún criterio falla): el feedback **siempre va en la subtarea de implementación** que se desmarca, nunca en la subtarea `[juez]`. Antes de actuar, comprueba si esa subtarea **ya contiene** un sufijo `— rechazado por juez (intento N)` de un intento previo y lee el número `N`. El umbral de reintentos es **10**: se acumulan hasta diez rechazos consecutivos antes de romper el bucle. Cada vez que incrementes el contador, si el nuevo recuento es `N ≥ 3` **escala el esfuerzo del modelo** editando `.ralph/.env` (ver «Escalado de esfuerzo del modelo»).
  - **Primer rechazo** (no hay sufijo previo en la subtarea):
    1. Desmarca la(s) subtarea(s) de implementación de su Alcance — de `- [x]` a `- [ ]`.
    2. Añade al final de cada subtarea desmarcada el sufijo ` — rechazado por juez (intento 1): <una sola línea con la razón>`. **No edites ni añadas feedback en la subtarea `[juez]`**.
    3. Detén el bucle aquí. No se emite `stop.md`: el rechazo con razón ya es señal suficiente para que el implementador rehaga el trabajo.
  - **Quinto rechazo — disparo del desatascado** (la subtarea ya tiene un sufijo `— rechazado por juez (intento 4)`, de modo que este rechazo elevaría el recuento a 5, **y aún no existe** una subtarea `[juez desatascar]` para este `[juez]`):
    1. **No desmarques** la(s) subtarea(s) de implementación: déjala(s) en `- [x]`. A medio camino del umbral, antes de gastar otra ronda de re-implementación a ciegas, toca diagnosticar si el bucle persigue un criterio inalcanzable (p. ej. el arnés mide algo que no se puede cumplir).
    2. Sustituye el sufijo previo por ` — rechazado por juez (intento 5): <una sola línea con la razón actual>`, incrementando el contador a 5. Mantén el sufijo en la subtarea de implementación.
    3. **Inserta una subtarea `[juez desatascar]`** inmediatamente **antes** de la subtarea `[juez]` de este bloque, con el formato de abajo. Será la siguiente acción del bucle (es el primer `[ ]` pendiente) y la enruta esta misma skill a `desatascar.md`.
    4. Detén el bucle aquí. **No se emite `stop.md`**: el desatascado decidirá si hay un imposible que documentar y arreglar o si el ciclo normal debe continuar.
  - **Re-rechazo por debajo del umbral** (la subtarea ya tiene un sufijo `— rechazado por juez (intento N)` con `N` entre 1 y 8, de modo que el nuevo recuento `N+1` sigue siendo menor que 10; incluye el salto a 5 **cuando ya existe** un `[juez desatascar]` previo para este bloque, es decir, el desatascado ya se hizo y el ciclo continúa):
    1. Desmarca la(s) subtarea(s) de implementación afectada(s) de nuevo.
    2. Sustituye el sufijo previo por ` — rechazado por juez (intento N+1): <una sola línea con la razón actual>`, incrementando el contador en uno. Mantén el sufijo en la subtarea de implementación, no en la `[juez]`.
    3. Detén el bucle aquí. **No se emite `stop.md`**: aún quedan reintentos; el implementador debe rehacer el trabajo con el nuevo feedback.
  - **Décimo rechazo** (la subtarea ya tiene un sufijo `— rechazado por juez (intento 9)`, de modo que este rechazo eleva el recuento a 10, el umbral):
    1. Desmarca la(s) subtarea(s) de implementación afectada(s) de nuevo.
    2. Sustituye el sufijo previo por ` — rechazado por juez (intento 10): <una sola línea con la razón actual>`. Mantén el sufijo en la subtarea de implementación, no en la `[juez]`.
    3. **Emite `stop.md`** en el mismo directorio que el fichero `plan/task/*.md` (sobrescribiendo si ya existe). Contenido en lenguaje natural y breve:
       - Qué subtarea ha sido rechazada repetidamente hasta alcanzar el 10º intento.
       - Razones acumuladas (la actual y, si se conocen, las anteriores).
       - Qué se necesita decidir o cambiar para desbloquear (cambio de enfoque, intervención humana, replanteamiento del criterio, etc.).
    4. Detén el bucle. El `stop.md` rompe el ciclo de re-implementación inútil y fuerza intervención.

  El implementador, al rehacer el trabajo y volver a marcar `[x]`, **debe conservar el sufijo `— rechazado por juez (intento N): …`** como historial. El número de intento sirve a la juez de la siguiente ronda para saber por qué reintento va. Solo cuando la juez verifica positivamente el bloque se considera resuelto el historial.

  Formato de la subtarea `[juez desatascar]` insertada en el quinto rechazo (respeta indentación y nivel de lista del fichero, colócala justo antes de la `[juez]` del bloque):

  ```
  - [ ] [juez desatascar] revisar por qué el bloque «<texto corto del [juez]>» acumula rechazos
    - Alcance: la(s) subtarea(s) de implementación rechazadas y la subtarea `[juez]` que las verifica.
    - Qué revisar: el plan, los logs del bucle (`.ralph/logs`) y cómo está validando la juez (criterio + arnés/evidencia).
    - Resultado esperado: o bien un bloque «Diagnóstico de bucle» con problema+solución y una tarea de implementación del arreglo (si el criterio es inalcanzable tal como está), o bien la confirmación de que el criterio es alcanzable y el ciclo normal debe continuar.
  ```
- **No evaluable** (no se ha podido recolectar la evidencia): ver sección "Imposibilidad de emitir evidencia" más abajo. Según la causa: si el entorno puede dejarse listo de forma autónoma, inserta una subtarea `[preparación entorno]`; si lo que falta es el código que produce la evidencia y puede crearse de forma autónoma, inserta una subtarea `[crear evidencia]`; en ambos casos detén la iteración **sin** `stop.md`. Solo si no puede resolverse de forma autónoma, emite `stop.md` y para.

La razón en el caso negativo es **una sola línea**, sin saltos de línea, sin detalles técnicos, sin código, sin rutas, sin comandos, sin citas literales. Describe en lenguaje natural qué criterio incumple, lo más corto posible. Se escribe siempre dentro de la subtarea de implementación desmarcada, nunca en la subtarea `[juez]`.

Ejemplos válidos de razón:
- `falta cobertura de tests para el caso de duplicado por banda`.
- `la migración no es idempotente al aplicarse dos veces`.
- `el endpoint expone campos internos del dominio`.

Ejemplos inválidos (no usar):
- `go test ./... falla con exit 1: ...` (incluye detalle técnico)
- `falta `deleted_at` en la query de listar` (incluye nombre de columna y código)
- Razones de más de una línea o con saltos de línea.

## Escalado de esfuerzo del modelo

El bucle Ralph relee `.ralph/.env` (en el directorio de invocación) **antes de cada iteración**: es su única fuente de configuración y cualquier cambio aplica en la iteración siguiente. La juez usa ese fichero para **subir** el esfuerzo del modelo cuando un bloque se atasca y **bajarlo** cuando se resuelve, de modo que las re-implementaciones difíciles se hagan con un modelo más capaz.

**Solo aplica si el fichero `.ralph/.env` existe** (es decir, se está ejecutando bajo Ralph). Si no existe, no hagas nada y **no lo crees**.

Al editarlo, modifica **únicamente** el valor de las dos claves indicadas abajo y **conserva intacto el resto del fichero** (`RALPH_TOOL`, flags, modelos por tier, etc.). No reescribas el fichero entero ni reordenes claves; cambia solo el lado derecho de esas dos líneas.

- **Escalar (bloque atascado)**: en cualquier rechazo cuyo contador resultante `(intento N)` sea **N ≥ 3**, deja en `.ralph/.env`:
  - `RALPH_MODEL_CAPABILITY=high`
  - `RALPH_THINKING=true`

  Es idempotente: si ya están así, no cambia nada. El esfuerzo elevado se **mantiene** en todas las iteraciones siguientes (intentos 3, 4, … hasta el desenlace) sin volver a tocarlo. Los rechazos de intento 1 y 2 **no** escalan.
- **Restaurar (bloque resuelto)**: cuando emitas un veredicto **positivo** (marcas el `[juez]` como `[x]`), deja **siempre** en `.ralph/.env`:
  - `RALPH_MODEL_CAPABILITY=med`
  - `RALPH_THINKING=false`

  Esto devuelve el bucle a esfuerzo medio en cuanto un bloque pasa, aunque el rechazo que lo había escalado fuera de otro bloque distinto.

Este escalado opera sobre el mismo contador `(intento N)` que ya gestiona el flujo de rechazo; no introduce un contador nuevo. Como el esfuerzo no se restaura hasta un positivo, una `[juez desatascar]` insertada en el 5º rechazo ya se ejecuta con el modelo escalado.

## Suite de evidencias persistente y regresiones

Las subtareas `[crear evidencia]` (ver "Imposibilidad de emitir evidencia", Caso B) producen código de prueba **persistente, commiteado y re-ejecutable de forma determinista**. En conjunto forman la **suite de evidencias del fichero**: el cinturón de regresión de todo lo ya verificado.

- **La inspección no se re-ejecuta**: un criterio declarativo o de inspección de artefacto que una juez anterior del mismo fichero ya verificó positivamente se da por bueno por referencia; no se vuelve a inspeccionar.
- **La suite persistente sí se re-ejecuta**: en **cada** subtarea `[juez]`, antes de dar por bueno su propio bloque, la juez ejecuta **íntegra** la suite de evidencias persistente acumulada en el fichero (todos los tests/scripts creados por `[crear evidencia]` previos). Es un gate de regresión completo, no una verificación por referencia.
- **Una regresión es un resultado negativo**: si una evidencia persistente que antes pasaba ahora falla, hay una regresión. La juez trata el bloque actual como **negativo** y aplica el flujo de rechazo habitual (desmarca su(s) subtarea(s) de implementación con razón de una línea del estilo `una regresión rompe evidencia previamente verde`, e incrementa el contador `(intento N)` y, solo al llegar al 10º intento, emite `stop.md`).

## Propiedades de runtime: no se juzgan leyendo código

Un criterio que describe una **propiedad de comportamiento en ejecución** —no
agotar memoria/«sin OOM», pico de RSS bajo un tope, latencia, throughput,
ausencia de fuga, idempotencia al re-ejecutar, etc.— **no se satisface ni se
refuta leyendo el código fuente**. Que el fuente "parezca" correcto o incorrecto
(por ejemplo, ver o no ver `:memory:`) no es evidencia de la propiedad: hay que
**ejecutar** un arnés que la ejercite y observar el resultado medido.

- Si existe un arnés ejecutable que mide la propiedad, córrelo y juzga su salida.
- Si **no existe** ese arnés, el criterio es no evaluable por falta de código de
  evidencia → **Caso B** (inserta `[crear evidencia]`), **no** un negativo por
  inspección. Leer el fuente y rechazar "porque sigo viendo el patrón malo" está
  prohibido para criterios de runtime.

## Arnés fuera de alcance: no es negativo de este bloque

Si la evidencia ejecuta, de forma transitiva, código que **no pertenece al
Alcance** del `[juez]` actual (p. ej. un script que verifica varios bloques a la
vez y arrastra un builder de un bloque posterior), un fallo atribuible a ese
código externo **no es un negativo de este bloque**: es un arnés mal aislado. No
desmarques la implementación de este bloque por un pecado de otro; trátalo como
Caso B e inserta `[crear evidencia]` para un arnés que ejercite **solo** el
Alcance de este `[juez]`.

## Reglas duras adicionales

- **No re-inspecciona, pero sí re-ejecuta la suite**. Ver la sección anterior: los criterios de inspección ya verificados se dan por buenos por referencia; la suite de evidencias persistente se re-ejecuta entera en cada `[juez]`.

## Imposibilidad de emitir evidencia (caso "no evaluable")

Este flujo aplica **solo** cuando la juez no puede recolectar la evidencia. Si la evidencia se ha podido recolectar y simplemente no cumple el criterio, eso es **negativo**, no "no evaluable", y se trata según la sección anterior — sin `stop.md`.

Casos típicos de "no evaluable":

- **Herramienta inexistente**: MCP no disponible, binario no instalado, credencial ausente, acceso a servicio externo bloqueado, permiso denegado.
- **Herramienta presente pero no funcional**: el comando existe pero falla por error de configuración, el MCP responde con error, el servicio devuelve 5xx persistentes, timeouts, credencial caducada, base de datos no responde, tests que no pueden ejecutarse por dependencias rotas.
- **Entorno inconsistente**: faltan fixtures, datos de prueba, variables de entorno o ficheros esperados; el estado del repositorio impide ejecutar la verificación.
- **Código de evidencia ausente**: la evidencia requerida es una prueba ejecutable (test, script) que demostraría el criterio, pero ese código no existe todavía y ninguna subtarea previa estaba encargada de crearlo. No es un fallo del criterio: es que falta el arnés que lo ejercita.
- **Evidencia no determinista**: la salida cambia entre ejecuciones sin contexto fijado y no es posible fijarlo.
- **Cualquier otra causa** que impida obtener una evidencia objetiva del criterio.

Ante un resultado "no evaluable", la juez distingue **por qué** no puede recolectar la evidencia y resuelve de forma autónoma siempre que sea posible, reservando `stop.md` solo para lo que de verdad exige intervención humana. Hay tres salidas autónomas:

- **Caso A** — el entorno no está listo pero puede prepararse de forma autónoma → inserta `[preparación entorno]`.
- **Caso B** — falta el código que produce la evidencia, pero puede crearse de forma autónoma → inserta `[crear evidencia]`.
- **Caso C** — no puede resolverse sin intervención humana (o los casos A/B ya se intentaron sin éxito) → emite `stop.md`.

### Caso A — el entorno se puede dejar listo de forma autónoma

Si la causa es un entorno que puede prepararse **sin intervención humana** (servicio caído que se puede levantar, volumen o base de datos por recrear, contenedor a arrancar, dependencia o binario instalable, fixture o dato de prueba generable, variable derivable de la configuración existente), la juez **no emite `stop.md`**. En su lugar:

1. **Inserta una subtarea de preparación de entorno** en el fichero `plan/task/*.md`, **justo antes** de la subtarea `[juez]` que no pudo evaluar, con el formato de abajo. Debe contener exactamente **lo que la juez necesita para que la evidencia pase a ser recolectable** (qué servicio levantar, qué volumen recrear, qué dependencia instalar, etc.), de forma determinista y desatendida.
2. **No desmarques la subtarea de implementación** si su trabajo está hecho y lo único que falta es preparar el entorno: la subtarea de preparación es la que debe ejecutarse a continuación. Solo desmarca implementación si su artefacto es realmente lo que falta.
3. **Detén la iteración** sin emitir `stop.md`. El bucle ejecutará la preparación en la siguiente iteración y volverá a la subtarea `[juez]`, que esta vez debería poder recolectar la evidencia.

**Guarda contra bucles**: si **ya existe** una subtarea de preparación de entorno inmediatamente anterior a esta `[juez]` (insertada en una ronda previa) y la evidencia **sigue** sin ser recolectable, la preparación autónoma ha fracasado: pasa al Caso C y emite `stop.md`. Nunca insertes una segunda subtarea de preparación para el mismo `[juez]`.

Formato de la subtarea de preparación insertada (respeta indentación y nivel de lista del fichero):

```
- [ ] [preparación entorno] <qué dejar operativo> para poder verificar «<texto corto de la subtarea [juez]>»
  - Pasos: <comando(s) o acción(es) deterministas y desatendidas para dejar el entorno listo>
  - Resultado esperado: <condición observable que confirma que la evidencia ya es recolectable>
```

### Caso B — falta el código que produce la evidencia, pero puede crearse

Si la evidencia requerida es una prueba ejecutable (test del framework nativo del repo, o script reproducible) que **no existe todavía** y crearla **no exige intervención humana**, la juez **no emite `stop.md`** ni desmarca la subtarea de implementación como negativo. En su lugar:

1. **Inserta una subtarea `[crear evidencia]`** en el fichero `plan/task/*.md`, **justo antes** de la subtarea `[juez]` que no pudo evaluar, con el formato de abajo. Debe describir qué prueba reproducible crear y qué casos/criterios debe ejercitar para que la evidencia pase a ser recolectable.
2. **No desmarques la subtarea de implementación** si su código de producción está hecho y lo único que falta es el arnés de prueba: el `[crear evidencia]` es lo que debe ejecutarse a continuación. Solo desmarca implementación si su propio artefacto es realmente lo que falta.
3. **Detén la iteración** sin emitir `stop.md`. El bucle creará la prueba en la siguiente iteración y volverá a la subtarea `[juez]`, que esta vez debería poder recolectar la evidencia.

El código creado por `[crear evidencia]` es **persistente**: queda commiteado en el repo (nunca en `/tmp`), es determinista y pasa a formar parte de la **suite de evidencias del fichero**, que toda juez posterior re-ejecuta como gate de regresión (ver "Suite de evidencias persistente y regresiones").

**Guarda contra bucles**: si **ya existe** una subtarea `[crear evidencia]` inmediatamente anterior a esta `[juez]` (insertada en una ronda previa) y la evidencia **sigue** sin poder recolectarse, la creación autónoma ha fracasado: pasa al Caso C y emite `stop.md`. Nunca insertes una segunda subtarea `[crear evidencia]` para el mismo `[juez]`. *(Si la prueba ya existe y se ejecuta pero el criterio falla, eso es **negativo**, no Caso B: trátalo como rechazo ordinario.)*

Formato de la subtarea `[crear evidencia]` insertada (respeta indentación y nivel de lista del fichero):

```
- [ ] [crear evidencia] <qué prueba reproducible crear> para poder verificar «<texto corto de la subtarea [juez]>»
  - Forma: test del framework nativo del repo si la evidencia encaja; si no, script reproducible commiteado en el repo (nunca en /tmp).
  - Cobertura: <los casos o criterios concretos que la prueba debe ejercitar>
  - Persistencia: queda commiteado y se incorpora a la suite de regresión, re-ejecutable de forma determinista en cada juez posterior.
  - Resultado esperado: <condición observable que confirma que la evidencia es recolectable: p. ej. el comando termina en exit 0 cubriendo los casos exigidos>
```

### Caso C — no se puede resolver de forma autónoma

Si la causa **no** puede resolverse sin intervención humana (credencial que solo posee una persona, decisión de negocio, recurso externo inaccesible, herramienta no instalable en el entorno) **o** ya se intentó preparar el entorno o crear la evidencia sin éxito (ver guardas anteriores), la juez debe:

1. **Emitir siempre un fichero `stop.md`** en el mismo directorio que el fichero `plan/task/*.md` que está juzgando (sobrescribiéndolo si ya existe). Debe contener, en lenguaje natural y breve:
   - Qué impide emitir evidencia y por qué no puede prepararse el entorno de forma autónoma.
   - Qué criterio de aceptación no se ha podido evaluar.
   - Qué se necesita para desbloquear (decisión humana, credencial, recurso, etc.).
2. **Desmarcar la subtarea de implementación afectada** con razón de una línea del estilo `bloqueado: no se puede verificar <criterio> por falta de evidencia`.
3. **Detener el bucle** sin continuar con criterios posteriores que dependan de la misma causa.

La emisión de `stop.md` es **exclusiva del Caso C**: nunca se emite en verificaciones negativas ordinarias, ni cuando el entorno puede prepararse de forma autónoma (Caso A) ni cuando la evidencia puede crearse de forma autónoma (Caso B).

## Bloqueo

Una subtarea de implementación **no se considera completada** hasta que la juez inmediatamente posterior marque positivamente su subtarea `[juez]`. Si la juez desmarca una subtarea, las posteriores quedan bloqueadas hasta que el implementador rehaga el trabajo, vuelva a marcarla `[x]` (conservando el sufijo `— rechazado por juez (intento N): …` como historial) y la juez se ejecute de nuevo y, esta vez, marque positivamente la subtarea `[juez]`.

Si una misma subtarea acumula diez rechazos consecutivos (ver "Décimo rechazo" más arriba), la juez emite `stop.md` para romper el bucle de re-implementación: el problema no se está resolviendo con el feedback actual y requiere intervención o replanteamiento.
