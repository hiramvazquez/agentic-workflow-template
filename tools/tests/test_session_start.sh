#!/usr/bin/env bash
# session-start: reset de estado + health report. El invariante que fija este
# archivo: **observar no modifica** (f-session-start-fx). Ejecutarlo "para ver
# el estado" borraba los markers a mitad de sesión y el siguiente Edit quedaba
# bloqueado — el observador alteraba lo observado.

_sst_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── FALSO POSITIVO guard: --report NO tiene efectos secundarios ─────
_case_report_es_puro() {
  touch .agents/state/skills-read/algo.read
  echo baseline > .agents/state/drift-baseline.txt
  bash scripts/agent-hooks/session-start.sh --report >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    --report BORRÓ los markers de lectura"; return 1; }
  [ -f .agents/state/drift-baseline.txt ]   || { echo "    --report borró el baseline de drift"; return 1; }
}
test_report_no_modifica_el_estado() { _sst_sandbox _case_report_es_puro; }

# ── …y el modo hook (sin args) SÍ resetea, como siempre ─────────────
_case_hook_resetea() {
  touch .agents/state/skills-read/algo.read
  bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] && { echo "    el modo hook dejó de resetear los markers"; return 1; }
  return 0
}
test_modo_hook_sigue_reseteando() { _sst_sandbox _case_hook_resetea; }

# ── el health-check detecta el Anillo 1 dormido ─────────────────────
_case_detecta_anillo_dormido() {
  cp "$PROJECT_ROOT/lefthook.yml" . 2>/dev/null || echo "pre-commit:" > lefthook.yml
  # repo git SIN `lefthook install` → sin .git/hooks/pre-commit de lefthook
  local out; out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *"ANILLO 1 DORMIDO"*) return 0 ;; esac
  echo "    no detectó lefthook.yml sin hooks instalados"; return 1
}
test_detecta_anillo1_dormido() { _sst_sandbox _case_detecta_anillo_dormido; }
