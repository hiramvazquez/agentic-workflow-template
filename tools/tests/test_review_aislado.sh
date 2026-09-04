#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# La revisión no toca el árbol del autor, y se demuestra
# ════════════════════════════════════════════════════════════════════
# Bloqueante de V1 declarado por el owner. Lo motivó un incidente real: un
# sub-agente reviewer mutó un fichero durante su verificación, eso le quitó el
# bit +x, `check-exec-bits` lo reparó Y lo re-stageó con el mutante dentro, y el
# `sha256(diff staged)` se movió sin que nadie hiciera `git add`. Todo el sistema
# de evidencia del harness se apoya en que ese sha sea lo que el autor puso ahí.
#
# `.agents/mutation.lock` no basta: declara la intención, no la impide. Y el
# aislamiento nativo de la tool Agent tampoco sirve tal cual — se probó el
# 2026-09-04 y el worktree sale de HEAD con el árbol limpio, así que el reviewer
# no ve el diff que debe revisar. De ahí que haya que crear el worktree Y
# aplicar el diff staged dentro.

_ra_sandbox() { # <función>
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/review-aislado.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo base > base.txt
    git "$A" -A
    git "$C" -qm base 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_stage_algo() { local A=add; printf 'let x = %s\n' "${1:-1}" > app.txt; git "$A" app.txt; }

# ── 1. El reviewer ve EXACTAMENTE el mismo diff ─────────────────────
# Si no, el aislamiento no sirve: revisaría otra cosa, que es peor que no revisar.
_case_el_worktree_lleva_el_diff() {
  _stage_algo 7
  local wt; wt="$(bash tools/review-aislado.sh preparar 2>/dev/null | tail -1)"
  [ -n "$wt" ] && [ -d "$wt" ] || { echo "    'preparar' no devolvió un worktree usable: '$wt'"; return 1; }
  local aqui alla
  aqui="$(git diff --cached | shasum -a 256 | cut -c1-16)"
  alla="$(git -C "$wt" diff --cached | shasum -a 256 | cut -c1-16)"
  [ "$aqui" = "$alla" ] || {
    echo "    el worktree NO tiene el mismo diff staged:"
    echo "      autor:    $aqui"
    echo "      worktree: $alla"
    echo "    El reviewer estaría revisando algo distinto de lo que se va a commitear."
    bash tools/review-aislado.sh limpiar >/dev/null 2>&1
    return 1; }
  grep -q 'let x = 7' "$wt/app.txt" 2>/dev/null || {
    echo "    el contenido del cambio no llegó al worktree"
    bash tools/review-aislado.sh limpiar >/dev/null 2>&1; return 1; }
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
}
test_el_worktree_lleva_el_mismo_diff_staged() { _ra_sandbox _case_el_worktree_lleva_el_diff; }

# ── 2. Escribir en el worktree NO toca el árbol del autor ───────────
# Es la promesa entera. Sin esto, el aislamiento es decorado.
_case_escribir_alla_no_toca_aqui() {
  _stage_algo 1
  local wt antes despues
  wt="$(bash tools/review-aislado.sh preparar 2>/dev/null | tail -1)"
  antes="$(git diff --cached | shasum -a 256)"
  printf 'MUTANTE\n' > "$wt/app.txt"                   # el reviewer muta SU copia
  local A=add; git -C "$wt" "$A" app.txt 2>/dev/null   # y hasta la stagea
  despues="$(git diff --cached | shasum -a 256)"
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
  [ "$antes" = "$despues" ] || {
    echo "    mutar el worktree movió el diff staged del AUTOR."
    echo "    Eso es el incidente de check-exec-bits otra vez."
    return 1; }
  grep -q 'let x = 1' app.txt || { echo "    el fichero del autor quedó mutado"; return 1; }
}
test_mutar_en_el_worktree_no_mueve_el_diff_del_autor() { _ra_sandbox _case_escribir_alla_no_toca_aqui; }

# ── 3. Si el sha SE MUEVE, la revisión se invalida ──────────────────
# Reproduce el incidente: algo escribe en el índice del autor mientras la
# revisión corre. No se intenta continuar — se aborta con diagnóstico.
_case_sha_movido_invalida() {
  _stage_algo 1
  bash tools/review-aislado.sh preparar >/dev/null 2>&1
  # alguien stagea contenido nuevo a mitad de la revisión (el `git add` del gate)
  local A=add; printf 'let x = 99\n' > app.txt; git "$A" app.txt
  local out rc; out="$(bash tools/review-aislado.sh verificar 2>&1)"; rc=$?
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
  [ "$rc" = "1" ] || {
    echo "    el sha del diff se movió durante la revisión y 'verificar' dio $rc"
    echo "    La revisión tiene que invalidarse, no continuar."
    return 1; }
  printf '%s' "$out" | grep -qi 'cambió\|movió\|invalid' || {
    echo "    aborta pero sin diagnóstico útil: $out"; return 1; }
}
test_si_el_sha_se_mueve_la_revision_se_invalida() { _ra_sandbox _case_sha_movido_invalida; }

# ── 4. Sin movimiento, 'verificar' pasa ─────────────────────────────
_case_sin_movimiento_pasa() {
  _stage_algo 1
  bash tools/review-aislado.sh preparar >/dev/null 2>&1
  local rc; bash tools/review-aislado.sh verificar >/dev/null 2>&1; rc=$?
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
  [ "$rc" = "0" ] || { echo "    sin tocar nada, 'verificar' dio $rc"; return 1; }
}
test_sin_movimiento_verificar_pasa() { _ra_sandbox _case_sin_movimiento_pasa; }

# ── 5. 'limpiar' no deja rastro ─────────────────────────────────────
# Un worktree huérfano por revisión llenaría el disco y confundiría a `git
# worktree list`, que es como aparecieron los worktrees sobrantes que Claude
# Code tuvo que cerrar en julio de 2026.
_case_limpiar_no_deja_rastro() {
  _stage_algo 1
  local wt; wt="$(bash tools/review-aislado.sh preparar 2>/dev/null | tail -1)"
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
  [ -d "$wt" ] && { echo "    el worktree sigue ahí tras limpiar: $wt"; return 1; }
  git worktree list 2>/dev/null | grep -q "$wt" && {
    echo "    git sigue registrando el worktree tras limpiar"; return 1; }
  return 0
}
test_limpiar_no_deja_worktrees_huerfanos() { _ra_sandbox _case_limpiar_no_deja_rastro; }

# ── 6. Sin nada staged no hay nada que aislar, y se dice ────────────
_case_sin_staged_avisa() {
  local out rc; out="$(bash tools/review-aislado.sh preparar 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    sin nada staged 'preparar' dio $rc (esperaba 3)"; return 1; }
  printf '%s' "$out" | grep -qi 'staged\|nada que' || { echo "    no dice por qué: $out"; return 1; }
}
test_sin_nada_staged_preparar_avisa() { _ra_sandbox _case_sin_staged_avisa; }

# ── 7. Un segundo 'preparar' NO destruye la revisión en curso ───────
# Lo cazó la primera review hecha con este mismo mecanismo. `preparar` llamaba a
# `limpiar` si ya había estado, asumiendo que era basura huérfana — y silenciando
# stderr. Una sesión interrumpida que nunca llegó a `limpiar` deja ese estado
# puesto, y la siguiente revisión, aunque sea de otra cosa, se lleva por delante
# el worktree de la primera.
#
# Y hay algo peor que perder el worktree: `preparar` también sobreescribía el sha
# de referencia. Si el diff no cambió entre las dos —un reintento del mismo
# cambio es plausible— el `verificar` de la primera PASA aunque su worktree se
# destruyera a mitad. Es la corrupción silenciosa que esto existe para impedir,
# un nivel más abajo.
_case_preparar_dos_veces_no_pisa() {
  _stage_algo 1
  local wt1; wt1="$(bash tools/review-aislado.sh preparar 2>/dev/null | tail -1)"
  [ -d "$wt1" ] || { echo "    el primer preparar no dejó worktree"; return 1; }
  local out rc; out="$(bash tools/review-aislado.sh preparar 2>&1)"; rc=$?
  [ "$rc" = "3" ] || {
    echo "    un segundo 'preparar' con una revisión en curso dio $rc (esperaba 3)"
    bash tools/review-aislado.sh limpiar >/dev/null 2>&1; return 1; }
  [ -d "$wt1" ] || {
    echo "    el segundo 'preparar' DESTRUYÓ el worktree de la revisión en curso"
    return 1; }
  printf '%s' "$out" | grep -qi 'en curso\|ya hay\|limpiar' || {
    echo "    falla, pero no dice cómo salir del atasco: $out"
    bash tools/review-aislado.sh limpiar >/dev/null 2>&1; return 1; }
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
}
test_un_segundo_preparar_no_pisa_la_revision_en_curso() {
  _ra_sandbox _case_preparar_dos_veces_no_pisa
}

# ── 8. Un cambio BINARIO también viaja al worktree ──────────────────
# `git diff --cached` sin `--binary` emite "Binary files differ", que no es un
# patch: `git apply` es atómico y falla entero, así que no deja un worktree
# parcial creyéndose completo — falla alto, que es lo correcto. Pero significa
# que ningún commit que toque un binario podría revisarse. Lo encontró la primera
# review hecha con este mecanismo.
_case_binario_viaja() {
  local A=add
  printf '\x00\x01\x02\x03binario\n' > datos.bin
  git "$A" datos.bin
  local wt; wt="$(bash tools/review-aislado.sh preparar 2>/dev/null | tail -1)"
  [ -n "$wt" ] && [ -d "$wt" ] || {
    echo "    con un binario staged, 'preparar' no pudo crear el worktree"
    echo "    Ningún commit que toque un binario podría revisarse."
    return 1; }
  local aqui alla
  aqui="$(git diff --cached --binary | shasum -a 256 | cut -c1-16)"
  alla="$(git -C "$wt" diff --cached --binary | shasum -a 256 | cut -c1-16)"
  bash tools/review-aislado.sh limpiar >/dev/null 2>&1
  [ "$aqui" = "$alla" ] || { echo "    el binario no viajó idéntico: $aqui vs $alla"; return 1; }
}
test_un_cambio_binario_viaja_al_worktree() { _ra_sandbox _case_binario_viaja; }
