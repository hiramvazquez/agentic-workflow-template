#!/usr/bin/env bash
# Sandbox y caminos de invocación compartidos por los tests de
# `check-review-marker.sh` — un repo git de usar y tirar con los tres anillos
# cableados encima.
#
# Vive aquí porque `test_review_marker_preset.sh` cruzó el hard limit de 400
# líneas (§4) al llegar la fase 3 del PRD 0011, y se partió por la junta que ya
# tenía: el PRESET (qué hace cada anillo con el mismo veredicto) por un lado, y
# el CARRIL (si hace falta veredicto siquiera) por otro. Mismo patrón que
# `dora-sandbox.sh` y `verify-sandbox.sh`.

_rm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tools/drift-ratchet.sh"
  # El clasificador de carriles: desde la fase 3 del PRD 0011 este gate le
  # pregunta. Sin él debe seguir exigiendo review — eso lo fija su propio caso.
  cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # TODO trackeado en el commit inicial, herramientas incluidas: desde la
    # fase 3 el gate ejecuta el clasificador desde el ÍNDICE, así que un sandbox
    # con `tools/` sin trackear no tendría clasificador y probaría otra cosa.
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# Camino Anillo 1 (lefthook): invoca el script DIRECTO.
_anillo1() { WORKFLOW_PRESET="$1" bash tools/check-review-marker.sh --staged >/dev/null 2>&1; echo $?; }
# Camino Anillo 2 (hook): pasa por reviewer-gate.
_anillo2() {
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET="$1" bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

# Un clasificador de mentira, COMMITEADO: el gate lo lee del índice, y dejarlo
# solo staged lo metería en el diff —donde `tools/carril.sh` es superficie de
# enforcement— y el caso pasaría por el guard de llaves en vez de por lo suyo.
_falso_clasificador() { # <linea...>
  local A=add C=commit
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > tools/carril.sh
  chmod +x tools/carril.sh
  git "$A" tools/carril.sh
  git "$C" -qm falso 2>/dev/null
}
