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
