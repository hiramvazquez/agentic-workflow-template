#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# post-edit-verify.sh — hook PostToolUse Edit|Write|MultiEdit
# ════════════════════════════════════════════════════════════════════
# EL BUCLE DE VERIFICACIÓN IN-LOOP. Es el gate de mayor ROI del harness.
#
# Sin él, el agente no recibe señal mecánica hasta el `Stop` o el commit: un
# error de tipos del turno 3 se descubre en el turno 40, con 37 turnos de
# trabajo construidos encima y el contexto ya contaminado. Con él, el linter
# corre sobre EL ARCHIVO QUE ACABA DE TOCAR y el resultado vuelve al agente
# vía `additionalContext` en el mismo turno.
#
# Reglas de diseño (importan tanto como el script):
#   - NUNCA bloquea. Solo informa. Un formateador con una opinión no debe
#     poder trabar el trabajo; para lo que sí debe bloquear están canon-enforce
#     (Stop) y los anillos 1 y 3.
#   - Solo el archivo tocado, jamás el repo. Debe costar < 2s.
#   - Silencioso cuando todo está bien: ruido constante = ruido ignorado.
#   - Sin linter configurado → no-op silencioso (lo reporta el health-check
#     del SessionStart, no cada edición).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
EV="PostToolUse"

case "$(hook_tool)" in
  Edit|Write|MultiEdit|create_file|edit_file|search_replace|str_replace*) : ;;
  *) hook_allow ;;
esac

FILE="$(hook_file_path)"
[ -z "$FILE" ] && hook_allow
[ -f "$FILE" ] || hook_allow
REL="$(hook_rel_path "$FILE")"

OUT=""
add() { [ -n "$1" ] && OUT="${OUT}$1"$'\n'; }
# Corre un comando con timeout suave y captura solo si falla.
try() { # try <etiqueta> <comando...>
  local label="$1"; shift
  command -v "$1" >/dev/null 2>&1 || return 0
  local o; o="$("$@" 2>&1)"; local rc=$?
  [ $rc -eq 0 ] && return 0
  add "── $label ──"
  add "$(printf '%s' "$o" | head -25)"
}

case "$REL" in
  # ── Shell: el harness es shell, así que esto SÍ está cableado ─────
  *.sh)
    try "shellcheck $REL" shellcheck -S warning "$FILE"
    try "bash -n $REL"    bash -n "$FILE"
    ;;

  # ── JSON / YAML: errores de sintaxis que rompen configs silenciosamente ─
  *.json)
    if command -v jq >/dev/null 2>&1; then
      o="$(jq empty "$FILE" 2>&1)" || { add "── JSON inválido en $REL ──"; add "$o"; }
    fi
    ;;
  *.yaml|*.yml)
    if command -v yq >/dev/null 2>&1; then
      o="$(yq e '.' "$FILE" 2>&1 >/dev/null)" || { add "── YAML inválido en $REL ──"; add "$o"; }
    fi
    ;;

  # <!-- FILL: cablea el lint/typecheck de TU stack. Regla: solo el archivo
  #      tocado, < 2s, y que devuelva texto accionable. Ejemplos:
  #
  #  *.swift)
  #    try "swiftformat --lint" swiftformat --lint "$FILE"
  #    try "swiftlint"          swiftlint lint --quiet --path "$FILE"
  #    ;;
  #  *.kt|*.kts)
  #    try "ktlint"             ktlint "$FILE"
  #    ;;
  #  *.ts|*.tsx)
  #    try "eslint"             npx --no-install eslint --format unix "$FILE"
  #    # typecheck del proyecto (más caro): déjalo para pre-push si tarda.
  #    try "tsc"                npx --no-install tsc --noEmit -p .
  #    ;;
  #  *.py)
  #    try "ruff"               ruff check "$FILE"
  #    try "mypy"               mypy "$FILE"
  #    ;;
  # -->
  *) : ;;
esac

# ── Señales universales, independientes del stack ───────────────────
# Tamaño de archivo (AGENTS.md §4): avisar en el momento en que se cruza el
# límite, no en el review, cuando dividirlo ya cuesta 10× más.
HARD=${DRIFT_FILE_HARD:-400}; SOFT=${DRIFT_FILE_SOFT:-200}
case "$REL" in
  *.swift|*.kt|*.kts|*.ts|*.tsx|*.js|*.jsx|*.py|*.java|*.go|*.rb|*.rs)
    n=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
    if [ "${n:-0}" -gt "$HARD" ]; then
      add "── tamaño ──"
      add "$REL tiene $n líneas (hard limit $HARD, AGENTS.md §4). Divídelo en ESTE mismo cambio."
    elif [ "${n:-0}" -gt "$SOFT" ]; then
      add "── tamaño ──"
      add "$REL tiene $n líneas (soft limit $SOFT). Vale la pena revisar si ya son dos responsabilidades."
    fi
    ;;
esac

[ -z "$OUT" ] && hook_allow   # todo limpio → silencio

hook_context "$EV" "🔧 Verificación automática de \`$REL\` (no bloquea, pero arréglalo AHORA — cuesta 10× menos que en el review):

$OUT"
