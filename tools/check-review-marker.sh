#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-review-marker.sh — ¿este cambio fue realmente revisado?
# ════════════════════════════════════════════════════════════════════
# UNA implementación de la verificación, consumida por los TRES anillos:
#   Anillo 1 (lefthook)     → cubre commits humanos y de Codex
#   Anillo 2 (reviewer-gate)→ bloqueo rápido y local en Claude/Cursor
#   Anillo 3 (run-gates)    → backstop server-side
#
# Antes vivía solo en el Anillo 2, así que no hacía falta `--no-verify` para
# saltárselo: bastaba commitear desde otra terminal. Ahora está en los tres.
#
# El marker debe estar ligado a TRES cosas para ser válido:
#   1. tiempo   (TTL)          — un review de ayer no vale para hoy
#   2. HEAD     (sha)          — si commiteaste entremedio, es stale
#   3. diff staged (sha256)    — lo revisado debe ser LO QUE SE COMMITEA
#   + 4. source: hook          — lo escribió el sistema, no el modelo
#
#   bash tools/check-review-marker.sh            # sobre el diff staged
#   bash tools/check-review-marker.sh --range    # sobre origin/main..HEAD (CI)
#   REVIEWER_MARKER_TTL=1800 …                   # TTL en segundos (default 3600)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

MODE="${1:---staged}"
TTL="${REVIEWER_MARKER_TTL:-3600}"
MARKER=".agents/state/markers/reviewer_run.txt"
# <!-- FILL: ajusta los globs de "NO es código de producto" a tu repo. -->
NON_PRODUCT='^(docs/|ci/|tools/|scripts/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|lefthook|\.gitleaks)'

fail() { echo "$1"; exit 1; }

# ── ¿Hay código de producto en el cambio? ───────────────────────────
if [ "$MODE" = "--range" ]; then
  BASE="${GATES_BASE_REF:-origin/main}"
  CHANGED="$(git diff --name-only "$BASE...HEAD" 2>/dev/null || echo "")"
else
  CHANGED="$(git diff --cached --name-only 2>/dev/null || echo "")"
fi
[ -z "$CHANGED" ] && { echo "✅ review-marker: sin cambios que revisar."; exit 0; }

CRITICAL="$(printf '%s\n' "$CHANGED" | grep -vE "$NON_PRODUCT" || true)"
[ -z "$CRITICAL" ] && { echo "✅ review-marker: el cambio no toca código de producto (solo docs/tooling)."; exit 0; }

# ── Preset: `lite` AVISA, `full` BLOQUEA (AGENTS.md §13) ────────────
# Esta comprobación vive AQUÍ, en la implementación compartida, y no en cada
# llamador. Cuando solo estaba en `reviewer-gate.sh` (Anillo 2), lefthook
# (Anillo 1) invocaba este script directo y bloqueaba igual en preset `lite`:
# el agente recibía luz verde y el `git commit` fallaba después, contradiciendo
# lo que §13 promete. Una regla implementada en dos sitios diverge; por eso
# vive en uno solo (README §"Una fuente de verdad").
# Fijado por `tools/tests/test_review_marker_preset.sh`.
PRESET="${WORKFLOW_PRESET:-}"
[ -z "$PRESET" ] && [ -f tools/preset ] && PRESET="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null)"
case "$PRESET" in
  lite)
    echo "⚠️  [lite] review-marker: hay código de producto sin review, pero el preset personal"
    echo "   solo avisa. Considera invocar el sub-agente \`reviewer\`. (Los trinquetes y las"
    echo "   capas SIGUEN duros en lite — ver AGENTS.md §9 y §13.)"
    exit 0 ;;
esac

# ── Override de emergencia, AUDITADO ────────────────────────────────
if [ "${REVIEWER_OVERRIDE:-0}" = "1" ]; then
  mkdir -p .agents/state/markers
  printf '[%s] override en %s · reason=%s · files=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)" \
    "${REVIEWER_OVERRIDE_REASON:-(SIN RAZÓN — esto es un smell)}" \
    "$(printf '%s' "$CRITICAL" | tr '\n' ',')" \
    >> .agents/state/markers/override_log.txt
  echo "⚠️  review-marker: OVERRIDE activo — registrado en override_log.txt."
  exit 0
fi

# ── 0. ¿Existe? ─────────────────────────────────────────────────────
[ -f "$MARKER" ] || fail "❌ review-marker: NO hay review de estos cambios de producto:
$(printf '%s\n' "$CRITICAL" | sed 's/^/  - /')

Invoca el sub-agente \`reviewer\`. Al terminar debe emitir:
  VERDICT: GREEN|AMBER|RED
El hook SubagentStop escribe el marker automáticamente a partir de ese veredicto.
Override auditado: REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\" <comando>"

get() { grep -E "^$1:" "$MARKER" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//"; }

# ── 1. ¿Lo escribió el sistema o el modelo? ─────────────────────────
SOURCE="$(get source)"
if [ "$SOURCE" != "hook" ]; then
  fail "❌ review-marker: el marker NO lo escribió el sistema (source='${SOURCE:-ausente}').

Un marker manual no es evidencia de review — es una afirmación del agente.
El marker válido lo produce el hook SubagentStop a partir del veredicto real
del sub-agente \`reviewer\`. Invócalo y deja que emita su VERDICT.
Si de verdad necesitas saltártelo: REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\""
fi

# ── 2. ¿El veredicto permite commitear? ─────────────────────────────
VERDICT="$(get verdict)"
case "$VERDICT" in
  GREEN|AMBER) : ;;
  *) fail "❌ review-marker: veredicto '${VERDICT:-ausente}' no permite commitear. Atiende los hallazgos y re-revisa." ;;
esac

# ── 3. Edad ─────────────────────────────────────────────────────────
NOW=$(date +%s)
MTIME=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)
[ $((NOW - MTIME)) -gt "$TTL" ] && fail "❌ review-marker: EXPIRADO (>${TTL}s). Re-corre \`reviewer\`."

# ── 4. Binding a HEAD ───────────────────────────────────────────────
MARKED_HEAD="$(get head)"; CUR_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo '')"
if [ -n "$MARKED_HEAD" ] && [ -n "$CUR_HEAD" ] && [ "$MARKED_HEAD" != "no-repo" ] && [ "$MARKED_HEAD" != "$CUR_HEAD" ]; then
  fail "❌ review-marker: STALE (HEAD cambió ${MARKED_HEAD}→${CUR_HEAD}). Re-corre \`reviewer\`."
fi

# ── 5. Binding al DIFF (solo aplica en modo staged) ─────────────────
if [ "$MODE" != "--range" ]; then
  MARKED_STAGED="$(get staged_sha)"
  CUR_STAGED="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
  if [ -n "$MARKED_STAGED" ] && [ -n "$CUR_STAGED" ] && [ "$MARKED_STAGED" != "$CUR_STAGED" ]; then
    fail "❌ review-marker: el diff STAGED cambió desde la review (revisado=${MARKED_STAGED:0:12}… actual=${CUR_STAGED:0:12}…).
Lo que se revisó ya no es lo que vas a commitear. Re-corre \`reviewer\`."
  fi
fi

echo "✅ review-marker: válido (agent=$(get agent) verdict=$VERDICT head=$MARKED_HEAD source=hook)."
exit 0
