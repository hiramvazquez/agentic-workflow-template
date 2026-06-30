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
echo "── Salud de configuración ──"
PRESET="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null)"; [ -n "$PRESET" ] || PRESET=full
echo "• Preset: $PRESET  (full=gates bloquean · lite=gates avisan)"
_health=1
grep -qE 'Plataformas:\*\* <!-- FILL' AGENTS.md 2>/dev/null && { echo "⚠️  AGENTS.md §2 (Stack) SIN rellenar — build/test/lenguaje desconocidos."; _health=0; }
_src=0; for d in ios android web src; do [ -d "$d" ] && _src=1; done
[ "$_src" = "0" ] && { echo "⚠️  Sin carpetas de código (ios/android/web/src) — check-drift inactivo."; _health=0; }
grep -qE '\*View\*|\*\.swift|\*\.kt|\*\.ts' scripts/agent-hooks/skill-reminder.sh 2>/dev/null \
  || { echo "⚠️  skill-reminder sin globs concretos — gate leer-skill MUDO (configura AGENTS.md §11)."; _health=0; }
[ "$_health" = "1" ] && echo "✓ Stack, código y matriz de skills configurados."

echo ""
echo "── Guardrails activos ──"
if [ "$PRESET" = "lite" ]; then
  echo "• Edit/Write: AVISA si no leíste la skill (skill-reminder) — preset lite."
  echo "• git commit: AVISA sin review; el drift-ratchet SÍ bloquea (reviewer-gate)."
else
  echo "• Edit/Write: BLOQUEA si no leíste la skill requerida (skill-reminder)."
  echo "• git commit: BLOQUEA sin review reciente o si sube el drift-ratchet (reviewer-gate)."
fi
echo "• Stop: BLOQUEA si introdujiste violaciones/errores nuevos (canon-enforce + drift-stop)."
echo "• Markers se borran cada sesión → re-leer requerido."
exit 0
