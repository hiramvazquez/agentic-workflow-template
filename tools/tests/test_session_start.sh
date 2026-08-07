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

# ── …y el modo hook (startup) SÍ resetea, como siempre ──────────────
_case_hook_resetea() {
  touch .agents/state/skills-read/algo.read
  echo '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] && { echo "    el modo hook dejó de resetear los markers"; return 1; }
  return 0
}
test_modo_hook_sigue_reseteando() { _sst_sandbox _case_hook_resetea; }

# ── source=compact JAMÁS resetea (defensa en profundidad) ───────────
# El bug real: SessionStart sin matcher borraba markers y baseline TRAS UNA
# COMPACTACIÓN — el drift-stop re-baseaba incluyendo los errores que el agente
# acababa de introducir, que pasaban a baseline y nunca se bloqueaban. El
# matcher de settings.json ya lo enruta bien; esto fija que, aunque un wrapper
# lo invoque mal, el script se defiende solo.
_case_compact_no_resetea() {
  touch .agents/state/skills-read/algo.read
  echo baseline > .agents/state/drift-baseline.txt
  echo '{"hook_event_name":"SessionStart","source":"compact"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    compact BORRÓ los markers de skills"; return 1; }
  [ -f .agents/state/drift-baseline.txt ]   || { echo "    compact borró el baseline de drift"; return 1; }
}
test_source_compact_no_resetea_estado() { _sst_sandbox _case_compact_no_resetea; }

_case_resume_no_resetea() {
  touch .agents/state/skills-read/algo.read
  echo '{"hook_event_name":"SessionStart","source":"resume"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    resume BORRÓ los markers de skills"; return 1; }
  return 0
}
test_source_resume_no_resetea_estado() { _sst_sandbox _case_resume_no_resetea; }

# ── el health-check detecta el Anillo 1 dormido ─────────────────────
_case_detecta_anillo_dormido() {
  cp "$PROJECT_ROOT/lefthook.yml" . 2>/dev/null || echo "pre-commit:" > lefthook.yml
  # repo git SIN `lefthook install` → sin .git/hooks/pre-commit de lefthook
  local out; out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *"ANILLO 1 DORMIDO"*) return 0 ;; esac
  echo "    no detectó lefthook.yml sin hooks instalados"; return 1
}
test_detecta_anillo1_dormido() { _sst_sandbox _case_detecta_anillo_dormido; }
