#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El REGISTRO DE EJECUCIÓN de un detector (`ran`, `targets`, `exit`)
# ════════════════════════════════════════════════════════════════════
# La telemetría del harness solo guardaba DETECCIONES, y solo de los hooks:
# de las 507 líneas de detections.jsonl, ni una la escribió un detector. Con
# eso, tres estados distintos producen el mismo cero y no hay forma de
# separarlos con datos:
#
#   (a) DISUASIÓN   — el detector corrió, miró objetivos reales, no halló nada.
#   (b) SIN OBJETIVOS — corrió pero no tenía qué mirar (el caso f-6b761f06:
#       `LAYERS_SUMMARY errors=0` desde una raíz sin fuentes, que además
#       alimenta un trinquete que solo baja).
#   (c) NO CORRIÓ   — nadie lo invocó.
#
# `gate-value.sh` ya declara honestamente que no puede separar (a) de las
# otras y remite al selftest. Pero el selftest responde "¿ve en un sandbox?",
# no "¿corrió sobre trabajo real y contra cuántos objetivos?". Eso solo lo
# sabe el detector, así que el registro se emite DENTRO de él — un caller no
# puede conocer `targets`.
#
# Fichero SEPARADO de detections.jsonl a propósito: `metrics-report.py`
# cuenta CADA fila de ese log como detección (`gate["detections"] += n`), así
# que mezclarlos inflaría métricas que ya se consumen.

_dr_sandbox() { # <función> — repo temporal con el lib y un detector de juguete
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/lib"
  cp "$PROJECT_ROOT/tools/lib/detector-run.sh" "$d/tools/lib/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# Un detector de juguete con el mismo esqueleto que los reales: salida
# TEMPRANA cuando no encuentra su conf, salida normal si la encuentra.
_dr_detector() { # <ruta> <targets-declarados|-> <exit-final>
  cat > "$1" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. tools/lib/detector-run.sh 2>/dev/null || true
detector_run_init juguete
[ -f objetivos.conf ] || { echo "JUGUETE_SUMMARY errors=0"; exit 0; }
detector_targets $2
echo "JUGUETE_SUMMARY errors=0"
exit $3
EOF
  chmod +x "$1"
}

_dr_lineas() { wc -l < .agents/state/metrics/runs.jsonl 2>/dev/null | tr -d ' '; }
_dr_campo()  { python3 -c "
import json,sys
print(json.loads(open('.agents/state/metrics/runs.jsonl').readlines()[-1])[sys.argv[1]])
" "$1" 2>/dev/null; }

# ── 1. La salida TEMPRANA también deja registro ─────────────────────
# El punto entero. Es la ruta por la que un detector se declara limpio sin
# haber mirado nada, y la que ninguna instrumentación puesta "antes del
# último exit" cubriría.
_case_salida_temprana_registra() {
  _dr_detector det.sh 5 0
  bash det.sh >/dev/null 2>&1
  [ "$(_dr_lineas)" = "1" ] || { echo "    una salida temprana no dejó registro (líneas=$(_dr_lineas)) — el estado 'corrió sin objetivos' sigue siendo invisible"; return 1; }
  local t; t="$(_dr_campo targets)"
  [ "$t" = "None" ] || { echo "    targets=$t tras una salida temprana; debe ser null: el detector NO declaró objetivos, y 0 sería inventarse una medición"; return 1; }
}
test_una_salida_temprana_deja_registro_de_ejecucion() { _dr_sandbox _case_salida_temprana_registra; }

# ── 2. targets refleja lo que el detector declaró ───────────────────
_case_targets_declarados() {
  _dr_detector det.sh 7 0
  touch objetivos.conf
  bash det.sh >/dev/null 2>&1
  [ "$(_dr_campo targets)" = "7" ] || { echo "    targets=$(_dr_campo targets), esperaba 7"; return 1; }
}
test_targets_refleja_lo_que_declaro_el_detector() { _dr_sandbox _case_targets_declarados; }

# ── 3. El exit REAL del detector queda registrado ───────────────────
_case_exit_real() {
  _dr_detector det.sh 3 1
  touch objetivos.conf
  bash det.sh >/dev/null 2>&1
  [ "$(_dr_campo exit)" = "1" ] || { echo "    exit registrado=$(_dr_campo exit), esperaba 1"; return 1; }
}
test_el_exit_real_queda_registrado() { _dr_sandbox _case_exit_real; }

# ── 4. Instrumentar NO puede cambiar el exit code ───────────────────
# El invariante nº1: un gate instrumentado que deja de bloquear es peor que
# uno sin telemetría. Mismo espíritu que `*_no_impide_que_el_gate_bloquee`.
_case_no_altera_el_exit() {
  # El rc se captura en una variable: `[ "$?" = ... ]` funciona, pero el `$?`
  # del MENSAJE ya es el del propio `[`, así que el diagnóstico imprimía un
  # número falso. Lo cazó shellcheck (SC2319) en el hook post-edit.
  local rc
  _dr_detector det.sh 3 1
  touch objetivos.conf
  bash det.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    la instrumentación cambió el exit del detector (dio $rc, esperaba 1)"; return 1; }
  _dr_detector det0.sh 3 0
  bash det0.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    la instrumentación cambió un exit 0 (dio $rc)"; return 1; }
}
test_la_instrumentacion_no_altera_el_exit_code() { _dr_sandbox _case_no_altera_el_exit; }

# ── 5. Sin el lib, el detector sigue funcionando ────────────────────
# Un detector que se cae porque falta su telemetría convierte una mejora de
# observabilidad en un fallo de disponibilidad del gate.
_case_sin_lib() {
  rm -f tools/lib/detector-run.sh
  _dr_detector det.sh 3 1
  touch objetivos.conf
  local out; out="$(bash det.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    sin el lib el detector devolvió $rc en vez de 1"; return 1; }
  printf '%s' "$out" | grep -q 'JUGUETE_SUMMARY' || { echo "    sin el lib el detector dejó de emitir su contrato de salida"; return 1; }
}
test_sin_el_lib_el_detector_sigue_funcionando() { _dr_sandbox _case_sin_lib; }

# ── 6. Un log no escribible no rompe el detector ────────────────────
_case_log_no_escribible() {
  _dr_detector det.sh 3 1
  touch objetivos.conf
  mkdir -p .agents/state
  : > .agents/state/metrics        # un FICHERO donde va el directorio
  local rc; bash det.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    con el log no escribible el detector devolvió $rc en vez de 1"; return 1; }
}
test_un_log_no_escribible_no_rompe_el_detector() { _dr_sandbox _case_log_no_escribible; }

# ── 7. Un trap EXIT que ya existía se conserva ──────────────────────
# Dos detectores reales (check-source-sets, semgrep-scan) ya usan trap para
# limpiar temporales. Si instalar el nuestro pisara el suyo, la telemetría
# dejaría basura en /tmp en cada corrida.
_case_trap_previo_se_conserva() {
  cat > det.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; echo "LIMPIE" >> huella.txt' EXIT
. tools/lib/detector-run.sh 2>/dev/null || true
detector_run_init juguete
detector_targets 2
exit 0
EOF
  bash det.sh >/dev/null 2>&1
  grep -q LIMPIE huella.txt 2>/dev/null || { echo "    el trap EXIT que el detector ya tenía se perdió: su limpieza dejó de correr"; return 1; }
  [ "$(_dr_lineas)" = "1" ] || { echo "    con un trap previo no se registró la ejecución"; return 1; }
}
test_un_trap_exit_previo_se_conserva() { _dr_sandbox _case_trap_previo_se_conserva; }

# ── 8. TODOS los detectores reales registran su ejecución ───────────
# El guardián mecánico de la clase, no de un caso. Dos detectores
# (check-source-sets, semgrep-scan) instalaban su propio `trap ... EXIT`
# DESPUÉS del init y lo pisaban: quedaron mudos, sin un solo error visible, y
# solo se vio al comparar la lista de registros con la de detectores. Este test
# hace esa comparación en cada corrida, así que cubre también a los detectores
# que aún no existen.
#
# No se afirma nada sobre `targets` ni sobre el exit: cada detector decide qué
# mirar y este repo no tiene fuentes de app. Lo que se exige es lo único
# universal — que dejen constancia de que corrieron.
_case_todos_registran() {
  local log faltan=""
  log="$(mktemp)"
  for d in check-layers check-drift check-exec-bits check-conflict-markers \
           check-source-sets semgrep-scan secret-scan; do
    [ -f "$PROJECT_ROOT/tools/$d.sh" ] || continue
    DETECTOR_RUNS_LOG="$log" bash "$PROJECT_ROOT/tools/$d.sh" >/dev/null 2>&1
    grep -q "\"source\":\"$d\"" "$log" 2>/dev/null || faltan="$faltan $d"
  done
  rm -f "$log"
  [ -z "$faltan" ] || {
    echo "    estos detectores NO registraron su ejecución:$faltan"
    echo "    (causa típica: instalan su propio \`trap ... EXIT\` después de"
    echo "     detector_run_init y lo pisan — usa detector_run_cleanup)"
    return 1; }
}
test_todos_los_detectores_registran_su_ejecucion() { _case_todos_registran; }

# ── 9. Un detector MATADO no se registra como si hubiera salido limpio ──
# Hallazgo de la ronda 1 del review, reproducido: al morir por una señal no
# atrapada mientras esperaba un comando en primer plano, bash no actualiza `$?`
# con esa espera, así que el trap EXIT leía el 0 del último comando que sí
# terminó. El llamador veía el 143 correcto —el gating nunca estuvo roto— pero
# el registro decía "corrió limpio". Un detector abortado por timeout de CI
# quedaba indistinguible de uno verde: justo lo que este fichero separa.
#
# Se cubren las TRES señales, no solo TERM. En la ronda 2 el review encontró un
# mutante vivo justamente ahí: borrar los traps de INT y HUP dejaba los 11 tests
# en verde, porque el comentario del lib hablaba de "señales" en general y solo
# una tenía guardián. Una defensa anunciada sin mecanismo es el pecado que este
# harness persigue, aunque sea a esta escala.
#
# El detector de juguete espera con `sleep N &` + `wait`, NO con un `sleep N` en
# primer plano. Con el sleep en foreground bash DIFIERE el trap hasta que el
# comando externo termina, así que el test tardaba 30 segundos deterministas —
# el 7% de la suite entera— por cada corrida. Con el builtin `wait`, la señal se
# atiende al instante. Lo midió el review en la ronda 2; no es flakiness (esa es
# f-wf01, otra familia), era una espera real y evitable.
# El detector corre en PRIMER PLANO y la señal la manda un matador de fondo.
# No es rebuscado, es obligatorio: un script lanzado con `&` tiene SIGINT
# IGNORADO al entrar, y POSIX dice que una señal ignorada al arrancar no se
# puede atrapar ni restaurar. Medido aquí: async+INT → exit 0 (el trap ni se
# instala), primer plano+INT → 130. HUP y TERM sí funcionan de las dos formas,
# pero se prueban igual para que las tres midan lo mismo.
#
# La espera es `sleep N &` + `wait`, no un `sleep N` en primer plano: con el
# sleep en foreground bash DIFIERE el trap hasta que el comando externo termina
# y el test tardaba 30 segundos deterministas —el 7% de la suite— por corrida.
# Con el builtin `wait` la señal se atiende al instante.
_dr_mata_con() { # <señal> <exit esperado>
  local sig="$1" esperado="$2" tok script log reg
  tok="dr$$-$sig"
  script="det-$tok.sh"; log="runs-$tok.jsonl"
  cat > "$script" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. tools/lib/detector-run.sh 2>/dev/null || true
detector_run_init sigtest
sleep 20 &
wait
EOF
  # El token hace que el pkill no pueda alcanzar a otra corrida en paralelo.
  ( sleep 0.4; pkill -"$sig" -f "$script" 2>/dev/null ) &
  DETECTOR_RUNS_LOG="$log" bash "$script" >/dev/null 2>&1
  wait 2>/dev/null
  reg="$(python3 -c "
import json
print(json.loads(open('$log').readlines()[-1])['exit'])
" 2>/dev/null)"
  [ "$reg" != "0" ] || { echo "    matado con SIG$sig se registró como exit=0 — indistinguible de un detector que corrió limpio"; return 1; }
  [ "$reg" = "$esperado" ] || { echo "    SIG$sig registró exit=$reg, esperaba $esperado (128+n, la convención del shell)"; return 1; }
}

# SIGINT NO se prueba por comportamiento, y no es una omisión: `run-tests.sh`
# ejecuta cada test en SEGUNDO PLANO con un watchdog (`... & pid=$!; wait`,
# línea 65), y POSIX dice que una señal ignorada al entrar —lo que el shell hace
# con INT en todo trabajo asíncrono— no se puede atrapar ni restaurar. Medido:
# async+INT deja exit 0 aunque el trap esté escrito; en primer plano da 130.
# O sea que NINGÚN test de esta suite puede ejercitar SIGINT, por construcción.
# Fingir que sí (con un pkill que no llega a un proceso que no puede atraparla)
# sería un test que pasa sin verificar — justo lo que §5 prohíbe. Se cubre por
# ESTRUCTURA en el caso de abajo, que es más débil pero honesto y sí mata el
# mutante de borrar la línea.
_case_senal_no_se_registra_como_limpio() {
  _dr_mata_con TERM 143 || return 1
  _dr_mata_con HUP  129 || return 1
}
test_un_detector_matado_por_senal_no_se_registra_como_limpio() {
  _dr_sandbox _case_senal_no_se_registra_como_limpio
}

# ── 10. La limpieza REGISTRADA se ejecuta de verdad ─────────────────
# `detector_run_cleanup` es el mecanismo que se introdujo para que un detector
# con temporales no tuviera que instalar su propio `trap ... EXIT` —que pisaba
# el del registro—. La ronda 1 del review probó que un no-op en su lugar dejaba
# los 8 tests en verde: el arreglo no tenía guardián. Con este, un
# `detector_run_cleanup(){ :; }` deja el temporal en disco y el test muere.
_case_la_limpieza_registrada_corre() {
  cat > det.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. tools/lib/detector-run.sh 2>/dev/null || true
detector_run_init juguete
TMP="basura.tmp"; : > "$TMP"
detector_run_cleanup 'rm -f "$TMP"'
detector_targets 1
exit 0
EOF
  bash det.sh >/dev/null 2>&1
  [ ! -f basura.tmp ] || { echo "    la limpieza registrada NO corrió: el temporal sigue en disco (los detectores con mktemp filtrarían en cada corrida)"; return 1; }
  [ "$(_dr_lineas)" = "1" ] || { echo "    con una limpieza registrada no se registró la ejecución"; return 1; }
}
test_la_limpieza_registrada_se_ejecuta() { _dr_sandbox _case_la_limpieza_registrada_corre; }

# ── 11. El registro lleva el ESQUEMA completo, no solo targets/exit ──
# Segundo mutante superviviente de la ronda 1: cambiar el commit por una
# constante dejaba los 8 tests verdes. `commit` es lo que permitirá atribuir una
# medición a un estado del árbol, y `duration_s` es el coste que paso 2 tiene
# que poder sumar. Un campo sin aserción es un campo que se puede romper.
_case_esquema_completo() {
  _dr_detector det.sh 2 0
  touch objetivos.conf
  bash det.sh >/dev/null 2>&1
  local commit real
  commit="$(_dr_campo commit)"
  # El sandbox no tiene commits, así que lo esperado aquí es "unknown" — y esa
  # es justo la rama donde vivía el bug del "HEADunknown".
  if ! real="$(git rev-parse HEAD 2>/dev/null)" || [ -z "$real" ]; then real="unknown"; fi
  [ "$commit" = "$real" ] || { echo "    commit registrado='$commit', el real es '$real'"; return 1; }
  case "$(_dr_campo duration_s)" in
    ''|*[!0-9]*) echo "    duration_s no es un entero: '$(_dr_campo duration_s)'"; return 1 ;;
  esac
  [ "$(_dr_campo kind)" = "run" ] || { echo "    kind='$(_dr_campo kind)', esperaba 'run' — es lo que separa estas filas de las de detecciones"; return 1; }
}
test_el_registro_lleva_el_esquema_completo() { _dr_sandbox _case_esquema_completo; }

# ── 12. Las señales quedan atrapadas — y lo que NO se puede afirmar ──
# Existe porque en la ronda 2 el review encontró un mutante vivo: borrar los
# traps de INT y HUP dejaba los 11 tests en verde, ya que solo TERM tenía
# guardián.
#
# Al escribirlo salió un hecho que conviene dejar por escrito, porque es
# contraintuitivo y ya costó dos intentos: **SIGINT no es observable desde esta
# suite, ni por comportamiento ni por estructura.** `run-tests.sh` corre cada
# test en SEGUNDO PLANO con un watchdog (`... & pid=$!; wait`, línea 65); el
# shell pone INT en SIG_IGN para todo trabajo asíncrono; y POSIX dice que una
# señal ignorada al entrar no se puede atrapar ni restaurar. Consecuencia
# medida: dentro del runner, `trap -p` ni siquiera LISTA el trap de INT — no es
# que no dispare, es que no se instala. En primer plano sí (exit 130 medido).
#
# Así que INT se cubre a nivel de FUENTE. Es la aserción más débil de este
# archivo y se declara como tal: no prueba que funcione, prueba que la línea
# sigue ahí, que es exactamente el mutante que hubo que matar. Inventar un test
# de comportamiento que "pasa" en un entorno donde la señal no puede llegar
# sería un test que aprueba sin verificar — lo que §5 prohíbe.
_case_las_senales_atrapadas() {
  cat > det.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. tools/lib/detector-run.sh 2>/dev/null || true
detector_run_init juguete
trap -p TERM HUP
exit 0
EOF
  local out falta=""
  out="$(bash det.sh 2>/dev/null)"
  for sig in TERM HUP; do
    printf '%s' "$out" | grep -q "SIG$sig" || falta="$falta $sig"
  done
  [ -z "$falta" ] || {
    echo "    detector_run_init no instaló trap para:$falta"
    echo "    (un detector matado con esa señal se registraría como si hubiera salido limpio)"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1; }
  # INT, a nivel de fuente. Ver el bloque de arriba para por qué no puede ser
  # más fuerte desde aquí.
  grep -q "trap 'exit 130' INT" "$PROJECT_ROOT/tools/lib/detector-run.sh" || {
    echo "    detector_run_init ya no atrapa INT (Ctrl-C sobre un detector en primer plano)"
    echo "    Esta comprobación es de FUENTE a propósito: el runner corre los tests en"
    echo "    segundo plano, donde INT es SIG_IGN y ni siquiera se puede instalar el trap."
    return 1; }
}
test_las_senales_quedan_atrapadas() { _dr_sandbox _case_las_senales_atrapadas; }
