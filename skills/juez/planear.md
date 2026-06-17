# Acción: Planear los checkpoints

Esta acción **no juzga evidencia**. Se usa durante la creación o la revisión del plan y valida que el fichero `plan/task/*.md` es apto para ejecutarse de forma **desatendida**. Tiene dos responsabilidades, ambas aplicadas directamente sobre el fichero sin pedir confirmación:

1. **Cobertura de jueces**: que existan suficientes subtareas `[juez]` tras los bloques con riesgo verificable. Si faltan, las inserta.
2. **Ejecución desatendida**: que ninguna subtarea exija intervención explícita del usuario. Si alguna lo hace, **edita el plan** para eliminar esa dependencia.
3. **Evidencia ejecutable disponible**: que cada `[juez]` cuyas evidencias requieran una prueba ejecutable tenga, antes de él, una subtarea encargada de crearla. Si no la hay, inserta una subtarea `[crear evidencia]`.

## Criterio de ejecución desatendida

El plan debe poder aplicarse **de principio a fin sin intervención humana**. Ninguna subtarea —ni su texto, ni sus criterios de aceptación, ni sus evidencias— puede depender de una acción explícita del usuario.

Cuenta como **intervención explícita del usuario** (y por tanto está prohibido) cualquier subtarea que:

- pida confirmación, aprobación o permiso antes de continuar ("preguntar al usuario si…", "esperar el visto bueno", "confirmar con el usuario");
- espere datos, decisiones o entradas del usuario a mitad de ejecución ("el usuario indica el valor de…", "según lo que prefiera el usuario");
- delegue en el usuario una acción manual que el plan podría automatizar ("el usuario entra al panel y pulsa…", "copiar a mano la credencial", "el usuario aplica la migración");
- introduzca pausas o gates que solo un humano puede levantar ("detenerse hasta que el usuario revise").

**No** cuenta como intervención del usuario que el plan lea configuración existente, use valores por defecto razonables, o falle de forma determinista ante una condición no cumplida: eso es comportamiento autónomo legítimo.

## Criterio de cobertura

Un fichero está suficientemente cubierto cuando, **tras cada bloque de implementación con riesgo verificable**, existe ya una subtarea `[juez]` que lo verifica.

Un bloque tiene **riesgo verificable** si su salida deja un artefacto observable: binario, migración aplicada, endpoint, fichero generado, test que pasa, métrica, configuración, etc.

**No exige juez** tras subtareas puramente declarativas o de planificación (decidir nombres, leer documentación, anotar pendientes, escribir notas) que no producen evidencia comprobable.

Regla de agrupación: si varias subtareas consecutivas comparten artefactos o forman una unidad lógica indivisible (p. ej. "definir modelo" + "crear migración" + "aplicar migración"), basta un único `[juez]` al final del grupo.

## Procedimiento

1. Lee el fichero `plan/task/*.md` completo.
2. **Ejecución desatendida**: recorre todas las subtareas (texto, criterios y evidencias) y marca las que exijan intervención explícita del usuario según el criterio de arriba. Para cada una, **edita el plan** para eliminar la dependencia humana:
   - sustituye la confirmación/aprobación por una decisión autónoma con un valor por defecto razonable o por un criterio determinista comprobable;
   - reemplaza la espera de input por la lectura de configuración existente o por un parámetro fijado en el propio plan;
   - convierte la acción manual delegada en un paso automatizado equivalente (comando, llamada, script);
   - si la dependencia no puede automatizarse sin perder el sentido de la subtarea, reescríbela para que el plan **falle de forma determinista** ante la condición en vez de pausar a la espera de un humano.
3. Identifica los bloques de implementación con riesgo verificable.
4. Para cada bloque, comprueba si **ya existe** una subtarea `[juez]` inmediatamente posterior que lo cubra. Si existe, no toques nada.
5. Para cada bloque **sin** `[juez]` posterior, redacta e inserta uno siguiendo el formato de abajo.
6. **Evidencia ejecutable**: para cada `[juez]` (preexistente o recién insertado) cuyo criterio exija una prueba ejecutable (test que pasa, script con salida esperada, petición con assertion) **o cualquier propiedad de runtime** (sin OOM, pico de memoria ≤ X, latencia < Y, throughput, ausencia de fuga, idempotencia), comprueba si alguna subtarea previa del mismo bloque ya está encargada de crear ese arnés. Esta comprobación **no depende** de que el campo "Evidencias requeridas" esté relleno: un `[juez]` que pide una propiedad de runtime exige un arnés aunque su redacción sea vaga o no liste comando alguno (leer el fuente no sirve para esos criterios). Si **ninguna** subtarea previa lo está, inserta una subtarea `[crear evidencia]` justo antes del `[juez]`, con el formato definido en `juzgar.md`. Así el bloque no se atasca en ejecución desatendida por falta del arnés de prueba.
7. No marcas, renombras, reordenas subtareas ni editas las `[juez]` ya presentes aunque te parezcan flojas. Las **únicas** ediciones de subtareas existentes permitidas son la del paso 2 (eliminar intervención del usuario) y las inserciones de los pasos 5 y 6.
8. Guardas el fichero. En la conversación confirmas: cuántas subtareas se editaron por exigir intervención del usuario (o "ninguna, plan ya desatendido"), cuántos `[juez]` se insertaron y en qué secciones (o "ninguno, cobertura suficiente"), y cuántas subtareas `[crear evidencia]` se insertaron (o "ninguna").

## Formato de la subtarea juez insertada

Mantén la indentación y nivel de lista del fichero:

```
- [ ] [juez] verificar <descripción corta del bloque>
  - Alcance: <lista de las subtareas del bloque inmediatamente anterior, citadas por su texto>
  - Criterios de aceptación:
    - <criterio objetivo 1>
    - <criterio objetivo 2>
    - ...
  - Evidencias requeridas:
    - <comando exacto a ejecutar, o ruta a inspeccionar, o petición HTTP, o fragmento a leer>
    - ...
```

Reglas para cada campo:

- **Alcance**: enumera las subtareas previas cubiertas, no inventes nuevas.
- **Criterios de aceptación**: condiciones literales y comprobables (exit 0, cadena exacta, nº de filas, hash, código HTTP, presencia/ausencia de campo). Evita criterios interpretativos ("funciona bien", "es correcto").
- **Evidencias requeridas**: comandos completos y deterministas, rutas absolutas o relativas al repo, peticiones HTTP con método+URL+payload. Si la evidencia depende de entorno, fija semilla/fixture/snapshot.

## Reglas duras adicionales

- **No juzgas** aquí: aunque haya subtareas previas marcadas `[x]`, esta acción ignora la evidencia y solo evalúa cobertura y ejecución desatendida. Para juzgar, se carga `juzgar.md`.
- **No implementas** lo que falta: si una subtarea es ambigua o no produce evidencia, añade igualmente un `[juez]` cuyos criterios fuercen al implementador a producirla; no la reescribas. La excepción es la subtarea que exige intervención del usuario: esa **sí** se reescribe (paso 2) para volverla desatendida, pero nunca para añadir lógica de implementación de código.
- **Editas el plan, no el código**: la reescritura por intervención del usuario afecta solo al texto del plan (subtareas, criterios, evidencias); jamás escribes código de la aplicación ni resuelves tú la tarea.
- **No duplicas**: si tras tu inserción quedaran dos `[juez]` consecutivos verificando lo mismo, fusiónalos en uno.
- **Una línea por criterio y por evidencia**: nada de párrafos largos; cada bullet es atómico.
