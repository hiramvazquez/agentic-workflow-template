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
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

JSON="${MUTATION_RATCHET_JSON:-tools/mutation-ratchet.json}"
MODE="${1:---check}"

floor() { sed -nE 's/.*"min_score"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$JSON" 2>/dev/null | head -1; }

# ── Cálculo del score ───────────────────────────────────────────────
compute_score() {
  if [ -n "${MUTATION_SCORE_OVERRIDE:-}" ]; then
    printf '%s' "$MUTATION_SCORE_OVERRIDE"; return 0
  fi

  # <!-- FILL: invoca el runner de mutación de TU stack y extrae el % entero.
  #      Recomendaciones por plataforma:
  #        Swift   → muter        (`muter run --format xcode`)
  #        Kotlin  → PIT/pitest   (`./gradlew pitest`)
  #        JS/TS   → StrykerJS    (`npx stryker run`)
  #        Python  → mutmut       (`mutmut run && mutmut results`)
  #        Java    → PIT          (`mvn org.pitest:pitest-maven:mutationCoverage`)
  #      El runner suele ser LENTO: va en CI/nocturno (Anillo 3), no en pre-commit.
  #      Ejemplo (Stryker):
  #        npx stryker run --reporters json >/dev/null 2>&1 || return 1
  #        sed -nE 's/.*"mutationScore":([0-9]+).*/\1/p' reports/mutation/mutation.json | head -1
  #  -->
  return 1
}

SCORE="$(compute_score 2>/dev/null || true)"

if [ -z "$SCORE" ]; then
  echo "⚠️  mutation-score: sin runner configurado (tools/mutation-score.sh §FILL)."
  echo "   Sin esta métrica NO puedes distinguir un test real de uno decorativo."
  echo "   Es el gate de mayor valor contra tests escritos por IA. Configúralo."
  # Fail-open en local, fail-closed en CI: run-gates decide con GATES_REQUIRE_MUTATION=1.
  [ "${GATES_REQUIRE_MUTATION:-0}" = "1" ] && exit 1
  exit 0
fi

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
