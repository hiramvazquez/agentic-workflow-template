#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-layers.sh — baseline de dirección sobre imports directos
# ════════════════════════════════════════════════════════════════════
# Enforza AGENTS.md §3 ("el dominio no depende de UI ni de infraestructura")
# de forma MECÁNICA, sobre directivas de import del archivo — no construye un
# grafo, no resuelve dependencias transitivas y no detecta ciclos. Es la
# diferencia entre un detector que el equipo respeta y uno
# que aprende a ignorar (Google midió que por encima de ~10% de falsos
# positivos los analizadores se descartan sistemáticamente).
#
# Reglas: tools/layers.conf   ·   Contrato de salida: LAYERS_SUMMARY errors=<N>
#
#   bash tools/check-layers.sh          # reporta y sale 1 si hay violaciones
#   DRIFT_SRC_DIRS="app lib" bash …     # acota dónde buscar
set -uo pipefail
# El lib se resuelve desde la UBICACION de este script, antes del `cd`: tomarlo
# relativo a la raiz del repo dejaria de encontrarlo en cuanto el harness viva
# en un subdirectorio — la misma clase de fallo que este detector protagoniza.
_DET_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/detector-run.sh"
# shellcheck source=tools/lib/detector-run.sh
. "$_DET_LIB" 2>/dev/null || true
command -v detector_run_init >/dev/null 2>&1 && detector_run_init check-layers

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# ── ¿Aplico en este repo? (decisión del owner, 2026-09-03) ──────────
# En un repo cuyo producto es el propio harness no hay codigo de app que mirar,
# y un `errors=0` que nadie midio alimenta un trinquete que SOLO BAJA. Se
# declara "no aplica" y se sale 0: NO es exit 3, que significa "no pude mirar" —
# aqui el detector funciona perfectamente, es que no hay nada de su competencia.
_DET_SCOPE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/scope.sh"
# shellcheck source=tools/lib/scope.sh
if [ -f "$_DET_SCOPE" ]; then
  # El stderr NO se manda a /dev/null: `_scope_verifica_declaracion` corre al
  # sourcear y es quien AVISA de una contradiccion declarado-vs-evidencia.
  # Silenciarlo hacia que en CI el detector saliera 3 con la salida vacia:
  # un gate que corta sin decir por que.
  . "$_DET_SCOPE" || true
  if command -v scope_detectores_de_app_aplican >/dev/null 2>&1 \
     && ! scope_detectores_de_app_aplican; then
    echo "LAYERS_SUMMARY estado=no-aplica errors=0"
    echo "ℹ️  check-layers: no aplica — este repo declara project_kind: harness, y aqui no"
    echo "   hay codigo de app que mirar. No se retiro del template: un adoptante"
    echo "   con fuentes reales lo sigue teniendo."
    exit 0
  fi
fi

CONF="${LAYERS_CONF:-tools/layers.conf}"
ERRORS=0
FILES=0

# Las DOS salidas de abajo son las que hacian indistinguible "mire y esta
# limpio" de "no tenia nada que mirar". Siguen saliendo 0 —cambiar eso es un
# cambio de contrato que va aparte (f-6b761f06)— pero ya no son mudas: la
# primera registra targets:null (sin conf, ni siquiera se que es un objetivo) y
# la segunda targets:0 (se contarlos y hay cero). Son estados distintos.
[ -f "$CONF" ] || { echo "LAYERS_SUMMARY errors=0"; exit 0; }

SRC_DIRS="${DRIFT_SRC_DIRS:-ios android web src app lib Sources}"
EXISTING=""; for d in $SRC_DIRS; do [ -d "$d" ] && EXISTING="$EXISTING $d"; done
[ -z "$EXISTING" ] && {
  command -v detector_targets >/dev/null 2>&1 && detector_targets 0
  echo "LAYERS_SUMMARY errors=0"; exit 0; }

# ── Extracción de imports REALES ────────────────────────────────────
# Solo cuenta una directiva de import al INICIO de línea. Un `// import X`
# o un `let s = "import X"` no son dependencias — son texto. Además se
# eliminan los bloques /* … */ antes de mirar.
extract_imports() {
  awk '
    { line = $0 }
    # Elimina bloques /* ... */ (multi-línea)
    /\/\*/ { inblock = 1 }
    inblock { if (line ~ /\*\//) { inblock = 0 }; next }
    { print line }
  ' "$1" 2>/dev/null | sed -E '
      # Swift / Kotlin / Java:  import Foo.Bar     (tolera @testable)
      s/^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*).*$/\2/
      t done
      # TS / JS:  import x from "mod"  ·  import "mod"  ·  export … from "mod"
      s/^[[:space:]]*(import|export)[[:space:]].*from[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*$/\2/
      t done
      s/^[[:space:]]*import[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*$/\1/
      t done
      # CommonJS:  const x = require("mod")
      s/^[[:space:]]*(const|let|var)[[:space:]].*require\([[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*$/\2/
      t done
      # Python:  from pkg.mod import x
      s/^[[:space:]]*from[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]+import[[:space:]].*$/\1/
      t done
      # C / C++:  #include <hdr>  ·  #include "hdr"
      s/^[[:space:]]*#include[[:space:]]*[<"]([^>"]+)[>"].*$/\1/
      t done
      # Nada de lo anterior → no es un import
      d
      :done
  ' | sed -E 's/[[:space:]]+$//' | grep -v '^$' || true
}

# ── Recorrido: por cada archivo, contra cada regla que aplique ──────
while IFS= read -r file; do
  [ -z "$file" ] && continue
  FILES=$((FILES+1))
  rel="./${file#./}"
  imports=""

  while IFS= read -r rule; do
    case "$rule" in ''|'#'*) continue ;; esac
    # <glob> :: <regex prohibido> :: <mensaje>
    glob="$(printf '%s' "$rule"  | awk -F' *:: *' '{print $1}')"
    deny="$(printf '%s' "$rule"  | awk -F' *:: *' '{print $2}')"
    msg="$(printf '%s' "$rule"   | awk -F' *:: *' '{print $3}')"
    [ -z "$glob" ] || [ -z "$deny" ] && continue

    # ¿este archivo pertenece a la capa de la regla?
    # shellcheck disable=SC2254
    case "$rel" in $glob) : ;; *) continue ;; esac

    # Extrae imports una sola vez por archivo (lazy).
    [ -z "$imports" ] && imports="$(extract_imports "$file")"
    [ -z "$imports" ] && continue

    while IFS= read -r mod; do
      [ -z "$mod" ] && continue
      if printf '%s' "$mod" | grep -qE "$deny" 2>/dev/null; then
        echo "❌ $file: importa \`$mod\` — $msg"
        ERRORS=$((ERRORS+1))
      fi
    done <<< "$imports"
  done < "$CONF"
done < <(find $EXISTING -type f \
           \( -name '*.swift' -o -name '*.kt' -o -name '*.kts' -o -name '*.java' \
              -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
              -o -name '*.py' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' \) \
           2>/dev/null)

command -v detector_targets >/dev/null 2>&1 && detector_targets "$FILES"
echo "LAYERS_SUMMARY errors=$ERRORS"
[ "$ERRORS" -eq 0 ] && exit 0
echo "   Las capas son un contrato (AGENTS.md §3). Invierte la dependencia o mueve el archivo."
exit 1
