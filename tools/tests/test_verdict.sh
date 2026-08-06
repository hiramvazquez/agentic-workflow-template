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
