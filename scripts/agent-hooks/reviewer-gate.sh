#!/usr/bin/env bash
# Hook PreToolUse Bash (Claude) / beforeShellExecution (Cursor) — BLOQUEANTE.
# Gate de `git commit`: bloquea si (a) el drift-ratchet subió, o (b) no hay
# marker reciente del sub-agente `reviewer` ligado al HEAD + diff actuales.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
CMD="$(hook_command)"
# Solo gateamos `git commit`.
printf '%s' "$CMD" | grep -qE '(^|[^a-z-])git commit' || hook_allow

# Override de emergencia (auditado).
if [ "${REVIEWER_OVERRIDE:-0}" = "1" ]; then
  mkdir -p "$(hook_state_dir)/markers"
  printf '[%s] override: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REVIEWER_OVERRIDE_REASON:-(sin razón)}" \
    >> "$(hook_state_dir)/markers/override_log.txt"
  echo "⚠️  reviewer-gate: override activo — commit permitido." >&2
  hook_allow
fi

# (a) Drift ratchet — el conteo solo baja.
if [ -x tools/drift-ratchet.sh ]; then
  if ! out="$(bash tools/drift-ratchet.sh --check 2>&1)"; then
    hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por drift-ratchet. Baja la deuda que subiste, o usa REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\"."
  fi
fi

# ¿Hay cambios staged en código de producto? (si solo docs/tooling → pasa)
CHANGED="$(git diff --cached --name-only 2>/dev/null || echo "")"
[ -z "$CHANGED" ] && hook_allow
# <!-- FILL: ajusta los globs de "código de producto" de tu repo. -->
CRITICAL="$(printf '%s\n' "$CHANGED" | grep -vE '^(docs/|ci/|tools/|scripts/|README|\.gitignore|lefthook|\.gitleaks)' || true)"
[ -z "$CRITICAL" ] && hook_allow

# (b) Marker del reviewer.
MARKER="$(hook_state_dir)/markers/reviewer_run.txt"
if [ ! -f "$MARKER" ]; then
  hook_block "❌ reviewer-gate: commit BLOQUEADO. Cambios críticos sin review:
$(echo "$CRITICAL" | sed 's/^/  - /')

Invoca el sub-agente \`reviewer\`, atiende RED/AMBER, y marca:
  bash scripts/mark-reviewer-run.sh \"scope: <descripción>\"
Override: REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\" git commit ..."
fi

# Edad (TTL 60 min).
NOW=$(date +%s)
MTIME=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)
if [ $((NOW - MTIME)) -gt 3600 ]; then
  hook_block "❌ reviewer-gate: marker EXPIRADO (>60 min). Re-corre \`reviewer\` y re-marca."
fi

# Binding a HEAD (si commiteaste entremedio, el review es stale).
MARKED_HEAD="$(grep -E '^head:' "$MARKER" | awk '{print $2}')"
CUR_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo '')"
if [ -n "$MARKED_HEAD" ] && [ -n "$CUR_HEAD" ] && [ "$MARKED_HEAD" != "no-repo" ] && [ "$MARKED_HEAD" != "$CUR_HEAD" ]; then
  hook_block "❌ reviewer-gate: marker STALE (HEAD cambió $MARKED_HEAD→$CUR_HEAD). Re-corre \`reviewer\` y re-marca."
fi

# Binding al DIFF STAGED: lo que se revisó debe ser exactamente lo que se commitea.
# (mark-reviewer-run.sh guarda staged_sha; si añadiste/quitaste cambios staged tras la
#  review, el marker es stale aunque HEAD no haya cambiado. Cierra el hueco real.)
MARKED_STAGED="$(grep -E '^staged_sha:' "$MARKER" | awk '{print $2}')"
CUR_STAGED="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
if [ -n "$MARKED_STAGED" ] && [ -n "$CUR_STAGED" ] && [ "$MARKED_STAGED" != "$CUR_STAGED" ]; then
  hook_block "❌ reviewer-gate: el diff STAGED cambió desde la review (revisado=${MARKED_STAGED:0:12}… actual=${CUR_STAGED:0:12}…).
Lo que se revisó ya no es lo que vas a commitear. Re-corre \`reviewer\` y re-marca,
o usa REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\" git commit ..."
fi

echo "✅ reviewer-gate: marker válido, commit permitido." >&2
hook_allow
