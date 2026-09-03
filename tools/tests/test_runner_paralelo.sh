#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El runner en PARALELO: mismo veredicto, o no sirve
# ════════════════════════════════════════════════════════════════════
# La suite corre entera en `verify-run` (antes de cada commit) y en el
# pre-push. Medido el 2026-09-02: 786 tests, ~7 minutos, secuencial. Es el
# coste dominante del bucle y se paga dos veces por cambio.
#
# Paralelizar el runner es tocar el script del que depende el marker de verify:
# si el camino paralelo cuenta mal, una suite ROJA puede parecer verde y
# firmarse. Por eso el invariante que más se prueba aquí no es la velocidad —
# es que **un worker sin resultado cuenta como FALLO**. Un fichero de tests que
# revienta, que se cuelga o que muere por señal no puede desaparecer del
# recuento en silencio: sería exactamente "un gate que no corrió pareciendo un
# gate que pasó" (§14.3), en el sitio donde más caro sale.

_rp_sandbox() { # <función> — un repo de juguete con el runner REAL dentro
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/tests"
  cp "$PROJECT_ROOT/tools/tests/run-tests.sh" "$d/tools/tests/"
  chmod +x "$d/tools/tests/run-tests.sh"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_rp_test_file() { # <nombre> <cuerpo-de-la-funcion>
  printf 'test_%s() {\n%s\n}\n' "$1" "$2" > "tools/tests/test_$1.sh"
}

_rp_corre() { # <jobs> → imprime la salida, devuelve el rc
  TESTS_JOBS="$1" TEST_TIMEOUT_SECS=5 bash tools/tests/run-tests.sh 2>&1
}

# ── 1. Paralelo y secuencial dan EL MISMO veredicto ─────────────────
# El guard de equivalencia. Con fallos de verdad mezclados, no solo verdes:
# un recuento paralelo que pierde rojos es el modo de fallo que importa.
_case_mismo_veredicto() {
  _rp_test_file aaa 'return 0'
  _rp_test_file bbb 'echo "razon del fallo"; return 1'
  _rp_test_file ccc 'return 0'
  _rp_test_file ddd 'return 1'
  local sec par rcs rcp
  sec="$(_rp_corre 1)"; rcs=$?
  par="$(_rp_corre 4)"; rcp=$?
  local res_sec res_par
  res_sec="$(printf '%s\n' "$sec" | grep -E 'tests del harness' | head -1)"
  res_par="$(printf '%s\n' "$par" | grep -E 'tests del harness' | head -1)"
  [ "$res_sec" = "$res_par" ] || {
    echo "    los recuentos NO coinciden:"
    echo "      secuencial: $res_sec"
    echo "      paralelo  : $res_par"; return 1; }
  [ "$rcs" = "$rcp" ] || { echo "    exit distinto: secuencial=$rcs paralelo=$rcp"; return 1; }
  # …y los MISMOS nombres, no solo el mismo número.
  local f_sec f_par
  f_sec="$(printf '%s\n' "$sec" | grep '^   - ' | sort)"
  f_par="$(printf '%s\n' "$par" | grep '^   - ' | sort)"
  [ "$f_sec" = "$f_par" ] || {
    echo "    los tests fallados no son los mismos:"
    echo "      secuencial: $(echo "$f_sec" | tr '\n' ' ')"
    echo "      paralelo  : $(echo "$f_par" | tr '\n' ' ')"; return 1; }
}
test_paralelo_y_secuencial_dan_el_mismo_veredicto() { _rp_sandbox _case_mismo_veredicto; }

# ── 2. UN WORKER SIN RESULTADO ES UN FALLO ──────────────────────────
# El invariante crítico. Un fichero de tests que mata su propio proceso no
# puede evaporarse del recuento: sin esto, `exit 0` a mitad de un archivo lo
# borraría de la suite y el resto seguiría en verde.
_case_worker_mudo_es_fallo() {
  _rp_test_file aaa 'return 0'
  # Un fichero que revienta el worker entero al SOURCEARLO.
  printf 'kill -9 $$\ntest_nunca() { return 0; }\n' > tools/tests/test_zzz_revienta.sh
  local out rc
  out="$(_rp_corre 4)"; rc=$?
  [ "$rc" != "0" ] || {
    echo "    un worker que muere sin dejar resultado pasó como VERDE (exit 0)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'zzz_revienta' || {
    echo "    el fichero que reventó no aparece nombrado en la salida:"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_worker_sin_resultado_cuenta_como_fallo() { _rp_sandbox _case_worker_mudo_es_fallo; }

# ── 3. Corre DE VERDAD en paralelo ──────────────────────────────────
# Prueba determinista, sin medir tiempos (medir tiempos es como nació la
# familia flaky f-wf01). `aaa` espera a que exista un fichero que solo crea
# `bbb`. En secuencial, `aaa` va primero y se cuelga hasta el watchdog; en
# paralelo, `bbb` lo libera. El veredicto no depende de cuánto tarde nada.
_case_corre_de_verdad_en_paralelo() {
  _rp_test_file aaa 'i=0; while [ ! -f "$PROJECT_ROOT/libre.flag" ] && [ $i -lt 100 ]; do i=$((i+1)); sleep 0.1; done; [ -f "$PROJECT_ROOT/libre.flag" ]'
  _rp_test_file bbb 'sleep 0.3; : > "$PROJECT_ROOT/libre.flag"; return 0'
  local out rc
  out="$(_rp_corre 4)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    con TESTS_JOBS=4 los dos ficheros NO se solaparon: el que espera"
    echo "    a que el otro lo libere nunca fue liberado, así que corrieron en serie."
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_los_ficheros_corren_de_verdad_en_paralelo() { _rp_sandbox _case_corre_de_verdad_en_paralelo; }

# ── 4. El guard del conjunto VACÍO sigue vivo en paralelo ───────────
# "0 tests, 0 fallos, ✅" es un gate mudo con disfraz de verde, y el runner ya
# lo trataba como error. El camino paralelo no puede perder esa propiedad.
_case_vacio_sigue_gritando() {
  rm -f tools/tests/test_*.sh
  local out rc
  out="$(_rp_corre 4)"; rc=$?
  [ "$rc" = "1" ] || { echo "    con CERO tests el runner paralelo salió $rc (esperaba 1)"; return 1; }
  printf '%s' "$out" | grep -q 'NO EXISTE' || { echo "    no explicó que la suite no existe: [$out]"; return 1; }
}
test_el_conjunto_vacio_sigue_siendo_un_error_en_paralelo() { _rp_sandbox _case_vacio_sigue_gritando; }

# ── 5. TESTS_JOBS=1 conserva el camino secuencial ───────────────────
# La salida de emergencia. Si el paralelo resulta sospechoso en una máquina o
# en CI, tiene que haber una forma de volver sin editar el script.
_case_jobs_1_es_secuencial() {
  _rp_test_file aaa 'return 0'
  _rp_test_file bbb 'return 1'
  local out rc
  out="$(_rp_corre 1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    con TESTS_JOBS=1 el rc fue $rc (esperaba 1)"; return 1; }
  printf '%s' "$out" | grep -q '1 pasaron, 1 FALLARON' || {
    echo "    recuento inesperado en secuencial: [$(printf '%s' "$out" | grep 'tests del harness')]"; return 1; }
}
test_jobs_1_conserva_el_camino_secuencial() { _rp_sandbox _case_jobs_1_es_secuencial; }

# ── 6. Una corrida FILTRADA no paga el fork de 67 workers ───────────
# Regresión real cazada en el review de la ronda 1: el dispatcher construía la
# lista con TODOS los ficheros sin mirar el filtro, así que
# `run-tests.sh <token>` lanzaba 67 workers para correr uno. Medido: 1,9s →
# 12,8s, 6,7× más lento. Y ese es exactamente el camino que usa
# `canon-enforce.sh` (CHECK 4) en cada cierre de turno que toque el harness —
# un camino que existe, con ese comentario, para NO pagar la suite entera.
# O sea que paralelizar la suite le había subido el coste al mecanismo creado
# para que la suite no se corriera.
#
# Se comprueba por OBSERVACIÓN, no por reloj (medir tiempos es como nació
# f-wf01): el fichero de perfil solo lo escribe el dispatcher paralelo, así que
# su ausencia tras una corrida filtrada prueba que no se entró por ahí.
_case_filtrado_no_dispara_el_pool() {
  _rp_test_file aaa 'return 0'
  _rp_test_file bbb 'return 0'
  local cache=".agents/state/metrics/tests-perfil.txt"
  rm -f "$cache"
  TEST_TIMEOUT_SECS=5 bash tools/tests/run-tests.sh aaa >/dev/null 2>&1
  [ ! -f "$cache" ] || {
    echo "    una corrida FILTRADA entró por el dispatcher paralelo (escribió el perfil):"
    echo "    forkea un worker por cada fichero del repo para correr uno solo."
    return 1; }
  # …y sin filtro sí debe entrar, o este test aprobaría con el paralelo roto.
  TEST_TIMEOUT_SECS=5 bash tools/tests/run-tests.sh >/dev/null 2>&1
  [ -f "$cache" ] || { echo "    sin filtro NO entró por el dispatcher paralelo"; return 1; }
}
test_una_corrida_filtrada_no_paga_el_pool() { _rp_sandbox _case_filtrado_no_dispara_el_pool; }

# ── 7. Un perfil con un basename REPETIDO no despacha dos veces ─────
# El review lo reprodujo: el orden se construye leyendo el perfil de la corrida
# anterior, y una línea duplicada ahí metía el mismo índice dos veces en la
# cola. Dos workers del MISMO fichero escribiendo al MISMO .out es una carrera
# — en el repro el recuento salía bien, así que no es un falso verde
# demostrado, pero un fichero de tests con efectos laterales corriendo dos
# veces no es algo que deba depender de la suerte.
_case_perfil_duplicado_no_duplica_la_corrida() {
  _rp_test_file aaa 'echo x >> "$PROJECT_ROOT/veces.log"; return 0'
  _rp_test_file bbb 'return 0'
  mkdir -p .agents/state/metrics
  printf '9 test_aaa.sh\n9 test_aaa.sh\n1 test_bbb.sh\n' > .agents/state/metrics/tests-perfil.txt
  TEST_TIMEOUT_SECS=5 bash tools/tests/run-tests.sh >/dev/null 2>&1
  local veces; veces="$(grep -c . veces.log 2>/dev/null || echo 0)"
  [ "$veces" = "1" ] || {
    echo "    con un basename repetido en el perfil, test_aaa.sh corrió $veces veces (esperaba 1)"
    return 1; }
}
test_un_perfil_con_duplicados_no_despacha_dos_veces() {
  _rp_sandbox _case_perfil_duplicado_no_duplica_la_corrida
}
