# scripts/agent-hooks — gates de IA compartidos (Anillo 2)

> **Una sola implementación de los gates, dos clientes.** Claude Code y Cursor tienen
> sistemas de hooks distintos (eventos y contratos de I/O diferentes), pero la lógica de los
> gates vive **aquí, una sola vez**. Cada cliente solo aporta un wrapper delgado que mapea sus
> eventos a estos scripts:
>
> - Claude → `.claude/settings.json`
> - Cursor → `.cursor/hooks.json`
> - Codex → **no tiene hooks** → su enforcement es el Anillo 1 (lefthook) + Anillo 3 (CI).

## La capa de normalización: `lib/io.sh`

Abstrae las diferencias entre clientes:

| Concepto | Claude | Cursor | `io.sh` lo expone como |
|---|---|---|---|
| input | stdin JSON `{tool_name, tool_input, session_id}` | stdin JSON `{hook_event_name, conversation_id, tool_input, command}` | `hook_tool`, `hook_file_path`, `hook_command`, `hook_session_id` |
| bloquear | `exit 2` + stderr (o JSON) | `exit 2` + stderr (== `permission:"deny"`) | `hook_block "razón"` |
| permitir | `exit 0` | `exit 0` | `hook_allow` |
| detectar cliente | — | `conversation_id` presente | `hook_client` |

> El **exit code 2 + stderr** es el mecanismo de bloqueo universal (ambos clientes lo respetan).
> Por eso los gates no necesitan emitir el JSON propietario de cada cliente.

## Los gates

| Script | Evento Claude | Evento Cursor | Bloquea | Qué hace |
|---|---|---|---|---|
| `session-start.sh` | SessionStart | sessionStart | no | reset markers + estado |
| `skill-reminder.sh` | PreToolUse Edit\|Write | preToolUse | **sí**¹ | leer-skill-antes-de-editar |
| `track-reads.sh` | PostToolUse Read | postToolUse | no | marca skills leídas |
| `track-trajectory.sh` | PostToolUse * | postToolUse | no | trayectoria sin secretos |
| `reviewer-gate.sh` | PreToolUse Bash | beforeShellExecution | **sí**¹ | gate de `git commit` + ratchet |
| `canon-enforce.sh` | Stop | stop | **sí** | reglas irrompibles (grep) |
| `drift-stop.sh` | Stop | stop | **sí** | errores nuevos de drift |

> ¹ En preset `lite` (`tools/preset`) `skill-reminder` y `reviewer-gate` **avisan** en vez de bloquear.
> El drift-ratchet del `reviewer-gate`, `canon-enforce` y `drift-stop` siguen **duros en ambos presets**.

## Notas de portabilidad

- **Nombres de tools varían entre clientes.** `skill-reminder.sh` y `track-reads.sh` filtran por
  nombre de tool (`Edit`, `edit_file`, `search_replace`, …). <!-- FILL: ajusta los `case` a los
  nombres reales que veas en `track-trajectory` de tu cliente. -->
- **Cursor no tiene un "before file edit" que deniegue**: por eso el skill-reminder se engancha a
  `preToolUse` (genérico) y se auto-filtra por tool de edición.
- **Failure-open**: todos hacen `exit 0` ante glitch. El backstop de lo que se cuele es el Anillo 3.
- **Los hooks `Stop` tienen un escape en Claude Code:** tras **8 bloqueos consecutivos** Claude
  anula el hook y cierra el turno igual. Por eso `canon-enforce`/`drift-stop` son una *red rápida*,
  no el muro final — las reglas que DEBEN cumplirse sí o sí viven también en el Anillo 1 (pre-commit)
  y el Anillo 3 (CI), que no tienen ese escape.
