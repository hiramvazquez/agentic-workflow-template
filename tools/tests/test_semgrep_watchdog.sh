#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Lo que el watchdog de semgrep DEJA DETRÁS
# ════════════════════════════════════════════════════════════════════
# Hermano de `test_fail_closed.sh`: aquél fija lo que el gate REPORTA cuando el
# scan se cuelga (exit 3, y diciendo timeout); éste fija lo que el gate no debe
# dejar por el camino. Se separan porque son dos disciplinas distintas —
# evidencia y recursos— y porque el fichero de fail-closed cruzaba las 400
# líneas de §4 al meter estos dos casos.
#
# Los dos casos existen porque sus mutantes SOBREVIVÍAN: quitar el `>/dev/null`
# del guardián o quitar el `pkill` de su hijo no mataba ningún test. Son las dos
# lecciones que `tools/tests/run-tests.sh` ya había pagado con su propio
# watchdog, y copiar el patrón sin copiar sus tests las dejaba listas para
# volver.

_sw_sandbox() { # <función> — repo de juguete con un semgrep de mentira dentro
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/bin"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  cat > "$d/bin/semgrep" <<'FAKE'
#!/usr/bin/env bash
echo '{"results":[],"errors":[]}'
FAKE
  chmod +x "$d/bin/semgrep"
  echo "rules: []" > "$d/tools/semgrep/rules/dummy.yaml"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; PATH="$d/bin:$PATH" "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── El guardián no puede retener el pipe del llamador ───────────────
# `check-drift.sh` lee este gate con `< <(bash tools/semgrep-scan.sh)`. Si el
# guardián hereda ese pipe, el llamador espera a que lo cierre — o sea, el
# TIMEOUT ENTERO en cada corrida, incluso cuando el scan termina en un segundo.
# El mecanismo que existe para evitar cuelgues colgaría a quien lo usa. Le pasó
# igual a `run-tests.sh` en su primer intento.
_case_el_guardian_no_retiene_el_pipe() {
  local t0 t1
  t0=$(date +%s)
  while IFS= read -r _l; do :; done < <(SEMGREP_TIMEOUT_SECS=8 bash tools/semgrep-scan.sh 2>/dev/null)
  t1=$(date +%s)
  [ "$((t1-t0))" -lt 5 ] || {
    echo "    leer el gate por sustitución tardó $((t1-t0))s con un scan instantáneo"
    echo "    y timeout=8: el guardián está reteniendo el pipe del llamador."
    return 1; }
}
test_el_guardian_no_retiene_el_pipe_del_llamador() {
  _sw_sandbox _case_el_guardian_no_retiene_el_pipe
}

# ── Y no deja su `sleep` huérfano ───────────────────────────────────
# `kill "$wd"` mata la SUBSHELL del guardián, no a su hijo `sleep`. Sin matar
# antes al hijo, cada scan deja uno vivo hasta que agote su plazo. En una
# máquina de desarrollo es basura; en un runner de 3 cores son slots de proceso
# ocupados — la presión bajo la que nació `f-wf01`, o sea que este descuido
# alimenta el peor flaky que tiene el repo.
#
# `pgrep -f` mira el process table ENTERO, así que un plazo constante convierte
# este test en flaky en cuanto haya dos corridas a la vez — y este repo tiene
# worktrees de review concurrentes por diseño. Reproducido por la review: con
# dos invocaciones simultáneas, una ve el guardián LEGÍTIMO de la otra (falso
# positivo) y la otra se queda sin el suyo porque el `pkill` ajena se lo llevó
# (falso negativo). El plazo se deriva del PID, que es lo que hace el token
# único de `test_detector_runs.sh` por la misma razón.
#
# Contar los `sleep` del sistema tampoco valdría: haría el veredicto dependiente
# de lo que corra la máquina. Y meter un test flaky en el repo cuyo peor finding
# es la flakiness sería una broma cara — la primera versión de este test la hizo.
_case_no_deja_sleeps_huerfanos() {
  local plazo=$((90000 + $$)) vivo=0
  SEMGREP_TIMEOUT_SECS="$plazo" bash tools/semgrep-scan.sh >/dev/null 2>&1
  pgrep -f "sleep $plazo" >/dev/null 2>&1 && vivo=1
  pkill -f "sleep $plazo" >/dev/null 2>&1   # limpiar SIEMPRE, incluso al fallar
  [ "$vivo" = "0" ] || {
    echo "    el scan termino pero su 'sleep $plazo' sigue vivo: guardián huérfano."
    echo "    Uno por scan, y en un runner pequeño eso es presión de procesos (f-wf01)."
    return 1; }
}
test_el_guardian_no_deja_sleeps_huerfanos() {
  _sw_sandbox _case_no_deja_sleeps_huerfanos
}

# ── Un plazo mal escrito no puede inculpar al scan ──────────────────
# `sleep abc` falla al instante, el guardián pasa directo a su `kill -9`, y el
# scan real muere sin oportunidad — reportado como TIMEOUT. Falla del lado
# seguro (exit 3, nunca "limpio"), pero la razón sería FALSA, y eso es lo que
# §14.3 prohíbe: el hueco se declara con su razón y esa razón tiene que ser
# verdadera. Lo cazó la review del propio watchdog, con este repro.
_case_plazo_no_numerico_no_inculpa_al_scan() {
  cat > bin/semgrep <<'FAKE'
#!/usr/bin/env bash
sleep 1
echo '{"results":[],"errors":[]}'
FAKE
  chmod +x bin/semgrep
  local out rc
  out="$(SEMGREP_TIMEOUT_SECS=abc bash tools/semgrep-scan.sh 2>&1)"; rc=$?
  # Se busca la FRASE del error, no la palabra "timeout": el propio aviso de
  # config la contiene dentro de `SEMGREP_TIMEOUT_SECS`, y la primera version
  # de este test se acusaba a si misma por eso.
  printf '%s' "$out" | grep -q "no pudo mirar" && {
    echo "    un plazo no numérico se reportó como cuelgue del scan:"
    printf '%s' "$out" | grep "no pudo mirar" | sed 's/^/      /' | head -2
    echo "    El scan nunca se colgó — la razón del hueco es falsa (§14.3)."
    return 1; }
  [ "$rc" = "0" ] || {
    echo "    con plazo no numérico y un scan sano, exit fue $rc (esperaba 0)"; return 1; }
}
test_un_plazo_no_numerico_no_inculpa_al_scan() {
  _sw_sandbox _case_plazo_no_numerico_no_inculpa_al_scan
}
