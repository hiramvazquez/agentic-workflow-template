#!/usr/bin/env bash
# Sandbox compartido de los tests de `verify-run` — un repo git de usar y tirar
# con las herramientas del harness copiadas dentro.
#
# Vive aquí porque `test_verify_marker.sh` cruzó el hard limit de 400 líneas
# (§4) y se partió por la misma junta que el código: qué LIGA la evidencia al
# diff (el marker) por un lado, y qué DECIDE cuánto se ejecuta (el carril) por
# otro. Duplicar el sandbox en los dos ficheros habría sido el drift que este
# repo persigue en todo lo demás. Mismo patrón que `dora-sandbox.sh`.

_vm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/app"
  cp "$PROJECT_ROOT/tools/verify-run.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-verify-marker.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/" 2>/dev/null
  # El clasificador de carriles y su conf: sin ellos `verify-run` cae en su
  # default seguro (correr TODO) y el fixture no puede probar el carril ligero.
  # `_VM_SIN_CARRIL=1` monta el sandbox SIN él a propósito, para probar
  # justo ese default. Borrarlo después no vale: dejaría una eliminación sin
  # stagear y `verify-run` rechazaría el árbol antes de llegar al carril.
  if [ "${_VM_SIN_CARRIL:-0}" != "1" ]; then
    cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/" 2>/dev/null
    cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/" 2>/dev/null
  fi
  (
    cd "$d" || exit 1
    local A=add C=commit
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    printf 'full\n' > tools/preset
    printf 'true\n' > tools/verify.conf          # "build" que siempre pasa
    # TODO trackeado en el commit inicial, herramientas incluidas. Antes solo se
    # commiteaba `seed.txt` y el resto quedaba sin trackear — un árbol que ningún
    # repo real tiene, y que hacía invisible el agujero de `f-5a4e0204`: si el
    # fixture ya vive con ficheros sin trackear, no puede probar qué pasa cuando
    # aparece uno.
    git "$A" -A 2>/dev/null
    git "$C" -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_stage_producto() { mkdir -p app; printf 'let x = %s\n' "${1:-1}" > app/Main.swift; git add app/Main.swift; }
