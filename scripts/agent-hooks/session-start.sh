#!/usr/bin/env bash
# Hook SessionStart (Claude) / sessionStart (Cursor).
# Tabula rasa por sesión: borra markers de skills leídos + baseline de drift,
# e imprime el estado del proyecto. Observe-only (no bloquea nunca).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 0

state_dir=".agents/state"
mkdir -p "$state_dir/skills-read" "$state_dir/markers" "$state_dir/trajectory"
# Reset: obliga a re-leer las skills requeridas en cada sesión nueva.
find "$state_dir/skills-read" -mindepth 1 -delete 2>/dev/null || true
rm -f "$state_dir/drift-baseline.txt" "$state_dir/drift-baseline.head" 2>/dev/null || true

echo "═══ <PROJECT> — estado del proyecto ═══"
if command -v git >/dev/null 2>&1; then
  echo "Branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"
  echo "Último commit: $(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo '(sin commits)')"
fi

map="docs/process/current_execution_map.md"
if [ -f "$map" ]; then
  echo ""
  echo "── Estado actual (extracto) ──"
  awk '/^## Estado actual|^## Current/{flag=1; next} /^## /{flag=0} flag' "$map" | head -15
fi

echo ""
echo "── Guardrails activos ──"
echo "• Edit/Write: BLOQUEA si no leíste la skill requerida (skill-reminder)."
echo "• git commit: BLOQUEA sin review reciente o si sube el drift-ratchet (reviewer-gate)."
echo "• Stop: BLOQUEA si introdujiste violaciones/errores nuevos (canon-enforce + drift-stop)."
echo "• Markers se borran cada sesión → re-leer requerido."
exit 0
