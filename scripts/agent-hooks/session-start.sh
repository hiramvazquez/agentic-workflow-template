#!/usr/bin/env bash
# Hook SessionStart (Claude) / sessionStart (Cursor).
# Tabula rasa por sesión: borra markers de skills leídos + baseline de drift,
# e imprime el estado del proyecto. Observe-only (no bloquea nunca).
#
#   sin args    → reset + reporte   (lo que invoca el hook)
#   --report    → SOLO reporte, sin efectos secundarios
#
# El modo --report existe porque observar no puede modificar: ejecutar este
# script "para ver el estado" borraba los markers de skills leídas a mitad de
# sesión y el siguiente Edit quedaba bloqueado — nos pasó (f-session-start-fx).
# Un script que un humano ejecuta para inspeccionar necesita un modo puro.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 0

MODE="${1:---reset}"

state_dir=".agents/state"
mkdir -p "$state_dir/skills-read" "$state_dir/markers" "$state_dir/trajectory"
if [ "$MODE" != "--report" ]; then
  # Reset: obliga a re-leer las skills requeridas en cada sesión nueva.
  find "$state_dir/skills-read" -mindepth 1 -delete 2>/dev/null || true
  rm -f "$state_dir/drift-baseline.txt" "$state_dir/drift-baseline.head" 2>/dev/null || true
fi

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

# ── Niveles de la pirámide que están MUDOS (verification-loop.md) ────
# Un gate no configurado es peor que ausente si el harness lo anuncia como
# activo: da falsa confianza. Aquí se declara explícitamente qué NO cubre.
command -v semgrep >/dev/null 2>&1 \
  || { echo "⚠️  Nivel 2 MUDO: semgrep no instalado (\`brew install semgrep\`) — sin detectores AST."; _health=0; }
grep -q '<!-- FILL' scripts/agent-hooks/post-edit-verify.sh 2>/dev/null \
  && grep -qE '^\s*\*\)\s*:\s*;;' scripts/agent-hooks/post-edit-verify.sh 2>/dev/null \
  && { echo "⚠️  Nivel 1 PARCIAL: post-edit-verify sin lint/typecheck de tu stack (§FILL) — el agente no recibe señal in-loop."; _health=0; }
grep -q '"min_score": 0' tools/mutation-ratchet.json 2>/dev/null \
  && { echo "⚠️  Nivel 4 MUDO: mutation score en 0 — NADA distingue un test real de uno decorativo."; _health=0; }
command -v gitleaks >/dev/null 2>&1 \
  || echo "⚠️  gitleaks no instalado — el scan de secretos del Anillo 1 no corre en local."

# ── ¿El Anillo 1 está DORMIDO? ──────────────────────────────────────
# lefthook.yml en el repo no significa nada si nadie corrió `lefthook install`:
# los hooks de git simplemente no existen y TODO el anillo universal calla.
# Nos pasó: el anillo estuvo mudo durante días y nadie lo notó, porque un
# gate que nunca dispara y uno que no existe se ven igual desde fuera (G5).
if [ -f lefthook.yml ] && [ -d .git ]; then
  if [ ! -f .git/hooks/pre-commit ] || ! grep -q lefthook .git/hooks/pre-commit 2>/dev/null; then
    echo "⚠️  ANILLO 1 DORMIDO: lefthook.yml existe pero los hooks de git NO están instalados."
    echo "   Ningún gate corre en git commit/push. Actívalo:  lefthook install"
    _health=0
  fi
fi

[ "$_health" = "1" ] && echo "✓ Stack, código, matriz de skills y pirámide de verificación configurados."

# ── Findings abiertos (AGENTS.md §10: el que toca, cierra) ──────────
if [ -f tools/findings/ledger.jsonl ]; then
  _open="$(grep -c '"status":"open"' tools/findings/ledger.jsonl 2>/dev/null || echo 0)"
  [ "${_open:-0}" -gt 0 ] && { echo ""; echo "── Findings abiertos: $_open (si tocas su área, ciérralos o actualízalos) ──"; }
fi

echo ""
echo "── Guardrails activos ──"
echo "• Anillo 0 (permissions): --no-verify, --amend, --force, lectura de .env y edición"
echo "  de los trinquetes están DENEGADOS de forma nativa. No dependen del modelo."
if [ "$PRESET" = "lite" ]; then
  echo "• Edit/Write: AVISA si no leíste la skill (skill-reminder) — preset lite."
  echo "• git commit: AVISA sin review; trinquete y capas SÍ bloquean (reviewer-gate)."
else
  echo "• Edit/Write: BLOQUEA si no leíste la skill requerida (skill-reminder)."
  echo "• git commit: BLOQUEA sin marker de review válido, o si sube el trinquete, o si"
  echo "  se violan las capas (reviewer-gate + lefthook + CI: los 3 anillos)."
fi
echo "• PostToolUse Edit/Write: lint+typecheck del archivo tocado → de vuelta al agente."
echo "• SubagentStop: el marker de review lo escribe el SISTEMA a partir del VERDICT"
echo "  real del sub-agente. Un marker escrito a mano se RECHAZA."
echo "• Stop: BLOQUEA si introdujiste violaciones/errores nuevos (canon-enforce + drift-stop)."
echo "• PostCompact: reinyecta el digest de reglas + findings tras compactar el contexto."
echo "• Markers se borran cada sesión → re-leer requerido."
exit 0
