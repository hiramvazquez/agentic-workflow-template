#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# run-tests.sh — runner de los tests de shell del HARNESS
# ════════════════════════════════════════════════════════════════════
# Los gates son código. Código con lógica de decisión sin test es deuda
# (AGENTS.md §5). Estos tests fijan los INVARIANTES del harness, no del
# producto: si alguien rompe "el ratchet solo baja" o "lite no relaja el
# ratchet", esto falla.
#
#   bash tools/tests/run-tests.sh            # todos
#   bash tools/tests/run-tests.sh verdict    # solo los que matcheen "verdict"
#
# Contrato de un archivo de test: `tools/tests/test_*.sh` que define
# funciones `test_*`. El runner las descubre y las corre en un subshell
# con un repo git temporal como cwd cuando pide aislamiento.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
cd "$PROJECT_ROOT"

FILTER="${1:-}"
PASS=0; FAIL=0; FAILED_NAMES=()

# ── Aserciones disponibles para los tests ───────────────────────────
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  echo "    esperado: [$1]"; echo "    obtenido: [$2]"; return 1
}
assert_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  echo "    esperaba encontrar: [$2]"; echo "    en: [$1]"; return 1
}
assert_exit() { # assert_exit <esperado> <comando...>
  local want="$1"; shift
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then return 0; fi
  echo "    exit esperado: $want · obtenido: $got · cmd: $*"; return 1
}

# Crea un repo git desechable y ejecuta el cuerpo dentro. Se limpia siempre.
with_temp_repo() { # with_temp_repo <función>
  local d; d="$(mktemp -d)"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo init > .keep; git add .keep; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?
  rm -rf "$d"
  return $rc
}
export -f assert_eq assert_contains assert_exit with_temp_repo

# ── Descubrimiento y ejecución ──────────────────────────────────────
for f in "$PROJECT_ROOT"/tools/tests/test_*.sh; do
  [ -f "$f" ] || continue
  BASE="$(basename "$f")"
  # El filtro casa contra el ARCHIVO o contra el NOMBRE de un test. Si casa el
  # archivo, corren todos sus tests; si no, solo los tests cuyo nombre casa.
  FILE_MATCH=0
  if [ -z "$FILTER" ]; then
    FILE_MATCH=1
  else
    case "$BASE" in *"$FILTER"*) FILE_MATCH=1 ;; esac
  fi

  # shellcheck disable=SC1090
  . "$f"
  ALL_TESTS="$(declare -F | awk '{print $3}' | grep '^test_' || true)"

  # ¿Hay algo que correr en este archivo?
  if [ "$FILE_MATCH" -eq 0 ]; then
    HAS=0
    for t in $ALL_TESTS; do case "$t" in *"$FILTER"*) HAS=1 ;; esac; done
    if [ "$HAS" -eq 0 ]; then
      for t in $ALL_TESTS; do unset -f "$t"; done
      continue
    fi
  fi

  echo ""
  echo "━━━ $BASE ━━━"
  for t in $ALL_TESTS; do
    if [ "$FILE_MATCH" -eq 0 ]; then
      case "$t" in *"$FILTER"*) : ;; *) unset -f "$t"; continue ;; esac
    fi
    out="$( "$t" 2>&1 )"; rc=$?
    if [ $rc -eq 0 ]; then
      PASS=$((PASS+1)); printf '  ✅ %s\n' "$t"
    else
      FAIL=$((FAIL+1)); FAILED_NAMES+=("$t"); printf '  ❌ %s\n' "$t"
      [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/     /'
    fi
    unset -f "$t"
  done
done

echo ""
echo "────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ tests del harness: $PASS pasaron, 0 fallaron."
  exit 0
fi
echo "❌ tests del harness: $PASS pasaron, $FAIL FALLARON:"
for n in "${FAILED_NAMES[@]}"; do echo "   - $n"; done
exit 1
