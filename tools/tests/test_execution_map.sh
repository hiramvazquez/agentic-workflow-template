#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_execution_map.sh — tests de check-execution-map.sh
# ════════════════════════════════════════════════════════════════════
# El detector mide FRESCURA (dos fechas de commit), no semántica. Eso lo hace
# barato de acertar y barato de equivocar: el riesgo real no es que se le
# escape un mapa stale, es que dispare cuando no toca y alguien lo desactive
# (ley del 10%, AGENTS.md §14.2).
#
# Por eso la mitad de este archivo son FALSOS POSITIVOS explícitos. El MANIFEST
# de test_meta_fp.sh los exige el mismo día que el detector, no cuando alguien
# se queje — regla del PRD 0001, aprendida tres veces en carne propia.
#
# Cada caso corre en un repo git temporal con commits de verdad: la unidad que
# se prueba es "¿qué commit es más nuevo?", así que un sandbox sin historia no
# probaría nada.

# ── Sandbox: repo git nuevo con el detector dentro ───────────────────
_em_repo() { # _em_repo <función>
  local d rc; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process" "$d/backlog"
  cp "$PROJECT_ROOT/tools/check-execution-map.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    git config commit.gpgsign false 2>/dev/null
    "$1"
  ); rc=$?
  rm -rf "$d"
  return $rc
}

# Commits con timestamp CONTROLADO. Sin esto, dos commits seguidos comparten
# segundo y `-gt` es falso: el test pasaría o fallaría según lo rápido que vaya
# la máquina, que es la peor clase de test (lección del verde-en-Linux/rojo-en-macOS).
_em_commit() { # _em_commit <mensaje> <offset-en-segundos-desde-una-base-fija>
  local base=1700000000 ts
  ts=$((base + $2))
  GIT_AUTHOR_DATE="$ts +0000" GIT_COMMITTER_DATE="$ts +0000" \
    git commit -q -m "$1" --allow-empty
}

_em_mapa() { # _em_mapa <contenido>
  printf '%s\n' "$1" > docs/process/current_execution_map.md
}

# El template NO trae rutas de producto por defecto (es un FILL del adoptante),
# así que los casos las fijan por entorno. Rutas genéricas a propósito: este
# archivo viaja a proyectos de cualquier stack.
_em_run() { EXECUTION_MAP_PROD_DIRS="src/domain" bash tools/check-execution-map.sh 2>&1; }

# ════════════════════════════════════════════════════════════════════
# CASOS QUE DEBEN DISPARAR
# ════════════════════════════════════════════════════════════════════

_case_producto_mas_nuevo_que_el_mapa() {
  _em_mapa '# Mapa
## Estado actual
- Fase: lo que sea.'
  git add -A && _em_commit "docs: mapa" 100

  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  git add -A && _em_commit "feat: producto" 200

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    esperaba exit 1 (stale), obtuve $rc"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'EXECUTION_MAP_SUMMARY stale=1' \
    || { echo "    falta el contrato de stdout con stale=1"; return 1; }
}
test_producto_mas_nuevo_que_el_mapa_dispara() {
  _em_repo _case_producto_mas_nuevo_que_el_mapa
}

_case_historia_a_done_mas_nueva() {
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  _em_mapa '# Mapa
## Estado actual
- Fase: lo que sea.'
  git add -A && _em_commit "chore: base" 100

  printf -- '---\nid: 0003\nstatus: done\n---\n' > backlog/0003-algo.md
  git add -A && _em_commit "chore(backlog): 0003 a done" 300

  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    una historia a done después del mapa debería disparar (exit $rc)"; return 1; }
}
test_historia_a_done_despues_del_mapa_dispara() {
  _em_repo _case_historia_a_done_mas_nueva
}

_case_afirmacion_literal_desmentida() {
  # El mapa es lo MÁS reciente (frescura OK), pero afirma lo que el árbol
  # desmiente. Esta es la única aserción semántica del detector y va sola.
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  git add -A && _em_commit "feat: producto" 100

  _em_mapa '# Mapa
## Estado actual
- Fase: adopción completada; sin código de producto todavía.'
  git add -A && _em_commit "docs: mapa recién tocado" 400

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    el mapa es el más nuevo PERO miente: debía disparar (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'DESMENTID' \
    || { echo "    disparó, pero no por la aserción literal — el mensaje no la nombra"; return 1; }
}
test_afirmacion_literal_desmentida_por_el_arbol_dispara() {
  _em_repo _case_afirmacion_literal_desmentida
}

# ════════════════════════════════════════════════════════════════════
# FALSOS POSITIVOS — los casos que NO deben disparar
# ════════════════════════════════════════════════════════════════════

_case_solo_docs_no_dispara() {
  # El cambio más común del repo: tocar documentación. Si esto disparase, el
  # detector se comería cada commit de docs y duraría una semana encendido.
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  git add -A && _em_commit "chore: base" 100

  mkdir -p docs
  printf 'otra cosa\n' > docs/OTRO.md
  git add -A && _em_commit "docs: algo que no es el mapa" 500

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un commit solo-docs disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_cambio_solo_de_docs_no_dispara() {
  _em_repo _case_solo_docs_no_dispara
}

_case_producto_y_mapa_juntos_no_dispara() {
  # El camino feliz del paso 4.3: tocar producto Y el mapa en el MISMO commit.
  # Si esto disparase, el detector castigaría exactamente la conducta que
  # existe para fomentar — y no habría forma de ponerlo verde.
  _em_mapa '# Mapa
## Estado actual
- Fase: arrancando.'
  git add -A && _em_commit "docs: mapa" 100

  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha, capas cableadas.'
  git add -A && _em_commit "feat: producto + mapa al día" 600

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: producto y mapa en el mismo commit disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_producto_y_mapa_en_el_mismo_commit_no_dispara() {
  _em_repo _case_producto_y_mapa_juntos_no_dispara
}

_case_repo_sin_producto_no_dispara() {
  # Un proyecto recién adoptado: harness sí, producto no. Aquí "sin código de
  # producto" es VERDAD y el detector debe callarse — si no, el día 1 de todo
  # adoptante empieza en rojo, que es su propia lección (a8280d0 del template).
  _em_mapa '# Mapa
## Estado actual
- Fase: adopción del harness; sin código de producto todavía.'
  git add -A && _em_commit "docs: mapa" 100

  mkdir -p tools
  printf '# algo\n' > tools/OTRA.md
  git add -A && _em_commit "chore: tooling" 700

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: repo sin producto disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_repo_sin_producto_no_dispara() {
  _em_repo _case_repo_sin_producto_no_dispara
}

_case_historia_tocada_sin_pasar_a_done() {
  # Corregir una errata en una historia que sigue en `ready` no invalida el
  # mapa. El detector busca `status: done` en el árbol del commit, no
  # "cualquier toque a backlog/".
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  printf -- '---\nid: 0003\nstatus: ready\n---\n' > backlog/0003-algo.md
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  git add -A && _em_commit "chore: base" 100

  printf -- '---\nid: 0003\nstatus: ready\n---\nerrata corregida\n' > backlog/0003-algo.md
  git add -A && _em_commit "docs(backlog): errata" 800

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: tocar una historia en ready disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_historia_en_ready_tocada_no_dispara() {
  _em_repo _case_historia_tocada_sin_pasar_a_done
}

_case_tocar_backlog_con_un_done_previo() {
  # EL FALSO POSITIVO QUE SE COLÓ EN LA PRIMERA VERSIÓN. El detector buscaba
  # "el commit más reciente cuyo árbol tenga alguna historia en done" — que en
  # cuanto existe UNA historia done lo cumple cualquier commit que roce
  # backlog/. Degeneraba en "cualquier toque al directorio".
  #
  # El caso `test_fp_historia_en_ready_tocada_no_dispara` NO lo cazaba, porque
  # su sandbox no tiene ninguna historia done previa. La diferencia entre
  # ambos tests es justo esa línea, y es lo que separa un test que verifica de
  # uno que acompaña.
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  printf -- '---\nid: 0003\nstatus: done\n---\n' > backlog/0003-vieja.md
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  git add -A && _em_commit "chore: base con una historia YA en done" 100

  # Commit posterior que toca backlog/ SIN ninguna transición a done.
  printf -- '---\nid: 0004\nstatus: ready\n---\n' > backlog/0004-nueva.md
  git add -A && _em_commit "chore(backlog): historia nueva en ready" 900

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: tocar backlog/ con un done PREEXISTENTE disparó (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_tocar_backlog_con_una_historia_ya_done_no_dispara() {
  _em_repo _case_tocar_backlog_con_un_done_previo
}

_case_renombrar_una_historia_ya_done() {
  # Lo cazó el `reviewer` en la SEGUNDA pasada, sobre el fix de la primera:
  # comparar por RUTA hace que `git mv` de una historia ya done parezca una
  # transición nueva. Es una versión más estrecha del mismo falso positivo, y
  # el arreglo (comparar por id) solo se sostiene si esto tiene test.
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  printf -- '---\nid: 0003\nstatus: done\n---\n' > backlog/0003-nombre-viejo.md
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  git add -A && _em_commit "chore: base con 0003 en done" 100

  git mv backlog/0003-nombre-viejo.md backlog/0003-nombre-nuevo.md
  git add -A && _em_commit "chore(backlog): renombra 0003, sigue en done" 950

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: renombrar una historia YA done disparó (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_renombrar_una_historia_ya_done_no_dispara() {
  _em_repo _case_renombrar_una_historia_ya_done
}

_case_transicion_real_con_done_previo_si_dispara() {
  # La otra mitad: con un done preexistente, una transición REAL sí debe
  # disparar. Sin este test, "arreglar" el FP de arriba devolviendo siempre 0
  # pasaría inadvertido.
  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  printf -- '---\nid: 0003\nstatus: done\n---\n' > backlog/0003-vieja.md
  printf -- '---\nid: 0004\nstatus: ready\n---\n' > backlog/0004-nueva.md
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  git add -A && _em_commit "chore: base" 100

  printf -- '---\nid: 0004\nstatus: done\n---\n' > backlog/0004-nueva.md
  git add -A && _em_commit "chore(backlog): 0004 pasa a done" 950

  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    una transición REAL a done con otra ya done no disparó (exit $rc)"; return 1; }
}
test_transicion_real_a_done_con_otra_ya_done_si_dispara() {
  _em_repo _case_transicion_real_con_done_previo_si_dispara
}

_case_mapa_en_curso_no_bloquea_su_propio_arreglo() {
  # EL CASO QUE HACE ÚTIL AL DETECTOR EN VEZ DE INSATISFACIBLE. El paso 4.3
  # pide actualizar el mapa EN EL MISMO COMMIT que lo invalida. Como `git log`
  # solo ve historia commiteada, sin la escapatoria el mapa se mediría por su
  # commit VIEJO y el gate bloquearía justo el commit que lo arregla — el
  # deadlock literal de §14.3.
  _em_mapa '# Mapa
## Estado actual
- Fase: arrancando.'
  git add -A && _em_commit "docs: mapa" 100

  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  git add -A && _em_commit "feat: producto" 200

  # Sin tocar el mapa: stale, como debe.
  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    precondición rota: debería estar stale antes de arreglarlo (exit $rc)"; return 1; }

  # Ahora lo estoy arreglando, aún sin commitear.
  _em_mapa '# Mapa
## Estado actual
- Fase: producto en marcha.'
  local out; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    DEADLOCK: el mapa modificado sin commitear sigue bloqueando (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_mapa_modificado_sin_commitear_no_bloquea_su_arreglo() {
  _em_repo _case_mapa_en_curso_no_bloquea_su_propio_arreglo
}

_case_en_curso_no_exime_de_la_afirmacion_muerta() {
  # La escapatoria de arriba vale para la FRESCURA, no para la aserción
  # literal. Si estás editando el mapa y aun así dejas dentro la frase que el
  # árbol desmiente, eso no es "trabajo en curso": es el bug.
  _em_mapa '# Mapa
## Estado actual
- Fase: arrancando.'
  git add -A && _em_commit "docs: mapa" 100

  mkdir -p src/domain
  printf 'entidad\n' > src/domain/entidad.txt
  git add -A && _em_commit "feat: producto" 200

  _em_mapa '# Mapa
## Estado actual
- Fase: tocando el mapa pero sin código de producto todavía.'
  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    la escapatoria de 'en curso' silenció la aserción literal (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'DESMENTID' \
    || { echo "    disparó, pero no por la aserción literal"; return 1; }
}
test_en_curso_no_exime_de_la_afirmacion_desmentida() {
  _em_repo _case_en_curso_no_exime_de_la_afirmacion_muerta
}

# ════════════════════════════════════════════════════════════════════
# CIFRAS DERIVABLES — "N tests" / "N líneas" literales en el mapa
# ════════════════════════════════════════════════════════════════════
# Pasó de verdad (`f-wf02-mapa-cifras-podridas`): el mapa declaró "477 tests"
# con 522 funciones test_* en el árbol y "236 líneas" de contexto con 250
# medidas. Un literal no se recalcula solo, y este doc se inyecta con
# autoridad en cada arranque. La regla (PRD 0005 fase 0b): cifra derivable en
# doc vivo = mentira futura garantizada — se cita el comando que la imprime,
# no su salida de un día concreto.

_case_cifra_de_tests_dispara() {
  _em_mapa '# Mapa
## Estado actual
- Salud: suite verde (hay 999 tests).'
  git add -A && _em_commit "docs: mapa con conteo copiado" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    'hay 999 tests' en el mapa debía disparar (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'DERIVABLE' \
    || { echo "    disparó, pero el mensaje no nombra la clase del problema"; return 1; }
  printf '%s' "$out" | grep -q 'línea 3:' \
    || { echo "    el contrato pide NOMBRAR LA LÍNEA del claim (esperaba 'línea 3:')"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_cifra_derivable_de_tests_dispara_nombrando_la_linea() {
  _em_repo _case_cifra_de_tests_dispara
}

_case_cifra_de_lineas_dispara() {
  _em_mapa '# Mapa
## Estado actual
- Contexto: la rotación lo dejó en 236 líneas.'
  git add -A && _em_commit "docs: mapa con líneas copiadas" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    '236 líneas' en el mapa debía disparar (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'EXECUTION_MAP_SUMMARY stale=1' \
    || { echo "    falta el contrato de stdout con stale=1"; return 1; }
}
test_cifra_derivable_de_lineas_dispara() {
  _em_repo _case_cifra_de_lineas_dispara
}

_case_cifra_de_pruebas_dispara() {
  # El sinónimo con el que el propio PRD 0004 escribió sus conteos ("347
  # pruebas de regresión"): un detector de conteos podridos que no cubre la
  # palabra con la que YA se escribieron es evasión servida, no prudencia.
  _em_mapa '# Mapa
## Estado actual
- Salud: 522 pruebas en verde.'
  git add -A && _em_commit "docs: mapa" 100

  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    '522 pruebas' debía disparar (exit $rc)"; return 1; }
}
test_cifra_derivable_de_pruebas_dispara() {
  _em_repo _case_cifra_de_pruebas_dispara
}

_case_en_curso_no_exime_cifra() {
  # La escapatoria "lo estoy editando" vale para la FRESCURA, no para esto:
  # si el commit que estás preparando deja dentro un conteo copiado, ese
  # commit es exactamente el que el detector existe para parar — misma
  # doctrina que test_en_curso_no_exime_de_la_afirmacion_desmentida.
  _em_mapa '# Mapa
## Estado actual
- Fase: en marcha.'
  git add -A && _em_commit "docs: mapa limpio" 100

  _em_mapa '# Mapa
## Estado actual
- Salud: verde (hay 999 tests).'
  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    la escapatoria de 'en curso' silenció la cifra derivable (exit $rc)"; return 1; }
}
test_en_curso_no_exime_de_la_cifra_derivable() {
  _em_repo _case_en_curso_no_exime_cifra
}

_case_numeros_no_derivables_no_disparan() {
  # FALSO POSITIVO — la mina que este repo ya pisó varias veces y tiene
  # lección propia: el detector que se dispara con el texto que HABLA de la
  # cosa. Un mapa real está lleno de números que NO son conteos derivables:
  # fechas, ids de PRD, §, shas, mutantes de una verificación histórica, el
  # NOMBRE del test que fija el límite (contiene "250_lineas" con guion bajo)
  # y verbos que empiezan por "test" ("testea"). Ninguno puede disparar.
  _em_mapa '# Mapa
## Estado actual
- Fase: PRD 0004 §16 en ventana (2–4 semanas desde 2026-08-19).
- Verificación de fase 10: 11 mutantes sobre 61e3d06, cada uno rojo solo en su test.
- El límite lo fija test_contexto_vivo_obligatorio_cabe_en_250_lineas.
- La cifra real la imprime `bash tools/tests/run-tests.sh`; el escenario 10 testea el smoke.
- 30 runs macOS consecutivos sin rerun (gate de salida de la fase 0a).'
  git add -A && _em_commit "docs: mapa con números legítimos" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un número que no es conteo derivable disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_numeros_no_derivables_no_disparan() {
  _em_repo _case_numeros_no_derivables_no_disparan
}

# ════════════════════════════════════════════════════════════════════
# CONTRATO §14.3 — "no pude mirar" nunca es "no encontré nada"
# ════════════════════════════════════════════════════════════════════

test_sin_el_doc_devuelve_3_no_1() {
  _sin_doc() {
    mkdir -p Pelis/Domain
    printf 'struct Movie {}\n' > src/domain/entidad.txt
    git add -A && _em_commit "feat: producto" 100
    rm -f docs/process/current_execution_map.md
    local out rc; out="$(_em_run)"; rc=$?
    [ "$rc" = "3" ] || { echo "    sin el doc esperaba exit 3 (no pude mirar), obtuve $rc"; return 1; }
    printf '%s' "$out" | grep -q 'EXECUTION_MAP_SUMMARY stale=0' \
      || { echo "    exit 3 debe seguir imprimiendo el contrato con stale=0"; return 1; }
  }
  _em_repo _sin_doc
}

test_fuera_de_un_repo_git_devuelve_3() {
  local d rc; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/check-execution-map.sh" "$d/tools/"
  printf '# Mapa\n' > "$d/docs/process/current_execution_map.md"
  ( cd "$d" && bash tools/check-execution-map.sh >/dev/null 2>&1 ); rc=$?
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    fuera de un repo git esperaba exit 3, obtuve $rc"; return 1; }
}

test_la_ultima_linea_es_el_contrato_exacto() {
  # El resumen lo parsean humanos y CI. Si cambia de forma sin querer, esto lo
  # caza — misma disciplina que el resto de detectores del repo.
  _contrato() {
    _em_mapa '# Mapa'
    git add -A && _em_commit "docs: mapa" 100
    local ultima
    ultima="$(bash tools/check-execution-map.sh 2>/dev/null | tail -1)"
    case "$ultima" in
      "EXECUTION_MAP_SUMMARY stale=0"|"EXECUTION_MAP_SUMMARY stale=1") return 0 ;;
      *) echo "    última línea inesperada: '$ultima'"; return 1 ;;
    esac
  }
  _em_repo _contrato
}

test_el_detector_corre_limpio_contra_el_repo_real() {
  # El propio repo debe estar al día. Si esto falla, el mapa se quedó atrás de
  # verdad y hay que actualizarlo — no silenciar el test.
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/check-execution-map.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-execution-map falla contra el repo real (exit $rc):"
    printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; return 1; }
}
