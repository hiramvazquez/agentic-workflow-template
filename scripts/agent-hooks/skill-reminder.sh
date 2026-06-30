#!/usr/bin/env bash
# Hook PreToolUse Edit|Write (Claude) / preToolUse (Cursor) — BLOQUEANTE.
# Si el path a editar requiere leer ciertas skill references y NO hay marker
# de lectura en esta sesión → bloquea (exit 2). El modelo lee los refs
# (track-reads.sh los marca) y reintenta.
#
# Failure-open: cualquier glitch → exit 0 (permite). Backstop = CI.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"

hook_read_input

tool="$(hook_tool)"
# Solo nos importan herramientas de edición/escritura.
case "$tool" in
  Edit|Write|MultiEdit|create_file|edit_file|search_replace|str_replace*) : ;;
  *) hook_allow ;;
esac

file_path="$(hook_file_path)"
[ -z "$file_path" ] && hook_allow
rel="$(hook_rel_path "$file_path")"

# ── Matriz path → lectura obligatoria ───────────────────────────────
# FILL: mapea TUS paths reales → skill references. Edita SOLO los globs de
# los `case` de abajo (deben ser patrones glob válidos de bash, NO comentarios).
declare -a required=()
# UI / pantallas:
case "$rel" in
  *View*.swift|*.tsx|*Screen*.kt|*/ui/*)
      required+=(".agents/skills/architecture/SKILL.md") ;;
esac
# Lógica / casos de uso:
case "$rel" in
  *Logic*.swift|*UseCase*.kt|*/services/*.ts|*/domain/*)
      required+=(".agents/skills/architecture/SKILL.md" ".agents/skills/domain/SKILL.md") ;;
esac
# PRDs:
case "$rel" in
  docs/process/prds/[0-9]*.md)
      required+=(".agents/skills/process/references/prd-lifecycle.md" \
                 ".agents/skills/process/references/feature-workflow.md") ;;
esac

[ ${#required[@]} -eq 0 ] && hook_allow

# ── Verificación de markers ─────────────────────────────────────────
marker_dir="$(hook_state_dir)/skills-read"
declare -a missing=()
for ref in "${required[@]}"; do
  flat="${ref//\//__}"
  [ -f "$marker_dir/${flat}.read" ] || missing+=("$ref")
done
[ ${#missing[@]} -eq 0 ] && hook_allow

reason="🛑 Antes de editar \`$rel\` debes LEER (con la tool Read) en esta sesión:"$'\n'
for m in "${missing[@]}"; do reason+="  • $m"$'\n'; done
reason+="Tras leerlas, reintenta el Edit/Write. El sistema registra los Reads solo."
hook_block "$reason"
