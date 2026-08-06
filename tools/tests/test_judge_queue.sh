#!/usr/bin/env bash
# Cola del process-judge. El juez existía desde el día 1 y NUNCA corría solo:
# nada lo invocaba ni recordaba invocarlo. La cola hace el trabajo pendiente
# VISIBLE cada turno (inject-context) hasta que un veredicto real lo vacía.
#
# Deliberadamente NO auto-invoca al juez (PRD 0002 §8): lanzar un agente desde
# un hook es coste no consentido. Visibilidad mecánica, invocación humana.

_jq_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/trajectory" "$d/tools/findings" "$d/docs/process"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    # Se commitea TODO el andamiaje copiado: el caso "sesión sin cambios"
    # exige un árbol base LIMPIO, o el propio sandbox sería el falso positivo.
    git add -A 2>/dev/null; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_end_session() { # _end_session <session_id>
  printf '{"session_id":"%s","hook_event_name":"SessionEnd"}' "$1" \
    | bash scripts/agent-hooks/session-end.sh >/dev/null 2>&1
}
QUEUE=".agents/state/judge-queue.txt"

# ── encolar ─────────────────────────────────────────────────────────
_case_sesion_con_codigo_encola() {
  mkdir -p src; echo "x" > src/App.swift          # árbol tocado
  _end_session s-abc
  [ -f "$QUEUE" ] && grep -q "s-abc" "$QUEUE" || { echo "    la sesión con código no se encoló"; return 1; }
}
test_sesion_que_toco_codigo_se_encola() { _jq_sandbox _case_sesion_con_codigo_encola; }

# ── FALSO POSITIVO: sesión sin trabajo no encola ────────────────────
_case_sesion_limpia_no_encola() {
  _end_session s-clean
  [ -f "$QUEUE" ] && grep -q "s-clean" "$QUEUE" && { echo "    FALSO POSITIVO: una sesión sin cambios se encoló"; return 1; }
  return 0
}
test_sesion_sin_cambios_no_se_encola() { _jq_sandbox _case_sesion_limpia_no_encola; }

_case_no_duplica_sesion() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-dup; _end_session s-dup
  local n; n="$(grep -c "s-dup" "$QUEUE" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || { echo "    la misma sesión se encoló $n veces"; return 1; }
}
test_la_misma_sesion_no_se_duplica() { _jq_sandbox _case_no_duplica_sesion; }

# ── visible cada turno ──────────────────────────────────────────────
_case_inject_muestra_cola() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-vis
  local out; out="$(echo '{}' | bash scripts/agent-hooks/inject-context.sh 2>/dev/null)"
  case "$out" in *process-judge*) return 0 ;; esac
  echo "    inject-context no muestra la cola pendiente"; return 1
}
test_la_cola_es_visible_por_turno() { _jq_sandbox _case_inject_muestra_cola; }

# ── el veredicto REAL del juez vacía la cola ────────────────────────
_case_verdict_del_juez_vacia() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-judged
  # printf '%s' para que el \n llegue ESCAPADO (como lo envía Claude Code):
  # un salto de línea real dentro de un string JSON es inválido y jq devuelve
  # vacío → el hook saldría por "sin mensaje" y el test pasaría por el motivo
  # equivocado.
  printf '%s' '{"agent_type":"process-judge","last_assistant_message":"Trayectoria revisada.\nVERDICT: AMBER\nFINDINGS: 2\nSCOPE: sesión s-judged"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -s "$QUEUE" ] && { echo "    el veredicto del juez NO vació la cola"; return 1; }
  [ -f ".agents/state/markers/process-judge_run.txt" ] || { echo "    no quedó marker del juicio"; return 1; }
  return 0
}
test_el_verdict_del_juez_vacia_la_cola() { _jq_sandbox _case_verdict_del_juez_vacia; }

# ── la sesión YA JUZGADA no se re-encola al terminar ────────────────
_case_sesion_juzgada_no_reencola() {
  mkdir -p src; echo "x" > src/App.swift
  # El juez corre DURANTE la sesión s-done (su payload trae el session_id):
  printf '%s' '{"session_id":"s-done","agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: lote"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  # …y al cerrar ESA sesión (árbol aún sucio), no debe volver a la cola.
  # La primera versión de este dedup era código muerto: grepeaba el SID en un
  # marker que nunca lo contenía, y el test de arriba pasaba solo porque el
  # fixture metía el SID en el SCOPE. Este caso fija el contrato REAL
  # (campo `session:` con match exacto).
  _end_session s-done
  [ -f "$QUEUE" ] && grep -q "s-done" "$QUEUE" && { echo "    la sesión ya juzgada se re-encoló"; return 1; }
  return 0
}
test_sesion_ya_juzgada_no_se_reencola() { _jq_sandbox _case_sesion_juzgada_no_reencola; }

_case_otro_sid_si_encola() {
  # FALSO POSITIVO guard del dedup: que s-aaa esté juzgada no puede tragarse
  # a s-aaab (match EXACTO, no substring).
  mkdir -p src; echo "x" > src/App.swift
  printf '%s' '{"session_id":"s-aaa","agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: lote"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  _end_session s-aaab
  grep -q "s-aaab" "$QUEUE" 2>/dev/null || { echo "    el dedup por substring se tragó una sesión distinta"; return 1; }
}
test_dedup_es_por_match_exacto() { _jq_sandbox _case_otro_sid_si_encola; }

# ── el juez NO desbloquea el gate del reviewer ──────────────────────
_case_juez_no_escribe_marker_de_reviewer() {
  printf '%s' '{"agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: x"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -f ".agents/state/markers/reviewer_run.txt" ] && { echo "    el JUEZ escribió el marker canónico del reviewer"; return 1; }
  return 0
}
test_el_juez_no_desbloquea_commits() { _jq_sandbox _case_juez_no_escribe_marker_de_reviewer; }
