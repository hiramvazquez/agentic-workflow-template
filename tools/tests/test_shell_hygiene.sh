#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Higiene de shell del harness — detector de una clase entera de bug
# ════════════════════════════════════════════════════════════════════
# El bug que motivó este archivo (PRD 0001 §18 G14):
#
#     fail "STALE (HEAD cambió $MARKED_HEAD→$CUR_HEAD)"
#
# Bash consume los bytes de `→` como parte del nombre de variable, así que
# expande `$MARKED_HEAD→` (una variable que no existe). Con `set -u` eso mata
# el script. Lo mismo con `«$SCOPE»`, `$VAR…`, `$VAR·`: cualquier carácter
# tipográfico pegado a una variable sin llaves.
#
# Es un bug especialmente traicionero en un harness ESCRITO EN ESPAÑOL:
# los mensajes usan →, «», …, · de forma natural, y solo explota en la RAMA
# que imprime ese mensaje. En `check-review-marker.sh` esa rama era
# "el marker está stale" — es decir, se rompía justo cuando el gate tenía
# que bloquear. Se descubrió por accidente, al intentar commitear P2.
#
# Estos tests son un DETECTOR, no un caso: barren todos los .sh del harness.

_shell_files() {
  find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/ci" \
       -name '*.sh' -type f 2>/dev/null
}

# ── El bug de G14: $VAR pegado a un carácter no-ASCII ───────────────
test_sin_variables_pegadas_a_caracteres_no_ascii() {
  local hits
  # Se saltan los COMENTARIOS: este mismo archivo documenta el anti-patrón y
  # se detectaba a sí mismo — el falso positivo de G7 otra vez, ahora en el
  # detector recién escrito. Confirma el patrón: el primer falso positivo de
  # un detector aparece en el repo del propio detector.
  hits="$(_shell_files | xargs perl -ne '
      next if /^\s*#/;
      print "$ARGV:$.: $_" if /\$[A-Za-z_]\w*[^\x00-\x7F\s]/;
      close ARGV if eof;
    ' 2>/dev/null)"
  [ -z "$hits" ] && return 0
  echo "    \$VAR pegado a un carácter no-ASCII (bash se lo traga como parte del nombre)."
  echo "    Usa \${VAR} con llaves. Ocurrencias:"
  printf '%s\n' "$hits" | sed 's/^/      /'
  return 1
}

# ── Todos los scripts deben parsear ─────────────────────────────────
test_todos_los_scripts_parsean() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    bash -n "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    scripts con error de sintaxis:"; printf '%s' "$bad"; return 1
}

# ── `set -u` en todos: una variable no definida debe gritar ─────────
test_todos_los_scripts_usan_set_u() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Se saltan los archivos que se SOURCEAN, no se ejecutan: los tests y las
    # librerías de `lib/`. En ellos `set -u` lo impone el llamador; ponerlo
    # dentro cambiaría las opciones del shell del que los carga.
    case "${f##*/}" in test_*.sh) continue ;; esac
    case "$f" in */lib/*) continue ;; esac
    grep -qE '^set -[a-z]*u' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    sin \`set -u\` (una variable vacía por error pasaría silenciosa):"
  printf '%s' "$bad"; return 1
}

# ── Los hooks derivan PROJECT_ROOT de su propio dirname ─────────────
# Si dependieran del cwd, se comportarían distinto según quién los invoque.
test_los_hooks_no_dependen_del_cwd() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -q 'PROJECT_ROOT=' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(find "$PROJECT_ROOT/scripts/agent-hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null)
  [ -z "$bad" ] && return 0
  echo "    hooks sin PROJECT_ROOT derivado de \$0 (dependerían del cwd):"
  printf '%s' "$bad"; return 1
}

# ── Las reglas de semgrep CARGAN de verdad ──────────────────────────
# `semgrep --validate` solo comprueba el YAML. Un patrón inválido para UNO de
# los `languages` que la regla declara (p.ej. `===` en C#, o `def $F(...):` en
# Java) pasa la validación y revienta la carga del ARCHIVO ENTERO al ejecutar.
# Las 6 reglas de universal.yaml tuvieron tres errores de este tipo, ninguno
# detectado hasta la primera ejecución real (PRD 0001 §18 G15).
test_las_reglas_de_semgrep_cargan() {
  command -v semgrep >/dev/null 2>&1 || return 0   # sin semgrep, no aplica
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/semgrep-scan.sh 2>&1)"; rc=$?
  # 3 = fallo del propio detector (reglas rotas o crash). 0 y 1 son válidos:
  # el repo puede tener hallazgos legítimos y eso no es un fallo de las reglas.
  [ "$rc" != "3" ] && return 0
  echo "    las reglas de semgrep NO cargan — el nivel 2 está mudo:"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

# ── Los detectores respetan su contrato de stdout ───────────────────
# El conteo del trinquete se parsea de estas líneas: si un detector deja de
# emitirlas, el trinquete lee 0 y aprueba en silencio (mismo patrón que G2).
test_los_detectores_emiten_su_contrato() {
  local bad=""
  grep -q 'DRIFT_SUMMARY errors=' "$PROJECT_ROOT/tools/check-drift.sh"    2>/dev/null || bad="${bad}      check-drift.sh sin DRIFT_SUMMARY"$'\n'
  grep -q 'LAYERS_SUMMARY errors=' "$PROJECT_ROOT/tools/check-layers.sh"  2>/dev/null || bad="${bad}      check-layers.sh sin LAYERS_SUMMARY"$'\n'
  grep -q 'SEMGREP_SUMMARY errors=' "$PROJECT_ROOT/tools/semgrep-scan.sh" 2>/dev/null || bad="${bad}      semgrep-scan.sh sin SEMGREP_SUMMARY"$'\n'
  grep -q 'MUTATION_SUMMARY score=' "$PROJECT_ROOT/tools/mutation-score.sh" 2>/dev/null || bad="${bad}      mutation-score.sh sin MUTATION_SUMMARY"$'\n'
  [ -z "$bad" ] && return 0
  echo "    detectores que rompieron su contrato de salida:"; printf '%s' "$bad"; return 1
}

# ── `stat -f` de GNU no falla: el orden del fallback ES el bug ──────
# Tercera aparicion de la misma trampa en este repo, y la que publico main en
# rojo: `stat -f` en BSD lee el modo/mtime de un ARCHIVO, pero en GNU lee el
# estado del FILESYSTEM — y sale con 0. Asi que
#
#     stat -f '%Lp' "$f" || stat -c '%a' "$f"      # BSD primero
#
# nunca llega al fallback en Linux: devuelve un volcado del filesystem con exit
# 0 y quien compara obtiene basura. Verde en el Mac de quien lo escribe, rojo en
# CI, y el mensaje de error dice "644, esperaba 644" — la comparacion rota
# esconde su propia causa.
#
# El orden correcto es GNU primero, BSD despues, y ya estaba escrito con este
# comentario en check-review-marker.sh y en check-verify-marker.sh. Que volviera
# a pasar es la ley de siempre: una regla implementada tres veces diverge. Esto
# la convierte en mecanica.
test_stat_lee_gnu_primero_y_bsd_despues() {
  # ── SEGUNDA VERSION. La primera cerro un finding sin poder detectar ─
  # `f-stat-f-orden-invertido` se cerro como "fixed" con la resolucion "Detector
  # nuevo que BARRE TODO EL REPO". No barria: miraba `tools/tests/*.sh` y nada
  # mas. Y aunque hubiera mirado, su desnudado de comillas rompia el caso real:
  # ante `mtime="$(stat -f %m "$f" || ...)"` el `s/"[^"]*"//g` empareja de
  # izquierda a derecha, se traga `$(stat -f %m ` dentro del primer par y deja
  # `mtime=$f$f` — sin rastro de `stat`. El 2026-09-02 la MISMA trampa volvio a
  # publicar main en rojo desde `scripts/agent-hooks/canon-enforce.sh`, un
  # fichero que ese detector no leia y en una forma que no sabia leer.
  #
  # O sea: cuarta aparicion, y la primera en la que el detector que debia
  # impedirla ya existia. Una resolucion de ledger que afirma cobertura es tan
  # peligrosa como un comentario que la afirma (f-74be77fe).
  #
  # Esta version cambia las dos cosas:
  #   · Mira scripts/ tools/ ci/ ENTEROS, tests incluidos.
  #   · No desnuda comillas. La regla es posicional y no necesita parsear: si en
  #     una linea aparece `stat -f`, tiene que haber un `stat -c` ANTES en esa
  #     misma linea. Eso caza tambien el fallback partido en dos sentencias
  #     —la evasion que encontro el review— porque la linea del `stat -f`
  #     tampoco lleva un `-c` delante.
  #
  # Exencion unica y declarada: ESTE fichero, que imprime la forma incorrecta en
  # su propio mensaje de error. Es la exencion minima; la version anterior
  # intento ser lista con las comillas y ahi es donde perdio el caso real.
  local hits
  hits="$(find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/ci" \
            -name '*.sh' -not -name 'test_shell_hygiene.sh' 2>/dev/null \
          | xargs grep -nE 'stat[[:space:]]+-f' 2>/dev/null \
          | grep -vE ':[0-9]+:[[:space:]]*#' \
          | grep -vE 'stat[[:space:]]+-c.*stat[[:space:]]+-f' || true)"
  [ -z "$hits" ] && return 0
  echo "    \`stat -f\` sin un \`stat -c\` DELANTE en la misma linea:"
  printf '%s\n' "$hits" | sed 's|^.*/||' | sed 's/^/      /'
  echo "    En GNU, \`stat -f\` NO falla: imprime el estado del FILESYSTEM con exit 0,"
  echo "    asi que el fallback nunca corre y en Linux lees basura. Orden correcto:"
  echo "      stat -c '%a' \"\$f\" 2>/dev/null || stat -f '%Lp' \"\$f\" 2>/dev/null"
  echo "    Verde en macOS, rojo en CI — asi se publico main en rojo dos veces."
  return 1
}

# El runner sanea el entorno del anfitrión antes de correr nada: un test cuyo
# veredicto dependa de una variable que él no puso mide otra cosa, y lo hace en
# silencio. Pasó dos veces (GATES_SKIP_TESTS tumbando golden_09 desde el step de
# CI; REVIEWER_OVERRIDE tumbando 12 de 26 tests de scope_kind desde la shell de
# un dev). Sin este test, borrar el `unset` no pondría nada en rojo.
test_el_runner_sanea_el_entorno_del_anfitrion() {
  local runner="$PROJECT_ROOT/tools/tests/run-tests.sh" falta="" v
  # LAS QUINCE, no una muestra: una versión anterior de este test comprobaba
  # siete y quedaba VERDE si alguien quitaba VERIFY_CMD del unset — con esa
  # sola quitada, `VERIFY_CMD=true bash tools/tests/run-tests.sh verify_marker`
  # da cinco rojos. Un test que cubre la mitad de su contrato invita a recortar
  # la otra mitad con luz verde falsa. Lo cazó el reviewer con ese mutante.
  # El ancla es `unset` + IDENTIFICADOR EN MAYÚSCULAS, no el literal `unset
  # GATES_`: con el literal, reordenar el bloque para que empiece por otra
  # variable dejaba de abrir el rango y el check reportaba las quince como
  # ausentes — un falso positivo que el propio hardening introdujo. (Y la
  # justificación de aquel literal era falsa: los `unset -f` del runner van
  # indentados, así que un ancla en columna 0 nunca los captura.)
  for v in GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
           GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
           AI_REVIEW_REQUIRED AI_REVIEW_OUT \
           REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
           VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
           MUTATION_SCORE_OVERRIDE; do
    awk '/^unset [A-Z_]/,/[^\\]$/' "$runner" | grep -qw "$v" || falta="$falta $v"
  done
  [ -z "$falta" ] \
    || { echo "    el runner no sanea variables que alteran gates:$falta"; return 1; }

  # Y que el saneo FUNCIONE, no solo que esté escrito. La comprobación es este
  # test MISMO: corre dentro del runner, así que si el saneo funciona ninguna de
  # esas variables puede estar definida aquí — da igual lo que trajera la shell
  # que lanzó la suite. Con `GATES_SKIP_TESTS=1 bash tools/tests/run-tests.sh`
  # esto es una prueba real; sin nada en el entorno, pasa trivialmente y el
  # check estático de arriba es el que sostiene el contrato.
  # (Invocar el runner desde aquí sería recursión infinita: el filtro casaría
  # con este mismo test. Se intentó y colgó la suite.)
  local sucias="" w
  for w in GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
           GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
           AI_REVIEW_REQUIRED AI_REVIEW_OUT \
           REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
           VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
           MUTATION_SCORE_OVERRIDE; do
    [ -z "${!w:-}" ] || sucias="$sucias $w"
  done
  [ -z "$sucias" ] \
    || { echo "    el saneo no surtió efecto: llegaron del anfitrión:$sucias"; return 1; }
}

# ── `grep -Z` alimentando un `read -d ''` no funciona en BSD ────────
# SEGUNDA trampa GNU/BSD en 24 horas, y de la misma forma exacta que la del
# orden de `stat`: una opción que en GNU hace una cosa y en BSD otra, fallando
# hacia el SILENCIO.
#
# En GNU, `grep -lZ` separa los nombres por NUL y el `read -d ''` los consume.
# En BSD/macOS, `-Z` NO emite NUL — verificado con `od -c`: separa por `\n`. El
# `read -d ''` espera un NUL que nunca llega, el bucle da CERO iteraciones, y el
# script sigue como si hubiera trabajado.
#
# Lo que costó: `scripts/bootstrap.sh` combinaba las dos cosas, así que su
# función principal —reemplazar `<PROJECT>` por el nombre del proyecto— NUNCA
# funcionó en macOS. Imprimía "→ Reemplazando…" y no reemplazaba nada. Todo
# adoptante de macOS se quedó con los placeholders puestos.
#
# La forma portable es `git ls-files -z` (que sí emite NUL en todas partes) o
# `find -print0`, con el grep por fichero dentro del bucle.
#
# ⚠️ LÍMITE DECLARADO, y hay que leerlo antes de confiar en este detector: caza
# el flag PEGADO a `grep` como texto. Se evade con indirección de variable —
# `_F="-lZ"; grep $_F … | while read -d ''` es funcionalmente idéntico y pasa en
# verde. Lo demostró el review con un mutante en vivo. Cubrirlo de verdad
# exigiría seguir el valor de una variable a través del script, que con `grep`
# de texto no se puede hacer sin falsos positivos — y un detector con más de
# ~10% de FP se descarta entero (§14.2).
#
# Se deja así, con el hueco ESCRITO, porque la alternativa no es un detector
# mejor: es uno que afirma una cobertura que no tiene, que es justo la lección
# que f-74be77fe lleva registrada. Lo que este detector sí garantiza es que la
# forma LITERAL —la que se escribe sin pensar, y la que causó el bug— no vuelve.
test_grep_Z_no_alimenta_un_read_nul() {
  # Se miran las líneas de CÓDIGO, no los comentarios. La primera versión se
  # cazaba a sí misma vía `bootstrap.sh`: el comentario que explica por qué NO
  # usar ese par contiene el par. Misma trampa que ya tuvo el detector del orden
  # de `stat`, y aquí la exención mínima es "los comentarios son texto", no
  # "este fichero está exento".
  #
  # `-print0` además, porque un detector de portabilidad que se rompe con un
  # nombre de fichero raro es una broma (lo señaló shellcheck SC2038 sobre la
  # primera versión de estas mismas líneas).
  local hits="" f cuerpo
  while IFS= read -r -d '' f; do
    cuerpo="$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null || true)"
    printf '%s' "$cuerpo" | grep -qE 'grep[^|]*-[a-zA-Z]*Z' || continue
    printf '%s' "$cuerpo" | grep -qE "read -r -d ''|read -d ''" || continue
    hits="$hits $f"
  done < <(find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/ci" \
             -name '*.sh' -not -name 'test_shell_hygiene.sh' -print0 2>/dev/null)
  [ -z "$hits" ] && return 0
  echo "    estos scripts usan \`grep … -Z\` Y un \`read -d ''\`:"
  for f in $hits; do echo "      ${f##*/}"; done
  echo "    En BSD/macOS \`grep -Z\` NO emite NUL (separa por \\n), así que el"
  echo "    \`read -d ''\` espera un NUL que nunca llega y el bucle no itera NI"
  echo "    UNA VEZ — en silencio, con el script anunciando que trabajó."
  echo "    Portable: \`git ls-files -z\` o \`find -print0\`, con el grep DENTRO."
  echo "    Le pasó a bootstrap.sh: nunca reemplazó los placeholders en macOS."
  return 1
}

# ── `scope.sh` se CONSULTA aislada, nunca se sourcea suelta ─────────
# Dos bugs distintos el mismo día, la misma forma. `scope.sh` ejecuta
# `_scope_verifica_declaracion` AL SOURCEARSE, y esa función hace `exit 3` bajo
# CI cuando la declaración contradice a la evidencia. Sourceada directa en un
# script, ese exit lo mata entero:
#
#   · `check-execution-map` moría antes de comparar nada.
#   · Los tres detectores retirados salían 3 y ENMASCARABAN la violación real
#     de capas con una queja de configuración — y ese ya estaba pusheado.
#
# Y ninguno de los dos se veía en local, porque la suite no corre con `CI=true`
# y GitHub Actions lo exporta en todos los jobs. "827 tests verdes" con la CI
# real a punto de ponerse roja.
#
# El patrón correcto ya existía en `session-start.sh:148`: subshell +
# `SCOPE_NO_CI_EXIT=1`. Quien necesite la librería para DECIDIR algo (un gate de
# scope) puede sourcearla directa; quien solo CONSULTA, no.
# ── La excepción, declarada y con nombre ────────────────────────────
# `check-review-marker` y `check-verify-marker` SÍ sourcean scope.sh directa, y
# es correcto: son los GATES DE SCOPE. Usan la librería para DECIDIR qué cuenta
# como producto, así que el `exit 3` bajo una declaración contradictoria es
# exactamente lo que deben honrar — un gate que clasifica con una config en la
# que no puede confiar tiene que parar, no seguir adivinando.
#
# La regla es consulta vs decisión: quien pregunta "¿aplico aquí?" aísla; quien
# decide con la respuesta, no. La lista es cerrada a propósito — si un tercer
# script necesita entrar, que sea con su razón escrita aquí y no por descuido.
_SCOPE_GATES_LEGITIMOS='check-review-marker.sh check-verify-marker.sh'

test_scope_sh_no_se_sourcea_sin_aislar() {
  # La regla es BASTA a propósito: "si usas scope.sh, o eres un gate declarado o
  # llevas el guard". La versión fina —buscar la línea del `.` con `scope.sh`
  # dentro— la evadía una variable: `_EM_SCOPE=".../scope.sh"` y luego
  # `. "$_EM_SCOPE"` no casa el literal. Lo demostró un mutante. Seguir el valor
  # de una variable con grep de texto no se puede sin falsos positivos (§14.2),
  # así que se pregunta lo que sí es decidible: ¿este fichero usa la librería, y
  # aparece el guard en alguna parte?
  local hits="" f cuerpo
  while IFS= read -r -d '' f; do
    cuerpo="$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null || true)"
    printf '%s' "$cuerpo" | grep -q 'scope\.sh' || continue
    printf '%s' "$cuerpo" | grep -q 'SCOPE_NO_CI_EXIT' && continue
    case " $_SCOPE_GATES_LEGITIMOS " in *" ${f##*/} "*) continue ;; esac
    hits="$hits $f"
  done < <(find "$PROJECT_ROOT/tools" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/ci" \
             -name '*.sh' -not -path '*/tests/*' -not -name 'scope.sh' -print0 2>/dev/null)
  [ -z "$hits" ] && return 0
  echo "    estos scripts sourcean scope.sh SIN SCOPE_NO_CI_EXIT=1:"
  for f in $hits; do echo "      ${f##*/}"; done
  echo "    scope.sh corre _scope_verifica_declaracion al sourcearse, y esa función"
  echo "    hace exit 3 bajo CI ante una contradicción declarado-vs-evidencia."
  echo "    Sourceada directa, ese exit MATA al script — y Actions exporta CI=true."
  echo "    Para CONSULTAR usa el patrón de session-start.sh:148:"
  echo "      X=\"\$(SCOPE_NO_CI_EXIT=1 bash -c '. tools/lib/scope.sh 2>/dev/null; …')\""
  return 1
}
