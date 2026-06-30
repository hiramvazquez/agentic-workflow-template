#!/usr/bin/env bash
# Hook PostToolUse * (Claude) / postToolUse (Cursor) — observe-only.
# Registra una TRAYECTORIA compacta y SIN SECRETOS/PII de las tool-calls,
# para que el sub-agente `process-judge` juzgue *cómo* se construyó un trabajo.
#
# PHI/secret-safety (crítico): SOLO metadata. NUNCA contenido de archivos,
# argumentos de comandos, prompts ni patrones de búsqueda. Del comando solo
# tomamos el PRIMER token (el binario) y lo descartamos si es `VAR=valor`
# (un secreto puede preceder al binario: `SERVICE_ROLE_KEY=… deno run`).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input
tool="$(hook_tool)"; [ -z "$tool" ] && exit 0
sid="$(hook_session_id)"; sid="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')"; [ -z "$sid" ] && sid="unknown"

# path seguro: file_path | primer token del command (descartando VAR=...)
path="$(printf '%s' "$HOOK_INPUT" | jq -rc '
  (.tool_input // {}) as $i
  | ( $i.file_path // .file_path
      // (($i.command // .command // "") | split(" ") | (.[0] // "") | if test("=") then "" else . end)
      // "" )' 2>/dev/null || true)"
case "$path" in "$PROJECT_ROOT"/*) path="${path#${PROJECT_ROOT}/}" ;; esac

dir="$(hook_state_dir)/trajectory"; mkdir -p "$dir" 2>/dev/null || exit 0
line="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$sid" --arg tool "$tool" --arg path "$path" \
  '{ts:$ts, sid:$sid, tool:$tool, path:$path}' 2>/dev/null || true)"
[ -n "$line" ] && printf '%s\n' "$line" >> "$dir/${sid}.jsonl" 2>/dev/null || true
exit 0
