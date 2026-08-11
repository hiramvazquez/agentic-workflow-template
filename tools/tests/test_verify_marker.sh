#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El invariante nº1, aplicado por fin a los TESTS y no solo al reviewer
# ════════════════════════════════════════════════════════════════════
# `check-review-marker.sh` ata el review a `sha256(diff staged)`: un review de
# otro diff no vale. Ninguna ejecución de build o de tests estaba atada a ese
# mismo diff, así que se podía commitear un árbol que NADIE llegó a compilar,
# con el reviewer en GREEN, los trinquetes dentro y las capas limpias — porque
# ninguno de los tres compila nada. (f-gate-sin-evidencia-de-build.)
#
# El riesgo de este gate es el de siempre: si bloquea de más, se apaga. Por eso
# hay tantos casos de "esto NO debe bloquear" como de "esto sí".

_vm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/app"
  cp "$PROJECT_ROOT/tools/verify-run.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-verify-marker.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    printf 'full\n' > tools/preset
    printf 'true\n' > tools/verify.conf          # "build" que siempre pasa
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_stage_producto() { mkdir -p app; printf 'let x = %s\n' "${1:-1}" > app/Main.swift; git add app/Main.swift; }

# ── El agujero, cerrado ─────────────────────────────────────────────
_case_sin_ejecucion_no_se_commitea() {
  _stage_producto
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    se pudo commitear producto SIN ninguna ejecución verde ligada"; return 1; }
}
test_producto_sin_ejecucion_verde_no_pasa() { _vm_sandbox _case_sin_ejecucion_no_se_commitea; }

_case_con_ejecucion_pasa() {
  _stage_producto
  bash tools/verify-run.sh >/dev/null 2>&1 || { echo "    verify-run falló con un comando que siempre pasa"; return 1; }
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    tras una ejecución verde, el gate siguió bloqueando"; return 1; }
}
test_con_ejecucion_verde_ligada_pasa() { _vm_sandbox _case_con_ejecucion_pasa; }

# ── Lo que hace que la evidencia SIGNIFIQUE algo ────────────────────
_case_el_diff_cambia_y_el_marker_caduca() {
  # Sin esto, "verifiqué" una vez valdría para cualquier cosa que stagearas
  # después — que es justo lo que hace inútil un marker.
  _stage_producto 1
  bash tools/verify-run.sh >/dev/null 2>&1
  _stage_producto 999
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    el marker de OTRO diff se dio por bueno"; return 1; }
}
test_si_cambia_el_diff_staged_el_marker_deja_de_valer() {
  _vm_sandbox _case_el_diff_cambia_y_el_marker_caduca
}

_case_marker_a_mano_no_cuenta() {
  # El invariante nº1: la evidencia la produce el sistema. Un marker escrito
  # por el modelo es una AFIRMACIÓN, y afirmar que los tests pasan es
  # exactamente lo que este gate existe para no tener que creerse.
  _stage_producto
  mkdir -p .agents/state/markers
  local sha; sha="$(git diff --cached | sha256sum | awk '{print $1}')"
  printf 'source: agent\nhead: %s\nstaged_sha: %s\n' "$(git rev-parse --short HEAD)" "$sha" \
    > .agents/state/markers/verify_run.txt
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un marker escrito A MANO se aceptó como ejecución real"; return 1; }
}
test_marker_sin_source_tool_se_rechaza() { _vm_sandbox _case_marker_a_mano_no_cuenta; }

_case_build_rojo_no_firma() {
  # Un marker escrito tras un fallo convertiría el gate en un sello.
  _stage_producto
  printf 'false\n' > tools/verify.conf
  bash tools/verify-run.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un build ROJO no devolvió 1"; return 1; }
  [ -f .agents/state/markers/verify_run.txt ] \
    && { echo "    FIRMÓ evidencia de un build que falló"; return 1; }
  return 0
}
test_un_build_rojo_no_deja_evidencia() { _vm_sandbox _case_build_rojo_no_firma; }

_case_sin_stagear_no_firma() {
  # El build corre sobre el ÁRBOL. Con cambios sin stagear, lo que se compila
  # no es lo que se commitea — firmar eso sería la mentira que esto impide.
  _stage_producto 1
  printf 'let x = 2\n' > app/Main.swift          # modificado y NO staged
  bash tools/verify-run.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    firmó con cambios sin stagear (verificó algo distinto de lo que se commitea)"; return 1; }
}
test_no_firma_si_hay_cambios_sin_stagear() { _vm_sandbox _case_sin_stagear_no_firma; }

# ── Guards de FALSO POSITIVO: donde este gate NO puede molestar ─────
# Cada falso positivo de un gate que corre un BUILD entero cuesta minutos, no
# segundos. Es el gate más caro del harness cuando se equivoca, así que los
# cuatro casos de abajo pesan más que los de arriba.
_case_docs_no_exigen_build() {
  mkdir -p docs; printf 'texto\n' > docs/nota.md; git add docs/nota.md
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    tocar SOLO documentación exigió compilar la app"; return 1; }
}
test_cambio_solo_de_docs_no_exige_build() { _vm_sandbox _case_docs_no_exigen_build; }

_case_sin_comando_avisa_pero_no_traba() {
  # Un proyecto recién adoptado no tiene verify.conf cableado. Exigir el marker
  # ahí sería un deadlock: no podría commitear NADA, ni siquiera el commit que
  # cablea el comando. Contrato §14.3: 3 = "no pude mirar" → avisa, CI bloquea.
  printf '# <!-- FILL: tu comando -->\n' > tools/verify.conf
  _stage_producto
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    sin comando cableado el gate trabó el commit (deadlock para todo adoptante nuevo)"; return 1; }
}
test_sin_comando_cableado_avisa_no_bloquea() {
  _vm_sandbox _case_sin_comando_avisa_pero_no_traba
}

_case_lite_avisa() {
  printf 'lite\n' > tools/preset
  _stage_producto
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    en preset lite el gate BLOQUEÓ (§13 dice que avisa)"; return 1; }
}
test_en_preset_lite_avisa_en_vez_de_bloquear() { _vm_sandbox _case_lite_avisa; }

_case_merge_no_reverifica() {
  _stage_producto
  : > "$(git rev-parse --git-dir)/MERGE_HEAD"
  bash tools/check-verify-marker.sh >/dev/null 2>&1
  local rc=$?; rm -f "$(git rev-parse --git-dir)/MERGE_HEAD"
  [ "$rc" = "0" ] || { echo "    un commit de MERGE exigió re-verificar lo ya verificado en la rama"; return 1; }
}
test_commit_de_merge_no_reverifica() { _vm_sandbox _case_merge_no_reverifica; }
