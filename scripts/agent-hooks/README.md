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
| `session-start.sh` | SessionStart | sessionStart | no | reset markers + estado + qué niveles están MUDOS |
| `inject-context.sh` | UserPromptSubmit | beforeSubmitPrompt | no | estado vivo por turno: findings abiertos, cola de juicio, árbol sucio |
| `skill-reminder.sh` | PreToolUse Edit\|Write | preToolUse | **sí**¹ | leer-skill-antes-de-editar (excluye docs/tooling — G1) |
| `post-edit-verify.sh` | PostToolUse Edit\|Write | postToolUse | no² | **verificación in-loop**: lint/typecheck del archivo tocado → `additionalContext` |
| `track-reads.sh` | PostToolUse Read | postToolUse | no | marca skills leídas |
| `track-trajectory.sh` | PostToolUse * | postToolUse | no | trayectoria sin secretos |
| `track-failure.sh` | PostToolUseFailure | — | no | detecta el bucle de reintentos (4 fallos = hipótesis equivocada) |
| `reviewer-gate.sh` | PreToolUse Bash | beforeShellExecution | **sí**¹ | gate de `git commit`: ratchet + capas + semgrep + marker |
| `capture-review-verdict.sh` | SubagentStop | — | — | **el invariante nº1**: deriva el marker del `VERDICT:` real del sub-agente; el juez vacía su cola |
| `canon-enforce.sh` | Stop | stop | **sí** | reglas irrompibles (capas, secretos, harness con tests verdes) |
| `drift-stop.sh` | Stop | stop | **sí** | errores nuevos de drift vs baseline de sesión |
| `post-compact.sh` | PostCompact | — | no | reinyecta el digest de reglas + findings tras compactar contexto |
| `session-end.sh` | SessionEnd | — | no | encola la sesión en `judge-queue` si tocó código sin juicio |

> ¹ En preset `lite` (`tools/preset`) `skill-reminder` y el marker de review **avisan** en vez de
> bloquear. Los detectores mecánicos (drift-ratchet, capas, hallazgos de semgrep) siguen **duros
> en ambos presets** — ni `lite` ni `REVIEWER_OVERRIDE` los relajan (test_ratchets.sh lo fija).
>
> ² `post-edit-verify` no bloquea NUNCA por diseño: informa en el mismo turno. Un formateador con
> una opinión no puede trabar el trabajo; para bloquear están Stop y los Anillos 1/3.
>
> Cursor no expone `SubagentStop`/`PostCompact`/`SessionEnd`: para Cursor (y Codex) el backstop de
> esos gates es el Anillo 1 (lefthook) + Anillo 3 (`ci/run-gates.sh` + `ci/ai-review.sh`).

## El contrato de veredicto (VERDICT)

Los sub-agentes de review (`reviewer`, `security-reviewer`, `design-reviewer`, `process-judge`)
terminan su mensaje con `VERDICT: GREEN|AMBER|RED` + `FINDINGS: n` + `SCOPE: …`. El hook
`capture-review-verdict.sh` lo parsea (`lib/verdict.sh`) y **el sistema** escribe el marker —
nunca el modelo. `tools/check-review-marker.sh` solo acepta `source: hook`, ligado al `sha256`
del diff staged. Alcance honesto: defiende contra *error de proceso*, no contra un agente
adversario con shell — para eso está el Anillo 3 (ver README raíz, "Qué garantiza y qué no").

## Telemetría (nivel 9)

`hook_log_detection <source> <rule> <area> [n]` (en `lib/io.sh`) registra cada detección en
`.agents/state/metrics/detections.jsonl` (local, gitignored). `tools/metrics/escape-rate.sh` lo
agrega con el ledger. Contrato duro: **best-effort total — la telemetría jamás rompe al gate
que la llama** (devuelve 0 pase lo que pase; hay test que lo fija sin python3 en el PATH).

## Tests

Los gates son código: `tools/tests/` los fija (105 tests), y `test_meta_fp.sh` exige que todo
detector tenga **tests de sus falsos positivos** — la lección más cara del PRD 0001: el primer
FP de un detector casi siempre aparece en el repo del propio detector.

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
