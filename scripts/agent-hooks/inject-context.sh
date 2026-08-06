#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# inject-context.sh — hook UserPromptSubmit
# ════════════════════════════════════════════════════════════════════
# Inyecta el estado VIVO del proyecto en cada turno, sin coste permanente.
#
# La alternativa —meterlo en CLAUDE.md— tiene dos problemas: (a) se carga en
# TODAS las sesiones aunque no aplique, y (b) queda congelado en el momento en
# que se cargó. La doc oficial es explícita: un CLAUDE.md inflado hace que el
# modelo ignore las reglas que sí importan. Aquí se inyecta poco, fresco y
# solo lo que cambia.
#
# Se mantiene DELIBERADAMENTE corto (~15 líneas). Si crece, deja de leerse.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
LINES=""
add() { LINES="${LINES}$1"$'\n'; }

# ── Findings abiertos: "el que toca, cierra" (AGENTS.md §10) ────────
LEDGER="tools/findings/ledger.jsonl"
if [ -f "$LEDGER" ]; then
  N="$(grep -c '"status":"open"' "$LEDGER" 2>/dev/null || echo 0)"
  if [ "${N:-0}" -gt 0 ]; then
    add "· Findings ABIERTOS: $N — si tocas su área, los cierras o los actualizas (§10):"
    grep '"status":"open"' "$LEDGER" 2>/dev/null \
      | sed -E 's/.*"id":"([^"]+)".*"title":"([^"]+)".*"area":"([^"]+)".*/    [\1] \3 — \2/' \
      | head -5 | while IFS= read -r l; do printf '%s\n' "$l"; done > /tmp/.ic_$$ 2>/dev/null
    [ -f /tmp/.ic_$$ ] && { LINES="${LINES}$(cat /tmp/.ic_$$)"$'\n'; rm -f /tmp/.ic_$$; }
  fi
fi

# ── Trabajo sin commitear: evita que se pierda entre turnos ─────────
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\? \.agents/state/' | wc -l | tr -d ' ')"
[ "${DIRTY:-0}" -gt 0 ] && add "· Árbol SUCIO: $DIRTY archivos sin commitear en $(git rev-parse --abbrev-ref HEAD 2>/dev/null)."

# ── Deuda técnica al límite del trinquete ───────────────────────────
if [ -f tools/drift-ratchet.json ] && [ -f tools/check-drift.sh ]; then
  CEIL_E="$(sed -nE 's/.*"errors"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' tools/drift-ratchet.json | head -1)"
  [ "${CEIL_E:-0}" = "0" ] && add "· Trinquete de drift en 0 errores: cualquier violación nueva BLOQUEA el commit."
fi

# ── Estado de configuración del template ────────────────────────────
if grep -q '<!-- FILL' AGENTS.md 2>/dev/null; then
  add "· ⚠️  AGENTS.md tiene placeholders <!-- FILL --> sin rellenar (stack/build/tests desconocidos)."
fi

[ -z "$LINES" ] && hook_allow

hook_context "UserPromptSubmit" "📌 Estado vivo del proyecto (inyectado por hook, no lo pidas de nuevo):
$LINES"
