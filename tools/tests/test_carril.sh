#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El carril se DERIVA del diff, y la más severa gana
# ════════════════════════════════════════════════════════════════════
# PRD 0011 fase 1. El workflow cobraba lo mismo por añadir un string que por
# reescribir el motor: suite completa, una revisión y doce gates. Este
# clasificador es lo que permite cobrar en proporción.
#
# Fase 1 a propósito NO cambia nada: deriva e imprime. Decidir qué corre en cada
# carril sin haber medido antes cuántos cambios caen en cada uno sería elegir a
# ciegas — y elegir a ciegas es como se llegó aquí.

_c_sandbox() { # <función> — repo de juguete con el clasificador dentro
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools" "$d/docs/process" "$d/scripts/agent-hooks" "$d/ci"
  cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # El fichero base se COMMITEA: dejarlo staged contaminaba todos los casos
    # con un archivo de raíz que cae en `normal`, y dos tests fallaban por el
    # montaje en vez de por lo que probaban.
    echo base > base.txt
    git "$A" base.txt
    git "$C" -qm base 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_c()  { bash tools/carril.sh "$@" 2>&1; }
_stage() { local A=add f; for f in "$@"; do mkdir -p "$(dirname "$f")"; echo x >> "$f"; git "$A" "$f"; done; }

# ── 1. Nada que se ejecute → ligero ─────────────────────────────────
_case_docs_es_ligero() {
  _stage docs/process/algo.md
  _c | grep -q 'carril=ligero' || { echo "    un cambio solo de docs no salió ligero: $(_c)"; return 1; }
}
test_solo_docs_es_carril_ligero() { _c_sandbox _case_docs_es_ligero; }

# ── 2. Código que se ejecuta → normal ───────────────────────────────
_case_detector_es_normal() {
  _stage tools/check-algo.sh
  _c | grep -q 'carril=normal' || { echo "    un detector no salió normal: $(_c)"; return 1; }
}
test_un_detector_es_carril_normal() { _c_sandbox _case_detector_es_normal; }

# ── 3. La maquinaria que decide qué se verifica → estructural ───────
# La frontera no es arbitraria: un detector equivocado da un resultado malo,
# pero tocar la maquinaria puede hacer que NINGÚN detector corra, y eso no lo
# caza ningún test del propio detector.
_case_lefthook_es_estructural() {
  _stage lefthook.yml
  _c | grep -q 'carril=estructural' || { echo "    lefthook.yml no salió estructural: $(_c)"; return 1; }
}
test_lefthook_es_carril_estructural() { _c_sandbox _case_lefthook_es_estructural; }

# ── 4. La MÁS SEVERA gana ───────────────────────────────────────────
# Si un solo fichero es estructural, el cambio entero lo es. Al revés —tomar el
# más leve, o el mayoritario— un cambio estructural escondido entre veinte de
# docs se saltaría la suite, que es el único fallo grave que este clasificador
# puede tener.
_case_mezcla_gana_la_severa() {
  _stage docs/process/uno.md docs/process/dos.md lefthook.yml
  _c | grep -q 'carril=estructural' || {
    echo "    mezcla de docs + lefthook no salió estructural: $(_c)"
    echo "    Un estructural escondido entre docs se saltaría la suite."
    return 1; }
}
test_la_mezcla_toma_el_carril_mas_severo() { _c_sandbox _case_mezcla_gana_la_severa; }

# ── 5. AGENTS.md es .md, y aun así es estructural ───────────────────
# Es la fuente canónica de las reglas: cambiarla cambia lo que TODOS los agentes
# hacen. Que case con el patrón de ligero no puede ganarle a que case con el de
# estructural.
_case_agents_md_es_estructural() {
  _stage AGENTS.md
  _c | grep -q 'carril=estructural' || { echo "    AGENTS.md salió como doc cualquiera: $(_c)"; return 1; }
}
test_agents_md_es_estructural_pese_a_ser_md() { _c_sandbox _case_agents_md_es_estructural; }

# ── 6. Lo desconocido cae en normal, no en ligero ───────────────────
# El default tiene que ser el SEGURO. Un fichero que nadie previó no puede
# colarse por el carril que no ejecuta nada.
_case_desconocido_es_normal() {
  _stage src/algo.rs
  _c | grep -q 'carril=normal' || { echo "    un fichero no previsto no cayó en normal: $(_c)"; return 1; }
}
test_lo_no_previsto_cae_en_normal() { _c_sandbox _case_desconocido_es_normal; }

# ── 7. Sin nada staged se DICE, no se inventa un carril ─────────────
_case_sin_nada_staged() {
  local out; out="$(_c)"
  printf '%s' "$out" | grep -q 'carril=ninguno' || {
    echo "    sin nada staged se inventó un carril: $out"; return 1; }
}
test_sin_nada_staged_no_hay_carril() { _c_sandbox _case_sin_nada_staged; }

# ── 8. El conf manda: si se le añade una fila, cambia el veredicto ──
# Sin esto, los patrones podrían estar hardcodeados en el script y el conf sería
# decorado — el mismo drift que ya costó caro en la matriz de skills.
_case_el_conf_manda() {
  _stage src/nuevo.py
  _c | grep -q 'carril=normal' || { echo "    precondición: debía ser normal"; return 1; }
  printf 'estructural|src/nuevo.py\n' >> tools/carril.conf
  _c | grep -q 'carril=estructural' || {
    echo "    añadir una fila al conf NO cambió el veredicto: $(_c)"
    echo "    Entonces los patrones viven en el script y el conf es decorado."
    return 1; }
}
test_el_conf_es_la_fuente_unica() { _c_sandbox _case_el_conf_manda; }

# ── 9. Sin git no puede mirar, y lo dice (§14.3) ────────────────────
_case_sin_git_no_pudo_mirar() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/"
  local rc; ( cd "$d" && bash tools/carril.sh >/dev/null 2>&1 ); rc=$?
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    fuera de un repo git no devolvió 3 sino $rc"; return 1; }
}
test_fuera_de_un_repo_git_devuelve_3() { _case_sin_git_no_pudo_mirar; }

# ── `--tests`: qué hay que ejecutar para este cambio ────────────────
# PRD 0011 fase 2. El carril por sí solo no ahorra nada: hay que traducirlo a
# QUÉ tests corren. Medido en el repo real, un cambio normal pasa de los ~140 s
# de la suite entera a entre 2 y 39 s según a cuántos ficheros de test nombre.
#
# La derivación es por REFERENCIA, no por convención de nombres: se buscan los
# tests que NOMBRAN el fichero tocado. La convención no se cumple —`check-drift.sh`
# lo ejercitan `test_drift_stop` y `test_drift_aggregation`, dos nombres
# distintos— y una convención que falla en silencio dejaría tests sin correr
# creyendo que corrieron.
_case_ligero_no_corre_tests() {
  _stage docs/process/algo.md
  _c --tests | grep -qx 'NINGUNO' || { echo "    ligero no dijo NINGUNO: $(_c --tests)"; return 1; }
}
test_ligero_no_ejecuta_tests() { _c_sandbox _case_ligero_no_corre_tests; }

_case_estructural_corre_todo() {
  _stage lefthook.yml
  _c --tests | grep -qx 'TODOS' || { echo "    estructural no dijo TODOS: $(_c --tests)"; return 1; }
}
test_estructural_ejecuta_la_suite_entera() { _c_sandbox _case_estructural_corre_todo; }

_case_normal_deriva_sus_tests() {
  mkdir -p tools/tests
  printf '#!/usr/bin/env bash\necho x\n' > tools/mi-detector.sh
  printf '# ejercita tools/mi-detector.sh\ntest_algo() { :; }\n' > tools/tests/test_mi_detector.sh
  printf '# no tiene nada que ver\ntest_otro() { :; }\n' > tools/tests/test_ajeno.sh
  local A=add C=commit
  git "$A" -A
  git "$C" -qm base 2>/dev/null
  printf '#!/usr/bin/env bash\necho y\n' > tools/mi-detector.sh
  git "$A" tools/mi-detector.sh
  local out; out="$(_c --tests)"
  printf '%s' "$out" | grep -qx 'test_mi_detector' || {
    echo "    no derivó el test que NOMBRA el fichero tocado: $out"; return 1; }
  printf '%s' "$out" | grep -qx 'test_ajeno' && {
    echo "    derivó un test que no lo nombra: correría de más"; return 1; }
  return 0
}
test_normal_deriva_los_tests_que_lo_nombran() { _c_sandbox _case_normal_deriva_sus_tests; }

# ── Sin tests derivables, la suite ENTERA. El default es el seguro ──
# Un fichero que ningún test nombra puede estar sin cubrir, o puede que su test
# lo ejercite sin nombrarlo. Correr cero tests en ese caso sería firmar una
# evidencia vacía — exactamente el gate mudo que §14.3 prohíbe.
_case_normal_sin_tests_corre_todo() {
  local A=add C=commit
  mkdir -p tools/tests
  printf 'x\n' > tools/tests/test_cualquiera.sh
  git "$A" -A
  git "$C" -qm base 2>/dev/null
  printf '#!/usr/bin/env bash\necho solo\n' > tools/huerfano.sh
  git "$A" tools/huerfano.sh
  _c --tests | grep -qx 'TODOS' || {
    echo "    un fichero sin tests que lo nombren no cayó en TODOS: $(_c --tests)"
    echo "    Correr cero tests firmaría una evidencia vacía."
    return 1; }
}
test_sin_tests_derivables_corre_la_suite_entera() { _c_sandbox _case_normal_sin_tests_corre_todo; }

# ── El fallback a TODOS es POR FICHERO, no sobre la unión ───────────
# Lo cazó el review. `DERIVADOS` se acumulaba como unión de todos los ficheros
# tocados, y el fallback solo miraba si esa unión quedaba vacía. Con un commit
# que toca A (tiene tests que lo nombran) y B (no tiene ninguno), la unión NO
# está vacía, así que se corrían los tests de A y se firmaba en verde habiendo
# verificado CERO de lo que B cambió. Y lo perverso: B commiteado SOLO sí caía
# en TODOS. El mismo fichero, cubierto o no según con quién viaje.
_case_un_fichero_sin_tests_arrastra_a_todos() {
  local A=add C=commit
  mkdir -p tools/tests
  printf '#!/usr/bin/env bash\necho a\n' > tools/con-tests.sh
  printf '#!/usr/bin/env bash\necho b\n' > tools/sin-tests.sh
  printf '# ejercita tools/con-tests.sh\ntest_x() { :; }\n' > tools/tests/test_con_tests.sh
  git "$A" -A
  git "$C" -qm base 2>/dev/null
  printf '#!/usr/bin/env bash\necho a2\n' > tools/con-tests.sh
  printf '#!/usr/bin/env bash\necho b2\n' > tools/sin-tests.sh
  git "$A" tools/con-tests.sh tools/sin-tests.sh
  _c --tests | grep -qx 'TODOS' || {
    echo "    un fichero SIN tests que lo nombren viajó con otro que sí, y no forzó TODOS:"
    _c --tests | sed 's/^/      /'
    echo "    Se firmaría en verde sin verificar nada de ese fichero."
    return 1; }
}
test_un_fichero_sin_tests_fuerza_la_suite_entera() {
  _c_sandbox _case_un_fichero_sin_tests_arrastra_a_todos
}

# ── En `--tests`, un exit 3 imprime TODOS, no su línea de resumen ───
# La otra mitad del mismo agujero. `carril.sh` imprimía `CARRIL_SUMMARY ...` en
# sus dos rutas de exit 3 sin mirar el modo, y el consumidor hacía
# `$(carril.sh --tests || echo TODOS)` — que CONCATENA en vez de reemplazar. El
# resultado era basura de dos líneas que caía en la rama de tests dirigidos,
# filtraba por "CARRIL_SUMMARY", no casaba nada, y `run-tests` sale 0 cuando un
# filtro no casa. Se firmaba en verde habiendo corrido CERO tests.
_case_exit3_en_modo_tests_dice_todos() {
  rm -f tools/carril.conf
  local out; out="$(bash tools/carril.sh --tests 2>/dev/null)"
  printf '%s' "$out" | grep -q 'CARRIL_SUMMARY' && {
    echo "    en --tests, el exit 3 imprimió su línea de resumen: $out"
    echo "    El consumidor la toma como nombre de test y no corre nada."
    return 1; }
  printf '%s' "$out" | grep -qx 'TODOS' || {
    echo "    en --tests, el exit 3 no dijo TODOS: [$out]"; return 1; }
}
test_en_modo_tests_el_exit3_pide_la_suite_entera() {
  _c_sandbox _case_exit3_en_modo_tests_dice_todos
}

# ── La definición de un agente NO es prosa ──────────────────────────
# `ligero|*.md` casaba `.claude/agents/reviewer.md`: el glob no distingue la
# prosa del PROMPT DEL PROPIO REVISOR. Reproducido con el clasificador real
# antes de arreglarlo: salía `ligero` → `NINGUNO`. Editar las instrucciones de
# quien revisa es tocar la maquinaria que decide qué se verifica (§6 del PRD
# 0011), igual que `.claude/settings.json`, que ya era estructural.
_case_definicion_de_agente_es_estructural() {
  _stage .claude/agents/reviewer.md
  _c | grep -q 'carril=estructural' || {
    echo "    el prompt del revisor salió como prosa: $(_c)"; return 1; }
}
test_la_definicion_de_un_agente_es_estructural() {
  _c_sandbox _case_definicion_de_agente_es_estructural
}

# ── Un fixture SÍ se ejecuta: lo consume un test ────────────────────
# Estaba en `ligero` — la tabla del PRD lo listaba así— pero `ligero` significa
# "nada que se ejecute", y un fixture es exactamente la entrada que un test
# interpreta. Con `ligero` no corría NINGÚN test: cambiar el dato con el que se
# afirma algo quedaba sin verificar. Cae a `normal`, donde la derivación por
# referencia encuentra justo los tests que lo NOMBRAN.
_case_fixture_no_es_ligero() {
  _stage tools/tests/fixtures/algo.json
  _c | grep -q 'carril=normal' || {
    echo "    un fixture no salió normal: $(_c)"; return 1; }
}
test_un_fixture_no_es_carril_ligero() { _c_sandbox _case_fixture_no_es_ligero; }
