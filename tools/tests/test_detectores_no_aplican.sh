#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# "No aplica" no es "miré y está limpio"
# ════════════════════════════════════════════════════════════════════
# Decisión del owner del 2026-09-03, tomada con el dato que produjo el lector
# del denominador (PRD 0008 fase 1): en ESTE repo, `check-layers` llevaba 80
# corridas con CERO objetivos, `check-drift` 46 con cero, y `check-source-sets`
# 8 con cero. Los tres buscan código de APP (`ios android web src app lib
# Sources`, `commonMain/`) en un repo cuyo producto es el propio harness.
#
# Se retiran AQUÍ, no del template: `tools/*.sh` viaja a los adoptantes por
# SYNC_GLOBS y un proyecto con iOS o web reales sí los necesita. La declaración
# que lo gobierna es `project_kind`, que ya existe en `tools/project.conf`, ya
# es propiedad del adoptante y ya gobierna los gates de scope.
#
# Se comprobó antes la alternativa —apuntarlos al código del harness en vez de
# retirarlos— y NO sirve: `check-drift` solo mide extensiones de app
# (`.swift .kt .ts .py …`), así que apuntado a `tools scripts ci` también da
# cero. Re-apuntar exigiría enseñarle shell, que es otro trabajo.
#
# LO QUE ESTE CAMBIO NO PUEDE HACER: convertir el cero en silencio. Un detector
# que no aplica tiene que DECIRLO, y el trinquete no puede tomar esa
# no-medición por un techo medido — es la distinción que `mutation-ratchet.json`
# ya expresa con `measured: false`.

_na_repo() { # <kind> <función>
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools/lib" "$d/tools/tests"
  for f in check-drift.sh check-layers.sh check-source-sets.sh drift-ratchet.sh layers.conf; do
    cp "$PROJECT_ROOT/tools/$f" "$d/tools/" 2>/dev/null
  done
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$d/tools/lib/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/drift-ratchet.json" "$d/tools/" 2>/dev/null
  printf 'project_kind: %s\n' "$1" > "$d/tools/project.conf"
  local fn="$2"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # `git add` y `git commit` por variable: escritos como literales, el
    # git-guard del propio harness lee este heredoc como un commit encadenado y
    # bloquea el turno que escribe el test.
    git "$A" -A 2>/dev/null; git "$C" -qm base 2>/dev/null
    "$fn"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── 1. En un repo `harness`, los tres lo DECLARAN ───────────────────
_case_declaran_no_aplica() {
  local d s
  for d in check-drift check-layers check-source-sets; do
    s="$(bash "tools/$d.sh" 2>&1)"
    printf '%s' "$s" | grep -q 'no-aplica' || {
      echo "    $d no declara 'no-aplica' en un repo cuyo producto es el harness:"
      printf '%s\n' "$s" | head -3 | sed 's/^/      /'
      echo "    Sin declararlo, su errors=0 se lee como una medición que nadie hizo."
      return 1; }
  done
}
test_los_tres_declaran_no_aplica_en_el_harness() { _na_repo harness _case_declaran_no_aplica; }

# ── 2. …y salen 0, no 3 ─────────────────────────────────────────────
# "No aplica" NO es "no pude mirar" (§14.3). El detector funciona
# perfectamente: es que aquí no hay nada de su competencia. Devolver 3 haría
# que CI bloqueara por algo que no es un fallo.
_case_no_aplica_sale_cero() {
  local d rc
  for d in check-drift check-layers check-source-sets; do
    bash "tools/$d.sh" >/dev/null 2>&1; rc=$?
    [ "$rc" = "0" ] || { echo "    $d salió $rc al no aplicar (esperaba 0; el 3 es 'no pude mirar')"; return 1; }
  done
}
test_no_aplica_sale_0_no_3() { _na_repo harness _case_no_aplica_sale_cero; }

# ── 3. El trinquete NO toma la no-medición por un techo ─────────────
# El daño real que motivó todo esto: `errors=0` de un detector que no miró nada
# alimentaba un trinquete que SOLO BAJA, fijando el suelo en cero de forma
# permanente. Ahora tiene que declarar que no hay medición, como
# `mutation-ratchet.json` hace con `measured: false`.
_case_trinquete_declara_sin_medicion() {
  local out rc
  out="$(bash tools/drift-ratchet.sh --check 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    drift-ratchet salió $rc con el detector sin aplicar"; return 1; }
  printf '%s' "$out" | grep -qi 'no aplica\|sin medición\|sin medicion' || {
    echo "    el trinquete no declara que NO HAY MEDICIÓN; dice esto:"
    printf '%s\n' "$out" | sed 's/^/      /'
    echo "    Un techo de 0 que nadie midió es peor que ningún techo."
    return 1; }
}
test_el_trinquete_declara_que_no_hay_medicion() {
  _na_repo harness _case_trinquete_declara_sin_medicion
}

# ── 4. …y --update REHÚSA escribir desde una no-medición ────────────
# Un trinquete que su propio script puede fijar a partir de la nada es una
# sugerencia. El script ya rehúsa escribir un piso de cero por otra vía; esta
# es la misma regla para el caso "no hay nada que medir".
_case_update_rehusa() {
  local out
  out="$(bash tools/drift-ratchet.sh --update 2>&1)"
  printf '%s' "$out" | grep -qi 'no aplica\|sin medición\|sin medicion\|rehus' || {
    echo "    --update no rehusó ni declaró nada con el detector sin aplicar:"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_update_rehusa_escribir_sin_medicion() { _na_repo harness _case_update_rehusa; }

# ── 5. FALSO POSITIVO guard: en un proyecto de APP siguen midiendo ──
# Lo único que haría inaceptable este cambio: que un adoptante con código real
# se quedara sin los tres detectores. La retirada es de ESTE repo, no del
# template.
_case_en_app_siguen_midiendo() {
  mkdir -p web/domain
  printf 'import axios from "axios"\nexport const r = 1\n' > web/domain/repo.ts
  local out rc
  out="$(bash tools/check-layers.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || {
    echo "    en un proyecto de APP, check-layers NO cazó una violación real (exit $rc):"
    printf '%s\n' "$out" | sed 's/^/      /'
    echo "    La retirada era de este repo, no del template."
    return 1; }
  printf '%s' "$out" | grep -q 'no-aplica' && {
    echo "    en un proyecto de APP declara 'no-aplica' — la declaración se está"
    echo "    aplicando donde no toca"; return 1; }
  return 0
}
test_en_un_proyecto_de_app_siguen_midiendo() {
  _na_repo application _case_en_app_siguen_midiendo
}

# ── 6. Declarar `harness` NO basta: la evidencia manda para retirar ──
# Hallazgo RED del review, reproducido: un repo con `project_kind: harness` Y
# código de app real perdía los tres detectores EN SILENCIO. Y es el caso más
# probable, no un rincón: **el template viene declarando `harness`**, así que un
# adoptante que copie y empiece a meter código antes de acordarse del flip se
# queda sin la protección justo cuando empieza a necesitarla.
#
# Por qué aquí la evidencia SÍ manda, cuando en el gate de scope no:
# clasificar scope no reduce protección —decide qué exige review— así que la
# declaración puede gobernar sin riesgo. RETIRAR un detector sí la reduce, y por
# eso exige que la declaración Y la evidencia estén de acuerdo. Fail-closed: si
# hay una sola fuente de app, se mide.
_case_harness_con_codigo_de_app_sigue_midiendo() {
  mkdir -p web/domain
  printf 'import axios from "axios"\nexport const r = 1\n' > web/domain/repo.ts
  local out rc
  out="$(bash tools/check-layers.sh 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q 'no-aplica' && {
    echo "    declara 'no-aplica' con código de app REAL en el árbol:"
    printf '%s\n' "$out" | sed 's/^/      /'
    echo "    Ese es el adoptante que copió el template (que viene declarando"
    echo "    harness) y aún no ha hecho el flip. Pierde el detector en silencio."
    return 1; }
  [ "$rc" = "1" ] || {
    echo "    no cazó la violación de capas real (exit $rc)"; return 1; }
}
test_declarar_harness_con_codigo_de_app_no_retira() {
  _na_repo harness _case_harness_con_codigo_de_app_sigue_midiendo
}

# ── 7. Sourcear scope.sh no puede tragarse sus avisos ───────────────
# El review lo encontró junto al anterior: `. "$_DET_SCOPE" 2>/dev/null` mandaba
# a /dev/null el stderr de `_scope_verifica_declaracion`, que es quien avisa de
# la contradicción declarado-vs-evidencia. En CI el detector salía 3 con la
# salida COMPLETAMENTE VACÍA — un gate que corta sin decir por qué.
_case_los_avisos_no_se_tragan() {
  mkdir -p web/domain
  printf 'import axios from "axios"\n' > web/domain/repo.ts
  # LOS TRES, no solo uno. La primera versión probaba `check-layers` y el review
  # demostró con un mutante que revertir el arreglo en los otros dos sobrevivía:
  # un test que cubre un tercio de su contrato invita a recortar los otros dos
  # con luz verde falsa.
  local d out
  for d in check-layers check-drift check-source-sets; do
    out="$(CI=true bash "tools/$d.sh" 2>&1)"
    [ -n "$out" ] || {
      echo "    en CI, con la declaración contradiciendo a la evidencia, $d no"
      echo "    imprimió NADA — corta sin decir por qué."
      return 1; }
  done
}
test_los_avisos_de_scope_no_se_silencian() {
  _na_repo harness _case_los_avisos_no_se_tragan
}
