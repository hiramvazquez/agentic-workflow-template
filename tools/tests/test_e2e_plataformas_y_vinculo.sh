#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_plataformas_y_vinculo.sh — GOLDEN 10 + el vínculo con el PRD
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre dos cosas que no encajaban en ninguna otra familia: (a) que la
# matriz de CI declare de verdad las dos plataformas y que el smoke contra
# ESTA máquina no pueda mentir sobre su propio estado (G10); y (b) el
# VÍNCULO mecánico entre el PRD 0004 §9 y los `test_golden_NN_` que lo
# demuestran — sin él, un escenario 11 sin test se leería como Definition
# of Done cumplida. Las hermanas de esta matriz — capacidades declaradas,
# orquestador del backlog, ledger/lecciones, gates del Anillo 3 — viven en
# los otros `test_e2e_*.sh`.
#
# A diferencia de las otras familias, NINGUNO de los dos tests de aquí usa
# el sandbox `_e2e_repo`: G10 corre contra ESTE repo y el smoke es real por
# diseño (§ arriba), y el vínculo lee el PRD y los propios `test_e2e_*.sh`
# del árbol de trabajo — sandboxearlos sería probar una copia, no la matriz.

# ════════════════════════════════════════════════════════════════════
# GOLDEN 10 — dos plataformas, y un smoke real que no puede mentir
# ════════════════════════════════════════════════════════════════════
# Las dos mitades del escenario: (a) la promesa de macOS+Linux es una matriz
# real en el workflow, no una frase en un doc; (b) el smoke contra el entorno
# de ESTA máquina no exige un estado concreto —puede faltar semgrep, puede
# estar roto— pero sí que estado y exit code sean el mismo hecho. Un verde
# solo puede salir de un probe que corrió y detectó su fixture.
test_golden_10_dos_plataformas_y_smoke_sin_falso_verde() {
  local wf="$PROJECT_ROOT/.github/workflows/harness-ci.yml"
  [ -f "$wf" ] || { echo "    no hay workflow que ejecute la suite"; return 1; }
  local matriz
  matriz="$(awk '/^ *os: \[/{print; exit}' "$wf")"
  case "$matriz" in
    *ubuntu*macos*|*macos*ubuntu*) : ;;
    *) echo "    la matriz de OS no cubre Linux y macOS: ${matriz:-ausente}"; return 1 ;;
  esac
  grep -q 'bash tools/tests/run-tests.sh' "$wf" \
    || { echo "    la matriz de OS no ejecuta la suite del harness"; return 1; }

  local probe rc estado
  probe="$(PROBE_TIMEOUT_SECS=20 bash "$PROJECT_ROOT/tools/probe-capability.sh" semgrep 2>/dev/null)"
  rc=$?
  estado="$(printf '%s' "$probe" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null \
    || echo unknown)"
  case "$estado:$rc" in
    operational:0|missing:1|broken:1|unknown:3) : ;;
    *)
      echo "    el smoke real emparejó mal estado y exit ($estado:$rc): un falso verde es posible"
      return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
# EL VÍNCULO — la matriz no puede quedarse atrás del PRD
# ════════════════════════════════════════════════════════════════════
# Sin esto, añadir un escenario golden 11 dejaría la "Definition of Done" en
# verde sin cubrirlo: la lista y su demostración divergen en silencio, que es
# el modo de fallo que este PRD persigue. La fuente es el PRD; el test solo
# comprueba que exista un `test_golden_NN_` por escenario declarado.
#
# ⚠️ La matriz vive dividida en varios `tools/tests/test_e2e_*.sh` (fase 2a
# del PRD 0005 — cada archivo por debajo del hard limit, AGENTS.md §4). El
# vínculo busca en TODOS los que casen ese glob, no en un nombre de archivo
# fijo: un vínculo que solo mirara `test_e2e_matrix.sh` habría quedado
# pasando en falso —0 tests golden encontrados, o peor, el test ni se habría
# corrido— en el momento mismo en que la propia división lo movió.
test_matriz_e2e_cubre_los_diez_escenarios_golden() {
  local prd="$PROJECT_ROOT/docs/process/prds/0004-reconciliar-workflow-agentico.md"
  local archivos=("$PROJECT_ROOT"/tools/tests/test_e2e_*.sh)
  [ -f "$prd" ] || { echo "    falta el PRD 0004: la matriz no tiene contra qué cuadrar"; return 1; }
  local total
  total="$(awk '/^## 9\. Escenarios golden/{s=1;next} /^## 10\./{s=0} s && /^[0-9]+\./{n++} END{print n+0}' "$prd")"
  [ "${total:-0}" -gt 0 ] \
    || { echo "    no pude leer los escenarios golden del PRD (¿cambió el encabezado §9?)"; return 1; }

  local i=1 n faltan=""
  while [ "$i" -le "$total" ]; do
    n="$(printf '%02d' "$i")"
    grep -q "^test_golden_${n}_" "${archivos[@]}" || faltan="$faltan $n"
    i=$((i + 1))
  done
  [ -z "$faltan" ] || { echo "    escenarios golden del PRD sin test E2E:$faltan"; return 1; }

  local tiene nfiles
  tiene="$(grep -h '^test_golden_[0-9][0-9]_' "${archivos[@]}" | wc -l | tr -d ' ')"
  nfiles="${#archivos[@]}"
  [ "$tiene" = "$total" ] \
    || { echo "    la matriz declara $tiene tests golden repartidos en $nfiles archivos y el PRD $total escenarios"; return 1; }
}
