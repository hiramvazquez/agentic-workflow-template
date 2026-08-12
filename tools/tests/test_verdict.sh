#!/usr/bin/env bash
# Invariante nº1 del harness: EL VEREDICTO NO LO EMITE EL MODELO.
# El marker de review se deriva del mensaje final REAL del sub-agente.
# Si estos tests se relajan, el reviewer-gate vuelve a ser decorativo.
# shellcheck disable=SC1091
. "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh"

MSG_GREEN='Revisé el diff.

VERDICT: GREEN
FINDINGS: 0
SCOPE: gates de anillo 2'

MSG_AMBER='Hay cosas menores.
VERDICT: AMBER
FINDINGS: 3
SCOPE: refactor de io.sh'

MSG_RED='Esto no puede entrar.
VERDICT: RED
FINDINGS: 2
SCOPE: secretos en logs'

# ── happy path ──────────────────────────────────────────────────────
test_verdict_green() {
  assert_eq "GREEN" "$(verdict_parse "$MSG_GREEN")"
}

test_verdict_scope_extraido() {
  assert_eq "gates de anillo 2" "$(verdict_scope "$MSG_GREEN")"
}

test_verdict_findings_extraido() {
  assert_eq "3" "$(verdict_findings "$MSG_AMBER")"
}

# ── ramas de error / borde ──────────────────────────────────────────
test_verdict_amber_es_aceptable() {
  # AMBER permite commit (con findings atendidos); GREEN y AMBER son los únicos que marcan.
  assert_exit 0 verdict_is_markable "AMBER" || return 1
  assert_exit 0 verdict_is_markable "GREEN"
}

test_verdict_red_no_marca() {
  # RED NUNCA produce marker. Es la rama que impide que un review negativo se ignore.
  assert_exit 1 verdict_is_markable "RED"
}

test_verdict_ausente_no_marca() {
  # Sub-agente que muere o divaga sin emitir el contrato → NO hay marker.
  # Ausencia de evidencia no es evidencia de ausencia.
  assert_eq "" "$(verdict_parse 'terminé, todo bien, se ve correcto')" || return 1
  assert_exit 1 verdict_is_markable ""
}

test_verdict_texto_suelto_no_cuenta() {
  # Que el agente MENCIONE la palabra no basta: exige el contrato en su propia línea.
  assert_eq "" "$(verdict_parse 'yo diría que el verdict green estaría bien')"
}

test_verdict_ultima_linea_gana() {
  # Si el agente se autocorrige, vale el ÚLTIMO veredicto emitido, no el primero.
  local m='VERDICT: GREEN
me equivoqué, revisando de nuevo:
VERDICT: RED'
  assert_eq "RED" "$(verdict_parse "$m")"
}

test_verdict_valor_invalido_se_rechaza() {
  # Un valor fuera del enum no se interpreta como aprobación.
  assert_eq "" "$(verdict_parse 'VERDICT: PROBABLEMENTE_OK')" || return 1
  assert_exit 1 verdict_is_markable "PROBABLEMENTE_OK"
}

test_verdict_tolera_minusculas_y_espacios() {
  assert_eq "GREEN" "$(verdict_parse '   verdict:   green   ')"
}

# ════════════════════════════════════════════════════════════════════
# MODO CONTRATO — el review que ocurre ANTES de que exista el código
# ════════════════════════════════════════════════════════════════════
# Invierte el orden (patrón de harness-design de Anthropic): el evaluador
# acuerda qué es "hecho" antes de que se escriba nada, y la review final deja
# de ser exploratoria. El riesgo del mecanismo es UNO y es grave: si el
# contrato pudiera escribir marker, pedirlo desbloquearía el commit del
# código que aún no existe — el agujero exacto que el invariante nº1 tapa.
test_contrato_ready_se_reconoce() {
  local out; out="$(contract_parse 'Riesgos: capas, TDD.

CONTRACT: READY
SCOPE: historia 0005')"
  [ "$out" = "READY" ] || { echo "    CONTRACT: READY no se reconoció (obtuve '$out')"; return 1; }
}

test_contrato_no_es_veredicto() {
  # LO MÁS IMPORTANTE DE ESTE ARCHIVO: un contrato NO puede producir marker.
  local v; v="$(verdict_parse 'CONTRACT: READY
SCOPE: historia 0005')"
  [ -z "$v" ] || { echo "    un CONTRACT produjo veredicto '$v' — escribiría marker sin código"; return 1; }
  verdict_is_markable "$v" && { echo "    un contrato vacío resultó markable"; return 1; }
  return 0
}

test_veredicto_no_es_contrato() {
  # Y la simétrica: una review normal no debe leerse como contrato, o el
  # cierre saldría por la rama equivocada y no escribiría el marker legítimo.
  local c; c="$(contract_parse 'VERDICT: GREEN
FINDINGS: 0
SCOPE: x')"
  [ -z "$c" ] || { echo "    un VERDICT se leyó como contrato ('$c')"; return 1; }
}

test_contrato_mencionado_en_prosa_no_cuenta() {
  # Mismo rigor que el veredicto: solo la línea al inicio, nunca la prosa.
  local out; out="$(contract_parse 'te dejo el contract: ready cuando quieras')"
  [ -z "$out" ] || { echo "    una mención en prosa se leyó como contrato ('$out')"; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# f-review-red-sin-huella — un RED tiene que dejar rastro
# ════════════════════════════════════════════════════════════════════
# Medido en un proyecto real: 36 RED, 9 AMBER y CERO GREEN en todo el
# historial, con secuencias RED→RED→GREEN sobre archivos cuyo mtime era
# ANTERIOR al primer RED — ni un byte cambió entre veredictos. La lectura
# benigna era la correcta ahí (los RED pedían registrar gaps en el ledger),
# y ese es justo el problema: el harness no podía distinguirla de un
# verdict-shopping. Con el sha del diff guardado también en RED, la diferencia
# pasa a ser mecánica.
_crv_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/.gitignore" "$d/.gitignore" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    echo 'let x = 1' > app.swift; git add app.swift
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_crv() { # _crv <mensaje final del sub-agente>
  printf '{"agent_type":"reviewer","last_assistant_message":%s}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
}

_case_red_deja_huella() {
  _crv 'Hay problemas.
VERDICT: RED
FINDINGS: 3
SCOPE: el adapter'
  [ -f .agents/state/markers/last_red.txt ] \
    || { echo "    un RED no dejó huella del diff que juzgó"; return 1; }
  grep -q '^staged_sha: [0-9a-f]' .agents/state/markers/last_red.txt \
    || { echo "    la huella del RED no lleva el sha del diff"; return 1; }
  [ -f .agents/state/review-history.jsonl ] \
    || { echo "    el RED no entró en el historial de veredictos"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    un RED escribió marker (desbloquearía el commit)"; return 1; }
  return 0
}
test_un_red_deja_huella_del_diff_juzgado() { _crv_sandbox _case_red_deja_huella; }

_case_green_sobre_el_mismo_diff_se_rechaza() {
  _crv 'VERDICT: RED
FINDINGS: 2
SCOPE: el adapter'
  _crv 'Ya está.
VERDICT: GREEN
FINDINGS: 0
SCOPE: el adapter'
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    un GREEN sobre EL MISMO diff que fue RED escribió marker (verdict-shopping)"; return 1; }
  grep -q 'RECHAZADO' .agents/state/review-history.jsonl 2>/dev/null \
    || { echo "    el rechazo no quedó registrado en el historial"; return 1; }
  return 0
}
test_green_sobre_el_mismo_diff_que_el_red_no_marca() {
  _crv_sandbox _case_green_sobre_el_mismo_diff_se_rechaza
}

_case_green_tras_arreglar_si_marca() {
  # EL GUARD QUE IMPORTA: una remediación de verdad tiene que pasar. Si esto
  # fallara habríamos cambiado un agujero por un deadlock — el reviewer no
  # podría aprobar nunca nada que hubiera sido RED alguna vez.
  _crv 'VERDICT: RED
FINDINGS: 2
SCOPE: el adapter'
  echo 'let x = 2 // arreglado' > app.swift; git add app.swift
  _crv 'Arreglado.
VERDICT: GREEN
FINDINGS: 0
SCOPE: el adapter'
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    una remediación REAL (diff distinto) no consiguió marker: deadlock"; return 1; }
}
test_green_tras_cambiar_el_codigo_si_marca() { _crv_sandbox _case_green_tras_arreglar_si_marca; }

_case_override_auditado() {
  # Para el RED que se resuelve con un argumento y no con código. Mismo patrón
  # que REVIEWER_OVERRIDE: existe, pero deja rastro.
  _crv 'VERDICT: RED
FINDINGS: 1
SCOPE: el adapter'
  printf '{"agent_type":"reviewer","last_assistant_message":"VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: el adapter"}' \
    | REVIEW_SAME_DIFF_OVERRIDE=1 REVIEW_SAME_DIFF_REASON="el RED era un malentendido" \
      bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    el override no permitió marcar"; return 1; }
  grep -q 'same-diff-override' .agents/state/markers/override_log.txt 2>/dev/null \
    || { echo "    el override NO quedó auditado"; return 1; }
}
test_el_override_de_mismo_diff_queda_auditado() { _crv_sandbox _case_override_auditado; }
