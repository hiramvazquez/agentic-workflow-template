#!/usr/bin/env bash
# La matriz path→skill vivía en CINCO sitios y "nada se duplica" era mentira.
# Ahora la FUENTE ÚNICA es tools/skill-matrix.conf (skill-reminder la lee en
# runtime). Estos tests fijan: (1) toda ref citada EXISTE — una matriz que
# exige leer archivos inexistentes bloquea el trabajo para siempre; (2) el
# hook consume el conf de verdad; (3) sin conf, el fallback de fábrica sigue.

test_toda_ref_de_la_matriz_existe() {
  [ -f tools/skill-matrix.conf ] || { echo "    tools/skill-matrix.conf no existe"; return 1; }
  local glob refs r bad=0 _old
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { echo "    ref inexistente: $r (glob '$glob')"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}

_smx_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read" "$d/src"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_conf_gobierna_el_gate() {
  # Matriz mínima propia: SOLO los .py exigen leer una ref.
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  mkdir -p docs; echo regla > docs/regla.md
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el conf no gobernó el gate (exit $rc, esperaba 2)"; return 1; }
  # …y con el marker de lectura presente, pasa.
  touch .agents/state/skills-read/docs__regla.md.read
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    con marker presente siguió bloqueando (exit $rc)"; return 1; }
}
test_skill_reminder_lee_el_conf() { _smx_sandbox _case_conf_gobierna_el_gate; }

# FALSO POSITIVO guard: un path que NO casa ningún glob no puede bloquearse.
_case_path_fuera_de_matriz_pasa() {
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/main.go"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    bloqueó un path fuera de la matriz (exit $rc)"; return 1; }
}
test_path_fuera_de_la_matriz_no_bloquea() { _smx_sandbox _case_path_fuera_de_matriz_pasa; }

# ── consistencia matriz ↔ track-reads (bug real, cazado EN VIVO) ────
# Toda ref que la matriz EXIGE leer debe ser REGISTRABLE por track-reads.
# Si no, el flujo es un bucle infinito: el agente lee la skill (obedece),
# el marker no se crea, skill-reminder bloquea, el agente re-lee… Lo cazó
# el agente del primer proyecto real depurando el hook — platforms/*.md
# estaba en la matriz pero no en el filtro del tracker.
_case_refs_registrables() {
  cp "$PROJECT_ROOT/tools/skill-matrix.conf" tools/skill-matrix.conf
  local glob refs r _old bad=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"; [ -z "$r" ] && continue
      rm -rf .agents/state/skills-read
      printf '{"tool_name":"Read","tool_input":{"file_path":"%s/%s"}}' "$PWD" "$r" \
        | bash scripts/agent-hooks/track-reads.sh >/dev/null 2>&1
      [ -f ".agents/state/skills-read/${r//\//__}.read" ] \
        || { echo "    ref '$r' NO registrable por track-reads → skill-reminder bloquearía para siempre"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}
test_toda_ref_es_registrable_por_track_reads() { _smx_sandbox _case_refs_registrables; }

_case_sin_conf_usa_fallback() {
  rm -f tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/PagoLogic.swift"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    sin conf, el fallback de fábrica no gateó (exit $rc)"; return 1; }
}
test_sin_conf_cae_al_fallback_de_fabrica() { _smx_sandbox _case_sin_conf_usa_fallback; }
