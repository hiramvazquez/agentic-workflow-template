#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# io.sh — capa de I/O NORMALIZADA para hooks de IA (Claude Code + Cursor)
# ════════════════════════════════════════════════════════════════════
# Problema: Claude Code y Cursor pasan JSON por stdin con shapes distintos
# y esperan respuestas distintas. Esta librería abstrae ambas para que los
# gates (skill-reminder, reviewer-gate, …) se escriban UNA sola vez.
#
# Diferencias clave que abstraemos:
#   - Claude:  {tool_name, tool_input:{file_path,command}, session_id}
#   - Cursor:  {hook_event_name, conversation_id, generation_id,
#               tool_name?, tool_input:{...}, command?, file_path?}
#   - Bloqueo: AMBOS soportan `exit 2 + stderr` para bloquear la acción.
#              (En Cursor, exit 2 == permission:"deny"; en Claude, exit 2
#               bloquea y reinyecta stderr al modelo.) → usamos exit 2.
#
# Filosofía: FAILURE-OPEN. Si algo del hook revienta (jq falta, JSON raro),
# permitimos (exit 0). Un bug del hook NO debe trabar al dev. El backstop
# de lo que se cuele es el Anillo 3 (CI).
# ════════════════════════════════════════════════════════════════════

HOOK_INPUT=""

hook_read_input() { HOOK_INPUT="$(cat)"; }

# ¿qué cliente nos invocó? (heurística por keys propias de cada uno)
hook_client() {
  command -v jq >/dev/null 2>&1 || { echo "unknown"; return; }
  local cid
  cid="$(printf '%s' "$HOOK_INPUT" | jq -r '.conversation_id // .generation_id // empty' 2>/dev/null)"
  if [ -n "$cid" ]; then echo "cursor"; else echo "claude"; fi
}

# Extrae un campo con fallbacks, agnóstico al cliente.
_hook_jq() { printf '%s' "$HOOK_INPUT" | jq -r "$1" 2>/dev/null || true; }

hook_tool()       { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_name // empty'; }
hook_file_path()  { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_input.file_path // .file_path // empty'; }
hook_command()    { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_input.command // .command // empty'; }
hook_session_id() { command -v jq >/dev/null 2>&1 && _hook_jq '.session_id // .conversation_id // .generation_id // "unknown"'; }

# Ruta relativa al repo (los hooks razonan en rutas relativas).
hook_rel_path() {
  local abs="$1" root="${PROJECT_ROOT:-$(pwd)}"
  printf '%s' "${abs#${root}/}"
}

# ── Decisiones (universales vía exit code) ──────────────────────────
# BLOQUEAR: imprime razón a stderr + exit 2. Funciona en Claude y Cursor.
hook_block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# PERMITIR: exit 0 silencioso.
hook_allow() { exit 0; }

# ── Marcadores de estado compartidos (ambos clientes) ───────────────
# Viven en .agents/state/ (gitignored) para que Claude y Cursor compartan.
hook_state_dir() { echo "${PROJECT_ROOT:-$(pwd)}/.agents/state"; }
