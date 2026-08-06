#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# session-end.sh — hook SessionEnd
# ════════════════════════════════════════════════════════════════════
# El process-judge existía desde el día 1 y NUNCA corría: nada lo invocaba ni
# recordaba invocarlo. Un juez al que nadie llama es un juez que no existe
# (la lección G5 aplicada a agentes en vez de gates).
#
# Esto NO lo invoca (lanzar un agente desde un hook = coste no consentido,
# PRD 0002 §8). Hace lo mecánico: si la sesión tocó código y no hubo juicio,
# la ENCOLA. inject-context muestra la cola cada turno; el veredicto real del
# juez (vía capture-review-verdict) la vacía. Visibilidad mecánica,
# invocación humana.
#
# Observe-only: jamás bloquea (SessionEnd ignora exit codes de todas formas).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
SID="$(hook_session_id)"
[ -z "$SID" ] || [ "$SID" = "unknown" ] && SID="s-$(date +%s)"

QUEUE="$(hook_state_dir)/judge-queue.txt"

# ── ¿Tocó código esta sesión? ───────────────────────────────────────
# Señal: árbol sucio (fuera de .agents/state) o commits nuevos vs el inicio.
# Si la sesión fue solo lectura/conversación, no hay nada que juzgar.
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\? \.agents/state/' | wc -l | tr -d ' ')"
[ "${DIRTY:-0}" = "0" ] && exit 0

# ── ¿Ya la juzgaron? ────────────────────────────────────────────────
# Match EXACTO sobre el campo `session:` que escribe capture-review-verdict.
# La primera versión grepeaba el SID "a pelo" contra un marker que nunca lo
# contenía — código muerto que solo pasaba el test porque el fixture metía el
# SID en el SCOPE (hallazgo del reviewer). Dedup best-effort: si falla, la
# cola tolera entradas de más (PRD 0002 §7); nunca bloquea nada.
JUDGE_MARKER="$(hook_state_dir)/markers/process-judge_run.txt"
if [ -f "$JUDGE_MARKER" ] && grep -qx "session: ${SID}" "$JUDGE_MARKER" 2>/dev/null; then
  exit 0
fi

# ── Encolar (una línea por sesión, sin duplicar) ────────────────────
mkdir -p "$(dirname "$QUEUE")"
grep -q "· ${SID} ·" "$QUEUE" 2>/dev/null && exit 0
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
printf '%s · %s · %s · %s archivos tocados\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$BRANCH" "$DIRTY" >> "$QUEUE"
exit 0
