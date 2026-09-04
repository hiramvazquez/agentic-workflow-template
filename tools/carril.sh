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
# Exit: 0 clasificó (incluido `ninguno`) · 3 no pude mirar (sin git, sin conf)
set -uo pipefail

_RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CONF="${CARRIL_CONF:-$_RAIZ/carril.conf}"

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "⚠️  carril: esto no es un repo git — no puedo derivar nada (§14.3)." >&2
  echo "CARRIL_SUMMARY carril=desconocido archivos=0"
  exit 3
}
cd "$(git rev-parse --show-toplevel)" || exit 3

[ -f "$CONF" ] || {
  echo "⚠️  carril: falta $CONF — no puedo clasificar sin sus patrones (§14.3)." >&2
  echo "CARRIL_SUMMARY carril=desconocido archivos=0"
  exit 3
}

ARCHIVOS="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"
N="$(printf '%s' "$ARCHIVOS" | grep -c . || true)"
if [ "${N:-0}" -eq 0 ]; then
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

echo "CARRIL_SUMMARY carril=$CARRIL archivos=$N"
exit 0
