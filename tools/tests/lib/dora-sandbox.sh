#!/usr/bin/env bash
# Sandbox compartido de los tests de `dora` — un repo git de usar y tirar con
# los módulos copiados dentro.
#
# Vive aquí porque `test_dora.sh` cruzó el hard limit de 400 líneas (§4) y se
# partió en dos por la misma junta que el código: medir por un lado, agregar la
# serie por otro. Duplicar estos helpers en los dos ficheros habría sido el
# drift que este repo persigue en todo lo demás.

_dora_copiar_modulos() { # <destino> — la lista vive UNA vez
  # Los dos sandboxes copiaban su propia lista y una se quedó sin `dora_git.py`
  # al partir el módulo: un fichero que falta aquí no da error, da un traceback
  # dentro del sandbox y un test que falla por la razón equivocada.
  local f
  for f in dora.sh dora.py dora_git.py dora_rollup.py read-events.py; do
    cp "$PROJECT_ROOT/tools/metrics/$f" "$1/tools/metrics/" 2>/dev/null
  done
}

_dora_sandbox() { # <función>
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools/metrics" "$d/.agents/state/metrics"
  _dora_copiar_modulos "$d"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > a.txt; git "$A" -A 2>/dev/null; git "$C" -qm "primero" 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_dora_sandbox_vacio() { # <función> — repo recién inicializado, sin un solo commit
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics"
  _dora_copiar_modulos "$d"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_dora_review() { # <verdict> <sha>
  printf '{"ts":"2026-09-01T10:00:00Z","agent":"reviewer","verdict":"%s","staged_sha":"%s"}\n' \
    "$1" "$2" >> .agents/state/review-history.jsonl
}
_dora() { bash tools/metrics/dora.sh 2>&1; }
