# ralph — instrucciones del proyecto

## Paridad Bash ↔ PowerShell (IMPORTANTE)

El bucle existe en **dos implementaciones equivalentes**:

- `ralph-loop.sh` — versión Bash (referencia canónica).
- `ralph-loop.ps1` — versión PowerShell (pwsh 6+), con las mismas capacidades.

**Regla obligatoria:** cualquier cambio de funcionalidad (nueva opción
`RALPH_*`, cambio en la rotación de herramientas, en la detección de
agotamiento de tokens, en el formato de log, en el manejo de `stop.md`, en los
flags por defecto, etc.) **debe aplicarse a LOS DOS ficheros en el mismo
commit**, de forma que su comportamiento observable sea idéntico. No dejes uno
desactualizado respecto del otro.

Diferencia conocida y aceptada: el límite de RAM (`RALPH_MEMORY_MAX`) solo se
aplica en Linux vía `systemd-run --user --scope`. La versión PowerShell lo
respeta cuando corre sobre Linux; en otras plataformas (sin systemd) avisa con
un warning y ejecuta el agente sin límite, igual que hace el fallback del Bash.
