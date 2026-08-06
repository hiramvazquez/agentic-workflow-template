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
hook_event()      { command -v jq >/dev/null 2>&1 && _hook_jq '.hook_event_name // empty'; }

# ── Campos de sub-agente (SubagentStart / SubagentStop) ─────────────
hook_agent_type() { command -v jq >/dev/null 2>&1 && _hook_jq '.agent_type // empty'; }
hook_agent_id()   { command -v jq >/dev/null 2>&1 && _hook_jq '.agent_id // empty'; }
# El mensaje final del sub-agente: de aquí se DERIVA el veredicto (lib/verdict.sh).
hook_last_message() { command -v jq >/dev/null 2>&1 && _hook_jq '.last_assistant_message // empty'; }

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

# ── Salida JSON estructurada (solo Claude Code) ─────────────────────
# Claude Code parsea stdout como JSON en exit 0. Cursor lo ignora sin romperse,
# así que es seguro emitirlo siempre. Nos da dos cosas que `exit 2` no puede:
#
#   1. `additionalContext` — INYECTAR texto en el contexto del agente sin
#      bloquearlo. Es el mecanismo del bucle de verificación in-loop: el
#      linter falla → el agente lo lee en el mismo turno → lo corrige.
#   2. `decision: block` con razón, sin depender del exit code.
#
# hook_context <evento> <texto>   → informa (no bloquea)
hook_context() {
  local ev="$1" ctx="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg e "$ev" --arg c "$ctx" \
      '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
  else
    # Sin jq: degradamos a stderr, que el agente también ve.
    printf '%s\n' "$ctx" >&2
  fi
  exit 0
}

# hook_json_block <evento> <razón>  → bloquea vía JSON (equivalente a exit 2)
hook_json_block() {
  local ev="$1" why="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg e "$ev" --arg r "$why" \
      '{hookSpecificOutput:{hookEventName:$e, decision:"block", reason:$r}}'
    exit 0
  fi
  hook_block "$why"
}

# ── Marcadores de estado compartidos (ambos clientes) ───────────────
# Viven en .agents/state/ (gitignored) para que Claude y Cursor compartan.
hook_state_dir() { echo "${PROJECT_ROOT:-$(pwd)}/.agents/state"; }

# ── Preset: full (default, equipo) | lite (personal) ────────────────
# Lite degrada los gates "blandos" (skill-read, reviewer-marker) de BLOQUEAR a AVISAR.
# El drift-ratchet y canon/drift-stop siguen DUROS en ambos presets.
# Fuente: env WORKFLOW_PRESET, o la primera palabra de tools/preset.
hook_preset() {
  local p="${WORKFLOW_PRESET:-}" root="${PROJECT_ROOT:-$(pwd)}"
  [ -z "$p" ] && [ -f "$root/tools/preset" ] && p="$(awk 'NR==1{print $1; exit}' "$root/tools/preset" 2>/dev/null)"
  case "$p" in lite) echo lite ;; *) echo full ;; esac
}

# Bloquea (exit 2) en full; avisa a stderr y permite (exit 0) en lite.
hook_block_or_warn() {
  if [ "$(hook_preset)" = "lite" ]; then printf '⚠️  [lite] %s\n' "$1" >&2; exit 0; fi
  printf '%s\n' "$1" >&2; exit 2
}
