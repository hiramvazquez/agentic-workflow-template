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

  local out rc; out="$(_em_run 2>&1)"; rc=$?
  # El ATRASO avisa, no bloquea (decisión de la V1): un commit de producto no
  # puede exigir editar un mapa que no guarda historia. Lo que sigue duro es
  # que el atraso se DETECTE y se DIGA.
  [ "$rc" = "0" ] || { echo "    el atraso bloqueó (exit $rc); debe avisar"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'atrasado=1' \
    || { echo "    el contrato de stdout no expone atrasado=1: $out"; return 1; }
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

  local out rc; out="$(_em_run 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q 'atrasado=1' \
    || { echo "    una historia a done después del mapa debería marcar atraso: $out"; return 1; }
  # Y NO debe bloquear. Sin esta línea, reintroducir el bloqueo SOLO en la rama
  # de `done` sobrevivía: `atrasado=1` sale igual bloquee o no. Lo cazó el review
  # con ese mutante exacto — `TS_PROD` y `TS_DONE` son dos ramas, y el test
  # dedicado del aviso solo ejercita la primera.
  [ "$rc" = "0" ] || { echo "    la rama de 'done' BLOQUEA (exit $rc); debe avisar"; return 1; }
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

  local out rc; out="$(_em_run 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q 'atrasado=1' \
    || { echo "    una transición REAL a done con otra ya done no marcó atraso: $out"; return 1; }
  [ "$rc" = "0" ] || { echo "    la rama de 'done' BLOQUEA (exit $rc); debe avisar"; return 1; }
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

  # Sin tocar el mapa: atrasado, como debe.
  local out; out="$(_em_run 2>&1)"
  printf '%s' "$out" | grep -q 'atrasado=1' \
    || { echo "    precondición rota: debería estar atrasado antes de arreglarlo: $out"; return 1; }

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
      "EXECUTION_MAP_SUMMARY stale="[01]" atrasado="[01]) return 0 ;;
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

# ════════════════════════════════════════════════════════════════════
# PRD 0005 fase 2b — ningún doc canónico recomienda `git add -A` a ciegas
# ════════════════════════════════════════════════════════════════════
# `f-wf08-git-add-A-canonico`: el mapa —que `session-start.sh` imprime en CADA
# arranque y `post-compact.sh` reinyecta tras cada compactación— recomendaba
# `git add -A && verify-run && commit` mientras AGENTS.md §7 prohíbe `-A` con
# cambios fuera de scope. No era un doc cualquiera contradiciendo la regla: era
# la puerta de entrada de cada sesión enseñando lo contrario de la norma, con
# más autoridad práctica que la norma.
#
# La precondición NO es una lista de negaciones (esa lista crece para siempre y
# el detector se vuelve un colador). Es concreta y sale del propio PRD: `-A`
# solo tiene sentido tras comprobar `git status`, así que se exige que `git
# status` o una prohibición explícita aparezcan en la MISMA línea o en una
# adyacente. Medido contra la doc real: 2 candidatos, 0 falsos positivos.
#
# Histórico EXCLUIDO a propósito — `lessons_archive`, `docs/process/reviews/`,
# los PRDs y el ledger renderizado NARRAN el problema y citarlo no es
# recomendarlo. Un detector que no distingue narrar de prescribir es el mismo
# falso positivo que este repo ya ha pisado siete veces.
_ADDA_PATRON='git add (-A|--all|\.)([[:space:]]|$|`|&|;)'
# Cuidado con el locale: la suite corre con LANG="" (locale C), y ahí una CLASE
# de caracteres como `[áa]` no es "á o a" — son los BYTES de `á` en UTF-8 más
# `a`, así que deja de casar lo que casaba en tu shell. El detector daba verde a
# mano y rojo en el runner por eso. Lo que NO falla en locale C es un LITERAL
# no-ASCII fuera de corchetes: `prohíb` casa "prohíbe" sin problema. De ahí que
# aquí convivan un stem ASCII y un literal acentuado, y no una clase.
#
# Y hace falta el literal: `prohib` a secas NO casa "prohíbe" —la forma
# conjugada, que es la que domina en este repo ("AGENTS.md §7 lo prohíbe")—
# porque exige una `i` ASCII donde el texto tiene `í`. Estuvo como rama muerta
# y lo cazó el reviewer: el comentario afirmaba cubrirla y era falso.
_ADDA_PRECOND='git status|[Jj]am|[Nn]unca|NUNCA|prohib|prohíb'
_ADDA_DOCS() {
  git ls-files '*.md' 2>/dev/null \
    | grep -vE 'lessons_archive|docs/process/reviews/|findings-ledger|docs/process/prds/'
}
_adda_infractores() {  # _adda_infractores <archivo>... → líneas sin precondición
  local f n ctx
  for f in "$@"; do
    [ -f "$f" ] || continue
    for n in $(grep -nE "$_ADDA_PATRON" "$f" 2>/dev/null | cut -d: -f1); do
      ctx="$(sed -n "$((n > 1 ? n - 1 : 1)),$((n + 1))p" "$f" 2>/dev/null)"
      printf '%s\n' "$ctx" | grep -qE "$_ADDA_PRECOND" && continue
      echo "$f:$n"
    done
  done
}

test_ningun_doc_canonico_recomienda_git_add_A_a_ciegas() {
  local malos; malos="$(_adda_infractores $(_ADDA_DOCS))"
  [ -z "$malos" ] || {
    echo "    recomiendan 'git add -A' sin precondición:"
    printf '%s\n' "$malos" | sed 's/^/      /'
    echo "    AGENTS.md §7 lo prohíbe con cambios fuera de scope. Stagea por paths,"
    echo "    o menciona 'git status' como precondición en la línea o su vecina."
    return 1; }
}

# FALSO POSITIVO: narrar no es prescribir. Los tres literales de abajo son
# formas legítimas que una versión ingenua del patrón marcaría.
test_narrar_git_add_A_no_cuenta_como_recomendarlo() {
  local d rc=0; d="$(mktemp -d)" || return 1
  # Cada caso en SU PROPIO archivo. Juntos, la ventana de ±1 línea hace que el
  # vecino de al lado satisfaga la precondición y el caso deja de probar lo
  # suyo — pasó: con los cuatro en un archivo, quitar `prohíb` del patrón no
  # ponía rojo nada, porque la línea siguiente traía un `git status`.
  printf '%s\n' '- Jamás `git add -A` con cambios fuera de scope.'          > "$d/1.md"
  printf '%s\n' 'Usa `git add -A` solo si `git status --short` sale limpio.' > "$d/2.md"
  printf '%s\n' 'Este doc prohíbe usar `git add -A` a ciegas.'              > "$d/3.md"
  printf '%s\n' 'Nunca uses `git add -A` aquí.'                             > "$d/4.md"
  # 5 y 6 existen porque el reviewer aplicó a este patrón el mismo criterio que
  # yo le pedí: quitó cada alternativa por separado y `NUNCA` y `prohib` no
  # mataban ningún test. Una rama que nadie ejercita es decoración — y encima
  # estas dos son las que NO cubren sus vecinas (`[Nn]unca` no casa mayúsculas;
  # `prohíb` no casa la forma sin acento). O se ejercitan o se retiran.
  printf '%s\n' 'NUNCA uses `git add -A` en este repo.'                     > "$d/5.md"
  printf '%s\n' 'Está prohibido hacer `git add -A` sin revisar.'            > "$d/6.md"
  local f malos
  for f in "$d"/1.md "$d"/2.md "$d"/3.md "$d"/4.md "$d"/5.md "$d"/6.md; do
    malos="$(_adda_infractores "$f")"
    [ -z "$malos" ] || {
      echo "    FALSO POSITIVO en $(basename "$f"): prosa que NOMBRA -A contó como recomendación"
      sed 's/^/      /' "$f"; rc=1; }
  done
  rm -rf "$d"; return $rc
}

# Y el otro lado: una recomendación de verdad SÍ se caza.
test_una_recomendacion_real_de_git_add_A_se_caza() {
  local d; d="$(mktemp -d)" || return 1
  printf '%s\n' 'Para cerrar el cambio:' '' '```bash' \
    'git add -A && git commit -m "listo"' '```' > "$d/doc.md"
  local malos; malos="$(_adda_infractores "$d/doc.md")"
  rm -rf "$d"
  [ -n "$malos" ] || { echo "    FALSO NEGATIVO: una recomendación real de -A pasó"; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# AFIRMACIONES DE ESTADO — "aún no ha corrido nunca" y sus cuatro primas
# ════════════════════════════════════════════════════════════════════
# El incidente: en un adoptante real el mapa afirmaba que `gates.yml` "aún no
# ha corrido nunca". Había corrido y pasado TRES veces. Dos agentes seguidos se
# lo repitieron al owner como cierto — porque este doc se inyecta con autoridad
# en cada arranque y nadie recomprueba un doc que se presenta como estado.
#
# Las cifras derivables no lo cazaban por CLASE, no por cobertura: la frase no
# lleva ningún número. Es una afirmación de estado, y el estado se pudre igual
# que un conteo — peor, porque nada en su forma delata que caducó.
#
# ⚠️ ESTE ES EL CHEQUEO MÁS FÁCIL DE CONVERTIR EN RUIDO de todo el detector, y
# por eso la mitad de estos tests son falsos positivos. La ley del 10% (§14.2)
# no es un consejo: `check-version-claims.sh` ya murió en este repo al 67% de FP
# contra prosa española. Medido hoy contra el mapa real: 0 hits.

_case_estado_sin_evidencia_dispara() {
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** gates.yml aún no ha corrido nunca contra un push real.'
  git add -A && _em_commit "docs: mapa con afirmación de estado desnuda" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    la frase EXACTA del incidente no disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'AFIRMACIONES DE ESTADO SIN EVIDENCIA' \
    || { echo "    disparó, pero el mensaje no nombra la clase del problema"; return 1; }
  printf '%s' "$out" | grep -q 'línea 3:' \
    || { echo "    el contrato pide NOMBRAR LA LÍNEA (esperaba 'línea 3:')"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_afirmacion_de_estado_sin_evidencia_dispara() {
  _em_repo _case_estado_sin_evidencia_dispara
}

_case_estado_con_comando_no_dispara() {
  # FALSO POSITIVO CRÍTICO: la misma frase, redimida por el comando que la
  # comprueba. Si esto disparase, el detector castigaría exactamente la
  # conducta que existe para fomentar y no habría forma de ponerlo verde.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** gates.yml aún no ha corrido nunca (`bash tools/check-ring3.sh`).'
  git add -A && _em_commit "docs: mapa con evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: una afirmación CON su comando disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_afirmacion_de_estado_con_comando_no_dispara() {
  _em_repo _case_estado_con_comando_no_dispara
}

_case_evidencia_en_linea_vecina_no_dispara() {
  # FALSO POSITIVO POR DISEÑO SI SE EXIGIERA "la misma línea": este mapa es
  # markdown que ENVUELVE a ~100 columnas, así que el claim cae en una línea y
  # el comando que lo respalda en la siguiente. Exigir la misma línea convierte
  # un salto de párrafo en un fallo. La ventana de ±1 es la MISMA que ya usa
  # `_adda_infractores` en este archivo, contra esta misma prosa.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** gates.yml aún no ha corrido nunca contra un push real, lo
  comprueba `bash tools/check-ring3.sh` en cada arranque de sesión.'
  git add -A && _em_commit "docs: mapa con evidencia envuelta" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: la evidencia en la línea vecina no contó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_evidencia_en_la_linea_vecina_no_dispara() {
  _em_repo _case_evidencia_en_linea_vecina_no_dispara
}

_case_marcador_verificado_redime() {
  # La segunda salida, para lo que NINGÚN comando resuelve. Sin ella el
  # detector sería insatisfacible para afirmaciones legítimas que solo un
  # humano puede comprobar, y un gate insatisfacible se desactiva entero.
  _em_mapa '# Mapa
## Estado actual
- El runner de mutación sigue sin existir. <!-- verificado: no hay runner de mutación para bash, 2026-08-28 -->'
  git add -A && _em_commit "docs: mapa con marcador" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: el marcador <!-- verificado: --> no redimió (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_marcador_verificado_redime_la_afirmacion() {
  _em_repo _case_marcador_verificado_redime
}

# ── LA LISTA ES DE CINCO. Ampliarla es una DECISIÓN, no una pendiente ──
# Este es el test que impide la pendiente resbaladiza. Cada fórmula que se
# añada baja la precisión y sube el riesgo de que alguien desactive el detector
# entero (§14.2). Que ampliar la lista OBLIGUE a tocar este test es el punto:
# convierte un `+1 alternativa` descuidado en una decisión con revisor.
#
# Ocho ALTERNATIVAS, cinco FÓRMULAS: tres llevan variante sin tilde porque la
# suite corre en locale C, donde una clase `[íi]` no casa lo que parece (ver el
# comentario de _ADDA_PRECOND, misma mina). Literales, nunca clases.
_STATE_ERE_ESPERADA='nunca ha|aún no|aun no|todavía no|todavia no|(^|[^[:alpha:]])sigue sin|es lo único que queda|es lo unico que queda'

_state_ere_real() {
  sed -n 's/^STATE_ERE="\${EXECUTION_MAP_STATE_ERE:-\(.*\)}"$/\1/p' \
    "$PROJECT_ROOT/tools/check-execution-map.sh"
}

test_fp_la_lista_de_formulas_es_exactamente_cinco() {
  local real; real="$(_state_ere_real)"
  [ -n "$real" ] || { echo "    no encuentro el default de STATE_ERE en check-execution-map.sh"; return 1; }
  [ "$real" = "$_STATE_ERE_ESPERADA" ] || {
    echo "    la lista de fórmulas CAMBIÓ. Esto no es un fallo: es la pregunta."
    echo "      esperada: $_STATE_ERE_ESPERADA"
    echo "      real:     $real"
    echo "    Si la ampliaste a propósito, mide primero los hits contra el mapa real"
    echo "    (\`grep -inE \"<la nueva ERE>\" docs/process/current_execution_map.md\`) y"
    echo "    actualiza _STATE_ERE_ESPERADA. Si pasa de ~5 hits legítimos, la fórmula"
    echo "    nueva es ruido y §14.2 dice que se descarta el detector entero, no la fila."
    return 1; }
  # Y que sigan siendo CINCO conceptos: 8 alternativas, 3 con variante de tilde.
  # Se quita primero el grupo de frontera de `sigue sin` —lleva un `|` dentro
  # que no separa fórmulas— o el conteo mediría la sintaxis en vez de la lista.
  local alts; alts="$(printf '%s' "$real" | sed 's/(\^|\[\^\[:alpha:\]\])//g' | tr '|' '\n' | grep -c .)"
  [ "$alts" = "8" ] || { echo "    esperaba 8 alternativas (5 fórmulas, 3 con variante sin tilde), hay $alts"; return 1; }
}

# ── Y cada una de las cinco se EJERCITA: sin esto son ramas decorativas ──
# El `reviewer` aplicó este criterio a `_ADDA_PRECOND` y encontró alternativas
# que no mataban ningún test. Una rama que nadie ejercita es decoración: o se
# prueba o se retira. Cada fórmula va en SU archivo/línea, sin vecinas que la
# rediman por la ventana de ±1.
test_las_cinco_formulas_disparan_cada_una() {
  local d rc=0 f n=0; d="$(mktemp -d)" || return 1
  local formulas=(
    'El gate nunca ha corrido en este repo.'
    'La fase 3 aún no está cerrada.'
    'El runner todavía no existe.'
    'El nivel 4 sigue sin cablear.'
    'Cablear el runner es lo único que queda.'
  )
  for f in "${formulas[@]}"; do
    n=$((n + 1))
    printf '# Mapa\n%s\n' "$f" > "$d/m$n.md"
    EXECUTION_MAP_DOC="$d/m$n.md" bash "$PROJECT_ROOT/tools/check-execution-map.sh" >/dev/null 2>&1
    [ "$?" = "1" ] || { echo "    la fórmula #$n NO disparó — rama muerta: $f"; rc=1; }
  done
  rm -rf "$d"; return $rc
}

_case_fp_prosa_legitima_del_mapa() {
  # FALSOS POSITIVOS reales, sacados del mapa de este repo y de prosa de
  # planificación normal. Ninguno afirma que algo no haya ocurrido:
  #   · "Lo que NO hacemos todavía" — el ENCABEZADO real del mapa (línea 209).
  #     Es una declaración de alcance diferido, no un hecho comprobable. No casa
  #     porque la fórmula exige el "no" DETRÁS ("todavía no"), y aquí va delante.
  #   · "falta" / "pendiente" / "no está" — deliberadamente FUERA de la lista:
  #     son el vocabulario normal de cualquier plan y meterlas es el 67% de FP.
  #   · "nunca demuestra" — el mapa ya lo usa (línea 59) y no es "nunca ha".
  _em_mapa '# Mapa
## Estado actual
- Fase: en marcha; falta cablear el nivel 4 y queda pendiente la fase 3.
- Un grep que no encuentra la grafía **nunca demuestra que algo no exista**.
- El PRD 0004 no está cerrado; la ventana sigue abierta.

## Lo que NO hacemos todavía (explícito)
- Fuzzing, métodos formales, SBOM.'
  git add -A && _em_commit "docs: mapa con prosa legítima" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: prosa legítima del mapa real disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_prosa_legitima_de_planificacion_no_dispara() {
  _em_repo _case_fp_prosa_legitima_del_mapa
}

test_el_mapa_real_no_tiene_afirmaciones_de_estado_desnudas() {
  # El propio repo debe estar limpio. Si esto falla, el mapa tiene una
  # afirmación de estado sin evidencia — se arregla el mapa, no el test.
  # Es además la medida de RUIDO en vivo: 0 hits el día que se escribió.
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/check-execution-map.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-execution-map falla contra el mapa real (exit $rc):"
    printf '%s\n' "$out" | tail -12 | sed 's/^/      /'; return 1; }
}

# ── REGRESIÓN: un mapa SIN historia de commits no salta el contenido ──
# Agujero PREEXISTENTE cazado por la prueba de bolsillo de esta tanda: con
# `TS_MAP` vacío el detector hacía `exit 0` y se saltaba TAMBIÉN las aserciones
# de contenido (frases muertas, cifras derivables y estas afirmaciones), que no
# dependen de la historia de git para nada.
#
# No era teórico: es exactamente el caso de un adoptante recién clonado, cuyo
# mapa aún no tiene commit propio. El detector le daba verde a un mapa que
# podía afirmar cualquier cosa — un gate que no puede mirar la FRESCURA no es
# un gate que no pueda mirar NADA (§14.3).
test_mapa_sin_historia_no_salta_las_aserciones_de_contenido() {
  local d rc=0; d="$(mktemp -d)" || return 1
  printf '# Mapa\n- Salud: verde (hay 999 tests).\n' > "$d/sin-historia.md"
  EXECUTION_MAP_DOC="$d/sin-historia.md" bash "$PROJECT_ROOT/tools/check-execution-map.sh" >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una cifra derivable en un mapa sin commits NO disparó"; rc=1; }

  printf '# Mapa\n- gates.yml aún no ha corrido nunca.\n' > "$d/estado.md"
  EXECUTION_MAP_DOC="$d/estado.md" bash "$PROJECT_ROOT/tools/check-execution-map.sh" >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una afirmación de estado en un mapa sin commits NO disparó"; rc=1; }

  printf '# Mapa\n- Fase: en marcha, todo cableado.\n' > "$d/limpio.md"
  EXECUTION_MAP_DOC="$d/limpio.md" bash "$PROJECT_ROOT/tools/check-execution-map.sh" >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    y el otro lado: un mapa sin commits y LIMPIO debe dar 0"; rc=1; }
  rm -rf "$d"; return $rc
}

_case_fp_sigue_sin_dentro_de_otra_palabra() {
  # LO CAZÓ EL `reviewer` sobre el diff de esta misma tanda, y es la lección
  # entera de §14.2 en una línea: yo había medido "0 hits" y era verdad, pero
  # contra un corpus de UNO (el mapa de hoy). Un literal sin frontera de palabra
  # no falla en el corpus que miraste; falla en la frase que alguien escribirá
  # mañana. `sigue sin` casa dentro de conSIGUE SIN, proSIGUE SIN, perSIGUE SIN
  # — todas prosa de progreso legítima.
  _em_mapa '# Mapa
## Estado actual
- El pipeline consigue sin reintentos pasar los gates.
- La suite prosigue sin fallos desde el martes.
- El detector persigue sin descanso los falsos positivos.'
  git add -A && _em_commit "docs: mapa con verbos en -sigue" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: 'sigue sin' casó dentro de otra palabra (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_sigue_sin_dentro_de_otra_palabra_no_dispara() {
  _em_repo _case_fp_sigue_sin_dentro_de_otra_palabra
}

_case_sigue_sin_de_verdad_si_dispara() {
  # El otro lado de la frontera: arreglar el FP poniendo una frontera que
  # tampoco deje pasar el caso REAL sería cambiar un fallo por otro peor.
  _em_mapa '# Mapa
## Estado actual
- El nivel 4 sigue sin cablear.'
  git add -A && _em_commit "docs: mapa" 100
  local rc; _em_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    la frontera de palabra silenció el caso REAL de 'sigue sin' (exit $rc)"; return 1; }
}
test_sigue_sin_al_principio_de_palabra_si_dispara() {
  _em_repo _case_sigue_sin_de_verdad_si_dispara
}

# ════════════════════════════════════════════════════════════════════
# La evidencia tiene que ser un COMANDO, no cualquier cosa entrecomillada
# ════════════════════════════════════════════════════════════════════
# Falso NEGATIVO encontrado en la primera pasada del detector sobre un repo
# adoptante real, y reproducido por tres sesiones distintas. `EVIDENCIA_ERE`
# aceptaba cualquier `` `...` ``, así que un identificador que hablaba de OTRA
# cosa excusaba la afirmación vecina. En el mapa real eso dejó pasar la MISMA
# frase falsa que sí se cazó doce líneas más abajo: el gate quedó
# probabilístico, que es peor que ausente — da sensación de cobertura donde no
# la hay, y es literalmente «un gate que no corrió pareciendo uno que pasó».
#
# No viola la ley del 10% (es falso negativo, no positivo), pero sí rompe la
# intención declarada en la cabecera del script: lo que redime una afirmación
# es «un COMANDO que quien lo lea puede recomprobar en 2 segundos».
#
# ⚠️ El arreglo evidente NO funciona, y hay un test para ello: exigir el
# backtick en la MISMA línea deja pasar el caso `gates.yml`, que es la forma
# más natural de escribir la frase. Lo que hay que mirar es el CONTENIDO.

_case_backtick_ajeno_en_la_vecina_no_redime() {
  # EL CASO REAL. El backtick de la línea de arriba habla del rango del scan de
  # secretos, no de la afirmación de abajo.
  _em_mapa '# Mapa
## Estado actual
- El rango sale de `github.event.before`, no de `origin/main`.
- **Anillo 3:** gates.yml aún no ha corrido nunca contra un push real.'
  git add -A && _em_commit "docs: backtick ajeno en la linea vecina" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un backtick que habla de OTRA cosa redimió la afirmación (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_backtick_ajeno_no_cuenta_como_evidencia() {
  _em_repo _case_backtick_ajeno_en_la_vecina_no_redime
}

_case_nombre_de_fichero_en_la_misma_linea_no_redime() {
  # EL CASO QUE MATA EL ARREGLO SIMPLE. Aquí el backtick está en la MISMA
  # línea, así que exigir "misma línea" no lo cazaría — y `gates.yml` no es
  # algo que nadie pueda ejecutar para comprobar nada.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca el workflow `gates.yml` sobre este repo.'
  git add -A && _em_commit "docs: nombre de fichero como falsa evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un nombre de fichero entre backticks se contó como evidencia (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_nombre_de_fichero_no_cuenta_como_evidencia() {
  _em_repo _case_nombre_de_fichero_en_la_misma_linea_no_redime
}

_case_ruta_sin_comando_no_redime() {
  # El falso positivo que acecha al apretar: `tools/` como prefijo permitido
  # casaría `tools/preset`, que es un ARCHIVO DE CONFIGURACIÓN, no un comando.
  _em_mapa '# Mapa
## Estado actual
- **Preset:** el modo estricto aún no ha entrado, según `tools/preset`.'
  git add -A && _em_commit "docs: ruta de config como falsa evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    una ruta de configuración se contó como comando (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_ruta_de_config_no_cuenta_como_comando() {
  _em_repo _case_ruta_sin_comando_no_redime
}

_case_palabra_que_empieza_por_gh_no_redime() {
  # El otro falso positivo del apretón: `gh` como prefijo casa `ghost`.
  _em_mapa '# Mapa
## Estado actual
- **Modo:** el proceso aún no ha corrido nunca en modo `ghost`.'
  git add -A && _em_commit "docs: palabra que empieza por gh" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    'ghost' se contó como el comando 'gh' (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_palabra_que_empieza_por_gh_no_es_el_comando_gh() {
  _em_repo _case_palabra_que_empieza_por_gh_no_redime
}

_case_comando_de_una_sola_palabra_con_sh_redime() {
  # La otra mitad: un script invocable SÍ es evidencia aunque no lleve espacio.
  # Sin este test, apretar hasta "exigir un espacio" rompería un caso legítimo.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; lo comprueba `tools/check-ring3.sh`.'
  git add -A && _em_commit "docs: script invocable como evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: un script .sh invocable no contó como evidencia (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_un_script_sh_sin_espacios_sigue_siendo_evidencia() {
  _em_repo _case_comando_de_una_sola_palabra_con_sh_redime
}

_case_prosa_entre_backticks_no_es_comando() {
  # LO QUE SE ME ESCAPÓ EN LA PRIMERA VERSIÓN, y lo cazó el reviewer. La regla
  # era "que lleve un espacio", así que cualquier frase entrecomillada contaba.
  # El caso que lo retrata: una cita que dice literalmente "sin verificar aún"
  # se aceptaba como su propia evidencia. Mis cuatro casos de prueba eran todos
  # de UNA palabra, así que ninguno tocaba esta variante.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca (`sin verificar aun`).'
  git add -A && _em_commit "docs: prosa entre backticks como falsa evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    una frase de prosa entre backticks se contó como comando (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_prosa_entre_backticks_no_es_evidencia() {
  _em_repo _case_prosa_entre_backticks_no_es_comando
}

_case_nombre_propio_entre_backticks_no_es_comando() {
  # La otra forma del mismo FN: una atribución a una persona. Lleva espacios y
  # comas, y no es nada que nadie pueda ejecutar.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca, según `Juan Perez, el owner`.'
  git add -A && _em_commit "docs: atribucion como falsa evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    una atribución a una persona se contó como comando (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_atribucion_a_una_persona_no_es_evidencia() {
  _em_repo _case_nombre_propio_entre_backticks_no_es_comando
}

_case_comando_con_flags_sigue_siendo_evidencia() {
  # La otra mitad, para que apretar no rompa lo legítimo: un comando de verdad
  # con flags, cuyo primer token es un programa conocido y NO acaba en .sh.
  _em_mapa '# Mapa
## Estado actual
- **CI:** aún no ha corrido nunca; el estado real sale de `gh run list --limit 5`.'
  git add -A && _em_commit "docs: comando con flags como evidencia" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: un comando real con flags no contó como evidencia (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_un_comando_con_flags_sigue_siendo_evidencia() {
  _em_repo _case_comando_con_flags_sigue_siendo_evidencia
}

_case_palabra_espanola_que_es_binario_no_cuela() {
  # SEGUNDA LECCIÓN del reviewer sobre el mismo bug. Media lista de programas
  # son palabras corrientes en español: `cargo`, `task`, `make`, `just`, `go`.
  # Mirar solo el primer token dejaba pasar `cargo de responsabilidad` como si
  # fuera Rust. Por eso además se exige forma de invocación (`/`, `.` o `-`).
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; es `cargo de responsabilidad` del owner.'
  git add -A && _em_commit "docs: palabra espanola que coincide con un binario" 100

  local out rc; out="$(_em_run)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    'cargo de responsabilidad' se contó como el comando de Rust (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_palabra_espanola_que_coincide_con_un_binario_no_es_comando() {
  _em_repo _case_palabra_espanola_que_es_binario_no_cuela
}

_case_comandos_de_entorno_se_suman_no_sustituyen() {
  # `EXECUTION_MAP_COMANDOS` AMPLÍA la lista de fábrica. La primera versión
  # usaba `${VAR:-default}` y la sustituía: un adoptante que añadiera su
  # lanzador perdía `bash`, `git`, `gh`… en silencio, y toda su evidencia
  # legítima pasaba a marcarse. El comentario prometía lo contrario del código.
  _em_mapa '# Mapa
## Estado actual
- **CI:** aún no ha corrido nunca; se comprueba con `gh run list --limit 5`.'
  git add -A && _em_commit "docs: evidencia con un comando de fabrica" 100

  local rc
  EXECUTION_MAP_PROD_DIRS="src/domain" EXECUTION_MAP_COMANDOS="lein" \
    bash tools/check-execution-map.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    añadir un lanzador propio DESACTIVÓ los de fábrica (exit $rc)"; return 1; }
}
test_los_comandos_de_entorno_amplian_la_lista_de_fabrica() {
  _em_repo _case_comandos_de_entorno_se_suman_no_sustituyen
}

_case_un_sh_inventado_cuenta_igual() {
  # LÍMITE DECLARADO, con test para que esté escrito y no se descubra por
  # sorpresa: un token que acaba en `.sh` cuenta como evidencia SIN comprobar
  # que el script exista. Requiere inventarse un nombre a propósito —no es una
  # colisión accidental como los casos de arriba— y comprobar la existencia
  # obligaría a resolver rutas relativas al repo, que rompería las citas a
  # scripts de otros repos. Si algún día se aprieta, este test debe caer con su
  # justificación al lado.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; lo mira `guion-que-no-existe.sh`.'
  git add -A && _em_commit "docs: script inexistente como evidencia" 100

  local rc; _em_run >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    el límite declarado cambió: un .sh inexistente ya NO cuenta (exit $rc)"; return 1; }
}
test_un_script_sh_inexistente_cuenta_a_proposito() {
  _em_repo _case_un_sh_inventado_cuenta_igual
}

_case_prosa_con_puntuacion_suelta_no_cuela() {
  # LOS CUATRO REPROS DE LA TERCERA PASADA. La versión anterior exigía `/`, `.`
  # o `-` en el SPAN ENTERO, así que cualquier puntuación en cualquier parte de
  # la frase la redimía: bastaba un "de-facto" o un "v2.0". Ahora se miran los
  # ARGUMENTOS: un comando trae una ruta o un flag; una frase trae preposiciones.
  local frases='cargo de la tarea de-facto listo|task de v2.0 pendiente|just revisando el punto 4.1|make del reporte semanal, ver 2.1'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: prosa con puntuacion suelta" 100 >/dev/null 2>&1

    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] \
      || { echo "    '$frase' se contó como comando (exit $rc)"; return 1; }
  done
}
test_prosa_con_puntuacion_suelta_no_es_comando() {
  _em_repo _case_prosa_con_puntuacion_suelta_no_cuela
}

_case_comando_pelado_si_cuenta_ahora() {
  # ESTE TEST CAMBIÓ DE SIGNO, y queda la razón escrita porque la versión
  # anterior afirmaba lo contrario.
  #
  # Cuando la regla exigía "programa conocido + un argumento con forma de ruta o
  # flag", un `make` pelado no contaba, y eso se declaró como límite aceptado.
  # Esa regla se cayó: la puntuación que usaba para decidir aparece en prosa
  # técnica constantemente (`cargo asignado el 12/03` colaba por la fecha).
  #
  # La regla nueva detecta PROSA por sus palabras función en vez de detectar
  # comandos por su puntuación, y con ella un programa pelado ya no se distingue
  # de `git status` — que el reviewer señaló, con razón, que estaba siendo
  # rechazado siendo evidencia legítima.
  #
  # Se acepta el cambio a sabiendas: `make` a secas es evidencia DÉBIL (no dice
  # qué comprobar), pero rechazarlo exigía la regla que ya falló dos veces. Se
  # prefiere una regla simple y sin fugas a una precisa y porosa.
  _em_mapa '# Mapa
## Estado actual
- **Build:** aún no ha corrido nunca; se lanza con `make`.'
  git add -A && _em_commit "docs: comando pelado" 100

  local rc; _em_run >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    un programa conocido pelado dejó de contar como evidencia (exit $rc)"; return 1; }
}
test_un_comando_pelado_cuenta_como_evidencia() {
  _em_repo _case_comando_pelado_si_cuenta_ahora
}

_case_espacios_iniciales_fallan_cerrado() {
  # LÍMITE DECLARADO (H4 de la segunda pasada). `${1%% *}` con un espacio
  # inicial deja el primer token VACÍO, así que el span no casa nada y no cuenta
  # como evidencia. Falla cerrado, que es la dirección segura — pero estaba solo
  # dicho en prosa y §10 pide que un límite conocido esté fijado o registrado,
  # no mencionado. Aquí queda fijado.
  _em_mapa '# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; ver ` bash tools/check-ring3.sh`.'
  git add -A && _em_commit "docs: evidencia con espacio inicial" 100

  local rc; _em_run >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un span con espacio inicial dejó de fallar cerrado (exit $rc)"; return 1; }
}
test_un_span_con_espacio_inicial_falla_cerrado() {
  _em_repo _case_espacios_iniciales_fallan_cerrado
}

_case_repros_de_la_cuarta_pasada() {
  # Los cuatro casos que tumbaron la v4: prosa con fecha, versión, guion suelto
  # y palabra compuesta. Todos empiezan por un binario de la lista y todos
  # traían la puntuación que la v4 usaba para redimir.
  local frases='cargo asignado el 12/03, aun pendiente|task pendiente para el 12/03 revisar|go y venga sin problema -especial|make -alguna nota rara sobre esto'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: repro de la cuarta pasada" 100 >/dev/null 2>&1
    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] || { echo "    '$frase' se contó como comando (exit $rc)"; return 1; }
  done
}
test_los_repros_de_la_cuarta_pasada_no_cuelan() {
  _em_repo _case_repros_de_la_cuarta_pasada
}

_case_comando_con_argumento_simple_cuenta() {
  # El falso POSITIVO que señaló el reviewer en la v4: `git status` y compañía
  # eran evidencia legítima y quedaban rechazados por no traer ruta ni flag.
  _em_mapa '# Mapa
## Estado actual
- **Árbol:** aún no ha corrido nunca la limpieza; se ve con `git status`.'
  git add -A && _em_commit "docs: comando con argumento simple" 100
  local rc; _em_run >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: 'git status' no contó como evidencia (exit $rc)"; return 1; }
}
test_fp_un_comando_con_argumento_simple_cuenta() {
  _em_repo _case_comando_con_argumento_simple_cuenta
}

_case_prosa_con_tildes_correctas_no_cuela() {
  # EL SEXTO AGUJERO, y el más vergonzoso porque el arreglo ya estaba escrito 80
  # líneas más arriba: `STATE_ERE` duplica cada literal acentuado con su gemelo
  # sin tilde porque la suite corre en locale C y `tr` no toca diacríticos. La
  # lista de palabras función nació solo con las formas SIN tilde —o sea, las
  # incorrectas— así que una frase escrita en español correcto no traía ninguna
  # palabra "reconocida" y pasaba entera como comando.
  local frases='cargo revision pendiente aún|task de más adelante según el owner|make revisión todavía sin cerrar'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: prosa con tildes correctas" 100 >/dev/null 2>&1
    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] || { echo "    '$frase' coló por llevar la tilde correcta (exit $rc)"; return 1; }
  done
}
test_la_prosa_con_tildes_correctas_no_cuela() {
  _em_repo _case_prosa_con_tildes_correctas_no_cuela
}

_case_valores_y_subcomandos_no_son_prosa() {
  # LA CARA OPUESTA, también del reviewer: `no`, `es` y `ver` son palabras
  # función Y valores reales de comandos. Estaban en la lista y rechazaban
  # evidencia legítima. Se sacaron a sabiendas; esto lo fija.
  local frases='git config core.autocrlf no|npm run ver|git checkout es'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; se ve con \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: comando con valor que parece palabra funcion" 100 >/dev/null 2>&1
    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: '$frase' se rechazó como prosa (exit $rc)"; return 1; }
  done
}
test_fp_valores_de_comando_que_parecen_palabras_funcion() {
  _em_repo _case_valores_y_subcomandos_no_son_prosa
}

_case_estar_delata_prosa() {
  # El olvido más caro posible en un detector de afirmaciones de ESTADO: la
  # primera lista llevaba el demostrativo `esta` pero ninguna forma del verbo
  # ESTAR. Y "X está pendiente / estaba sin cerrar" es literalmente cómo este
  # mapa describe lo que le falta.
  local frases='cargo está pendiente|git están fallando|npm estaba roto|cargo estará listo'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: prosa con el verbo estar" 100 >/dev/null 2>&1
    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] || { echo "    '$frase' coló: el verbo estar no delata prosa (exit $rc)"; return 1; }
  done
}
test_el_verbo_estar_delata_prosa() {
  _em_repo _case_estar_delata_prosa
}

_case_ambiguas_en_medio_son_prosa() {
  # "comando + no + participio" es exactamente cómo se describe algo pendiente,
  # y quitar `no` de la lista lo reabrió entero. Vuelve, pero solo cuenta como
  # prosa si NO es el token final — que es donde va un valor de comando.
  local frases='git no inicializado|docker no configurado|make se detuvo|cargo es provisional'
  local IFS='|' frase
  for frase in $frases; do
    _em_mapa "# Mapa
## Estado actual
- **Anillo 3:** aún no ha corrido nunca; \`$frase\`."
    git add -A >/dev/null 2>&1
    _em_commit "docs: ambigua en medio de la frase" 100 >/dev/null 2>&1
    local rc; _em_run >/dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] || { echo "    '$frase' coló como comando (exit $rc)"; return 1; }
  done
}
test_una_ambigua_en_medio_delata_prosa() {
  _em_repo _case_ambiguas_en_medio_son_prosa
}

# ── El mapa se vigila a sí mismo en el repo del harness ─────────────
# PRD 0009 fase 4. El mapa es lo PRIMERO que lee cada sesión (§15) y lo que
# `session-start` imprime en cada arranque, y llegó a estar NUEVE DÍAS atrás
# mientras su detector decía `stale=0`. La causa no era que le faltara la
# dimensión —`check-execution-map` ya compara el último commit de producto
# contra el del mapa— sino que `PROD_DIRS` está vacío por defecto y nadie lo
# configuraba.
#
# Se DERIVA de `project_kind`, que ya existe, en vez de pedir una segunda
# declaración: una declaración, dos consumidores, cero drift. Es el mismo patrón
# que cerró la retirada de detectores.
#
# Para un repo de APP se deja VACÍO a propósito: inventarle una lista de
# directorios de producto a un adoptante sería una heurística imponiendo trabajo
# que él no pidió, y el env var sigue ahí para que la ponga él.

_emk_repo() { # <kind> <función> — nombre distinto del `_em_repo` de arriba A PROPÓSITO:
                    # ese ya existe con otra firma y redefinirlo rompía los 50
                    # tests que lo usan (`$2: unbound variable`). Los helpers de
                    # un fichero de test son globales en cuanto se sourcea.
  local d; d="$(mktemp -d)" A=add C=commit
  # `ci/` también: sin él, un typo que lo saque de la derivación (`ci` → `cli`)
  # sobrevive, porque ningún fixture ejerce esa rama. Lo encontró el review.
  mkdir -p "$d/tools/lib" "$d/docs/process" "$d/scripts" "$d/ci"
  cp "$PROJECT_ROOT/tools/check-execution-map.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$d/tools/lib/"
  printf 'project_kind: %s\n' "$1" > "$d/tools/project.conf"
  printf '# Mapa\n\n## Estado actual\n\nAlgo.\n\n## Próximo paso\n\nOtra cosa.\n' \
    > "$d/docs/process/current_execution_map.md"
  printf '#!/usr/bin/env bash\necho hola\n' > "$d/scripts/algo.sh"
  printf '#!/usr/bin/env bash\necho gate\n' > "$d/ci/algo.sh"
  local fn="$2"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # Las fechas se FIJAN, no se duermen: la comparación del detector es `>`
    # sobre timestamps de git, que tienen resolución de SEGUNDO, así que dos
    # commits instantáneos empatan y no disparan. Costó descubrirlo — con el
    # env var explícito también daba stale=0, lo que descartaba la derivación
    # como causa. `sleep 1` funcionaría y sería un test más lento y más frágil.
    export GIT_COMMITTER_DATE="2020-01-01T00:00:00" GIT_AUTHOR_DATE="2020-01-01T00:00:00"
    git "$A" -A 2>/dev/null; git "$C" -qm base 2>/dev/null
    unset GIT_COMMITTER_DATE GIT_AUTHOR_DATE
    "$fn"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# Commit posterior con fecha CONTROLADA, para que el orden sea inequívoco.
_emk_commit() { # <mensaje> <fecha ISO>
  local A=add C=commit
  GIT_COMMITTER_DATE="$2" GIT_AUTHOR_DATE="$2" sh -c "git $A -A 2>/dev/null; git $C -qm '$1' 2>/dev/null"
}

# ── 1. En el harness, tocar producto sin tocar el mapa lo delata ────
_case_harness_delata_el_mapa_viejo() {
  printf '#!/usr/bin/env bash\necho cambiado\n' > scripts/algo.sh
  _emk_commit "toco producto y NO el mapa" "2021-01-01T00:00:00" 
  local out rc
  out="$(bash tools/check-execution-map.sh 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q 'atrasado=1' || {
    echo "    se tocó scripts/ sin tocar el mapa y el detector no marcó atraso (exit $rc):"
    printf '%s\n' "$out" | grep SUMMARY | sed 's/^/      /'
    echo "    Es lo que dejó el mapa nueve días atrás diciendo que estaba al día."
    return 1; }
}
test_en_el_harness_el_mapa_viejo_se_delata() {
  _emk_repo harness _case_harness_delata_el_mapa_viejo
}

# ── 2. …y tocar los dos en el mismo commit pasa ─────────────────────
# Guard del falso positivo: si el detector no se pudiera satisfacer, sería una
# ceremonia que se acaba desactivando.
_case_harness_con_el_mapa_al_dia() {
  printf '#!/usr/bin/env bash\necho cambiado\n' > scripts/algo.sh
  printf '# Mapa\n\n## Estado actual\n\nAlgo NUEVO.\n\n## Próximo paso\n\nOtra cosa.\n' \
    > docs/process/current_execution_map.md
  _emk_commit "producto y mapa en el mismo commit" "2021-01-01T00:00:00" 
  local rc; bash tools/check-execution-map.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    con el mapa actualizado en el MISMO commit sigue diciendo stale (exit $rc)"; return 1; }
}
test_tocar_mapa_y_producto_juntos_pasa() {
  _emk_repo harness _case_harness_con_el_mapa_al_dia
}

# ── 3. A un proyecto de APP no se le impone nada ────────────────────
# Inventarle una lista de directorios de producto sería una heurística
# imponiendo trabajo que el adoptante no pidió. El env var sigue para él.
_case_app_no_hereda_la_carga() {
  printf '#!/usr/bin/env bash\necho cambiado\n' > scripts/algo.sh
  _emk_commit "toco scripts en un repo de app" "2021-01-01T00:00:00" 
  local rc; bash tools/check-execution-map.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || {
    echo "    a un proyecto de APP se le exige el mapa por tocar scripts/ (exit $rc)"
    echo "    Ahí scripts/ es andamio, no producto — es carga que no pidió."
    return 1; }
}
test_un_proyecto_de_app_no_hereda_la_carga() {
  _emk_repo application _case_app_no_hereda_la_carga
}

# ── 4. El env var sigue mandando ────────────────────────────────────
_case_el_env_gana() {
  printf '#!/usr/bin/env bash\necho cambiado\n' > scripts/algo.sh
  _emk_commit "toco scripts" "2021-01-01T00:00:00" 
  local rc
  EXECUTION_MAP_PROD_DIRS="no-existe-esta-carpeta" bash tools/check-execution-map.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || {
    echo "    el env var no ganó sobre la derivación (exit $rc): un adoptante no puede afinarlo"
    return 1; }
}
test_el_env_var_gana_sobre_la_derivacion() { _emk_repo harness _case_el_env_gana; }

# ── El detector sobrevive a CI con una declaración contradictoria ───
# Hallazgo RED del review, y la lección va más allá del bug: **la suite corre
# SIN `CI=true`**, así que toda una rama de comportamiento estaba sin test. El
# verify-run local daba 827 verdes con la CI real a punto de ponerse roja.
#
# El bug: `scope.sh` ejecuta `_scope_verifica_declaracion` AL SOURCEARSE, y esa
# función hace `exit 3` bajo CI cuando la declaración contradice a la evidencia.
# Sourceado directo, ese exit mataba a `check-execution-map` entero — y GitHub
# Actions exporta `CI=true` en todos los jobs. La consulta va ahora en subshell
# con `SCOPE_NO_CI_EXIT=1`, que es el patrón que el repo ya tenía en
# `session-start.sh:148` para exactamente este caso.
_case_sobrevive_a_ci() {
  # `application` declarado sin fuentes de app ES una contradicción para
  # scope.sh — el escenario exacto que disparaba el exit 3.
  local rc
  CI=true bash tools/check-execution-map.sh >/dev/null 2>&1; rc=$?
  [ "$rc" != "3" ] || {
    echo "    bajo CI=true el detector salió 3 por una contradicción de scope,"
    echo "    que no tiene NADA que ver con la frescura del mapa. Sourcear"
    echo "    scope.sh sin aislarlo mata al detector entero, y Actions exporta"
    echo "    CI=true en todos los jobs: esto pondría la CI real en rojo."
    return 1; }
}
test_el_detector_sobrevive_a_ci_con_declaracion_contradictoria() {
  _emk_repo application _case_sobrevive_a_ci
}

# ── Cada directorio derivado se vigila, no solo el primero ──────────
# El review encontró que cambiar `ci` por `cli` en la derivación sobrevivía:
# ningún fixture tocaba SOLO `ci/`, así que los demás casos disparaban por
# `scripts/` y el typo pasaba. Un test que ejercita un elemento de una lista no
# prueba la lista.
_case_tocar_solo_ci_tambien_delata() {
  printf '#!/usr/bin/env bash\necho gate cambiado\n' > ci/algo.sh
  _emk_commit "toco SOLO ci/ y no el mapa" "2021-01-01T00:00:00"
  local out; out="$(bash tools/check-execution-map.sh 2>&1)"
  printf '%s' "$out" | grep -q 'atrasado=1' || {
    echo "    se tocó SOLO ci/ sin tocar el mapa y no se marcó atraso: $out"
    echo "    ci/ cablea el Anillo 3 — si sale de la derivación, deja de vigilarse."
    return 1; }
}
test_tocar_solo_ci_tambien_delata_el_mapa() {
  _emk_repo harness _case_tocar_solo_ci_tambien_delata
}

# ── Los DATOS generados de tools/ no son "tocar producto" ───────────
# Falso positivo del propio detector, encontrado al usarlo: un commit que solo
# añade una fila al ledger (`tools/findings/ledger.jsonl`, que escribe
# `findings.sh`) contaba como tocar producto y exigía actualizar el mapa. Pero
# registrar un hallazgo NO es un cambio de fase, y el mapa acaba de quedarse sin
# historia a propósito: obligar a anotarlo ahí es empujar de vuelta lo que se
# acaba de sacar. Bloqueó un `git push` de verdad.
#
# Los ficheros de datos que escribe una herramienta —el ledger y los
# trinquetes— se excluyen. El CÓDIGO de `tools/` sigue exigiendo el mapa.
_case_solo_datos_generados() {
  local A=add C=commit
  mkdir -p tools/findings
  printf '{"id":"f-x","title":"algo"}\n' > tools/findings/ledger.jsonl
  git "$A" -A
  GIT_COMMITTER_DATE="2026-01-01T10:00:00" GIT_AUTHOR_DATE="2026-01-01T10:00:00" \
    git "$C" -qm base
  # el mapa se queda como está y solo cambia el ledger, DESPUÉS
  printf '{"id":"f-x","title":"algo"}\n{"id":"f-y","title":"otro"}\n' > tools/findings/ledger.jsonl
  git "$A" tools/findings/ledger.jsonl
  GIT_COMMITTER_DATE="2026-01-02T10:00:00" GIT_AUTHOR_DATE="2026-01-02T10:00:00" \
    git "$C" -qm "solo una fila de ledger"
  local out rc
  out="$(bash tools/check-execution-map.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    una fila de ledger marcó el mapa como stale (exit $rc):"
    printf '%s\n' "$out" | head -4 | sed 's/^/      /'
    echo "    Registrar un hallazgo no es un cambio de fase."
    return 1; }
}
test_una_fila_de_ledger_no_exige_tocar_el_mapa() {
  _emk_repo harness _case_solo_datos_generados
}

# Y el reverso, para que la exclusión no se coma el caso real: tocar CÓDIGO de
# tools/ en el mismo commit sí sigue exigiendo el mapa.
_case_codigo_junto_a_datos_si_exige() {
  local A=add C=commit
  mkdir -p tools/findings
  printf '{"id":"f-x"}\n' > tools/findings/ledger.jsonl
  git "$A" -A
  GIT_COMMITTER_DATE="2026-01-01T10:00:00" GIT_AUTHOR_DATE="2026-01-01T10:00:00" \
    git "$C" -qm base
  printf '{"id":"f-x"}\n{"id":"f-y"}\n' > tools/findings/ledger.jsonl
  printf '#!/usr/bin/env bash\necho cambiado\n' > tools/algo-nuevo.sh
  git "$A" tools/findings/ledger.jsonl tools/algo-nuevo.sh
  GIT_COMMITTER_DATE="2026-01-02T10:00:00" GIT_AUTHOR_DATE="2026-01-02T10:00:00" \
    git "$C" -qm "ledger Y código"
  local out; out="$(bash tools/check-execution-map.sh 2>&1)"
  printf '%s' "$out" | grep -q 'atrasado=1' || {
    echo "    tocar código de tools/ junto al ledger NO marcó atraso: $out"
    echo "    La exclusión de datos se comió el caso que el detector existe para cazar."
    return 1; }
}
test_tocar_codigo_junto_al_ledger_si_exige_el_mapa() {
  _emk_repo harness _case_codigo_junto_a_datos_si_exige
}

# ── Y el código DENTRO de tools/findings/ tampoco está excluido ─────
# El guard de arriba no bastaba: lleva un fichero en la RAÍZ de `tools/`, que
# por sí solo mantiene el test verde aunque la exclusión se coma
# `tools/findings/` entero. El review lo demostró con un mutante que le
# sobrevivía. Este caso toca EXCLUSIVAMENTE código dentro de esa carpeta, que
# es donde vive `findings.sh` — la herramienta, no sus datos.
_case_codigo_dentro_de_findings_si_exige() {
  local A=add C=commit
  mkdir -p tools/findings
  printf '{"id":"f-x"}\n' > tools/findings/ledger.jsonl
  printf '#!/usr/bin/env bash\necho v1\n' > tools/findings/gestor.sh
  git "$A" -A
  GIT_COMMITTER_DATE="2026-01-01T10:00:00" GIT_AUTHOR_DATE="2026-01-01T10:00:00" \
    git "$C" -qm base
  # SOLO código dentro de tools/findings/. Ni la raíz de tools/, ni el ledger.
  printf '#!/usr/bin/env bash\necho v2\n' > tools/findings/gestor.sh
  git "$A" tools/findings/gestor.sh
  GIT_COMMITTER_DATE="2026-01-02T10:00:00" GIT_AUTHOR_DATE="2026-01-02T10:00:00" \
    git "$C" -qm "cambio en la herramienta, no en sus datos"
  local out; out="$(bash tools/check-execution-map.sh 2>&1)"
  printf '%s' "$out" | grep -q 'atrasado=1' || {
    echo "    cambiar código dentro de tools/findings/ NO marcó atraso: $out"
    echo "    La exclusión se comió la herramienta junto con sus datos."
    return 1; }
}
test_codigo_dentro_de_findings_si_exige_el_mapa() {
  _emk_repo harness _case_codigo_dentro_de_findings_si_exige
}

# ── La FRESCURA avisa; el CONTENIDO bloquea ─────────────────────────
# Decisión del owner en la estabilización de V1. El detector acumulaba cuatro
# dimensiones en un solo `STALE`, y la de frescura dispara con CUALQUIER commit
# de producto posterior al mapa. En este repo el producto ES `tools/`, así que
# cada commit exigía editar el mapa — y el mapa acaba de quedarse sin historia a
# propósito, o sea sin contenido por-commit que añadir. Esa es la cascada de
# trabajo auxiliar que la V1 existe para eliminar, y tenía la suite en rojo
# DETERMINISTA: tres corridas, los mismos dos fallos.
#
# Las otras tres dimensiones —frases muertas, cifras derivables y afirmaciones
# de estado sin evidencia— son objetivas y baratas de cumplir: siguen duras.
_case_atraso_avisa_no_bloquea() {
  local A=add C=commit
  git "$A" -A
  GIT_COMMITTER_DATE="2026-01-01T10:00:00" GIT_AUTHOR_DATE="2026-01-01T10:00:00" \
    git "$C" -qm base
  printf '#!/usr/bin/env bash\necho v2\n' > tools/algo.sh
  git "$A" tools/algo.sh
  GIT_COMMITTER_DATE="2026-01-02T10:00:00" GIT_AUTHOR_DATE="2026-01-02T10:00:00" \
    git "$C" -qm "producto sin tocar el mapa"
  local out rc
  out="$(bash tools/check-execution-map.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    el mapa atrasado BLOQUEA (exit $rc); debe avisar:"
    printf '%s\n' "$out" | head -5 | sed 's/^/      /'
    return 1; }
  # y el aviso tiene que VERSE: un atraso silencioso es el incidente original.
  # OJO con la aserción: la propia línea de contrato dice `atrasado=1`, así que
  # un grep de "atras" pasa aunque el bloque de aviso no exista — un mutante que
  # lo borraba sobrevivía. Se afirma sobre el TEXTO del aviso, no sobre la clave.
  printf '%s' "$out" | grep -q 'va ATRASADO respecto del árbol' || {
    echo "    no bloquea, pero tampoco declara el atraso — silencio, que es peor:"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1; }
  printf '%s' "$out" | grep -q 'atrasado=1' || {
    echo "    la línea de contrato no expone el atraso por separado: $out"; return 1; }
}
test_el_mapa_atrasado_avisa_pero_no_bloquea() {
  _emk_repo harness _case_atraso_avisa_no_bloquea
}

# Y el reverso: una violación de CONTENIDO bloquea aunque el mapa esté fresco.
_case_contenido_bloquea_aunque_fresco() {
  local A=add C=commit
  printf '# Mapa\n\n## Estado actual\n\nLa suite tiene 869 tests verdes.\n\n## Próximo paso\n\nAlgo.\n' \
    > docs/process/current_execution_map.md
  git "$A" -A
  GIT_COMMITTER_DATE="2026-01-02T10:00:00" GIT_AUTHOR_DATE="2026-01-02T10:00:00" \
    git "$C" -qm "mapa fresco, con una cifra derivable dentro"
  local out rc
  out="$(bash tools/check-execution-map.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || {
    echo "    una cifra derivable NO bloqueó (exit $rc) con el mapa fresco:"
    printf '%s\n' "$out" | head -6 | sed 's/^/      /'
    echo "    La frescura pasa a aviso; el contenido tiene que seguir duro."
    return 1; }
  printf '%s' "$out" | grep -q 'stale=1' || {
    echo "    bloquea pero no lo declara en la línea de contrato: $out"; return 1; }
}
test_una_cifra_derivable_bloquea_con_el_mapa_fresco() {
  _emk_repo harness _case_contenido_bloquea_aunque_fresco
}
