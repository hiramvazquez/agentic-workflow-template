#!/usr/bin/env bash
# Reúne el contexto para el sub-agente `process-judge`:
#   - la trayectoria capturada de la sesión (sin secretos)
#   - el diff del trabajo (staged + último commit)
#   - puntero a las reglas
# Uso:  bash scripts/process-judge-context.sh [session_id]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
SID="${1:-}"
TRAJ_DIR=".agents/state/trajectory"

echo "═══ REGLAS ═══"
echo "Lee: AGENTS.md, el tramo vivo de docs/process/lessons_learned.md (hasta el índice), y la skill del área tocada. El archivo histórico es bajo demanda."

echo ""; echo "═══ TRAYECTORIA ($SID) ═══"
if [ -n "$SID" ] && [ -f "$TRAJ_DIR/$SID.jsonl" ]; then
  cat "$TRAJ_DIR/$SID.jsonl"
else
  echo "(sin session_id o sin archivo; trayectorias disponibles:)"
  ls -1 "$TRAJ_DIR" 2>/dev/null || echo "  (ninguna)"
fi

echo ""; echo "═══ DIFF (staged) ═══"
git diff --cached --stat 2>/dev/null || true
echo ""; echo "═══ DIFF (último commit) ═══"
git show --stat HEAD 2>/dev/null | head -40 || true
