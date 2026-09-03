#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-drift.sh — AGREGADOR de detectores mecánicos
# ════════════════════════════════════════════════════════════════════
# Ya NO es "un montón de greps". Su papel ahora es agregar los detectores
# especializados y emitir el contrato que consume el drift-ratchet:
#
#   tools/check-layers.sh   → capas, sobre el GRAFO DE IMPORTS
#   tools/semgrep-scan.sh   → patrones, sobre el AST
#   (aquí)                  → solo lo que de verdad es estructura de archivos
#                             (tamaños, existencia de tests) — lo único donde
#                             un `find`/`wc` no puede dar falso positivo.
#
# Por qué se movieron los greps: `grep -E '(==|!=) *"[^"]+"'` matchea el
# comentario que documenta el anti-patrón, el string de un test y el propio
# doc. Google midió que por encima de ~10% de falsos positivos los analizadores
# se descartan — y un agente, además, aprende a evadirlos.
#
# Contrato de salida (lo parsea drift-ratchet.sh):
#   - líneas de hallazgo con prefijo ❌ (error) o ⚠️ (warning)
#   - última línea EXACTA:  DRIFT_SUMMARY errors=<N> warns=<M>
set -uo pipefail
# El lib se resuelve desde la UBICACION de este script, antes del `cd`: tomarlo
# relativo a la raiz del repo dejaria de encontrarlo en cuanto el harness viva
# en un subdirectorio (la leccion de f-6b761f06).
_DET_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/detector-run.sh"
# shellcheck source=tools/lib/detector-run.sh
. "$_DET_LIB" 2>/dev/null || true
command -v detector_run_init >/dev/null 2>&1 && detector_run_init check-drift

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# ── ¿Aplico en este repo? (decisión del owner, 2026-09-03) ──────────
# En un repo cuyo producto es el propio harness no hay codigo de app que mirar,
# y un `errors=0` que nadie midio alimenta un trinquete que SOLO BAJA. Se
# declara "no aplica" y se sale 0: NO es exit 3, que significa "no pude mirar" —
# aqui el detector funciona perfectamente, es que no hay nada de su competencia.
_DET_SCOPE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/scope.sh"
# shellcheck source=tools/lib/scope.sh
if [ -f "$_DET_SCOPE" ]; then
  # La consulta va en SUBSHELL con SCOPE_NO_CI_EXIT=1, y el stderr SÍ pasa.
  # Las tres cosas importan y cada una tapa un fallo distinto:
  #   · subshell + SCOPE_NO_CI_EXIT: `scope.sh` ejecuta
  #     `_scope_verifica_declaracion` al sourcearse, y bajo CI esa funcion hace
  #     `exit 3` si la declaracion contradice a la evidencia. Sourceada directa,
  #     ese exit MATA al detector — y peor: enmascara la violacion real de capas
  #     con una queja de configuracion. Actions exporta CI=true en todos los jobs.
  #   · el stderr sin redirigir: ese aviso de contradiccion es justo lo que el
  #     adoptante necesita leer. Silenciarlo dejaba al detector cortando sin
  #     decir por que.
  # El repo ya tenia el patron para una CONSULTA en session-start.sh:148.
  _DET_APLICAN=0
  SCOPE_NO_CI_EXIT=1 bash -c ". '$_DET_SCOPE' 2>/dev/null; \
    command -v scope_detectores_de_app_aplican >/dev/null 2>&1 || exit 0; \
    scope_detectores_de_app_aplican" || _DET_APLICAN=1
  if [ "$_DET_APLICAN" = "1" ]; then
    echo "DRIFT_SUMMARY estado=no-aplica errors=0 warns=0"
    echo "ℹ️  check-drift: no aplica — este repo declara project_kind: harness, y aqui no"
    echo "   hay codigo de app que mirar. No se retiro del template: un adoptante"
    echo "   con fuentes reales lo sigue teniendo."
    exit 0
  fi
fi

ERRORS=0; WARNS=0; TARGETS=0
err() { echo "❌ $1"; ERRORS=$((ERRORS+1)); }
warn(){ echo "⚠️  $1"; WARNS=$((WARNS+1)); }

# Dónde buscar código (ajusta a tus carpetas).
SRC_DIRS="${DRIFT_SRC_DIRS:-ios android web src app lib Sources}"
EXISTING=""; for d in $SRC_DIRS; do [ -d "$d" ] && EXISTING="$EXISTING $d"; done

# ════════════════════════════════════════════════════════════════════
# 1) CAPAS — delegado al grafo de imports (0 falsos positivos)
# ════════════════════════════════════════════════════════════════════
if [ -f tools/check-layers.sh ]; then
  while IFS= read -r line; do
    case "$line" in
      "❌"*) echo "$line"; ERRORS=$((ERRORS+1)) ;;
      "⚠️"*) echo "$line"; WARNS=$((WARNS+1)) ;;
    esac
  done < <(bash tools/check-layers.sh 2>/dev/null)
fi

# ════════════════════════════════════════════════════════════════════
# 2) PATRONES — delegado a Semgrep (AST, no texto)
# ════════════════════════════════════════════════════════════════════
if [ -f tools/semgrep-scan.sh ]; then
  while IFS= read -r line; do
    case "$line" in
      "❌"*) echo "$line"; ERRORS=$((ERRORS+1)) ;;
      "⚠️"*) echo "$line"; WARNS=$((WARNS+1)) ;;
    esac
  done < <(bash tools/semgrep-scan.sh 2>/dev/null)
fi

# ════════════════════════════════════════════════════════════════════
# 3) ESTRUCTURA — lo único que se mide bien sin parsear
# ════════════════════════════════════════════════════════════════════

# 3a) Archivos por encima del hard limit (AGENTS.md §4).
HARD=${DRIFT_FILE_HARD:-400}
if [ -n "$EXISTING" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    TARGETS=$((TARGETS+1))
    n=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ "${n:-0}" -gt "$HARD" ] && err "Archivo > $HARD líneas: $f ($n líneas)"
  done < <(find $EXISTING -type f \
             \( -name '*.swift' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \
                -o -name '*.js' -o -name '*.py' -o -name '*.java' -o -name '*.go' \) 2>/dev/null)
fi

# 3b) Lógica de producción sin test espejo (TDD, AGENTS.md §5).
#     Heurística por EXISTENCIA de archivo, no por contenido: antes esto hacía
#     `grep "$base" *Tests.swift`, que se satisface con solo mencionar el nombre
#     en un comentario — trivial de gamear para un agente. Ahora exige que
#     exista un archivo de test con el nombre esperado.
#     Sigue siendo una señal, no un veredicto: la calidad real del test la mide
#     `tools/mutation-score.sh`, que es el gate que de verdad importa.
if [ -n "$EXISTING" ]; then
  # UN solo `find` para el universo de tests, no 6 por archivo de lógica: la
  # versión anterior era O(n·m) y en un repo mediano excedía el presupuesto del
  # hook (que al agotar timeout NO bloquea — el gate moría en silencio).
  ALL_TEST_BASES="$(find $EXISTING . -maxdepth 6 -type f 2>/dev/null \
    | sed -E 's|.*/||' | grep -iE '(test|spec)' | sort -u)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"; base="${base%.*}"
    found=0
    for cand in "${base}Tests." "${base}Test." "${base}_test." "${base}.test." "${base}.spec." "test_${base}."; do
      if printf '%s\n' "$ALL_TEST_BASES" | grep -qF "$cand"; then
        found=1; break
      fi
    done
    [ "$found" -eq 0 ] && warn "Lógica sin archivo de test (TDD §5): $f — falta ${base}Tests/${base}.test/test_${base}"
  done < <(find $EXISTING -type f \
             \( -name '*UseCase.*' -o -name '*Logic.*' -o -name '*Reducer.*' -o -name '*Service.*' \) \
             2>/dev/null | grep -viE '(test|spec|mock|fake|stub)')
fi

# ════════════════════════════════════════════════════════════════════
# 4) TUS convenciones estructurales
# ════════════════════════════════════════════════════════════════════
# <!-- FILL: añade aquí SOLO lo que se mida por estructura de archivos/rutas
#      (naming, existencia, ubicación). Todo lo que dependa de entender el
#      código va a tools/semgrep/rules/*.yaml; todo lo de dependencias va a
#      tools/layers.conf. Regla: si tu check necesita un grep sobre el CUERPO
#      del archivo, está en el sitio equivocado.
#      Ejemplos válidos aquí:
#        - toda View tiene su ViewModel hermano
#        - toda migración de DB tiene su archivo de rollback
#        - todo módulo bajo Feature/ tiene README
# -->

echo ""
# `targets` son los archivos de codigo que este agregado llego a mirar. Un
# DRIFT_SUMMARY con errors=0 y targets=0 no es "el proyecto esta limpio": es
# "no habia nada que medir", y ese cero alimenta un trinquete que solo baja.
command -v detector_targets >/dev/null 2>&1 && detector_targets "$TARGETS"
echo "DRIFT_SUMMARY errors=$ERRORS warns=$WARNS"
# exit 0 siempre: el GATE lo aplica drift-ratchet (delta), no este script.
exit 0
