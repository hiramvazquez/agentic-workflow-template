#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# run-tests.sh — runner de los tests de shell del HARNESS
# ════════════════════════════════════════════════════════════════════
# Los gates son código. Código con lógica de decisión sin test es deuda
# (AGENTS.md §5). Estos tests fijan los INVARIANTES del harness, no del
# producto: si alguien rompe "el ratchet solo baja" o "lite no relaja el
# ratchet", esto falla.
#
#   bash tools/tests/run-tests.sh            # todos
#   bash tools/tests/run-tests.sh verdict    # solo los que matcheen "verdict"
#
# Contrato de un archivo de test: `tools/tests/test_*.sh` que define
# funciones `test_*`. El runner las descubre y las corre en un subshell
# con un repo git temporal como cwd cuando pide aislamiento.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
cd "$PROJECT_ROOT"

# ── El entorno del ANFITRIÓN no entra: los tests son herméticos ──────
# Un test cuyo veredicto depende de una variable que él no puso mide otra cosa
# — y lo hace en silencio, dando un rojo que acusa al harness de un fallo del
# entorno. Pasó dos veces con la misma forma: un workflow de CI que pone
# GATES_SKIP_TESTS=1 en el step (legítimo: en Ubuntu no hay Xcode para el build
# de una app iOS) tumbaba `golden_09`, y un `export REVIEWER_OVERRIDE=1` en la
# shell de un dev tumba 12 de los 26 tests de `test_scope_kind.sh` — los que
# comprueban que el gate SIGUE exigiendo review.
#
# Se sanea UNA vez, aquí, en vez de exigir que cada archivo de test recuerde
# blindarse: la lista es corta, cerrada y está en el sitio por el que pasan
# todos. Los tests que necesitan una de estas variables la ponen ELLOS en la
# invocación (que es lo correcto y sigue funcionando: un `VAR=x cmd` gana).
unset GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
      GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
      AI_REVIEW_REQUIRED AI_REVIEW_OUT \
      REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
      VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
      MUTATION_SCORE_OVERRIDE 2>/dev/null || true

# ── Las variables del PARALELO se leen y se DESEXPORTAN ─────────────
# Misma razon que el bloque de arriba, y cazada en vivo: `RUN_TESTS_WORKER=1`
# viaja en el entorno del worker, asi que CUALQUIER test que invoque a
# run-tests.sh dentro de su sandbox heredaba el modo worker — el hijo emitia su
# trailer y se saltaba el resumen, y el test media otra cosa sin decirlo. Se
# capturan en variables internas (que este script no exporta) y se desexportan
# antes de correr nada. Leer PRIMERO y desexportar DESPUES: al reves se perderia
# el `VAR=x bash run-tests.sh` con el que el dispatcher invoca a sus workers.
_RT_IS_WORKER="${RUN_TESTS_WORKER:-0}"
_RT_ONLY_FILE="${RUN_TESTS_ONLY_FILE:-}"
_RT_JOBS_ENV="${TESTS_JOBS:-auto}"
unset RUN_TESTS_WORKER RUN_TESTS_ONLY_FILE TESTS_JOBS 2>/dev/null || true

FILTER="${1:-}"
PASS=0; FAIL=0; FAILED_NAMES=()

# ── Watchdog por test (sin depender de `timeout`, que macOS no trae) ──
# Un test que se CUELGA no falla: bloquea la suite y, en CI, el job entero
# hasta el límite del runner. Es peor que un rojo — un rojo te dice qué pasa
# en segundos; un cuelgue no dice nada durante una hora. Cazado en vivo: un
# mutante del guard de reentrada de un ViewModel produjo un deadlock y colgó
# la suite en vez de fallarla.
#
# Se implementa con un perro guardián en segundo plano en vez de con
# `timeout`: el test es una FUNCIÓN de shell, y `timeout` solo sabe ejecutar
# binarios — envolverla en `bash -c` la dejaría fuera de alcance. Además así
# no hay dependencia externa que pueda faltar.
TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-120}"
_run_test() { # _run_test <nombre-de-función> → imprime salida, devuelve rc (124 = colgado)
  local fn="$1" tmp pid wd rc
  tmp="$(mktemp)"
  # Ambos hijos van con stdout/stderr DESATADOS del pipe del llamador. Sin
  # esto, `out="$( _run_test … )"` esperaría a que el perro guardián cerrara
  # el pipe — o sea, los 120s completos en CADA test. El primer intento colgó
  # la suite entera justo con el mecanismo que existe para evitar cuelgues.
  ( "$fn" >"$tmp" 2>&1 ) >/dev/null 2>&1 & pid=$!
  ( sleep "$TEST_TIMEOUT_SECS"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 & wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  # ⚠️ `kill "$wd"` mata la SUBSHELL del perro guardián, no a su hijo `sleep`:
  # cada test filtraba un `sleep 120` huérfano (medido: 23 tras 23 tests). En
  # una máquina de desarrollo es basura; en un runner macOS de 3 cores son
  # cientos de slots de proceso ocupados — la presión bajo la que nació el
  # flaky de WF-01. Se mata primero a los HIJOS del guardián y luego a él.
  pkill -P "$wd" -x sleep 2>/dev/null   # -x sleep: si el pid de wd se reciclo, no matamos a un inocente
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  if [ "$rc" -ge 128 ]; then
    printf '    ⏱  el test se COLGÓ (>%ss) — no falló, se quedó esperando.\n' "$TEST_TIMEOUT_SECS"
    printf '    Un cuelgue en CI consume el job entero sin decir nada. Busca\n'
    printf '    deadlocks, esperas sin timeout, o algo que pida stdin.\n'
    rm -f "$tmp"; return 124
  fi
  cat "$tmp"; rm -f "$tmp"; return "$rc"
}

# ── Stub de scripts en el sandbox ───────────────────────────────────
# `printf ... > tools/x.sh` sobre un archivo COPIADO hereda su modo y sus
# flags. Eso hizo que la suite fuera verde en Linux y roja en macOS con
# "Permission denied" AL ESCRIBIR el stub: los archivos habían llegado al
# repo por un canal que los dejó en modo 700, y el sandbox los arrastró.
#
# Un test cuyo resultado depende de los PERMISOS del archivo que sobrescribe
# no está probando lo que cree — y falla de forma intermitente entre máquinas,
# que es la peor clase de test. `stub` elimina primero y crea limpio.
#
#   stub <ruta> <contenido-del-script>
stub() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")" 2>/dev/null
  rm -f "$path"
  # %b (no %s): el contenido llega con \n literales, igual que en los
  # `printf '...\n...'` que este helper sustituye. Con %s los stubs saldrían
  # en una sola línea y "funcionarían" de formas absurdas.
  printf '%b' "$*" > "$path"
  chmod +x "$path" 2>/dev/null
}
export -f stub 2>/dev/null || true

# ── Aserciones disponibles para los tests ───────────────────────────
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  echo "    esperado: [$1]"; echo "    obtenido: [$2]"; return 1
}
assert_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  echo "    esperaba encontrar: [$2]"; echo "    en: [$1]"; return 1
}
assert_exit() { # assert_exit <esperado> <comando...>
  local want="$1"; shift
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then return 0; fi
  echo "    exit esperado: $want · obtenido: $got · cmd: $*"; return 1
}

# Un detector que sale 3 NO es un falso positivo: es "no pude mirar" (§14.3),
# el fail-closed que se dispara cuando le falta su herramienta. Confundir los
# dos costó veinte minutos de diagnóstico el día que el Anillo 3 revivió y la
# suite corría sin semgrep: 10 tests gritaban "FALSO POSITIVO" sobre un exit 3.
# La distinción vive AQUÍ, en un solo sitio, y no copiada en cada aserción —
# que es exactamente como se quedó a medias la primera vez que se arregló.
assert_detector_limpio() { # assert_detector_limpio <rc> <salida> <mensaje-si-es-falso-positivo>
  local rc="$1" out="$2" msg="$3"
  [ "$rc" = "0" ] && return 0
  if [ "$rc" = "3" ]; then
    echo "    el detector NO PUDO MIRAR (exit 3): le falta su herramienta en este entorno."
    echo "    No es un falso positivo — es el fail-closed de §14.3. Este test"
    echo "    comprueba SEMÁNTICA y necesita el motor primario instalado."
  else
    echo "    FALSO POSITIVO: $msg (exit $rc)"
  fi
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

# Crea un repo git desechable y ejecuta el cuerpo dentro. Se limpia siempre.
with_temp_repo() { # with_temp_repo <función>
  local d; d="$(mktemp -d)"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo init > .keep; git add .keep; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?
  rm -rf "$d"
  return $rc
}
export -f assert_eq assert_contains assert_exit assert_detector_limpio with_temp_repo

# ════════════════════════════════════════════════════════════════════
# PARALELO POR ARCHIVO
# ════════════════════════════════════════════════════════════════════
# La suite corre entera en `verify-run` (antes de cada commit) y en el
# pre-push: medido el 2026-09-02, 786 tests en ~7 minutos, dos veces por
# cambio. Es el coste dominante del bucle.
#
# La unidad es el ARCHIVO, no el test: los tests de un archivo comparten los
# helpers que ese archivo define, y 60 de los 66 ya montan su propio sandbox
# con `mktemp -d`, así que el paralelismo por archivo no cambia lo que cada
# test ve.
#
# El dispatcher REINVOCA a este mismo script en modo worker en vez de duplicar
# la maquinaria. Así el saneado del entorno, el watchdog por test y el formato
# de salida son literalmente el mismo código en los dos caminos — una regla
# implementada dos veces diverge, y aquí divergir significa que el paralelo
# cuente distinto que el secuencial.
#
# ⚠️ EL INVARIANTE QUE MÁS IMPORTA: **un worker que no deja resultado cuenta
# como FALLO.** Este script decide el marker de `verify-run`; si un archivo que
# revienta, se cuelga o muere por señal pudiera desaparecer del recuento, una
# suite ROJA se firmaría como verde. Por eso el trailer es obligatorio y su
# ausencia es un rojo con nombre y apellido, no un hueco silencioso.
# Lo fija test_runner_paralelo.sh::test_un_worker_sin_resultado_cuenta_como_fallo.
#
# Efecto secundario que resulto valioso: correr cada fichero en su PROPIO
# proceso convierte al runner en detector de ACOPLAMIENTOS OCULTOS entre
# ficheros de test. El camino secuencial sourcea todos los test_*.sh antes de
# ejecutar nada, asi que un helper definido en A se cuela en B y B parece
# autocontenido sin serlo. Al paralelizar salio uno real de 66:
# test_lessons_rotacion.sh usaba `_doc` sin definirlo. Un fichero de tests
# sostenido por el orden de sourceo es una casualidad, no un diseno.
#
# Escotilla: TESTS_JOBS=1 vuelve al camino secuencial sin editar nada.
_rt_cores() {
  local n
  n="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)"
  case "$n" in ''|*[!0-9]*) n=2 ;; esac
  # Tope de 8: por encima, los tests que lanzan subprocesos y esperan señales
  # compiten por slots de proceso, que es la presión bajo la que nació el
  # flaky de WF-01. Más paralelismo del que la máquina sostiene no es más
  # rápido, es más flaky.
  [ "$n" -gt 8 ] && n=8
  echo "$n"
}
JOBS="$_RT_JOBS_ENV"
[ "$JOBS" = "auto" ] && JOBS="$(_rt_cores)"
case "$JOBS" in ''|*[!0-9]*) JOBS=1 ;; esac

# `-z "$FILTER"`: una corrida FILTRADA no entra al pool. El filtro puede casar
# el NOMBRE de un test, no solo el del archivo, asi que saber que archivos
# afecta exige sourcearlos todos — y el dispatcher acababa forkeando 67 workers
# para correr uno. Medido en el review: 1,9s -> 12,8s. Peor: `canon-enforce.sh`
# (CHECK 4) usa justamente ese camino en cada cierre de turno, y existe para NO
# pagar la suite entera; paralelizar la suite le habia subido el coste al
# mecanismo creado para no correrla. Una corrida dirigida no gana nada con el
# paralelismo y solo paga el fork.
if [ "$_RT_IS_WORKER" != "1" ] && [ "$JOBS" -gt 1 ] && [ -z "$FILTER" ]; then
  _RT_OUT="$(mktemp -d)"
  # El perfil de la corrida anterior solo sirve para ORDENAR. Si falta, está
  # corrupto o es de otra máquina, el orden es alfabético y el resultado es el
  # mismo: es una optimización, nunca una condición de corrección.
  _RT_PERFIL_CACHE="$PROJECT_ROOT/.agents/state/metrics/tests-perfil.txt"
  _RT_PERFIL=""
  # ── GRUPO SERIE: los que miden procesos y señales corren SOLOS ─────
  # No es una precaución teórica. Medido el 2026-09-02 con el pool a 8: tres
  # corridas seguidas dieron 2 ROJAS, y los cuatro fallos fueron del mismo
  # archivo (`test_agent_runner.sh`: timeouts que no matan descendientes,
  # cancelación que no propaga 143). Esos tests miden CUÁNDO muere un proceso;
  # con la máquina saturada, los plazos que comprueban dejan de cumplirse y el
  # test acusa al harness de un fallo del entorno. Es la familia f-wf01, que ya
  # estaba abierta como flaky en CI — el paralelismo la empeora, no la crea.
  #
  # Una suite roja 2 de cada 3 veces es PEOR que una lenta: se desactiva. Así
  # que estos archivos se ejecutan uno a uno y con el resto ya terminado.
  # Cuesta ~72s de los ~146s totales y es el precio de que el verde signifique
  # algo.
  #
  # SE INTENTÓ VACIARLA el 2026-09-04 y NO se pudo. La suite baja a 77s, medido
  # con 4 corridas verdes — pero con `TESTS_JOBS=32` sobre 10 núcleos el rojo
  # vuelve 3 de 3 veces, y falla exactamente esta familia. Lo que dispara el
  # flaky es la PRESIÓN DE PROCESOS, no macOS; local iba verde solo porque
  # sobraban núcleos. Así que esto no es deuda esperando a que alguien la
  # borre: es la única defensa viva contra una causa raíz que sigue ahí.
  #
  # El repro está en f-wf01, y es la ganancia real de aquel intento: antes era
  # un fantasma que solo aparecía en `macos-latest`; ahora sale a demanda en 81s.
  # Vaciar esta lista solo será correcto cuando el fixture deje de competir
  # contra su propio timeout — subirlo otra vez solo mueve el umbral.
  #
  # Y ojo al medir: `TESTS_SERIAL_FILES=""` NO desactiva nada. `${VAR:-default}`
  # cae en el default con una cadena vacía, así que hace falta un centinela no
  # vacío. Una tanda entera de medidas se perdió por eso, y solo se notó porque
  # los tiempos salían idénticos al control.
  _RT_SERIE="${TESTS_SERIAL_FILES:-test_agent_runner.sh test_capability_probe.sh test_verdict.sh}"
  _RT_FILES=(); _RT_SERIE_FILES=()
  for f in "$PROJECT_ROOT"/tools/tests/test_*.sh; do
    [ -f "$f" ] || continue
    case " $_RT_SERIE " in
      *" $(basename "$f") "*) _RT_SERIE_FILES+=("$f") ;;
      *) _RT_FILES+=("$f") ;;
    esac
  done
  _RT_N=${#_RT_FILES[@]}
  if [ "$_RT_N" -gt 0 ] || [ ${#_RT_SERIE_FILES[@]} -gt 0 ]; then
    # POOL con reposicion, no lotes. bash 3.2 (el de macOS) no tiene `wait -n`,
    # asi que la primera version esperaba a la tanda entera: cada lote duraba lo
    # que su miembro mas lento y la suite se quedaba en 162s teniendo un camino
    # critico de 50s (`TESTS_PROFILE=1` lo enseña). Se repone el slot sondeando
    # los PIDs vivos con `kill -0`, que es portable y cuesta un `sleep 0.05`.
    #
    # Los archivos se lanzan de MAS LARGO a MAS CORTO cuando hay un perfil de la
    # corrida anterior: meter el de 50s al final obliga a esperarlo solo. Sin
    # perfil (primera corrida) va en orden alfabetico y no pasa nada.
    _RT_ORDEN=""
    if [ -f "$_RT_PERFIL_CACHE" ]; then
      _RT_ORDEN="$(sort -rn "$_RT_PERFIL_CACHE" 2>/dev/null | awk '{print $2}')"
    fi
    _RT_PENDIENTES=()
    # El guard de duplicados va TAMBIEN aqui, no solo en el relleno de abajo: un
    # perfil con un basename repetido —un edit a mano, una fusion accidental—
    # metia el mismo indice dos veces, y eso son dos workers del MISMO fichero
    # escribiendo al MISMO .out. El review lo reprodujo; el recuento salio bien
    # por casualidad (la agregacion es por indice), pero un fichero de tests con
    # efectos laterales corriendo dos veces no puede depender de la suerte.
    for _rt_nombre in $_RT_ORDEN; do
      _rt_i=0
      while [ "$_rt_i" -lt "$_RT_N" ]; do
        if [ "$(basename "${_RT_FILES[$_rt_i]}")" = "$_rt_nombre" ]; then
          case " ${_RT_PENDIENTES[*]+${_RT_PENDIENTES[*]}} " in
            *" $_rt_i "*) : ;;
            *) _RT_PENDIENTES+=("$_rt_i") ;;
          esac
        fi
        _rt_i=$((_rt_i+1))
      done
    done
    _rt_i=0
    while [ "$_rt_i" -lt "$_RT_N" ]; do
      case " ${_RT_PENDIENTES[*]+${_RT_PENDIENTES[*]}} " in *" $_rt_i "*) : ;; *) _RT_PENDIENTES+=("$_rt_i") ;; esac
      _rt_i=$((_rt_i+1))
    done

    _RT_VIVOS=""
    for _rt_idx in ${_RT_PENDIENTES[@]+"${_RT_PENDIENTES[@]}"}; do
      # Espera a que haya hueco.
      while :; do
        _rt_nuevos=""; _rt_n_vivos=0
        for _rt_pid in $_RT_VIVOS; do
          if kill -0 "$_rt_pid" 2>/dev/null; then
            _rt_nuevos="$_rt_nuevos $_rt_pid"; _rt_n_vivos=$((_rt_n_vivos+1))
          fi
        done
        _RT_VIVOS="$_rt_nuevos"
        [ "$_rt_n_vivos" -lt "$JOBS" ] && break
        sleep 0.05
      done
      RUN_TESTS_WORKER=1 RUN_TESTS_ONLY_FILE="${_RT_FILES[$_rt_idx]}" \
        bash "$0" ${FILTER:+"$FILTER"} > "$_RT_OUT/$_rt_idx.out" 2>&1 &
      _RT_VIVOS="$_RT_VIVOS $!"
    done
    wait
    # Y ahora el grupo serie, uno a uno, con la máquina ya libre.
    for _rt_sf in ${_RT_SERIE_FILES[@]+"${_RT_SERIE_FILES[@]}"}; do
      _RT_FILES+=("$_rt_sf")
      RUN_TESTS_WORKER=1 RUN_TESTS_ONLY_FILE="$_rt_sf" \
        bash "$0" ${FILTER:+"$FILTER"} > "$_RT_OUT/$_RT_N.out" 2>&1
      _RT_N=$((_RT_N+1))
    done

    # Se imprime en ORDEN DE ARCHIVO, no de terminación: una suite cuya salida
    # cambia de orden entre corridas es imposible de diferenciar.
    _rt_k=0
    while [ "$_rt_k" -lt "$_RT_N" ]; do
      _rt_f="${_RT_FILES[$_rt_k]}"; _rt_o="$_RT_OUT/$_rt_k.out"
      grep -v '^__RT_' "$_rt_o" 2>/dev/null
      _rt_res="$(grep '^__RT_RESULT__' "$_rt_o" 2>/dev/null | tail -1)"
      if [ -z "$_rt_res" ]; then
        # Sin trailer: el worker no llegó al final. Nunca es un archivo verde.
        FAIL=$((FAIL+1))
        FAILED_NAMES+=("$(basename "$_rt_f")::(el worker murió sin dejar resultado)")
        echo ""
        echo "━━━ $(basename "$_rt_f") ━━━"
        echo "  ❌ el worker de este archivo terminó SIN resultado."
        echo "     Se cuenta como fallo a propósito: un archivo que revienta no"
        echo "     puede desaparecer del recuento y dejar la suite en verde."
      else
        _rt_p="${_rt_res#*pass=}"; _rt_p="${_rt_p%% *}"
        _rt_fa="${_rt_res#*fail=}"; _rt_fa="${_rt_fa%% *}"
        case "$_rt_p" in ''|*[!0-9]*) _rt_p=0 ;; esac
        case "$_rt_fa" in ''|*[!0-9]*) _rt_fa=0 ;; esac
        PASS=$((PASS+_rt_p)); FAIL=$((FAIL+_rt_fa))
        _rt_s="${_rt_res#*secs=}"; _rt_s="${_rt_s%% *}"
        case "$_rt_s" in ''|*[!0-9]*) _rt_s=0 ;; esac
        _RT_PERFIL="$_RT_PERFIL$_rt_s $(basename "$_rt_f")
"
        while IFS= read -r _rt_line; do
          [ -n "$_rt_line" ] && FAILED_NAMES+=("${_rt_line#__RT_FAILED__ }")
        done < <(grep '^__RT_FAILED__' "$_rt_o" 2>/dev/null)
      fi
      _rt_k=$((_rt_k+1))
    done
  fi
  rm -rf "$_RT_OUT"
  # El perfil solo se imprime si lo piden: la salida normal de una suite verde
  # no debe crecer. Sirve para saber DONDE esta el camino critico — con 8
  # trabajos, la suite no puede bajar del fichero mas lento.
  if [ -n "$_RT_PERFIL" ]; then
    mkdir -p "$(dirname "$_RT_PERFIL_CACHE")" 2>/dev/null \
      && printf '%s' "$_RT_PERFIL" > "$_RT_PERFIL_CACHE" 2>/dev/null || true
  fi
  if [ "${TESTS_PROFILE:-0}" = "1" ] && [ -n "$_RT_PERFIL" ]; then
    echo ""
    echo "━━━ perfil por archivo (segundos, los 12 mas lentos) ━━━"
    printf '%s' "$_RT_PERFIL" | sort -rn | head -12 | awk '{printf "   %4ss  %s\n", $1, $2}'
  fi
  # Cae al bloque de resumen de abajo, que es el mismo para los dos caminos.
  _RT_DISPATCHED=1
fi

# ── Descubrimiento y ejecución ──────────────────────────────────────
for f in "$PROJECT_ROOT"/tools/tests/test_*.sh; do
  [ "${_RT_DISPATCHED:-0}" = "1" ] && break
  # En modo worker, este proceso corre UN archivo y nada más.
  if [ -n "$_RT_ONLY_FILE" ] && [ "$f" != "$_RT_ONLY_FILE" ]; then continue; fi
  [ -f "$f" ] || continue
  BASE="$(basename "$f")"
  # El filtro casa contra el ARCHIVO o contra el NOMBRE de un test. Si casa el
  # archivo, corren todos sus tests; si no, solo los tests cuyo nombre casa.
  FILE_MATCH=0
  if [ -z "$FILTER" ]; then
    FILE_MATCH=1
  else
    case "$BASE" in *"$FILTER"*) FILE_MATCH=1 ;; esac
  fi

  # shellcheck disable=SC1090
  . "$f"
  ALL_TESTS="$(declare -F | awk '{print $3}' | grep '^test_' || true)"

  # ¿Hay algo que correr en este archivo?
  if [ "$FILE_MATCH" -eq 0 ]; then
    HAS=0
    for t in $ALL_TESTS; do case "$t" in *"$FILTER"*) HAS=1 ;; esac; done
    if [ "$HAS" -eq 0 ]; then
      for t in $ALL_TESTS; do unset -f "$t"; done
      continue
    fi
  fi

  echo ""
  echo "━━━ $BASE ━━━"
  for t in $ALL_TESTS; do
    if [ "$FILE_MATCH" -eq 0 ]; then
      case "$t" in *"$FILTER"*) : ;; *) unset -f "$t"; continue ;; esac
    fi
    out="$( _run_test "$t" )"; rc=$?
    if [ $rc -eq 0 ]; then
      PASS=$((PASS+1)); printf '  ✅ %s\n' "$t"
    else
      FAIL=$((FAIL+1)); FAILED_NAMES+=("$BASE::$t"); printf '  ❌ %s\n' "$t"
      [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/     /'
    fi
    unset -f "$t"
  done
done

# ── Trailer del worker: maquinal, obligatorio y lo ultimo que hace ──
# El padre lo exige; su ausencia es un fallo con nombre. El worker NO aplica el
# guard del conjunto vacio: un archivo sin tests que casen el filtro es normal,
# y quien decide si la SUITE entera esta vacia es el padre.
if [ "$_RT_IS_WORKER" = "1" ]; then
  printf '__RT_RESULT__ pass=%s fail=%s secs=%s\n' "$PASS" "$FAIL" "$SECONDS"
  for _rt_n in ${FAILED_NAMES[@]+"${FAILED_NAMES[@]}"}; do
    printf '__RT_FAILED__ %s\n' "$_rt_n"
  done
  exit 0
fi

echo ""
echo "────────────────────────────────────────"
# El conjunto VACÍO no aprueba: "0 tests, 0 fallos, ✅" es un gate mudo con
# disfraz de gate verde — exactamente lo que este harness combate. Si los
# test_*.sh desaparecen (clone parcial, borrado accidental), esto tiene que
# GRITAR, porque canon-enforce CHECK 4 y ci/run-gates.sh paso 1 dependen de
# que esta suite exista. Ausencia de evidencia no es evidencia.
if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
  if [ -n "$FILTER" ]; then
    echo "⚠️  0 tests matchearon el filtro '$FILTER' (¿typo?)."
    exit 0
  fi
  echo "❌ 0 tests descubiertos en tools/tests/test_*.sh — la suite del harness"
  echo "   NO EXISTE en esta copia. Un runner que aprueba el conjunto vacío es"
  echo "   un gate mudo. Restaura los tests antes de confiar en ningún gate."
  exit 1
fi
if [ "$FAIL" -eq 0 ]; then
  echo "✅ tests del harness: $PASS pasaron, 0 fallaron."
  exit 0
fi
echo "❌ tests del harness: $PASS pasaron, $FAIL FALLARON:"
for n in "${FAILED_NAMES[@]}"; do echo "   - $n"; done
exit 1
