#!/usr/bin/env bash
# upgrade.sh: traer mejoras del template SIN perder los rellenos del proyecto.
# Fija: los guards (árbol sucio, remote ausente con mensaje útil), el caso "ya
# al día", y el merge real de 3 vías — el cambio del template Y el relleno
# local sobreviven juntos cuando no chocan.

_upg_sandbox() { # crea TEMPLATE (origen) y PROYECTO (clon) reales
  local base tpl prj
  base="$(mktemp -d)"; tpl="$base/tpl"; prj="$base/prj"
  mkdir -p "$tpl/tools/tests" "$tpl/scripts"
  (
    cd "$tpl" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    printf 'v1 maquinaria\n' > scripts/gate.sh
    printf 'stack: <!-- FILL -->\n' > AGENTS.md
    git add -A; git commit -qm "template v1"
  )
  git clone -q "$tpl" "$prj" 2>/dev/null
  (
    cd "$prj" || exit 1
    git config user.email p@p.p; git config user.name p
    git remote rename origin template 2>/dev/null
    # upgrade.sh real + stubs de verificación en verde (aquí se prueba el
    # flujo de merge, no la suite entera — esa tiene sus propios tests).
    mkdir -p tools/tests
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/tests/run-tests.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/validate-harness.sh
    git add -A; git commit -qm "proyecto: añade upgrade"
    TPL_DIR="$tpl" "$1"
  )
  local rc=$?; rm -rf "$base"; return $rc
}

_case_arbol_sucio_rehusa() {
  echo tocado >> AGENTS.md
  bash tools/upgrade.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    aceptó correr con el árbol sucio"; return 1; }
  git checkout -q AGENTS.md
}
test_upgrade_rehusa_con_arbol_sucio() { _upg_sandbox _case_arbol_sucio_rehusa; }

_case_sin_remote_mensaje_util() {
  git remote remove template 2>/dev/null
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    sin remote no falló (exit $rc)"; return 1; }
  case "$out" in *"tools/upgrade.sh https://"*) return 0 ;; esac
  echo "    el error no explica cómo registrar el remote"; return 1
}
test_upgrade_sin_remote_explica_como() { _upg_sandbox _case_sin_remote_mensaje_util; }

_case_al_dia_es_noop() {
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    'al día' devolvió exit $rc"; return 1; }
  case "$out" in *"al día"*) return 0 ;; esac
  echo "    no reportó estar al día: $out"; return 1
}
test_upgrade_al_dia_no_hace_nada() { _upg_sandbox _case_al_dia_es_noop; }

_case_merge_conserva_ambos() {
  # El PROYECTO rellena su FILL…
  printf 'stack: Swift 6 + SwiftUI\n' > AGENTS.md
  git add AGENTS.md; git commit -qm "proyecto: rellena stack"
  # …y el TEMPLATE mejora la maquinaria (archivo distinto → sin conflicto).
  ( cd "$TPL_DIR" && printf 'v2 maquinaria mejorada\n' > scripts/gate.sh \
    && git add -A && git commit -qm "template v2" )
  bash tools/upgrade.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el upgrade limpio falló"; return 1; }
  grep -q "v2 maquinaria" scripts/gate.sh || { echo "    NO llegó la mejora del template"; return 1; }
  grep -q "Swift 6" AGENTS.md || { echo "    el merge PISÓ el relleno del proyecto"; return 1; }
}
test_upgrade_funde_template_y_rellenos() { _upg_sandbox _case_merge_conserva_ambos; }

_case_conflicto_clasificado() {
  # Ambos tocan la MISMA línea de AGENTS.md → conflicto clasificado como contenido.
  printf 'stack: Swift 6\n' > AGENTS.md; git add AGENTS.md; git commit -qm "proyecto: stack"
  ( cd "$TPL_DIR" && printf 'stack: <!-- FILL: ahora con ejemplo -->\n' > AGENTS.md \
    && git add -A && git commit -qm "template: mejora el placeholder" )
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "2" ] || { echo "    conflicto no devolvió exit 2 (fue $rc)"; return 1; }
  case "$out" in *"contenido TUYO"*"AGENTS.md"*|*"AGENTS.md"*) : ;; *)
    echo "    el conflicto no se listó/clasificó"; return 1 ;; esac
  git merge --abort 2>/dev/null; return 0
}
test_upgrade_conflicto_queda_clasificado() { _upg_sandbox _case_conflicto_clasificado; }

# ════════════════════════════════════════════════════════════════════
# MODO SYNC — adopción por COPIA (historias no relacionadas)
# ════════════════════════════════════════════════════════════════════
# El camino que docs/ADOPTION.md recomienda de verdad: copiar el harness a un
# proyecto que YA existe. Esos dos repos no comparten ancestro y `git merge`
# se niega ("refusing to merge unrelated histories"). Durante meses el script
# solo contemplaba el clone, así que su upgrade estaba roto justo para su ruta
# de adopción principal — y encima reportaba el fallo fatal como "conflictos",
# mandando al humano a resolver algo que no existía.
_upg_sandbox_copia() { # TEMPLATE y PROYECTO con historias SEPARADAS
  local base tpl prj
  base="$(mktemp -d)"; tpl="$base/tpl"; prj="$base/prj"
  mkdir -p "$tpl/tools/tests" "$tpl/scripts"
  (
    cd "$tpl" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    printf 'v2 maquinaria del template\n' > scripts/gate.sh
    printf 'stack: <!-- FILL -->\n' > AGENTS.md
    git add -A; git commit -qm "template"
  )
  mkdir -p "$prj/tools/tests" "$prj/scripts"
  (
    cd "$prj" || exit 1
    git init -q .; git config user.email p@p.p; git config user.name p
    printf 'app\n' > App.swift
    printf 'v1 maquinaria copiada\n' > scripts/gate.sh
    printf 'stack: iOS real\n' > AGENTS.md
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/tests/run-tests.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/validate-harness.sh
    git add -A; git commit -qm "proyecto con harness COPIADO"
    git remote add template "$tpl"
    TPL_DIR="$tpl" "$1"
  )
  local rc=$?; rm -rf "$base"; return $rc
}

_case_sync_trae_maquinaria() {
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'v2 maquinaria del template' scripts/gate.sh \
    || { echo "    MODO SYNC no trajo la maquinaria del template"; return 1; }
}
test_sync_trae_la_maquinaria_sin_ancestro_comun() {
  _upg_sandbox_copia _case_sync_trae_maquinaria
}

_case_sync_no_pisa_contenido() {
  # LO MÁS IMPORTANTE: el contenido del proyecto es SUYO. Si el sync tocara
  # AGENTS.md, cada upgrade borraría los rellenos reales del adoptante — el
  # daño exacto que hace que nadie vuelva a correr el upgrade.
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'stack: iOS real' AGENTS.md \
    || { echo "    el sync PISÓ AGENTS.md con el FILL del template"; return 1; }
  [ -f App.swift ] || { echo "    el sync tocó código de la app"; return 1; }
}
test_sync_jamas_pisa_contenido_del_proyecto() {
  _upg_sandbox_copia _case_sync_no_pisa_contenido
}

_case_sync_registra_base() {
  # Sin registro no hay delta posible la próxima vez: se volvería a traer la
  # maquinaria entera para siempre, pisando arreglos locales cada vez.
  bash tools/upgrade.sh >/dev/null 2>&1
  [ -f tools/.template-sync ] || { echo "    el sync no registró el SHA del template"; return 1; }
  grep -qE '^[0-9a-f]{7,40}' tools/.template-sync \
    || { echo "    el registro no contiene un SHA: $(cat tools/.template-sync)"; return 1; }
}
test_sync_registra_la_base_para_el_delta_futuro() {
  _upg_sandbox_copia _case_sync_registra_base
}

_case_sync_deja_staged_sin_commitear() {
  # El sync NO commitea por ti: trae, stagea y te enseña el diff. Commitear
  # solo lo que un humano ha visto es la diferencia entre un upgrade y una
  # sobreescritura silenciosa.
  local rc; bash tools/upgrade.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el sync devolvió $rc (esperaba 2: hay que revisar y commitear)"; return 1; }
  git diff --cached --name-only 2>/dev/null | grep -q 'scripts/gate.sh' \
    || { echo "    el sync no dejó los cambios staged para revisión"; return 1; }
}
test_sync_deja_los_cambios_staged_para_revision() {
  _upg_sandbox_copia _case_sync_deja_staged_sin_commitear
}
