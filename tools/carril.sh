#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# carril.sh — cuánto pesa este cambio, derivado de lo que toca
# ════════════════════════════════════════════════════════════════════
# PRD 0011. El workflow cobraba lo mismo por añadir un string que por reescribir
# el motor. Esto es lo que permite cobrar en proporción.
#
# NO decide qué se ejecuta: solo clasifica. Quién consume el carril y qué hace
# con él es la fase 2 — separarlo permite medir cuántos cambios caen en cada
# carril ANTES de decidir qué se les cobra.
#
# El autor nunca declara su carril: se deriva del diff staged. Una declaración
# es una afirmación, y este repo lleva una sesión entera aprendiendo que las
# afirmaciones caducan y las derivaciones no.
#
# Contrato de stdout:  CARRIL_SUMMARY carril=<ligero|normal|estructural|ninguno> archivos=<N>
# Con `--tests`, en cambio, imprime QUÉ hay que ejecutar para este cambio:
#   NINGUNO          nada se ejecuta (carril ligero)
#   TODOS            la suite entera (estructural, o normal sin tests derivables)
#   <nombres>        un test por línea (normal, derivados por REFERENCIA)
# Con `--review`:    REVIEW_DEPTH profundidad=<ninguna|enfocada|profunda> carril=<...>
#   Cuánta review pide este cambio (PRD 0011 §6b). La profundidad vive aquí y no
#   en el prompt del revisor porque un prompt no se puede testear y esto sí, y
#   porque el revisor debe DERIVARLA, no recordarla ni fiarse de quien le invoca.
#
# Se derivan buscando los tests que NOMBRAN el fichero tocado, no por convención
# de nombres: la convención no se cumple —`check-drift.sh` lo ejercitan
# `test_drift_stop` y `test_drift_aggregation`— y una convención que falla en
# silencio dejaría tests sin correr creyendo que corrieron.
#
# Exit: 0 clasificó (incluido `ninguno`) · 3 no pude mirar (sin git, sin conf)
set -uo pipefail

_RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CONF="${CARRIL_CONF:-$_RAIZ/carril.conf}"

# `--tests` se resuelve ANTES que nada: sus salidas de fallo tienen que hablar
# el vocabulario de `--tests`, no el del resumen. Imprimir `CARRIL_SUMMARY` aquí
# hacía que el consumidor —que hace `$(carril.sh --tests || echo TODOS)`, y eso
# CONCATENA en vez de reemplazar— recibiera basura de dos líneas, la tomara como
# nombres de test, no casara ninguno, y firmara en verde con CERO tests corridos.
_MODO_TESTS=0
_MODO_REVIEW=0
[ "${1:-}" = "--tests" ]  && _MODO_TESTS=1
[ "${1:-}" = "--review" ] && _MODO_REVIEW=1
_no_pude() { # <mensaje>
  echo "⚠️  carril: $1 (§14.3)." >&2
  # Cada modo contesta en SU vocabulario, y siempre hacia el lado seguro: no
  # saber cuánto pesa un cambio nunca puede traducirse en pedir menos. Imprimir
  # el resumen aquí es justo lo que hizo que un consumidor tomara una salida de
  # fallo por datos buenos en la fase 2.
  [ "$_MODO_TESTS" = "1" ]  && { echo "TODOS"; exit 3; }
  [ "$_MODO_REVIEW" = "1" ] && { echo "REVIEW_DEPTH profundidad=profunda carril=desconocido"; exit 3; }
  echo "CARRIL_SUMMARY carril=desconocido archivos=0"
  exit 3
}

git rev-parse --show-toplevel >/dev/null 2>&1 || \
  _no_pude "esto no es un repo git — no puedo derivar nada"
cd "$(git rev-parse --show-toplevel)" || exit 3

[ -f "$CONF" ] || _no_pude "falta $CONF — no puedo clasificar sin sus patrones"

MODO="${1:-}"
ARCHIVOS="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"
N="$(printf '%s' "$ARCHIVOS" | grep -c . || true)"
if [ "${N:-0}" -eq 0 ]; then
  [ "$MODO" = "--tests" ]  && { echo "NINGUNO"; exit 0; }
  [ "$MODO" = "--review" ] && { echo "REVIEW_DEPTH profundidad=ninguna carril=ninguno"; exit 0; }
  echo "CARRIL_SUMMARY carril=ninguno archivos=0"
  exit 0
fi

# ── El patrón de un carril, ¿casa este fichero? ─────────────────────
_casa_carril() { # <carril> <ruta>
  local carril="$1" ruta="$2" linea glob
  while IFS= read -r linea; do
    case "$linea" in ''|'#'*) continue ;; esac
    [ "${linea%%|*}" = "$carril" ] || continue
    glob="${linea#*|}"
    # shellcheck disable=SC2254  # el glob viene del conf a propósito
    case "$ruta" in $glob) return 0 ;; esac
  done < "$CONF"
  return 1
}

# La MÁS SEVERA gana: en cuanto un fichero es estructural, se acabó.
CARRIL=ligero
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if _casa_carril estructural "$f"; then
    CARRIL=estructural
    break
  fi
  # Lo que no casa `ligero` es `normal`: el default es el SEGURO, porque un
  # fichero que nadie previó puede ejecutar.
  _casa_carril ligero "$f" || CARRIL=normal
done <<< "$ARCHIVOS"

# ── --review: cuánta review pide esto (PRD 0011 §6b) ────────────────
# `ninguna` porque nada de lo tocado se ejecuta — el gate ya lo exime, y esto
# es la misma decisión dicha para quien pregunte. `enfocada` es el diff, sus
# tests y buscar un mutante que sobreviva: NO re-correr la suite, que
# `verify-run` ya corrió contra este mismo sha y su marker lo demuestra.
# `profunda` es el carril donde un fallo puede hacer que NINGÚN detector corra,
# y es el único que justifica una pasada de veinte minutos.
if [ "$MODO" = "--review" ]; then
  case "$CARRIL" in
    ligero) echo "REVIEW_DEPTH profundidad=ninguna carril=ligero" ;;
    normal) echo "REVIEW_DEPTH profundidad=enfocada carril=normal" ;;
    # Cualquier otra cosa —estructural, o un carril que alguien añada mañana y
    # nadie mapee aquí— pide la profunda. El default cae del lado caro.
    *)      echo "REVIEW_DEPTH profundidad=profunda carril=$CARRIL" ;;
  esac
  exit 0
fi

if [ "$MODO" != "--tests" ]; then
  echo "CARRIL_SUMMARY carril=$CARRIL archivos=$N"
  exit 0
fi

# ── --tests: qué ejecutar para este cambio ──────────────────────────
[ "$CARRIL" = "ligero" ]      && { echo "NINGUNO"; exit 0; }
[ "$CARRIL" = "estructural" ] && { echo "TODOS"; exit 0; }

# Normal: los tests que NOMBRAN alguno de los ficheros tocados.
# El fallback a TODOS se decide POR FICHERO, no sobre la unión. Antes se miraba
# si la unión entera quedaba vacía, así que un fichero sin tests que viajara con
# otro que sí los tiene quedaba sin verificar y se firmaba en verde — y el mismo
# fichero, commiteado solo, sí caía en TODOS. Lo cazó el review.
DERIVADOS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  _de_este=""
  # El propio fichero de test no se deriva a sí mismo por su nombre: si lo que
  # cambió ES un test, ese test corre igualmente por la vía de abajo.
  case "$base" in test_*.sh) DERIVADOS="${DERIVADOS}${base%.sh}"$'\n'; continue ;; esac
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    _de_este="${_de_este}$(basename "$t" .sh)"$'\n'
  done <<< "$(grep -rl -- "$base" tools/tests/test_*.sh 2>/dev/null || true)"
  if [ -z "$(printf '%s' "$_de_este" | grep -v '^$' || true)" ]; then
    # Este fichero no lo nombra ningún test. Puede estar sin cubrir, o su test
    # puede ejercitarlo sin nombrarlo. Correr solo los tests de sus compañeros
    # de commit firmaría en verde sin haber verificado nada suyo.
    echo "TODOS"
    exit 0
  fi
  DERIVADOS="${DERIVADOS}${_de_este}"
done <<< "$ARCHIVOS"

DERIVADOS="$(printf '%s' "$DERIVADOS" | grep -v '^$' | sort -u)"
if [ -z "$DERIVADOS" ]; then
  # Ningún test nombra lo que cambió. Puede estar sin cubrir, o su test puede
  # ejercitarlo sin nombrarlo — no se sabe. Correr CERO tests aquí firmaría una
  # evidencia vacía, que es el gate mudo que §14.3 prohíbe. Se corre todo.
  echo "TODOS"
  exit 0
fi
printf '%s\n' "$DERIVADOS"
exit 0
