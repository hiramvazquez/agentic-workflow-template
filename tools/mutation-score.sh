#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# mutation-score.sh — el ratchet que mide si los tests COMPRUEBAN algo
# ════════════════════════════════════════════════════════════════════
# La cobertura es un PISO, no una meta: un test que no asserta nada da 100%
# de cobertura y 0 de valor. La métrica real es el MUTATION SCORE: se inyectan
# fallos en el código y se mide qué porcentaje matan los tests.
#
# Por qué importa especialmente con agentes: la función objetivo de un agente
# es "que los tests pasen", y la forma más barata de conseguirlo es escribir
# tests que no comprueban nada. Este es el ÚNICO gate que distingue un test
# real de uno decorativo.
#
# Dirección del ratchet: el piso **SOLO SUBE** (opuesto al drift-ratchet, cuyo
# techo solo baja). Bajarlo a mano = esconder deuda (AGENTS.md §9).
#
#   --check    exit 1 si el score actual está por DEBAJO del piso
#   --update   sube el piso al score actual (nunca lo baja)
#   --report   solo imprime el score
#
# El score se obtiene de:
#   1. $MUTATION_SCORE_OVERRIDE  (tests del harness, o CI que ya lo calculó)
#   2. el runner del stack, en la sección FILL de abajo
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

JSON="${MUTATION_RATCHET_JSON:-tools/mutation-ratchet.json}"
MODE="${1:---check}"

floor() { sed -nE 's/.*"min_score"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$JSON" 2>/dev/null | head -1; }

# ── Cálculo del score ───────────────────────────────────────────────
compute_score() {
  if [ -n "${MUTATION_SCORE_OVERRIDE:-}" ]; then
    printf '%s' "$MUTATION_SCORE_OVERRIDE"; return 0
  fi

  # ── Swift → muter (referencia iOS, ACTIVA — se auto-desactiva sin muter) ─
  # Nacido en el primer proyecto real, y REPARADO ahí mismo dos veces. LENTO
  # (la suite entera por mutante): va en CI/nocturno (Anillo 3) o a mano,
  # NUNCA en pre-commit. Config: muter.conf.yml O muter.conf.json en la raíz
  # (`muter init` moderno genera .yml; versiones viejas .json).
  #
  # muter NO emite JSON fiable por stdout: `--format json` mezcla el logo
  # ASCII y el progreso; el reporte solo es JSON con `-o <archivo>`. La v1
  # hacía json.loads(stdout), fallaba SIEMPRE, y el fallo caía al mensaje de
  # "sin runner configurado" — 30-90 min de muter para un mensaje engañoso
  # (modo de fallo G5: gate anunciado y no operativo). Por eso ahora:
  # reporte a archivo, y todo fallo POST-arranque es RUIDOSO y distinto
  # (return 2), jamás confundible con "no hay runner" (return 1).
  if command -v muter >/dev/null 2>&1 && { [ -f muter.conf.yml ] || [ -f muter.conf.json ]; }; then
    local rc tmp
    tmp="$(mktemp)"
    muter run --format json --skip-update-check -o "$tmp" >/dev/null 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
      echo "muter CORRIÓ y falló (rc=$rc). Repro: muter run --format json -o /tmp/muter.json" >&2
      echo "Si el log dice 'wasn't able to discover any code': cobertura del scheme apagada," >&2
      echo "o la sintaxis Swift del código es más nueva que el SwiftSyntax de tu muter." >&2
      rm -f "$tmp"; return 2
    fi
    # JSON anidado → python3, no sed. Distingue "0 candidatos" de un score:
    # un run sin mutantes descubiertos NO es un 0% — es el detector sin ojos.
    local parsed
    parsed="$(python3 - "$tmp" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
score = total = None
def walk(o):
    global score, total
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "mutationScore" and isinstance(v, (int, float)) and score is None:
                score = int(v)
            if isinstance(v, (int, float)) and total is None and \
               k.lower() in ("totalappliedmutationoperators", "totalmutantsintroduced", "numberofmutants"):
                total = int(v)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(d)
if total == 0:
    print("NOMUTANTS")
elif score is not None:
    print(score)
PY
)"
    rm -f "$tmp"
    case "$parsed" in
      NOMUTANTS)
        echo "muter corrió pero descubrió 0 mutantes: eso NO es un score (ni bueno ni malo)." >&2
        echo "Causas típicas: cobertura del scheme apagada, o sintaxis Swift más nueva que" >&2
        echo "el SwiftSyntax de tu versión de muter (p. ej. typed throws)." >&2
        return 2 ;;
      "")
        echo "muter corrió pero el reporte no trae un mutationScore legible (formato inesperado)." >&2
        return 2 ;;
      *)
        printf '%s' "$parsed"; return 0 ;;
    esac
  fi
  # <!-- FILL: runner de mutación del RESTO de stacks:
  #      Kotlin/Java → PIT · JS/TS → StrykerJS · Python → mutmut.
  #      Contrato: imprime el % ENTERO por stdout, o return 1 (jamás 0 vacío). -->
  return 1
}

_ERRTMP="$(mktemp)"
SCORE="$(compute_score 2>"$_ERRTMP")"; _CRC=$?

if [ -z "$SCORE" ]; then
  if [ "$_CRC" = "2" ]; then
    # El runner EXISTE y corrió — esto no es "configúralo", es "está roto o
    # sin candidatos". Confundir ambos mensajes costó una tarde del owner.
    echo "❌ mutation-score: el runner corrió y NO produjo un score:"
    sed 's/^/   /' "$_ERRTMP"
    echo "   Contrato §14.3: el detector no pudo mirar (exit 3). CI lo trata como fallo"
    echo "   con GATES_REQUIRE_MUTATION=1; en local no bloquea, pero el nivel 4 está MUDO."
    rm -f "$_ERRTMP"
    [ "${GATES_REQUIRE_MUTATION:-0}" = "1" ] && exit 1
    exit 3
  fi
  rm -f "$_ERRTMP"
  echo "⚠️  mutation-score: sin runner configurado (tools/mutation-score.sh §FILL)."
  echo "   Sin esta métrica NO puedes distinguir un test real de uno decorativo."
  echo "   Es el gate de mayor valor contra tests escritos por IA. Configúralo."
  # Fail-open en local, fail-closed en CI: run-gates decide con GATES_REQUIRE_MUTATION=1.
  [ "${GATES_REQUIRE_MUTATION:-0}" = "1" ] && exit 1
  exit 0
fi
rm -f "$_ERRTMP"

# ── Evidencia CORRUPTA no es evidencia de aprobación ────────────────
# `[ "$SCORE" -lt "$MIN" ]` con un $SCORE no numérico lanza "integer expression
# expected", la condición se evalúa como FALSA, y el script caía al camino de
# ÉXITO. Un typo del runner, un override mal puesto o una salida truncada se
# leían como "gate aprobado" — peor que el caso vacío, que sí estaba cubierto.
# Lo cazó el `reviewer` revisando P1, con repro en vivo.
case "$SCORE" in
  ''|*[!0-9]*)
    echo "❌ mutation-score: el score obtenido no es un entero: '$SCORE'"
    echo "   Un valor corrupto NO se interpreta como aprobado. Revisa el runner"
    echo "   (tools/mutation-score.sh §FILL) o \$MUTATION_SCORE_OVERRIDE."
    exit 1 ;;
esac

# ── Un trinquete CORRUPTO no es un trinquete en cero ────────────────
# Degradar a 0 en silencio parecía prudente, pero desde que el piso >0 activa
# automáticamente el gate obligatorio en CI, corromper el archivo se convierte
# en una forma de DESACTIVAR el gate. "No pude leer el piso" y "el piso es 0"
# son estados distintos y deben distinguirse.
# Archivo AUSENTE → piso 0 (legítimo: aún sin inicializar).
# Archivo PRESENTE pero ilegible → error ruidoso.
if [ -f "$JSON" ]; then
  MIN="$(floor)"
  case "$MIN" in
    ''|*[!0-9]*)
      echo "❌ mutation-score: '$JSON' existe pero no tiene un \"min_score\" entero legible."
      echo "   Un trinquete corrupto NO se interpreta como piso 0: eso convertiría"
      echo "   corromper el archivo en una forma de desactivar el gate (AGENTS.md §9)."
      echo "   Restáuralo desde git, o re-inicialízalo con --update."
      exit 1 ;;
  esac
else
  MIN=0
fi

case "$MODE" in
  --report)
    echo "MUTATION_SUMMARY score=$SCORE floor=$MIN"; exit 0 ;;

  --update)
    if [ "$SCORE" -gt "$MIN" ]; then
      cat > "$JSON" <<EOF
{
  "min_score": $SCORE,
  "_note": "Piso del mutation score (% de mutantes muertos). SOLO SUBE. Bajarlo a mano = esconder deuda (AGENTS.md §9)."
}
EOF
      echo "✅ piso de mutación subido: $MIN → $SCORE (commitea $JSON)."
    else
      echo "ℹ️  piso sin cambios: score=$SCORE no supera el piso actual ($MIN). El ratchet solo sube."
    fi
    exit 0 ;;

  *)
    echo "MUTATION_SUMMARY score=$SCORE floor=$MIN"
    if [ "$SCORE" -lt "$MIN" ]; then
      echo "❌ mutation-score: $SCORE% está por DEBAJO del piso ($MIN%)."
      echo "   Tus tests dejaron vivos mutantes que antes mataban. Añade aserciones"
      echo "   reales (o property-based) hasta recuperar el piso. El piso solo sube."
      exit 1
    fi
    echo "✅ mutation-score: $SCORE% ≥ piso $MIN%."
    exit 0 ;;
esac
