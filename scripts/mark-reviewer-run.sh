#!/usr/bin/env bash
# Marca que el sub-agente `reviewer` corrió con verdict GREEN/AMBER sobre el
# estado actual. Liga el marker al HEAD + al sha del diff staged para que el
# reviewer-gate detecte si editas/commiteas algo distinto a lo revisado.
#
# Uso:  bash scripts/mark-reviewer-run.sh "scope: <descripción del review>"
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

SCOPE="${1:-(sin scope)}"
DIR=".agents/state/markers"; mkdir -p "$DIR"
HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"

cat > "$DIR/reviewer_run.txt" <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
scope: $SCOPE
head: $HEAD
staged_sha: $STAGED_SHA
EOF
echo "✅ marker escrito (head=$HEAD). El commit debe ocurrir en <60 min y sobre el mismo diff."
