#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# ci/ai-review.sh — Anillo 3 con IA (headless), PROVIDER-AGNÓSTICO
# ════════════════════════════════════════════════════════════════════
# Hasta ahora el Anillo 3 era 100% mecánico: los sub-agentes `reviewer` y
# `security-reviewer` solo corrían dentro de Claude Code. Consecuencia: los
# commits de Codex (sin hooks) y los de humanos NUNCA pasaban por review de IA.
#
# Este script cierra ese hueco corriendo la review en modo no interactivo.
#
# Requisitos: el binario `claude` en el runner + autenticación
# (ANTHROPIC_API_KEY, o el proveedor cloud que uses).
#
# Variables:
#   GATES_BASE_REF     rama base del diff (default: origin/main)
#   AI_REVIEW_REQUIRED 1 = su ausencia hace fallar el gate (default: 0 = avisa)
#   AI_REVIEW_MODEL    modelo a usar (default: el de la config del runner)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

BASE="${GATES_BASE_REF:-origin/main}"
REQUIRED="${AI_REVIEW_REQUIRED:-0}"

if ! command -v claude >/dev/null 2>&1; then
  echo "⚠️  ai-review: el binario \`claude\` no está en el runner."
  echo "   Instálalo para cubrir los commits que no pasan por hooks (Codex, humanos):"
  echo "     npm i -g @anthropic-ai/claude-code   # y exporta ANTHROPIC_API_KEY"
  [ "$REQUIRED" = "1" ] && exit 1
  exit 0
fi

DIFF_FILES="$(git diff --name-only "$BASE...HEAD" 2>/dev/null || true)"
if [ -z "$DIFF_FILES" ]; then
  echo "✅ ai-review: sin cambios respecto a $BASE."
  exit 0
fi

OUT_DIR="${AI_REVIEW_OUT:-.agents/state/ci}"; mkdir -p "$OUT_DIR"

# ── Prompt: pedimos EL MISMO contrato de veredicto que en local ─────
# Así la salida es parseable por máquina y comparable entre anillos.
PROMPT="Eres el sub-agente \`reviewer\` de este repositorio (ver .claude/agents/reviewer.md).

Revisa el diff de \`$BASE...HEAD\` contra las reglas duras de AGENTS.md.
Corre las verificaciones mecánicas (tools/check-layers.sh, tools/check-drift.sh,
tools/drift-ratchet.sh --check, tools/tests/run-tests.sh) y reporta su salida REAL.

Reporta solo lo que afecta a la corrección o a una regla explícita del proyecto.
No reportes preferencias de estilo: un revisor que señala todo se ignora entero.

Termina tu respuesta con el contrato, cada línea por separado:
VERDICT: GREEN|AMBER|RED
FINDINGS: <n>
SCOPE: <qué revisaste>"

echo "━━━ ai-review sobre $BASE...HEAD ($(printf '%s\n' "$DIFF_FILES" | wc -l | tr -d ' ') archivos) ━━━"

set +e
claude -p "$PROMPT" \
  --output-format json \
  --permission-mode plan \
  --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(bash tools/*)" \
  ${AI_REVIEW_MODEL:+--model "$AI_REVIEW_MODEL"} \
  > "$OUT_DIR/ai-review.json" 2>"$OUT_DIR/ai-review.err"
RC=$?
set -e 2>/dev/null || true

if [ $RC -ne 0 ]; then
  echo "⚠️  ai-review: la ejecución falló (rc=$RC):"
  tail -10 "$OUT_DIR/ai-review.err" 2>/dev/null | sed 's/^/   /'
  [ "$REQUIRED" = "1" ] && exit 1
  exit 0
fi

# ── Extraer el veredicto con el MISMO parser que usa el hook ────────
if command -v jq >/dev/null 2>&1; then
  RESULT="$(jq -r '.result // empty' "$OUT_DIR/ai-review.json" 2>/dev/null)"
else
  RESULT="$(cat "$OUT_DIR/ai-review.json")"
fi

# shellcheck source=../scripts/agent-hooks/lib/verdict.sh
. scripts/agent-hooks/lib/verdict.sh
VERDICT="$(verdict_parse "$RESULT")"
FINDINGS="$(verdict_findings "$RESULT")"

printf '%s\n' "$RESULT" | tee "$OUT_DIR/ai-review.md" | tail -40

case "$VERDICT" in
  GREEN) echo ""; echo "✅ ai-review: GREEN (${FINDINGS:-0} hallazgos)."; exit 0 ;;
  AMBER) echo ""; echo "⚠️  ai-review: AMBER (${FINDINGS:-?} hallazgos) — revisa el reporte, no bloquea."; exit 0 ;;
  RED)   echo ""; echo "❌ ai-review: RED (${FINDINGS:-?} hallazgos). Ver $OUT_DIR/ai-review.md"; exit 1 ;;
  *)
    echo ""
    echo "⚠️  ai-review: no emitió el contrato VERDICT — no se puede derivar un veredicto."
    [ "$REQUIRED" = "1" ] && exit 1
    exit 0 ;;
esac
