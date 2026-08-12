#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# gate-value.sh — ¿qué gate sigue siendo LOAD-BEARING?
# ════════════════════════════════════════════════════════════════════
# El harness solo sabía CRECER. Cada error añadía un detector, cada lección
# un test, cada incidente un anillo — y no existía ningún momento en el que
# se preguntara si algo de eso ya sobra. Un sistema que solo acumula acaba
# cobrando su peaje (tiempo de gate, tokens de contexto, fricción) por
# defensas que quizá ya no defienden de nada.
#
# La idea es de la ingeniería de harnesses de Anthropic: revisar con
# regularidad si los componentes siguen siendo *load-bearing* a medida que
# los modelos mejoran. Un gate que existía para un error que el modelo ya no
# comete es ceremonia; y la ceremonia no es neutra — es justo lo que hace
# que un equipo termine desactivando el harness entero.
#
# ⚠️  EL MATIZ QUE HACE HONESTO ESTE INFORME, y que hay que leer SIEMPRE:
# un gate con CERO detecciones puede estar en dos estados opuestos, y los
# datos por sí solos no los distinguen:
#     (a) DISUASIÓN — funciona tan bien que nadie intenta ya lo que prohíbe.
#         Es el éxito perfecto y se ve idéntico al fracaso.
#     (b) MUDO o INÚTIL — nunca disparó porque no puede, o porque el riesgo
#         que cubría no existe en este proyecto.
# Para separarlos: (a) lo confirma `validate-harness --selftest`, donde el
# gate DEMUESTRA que ve. Cero detecciones + selftest verde = disuasión, se
# queda. Cero detecciones + sin selftest = candidato REAL a revisión.
# Por eso este informe no recomienda borrar nada: hace la pregunta
# respondible con datos en vez de con intuición. La decisión es del owner.
#
#   bash tools/metrics/gate-value.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

DETECTIONS="${DETECTIONS_LOG:-.agents/state/metrics/detections.jsonl}"
LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"

# Vista mixta durante la migración: JSONL v1 se expone como unknown/null y
# JSONL v2 conserva su identidad. El log local nunca se reescribe.
EVENTS_VIEW="$DETECTIONS"
EVENTS_TMP=""
if [ -f "$DETECTIONS" ] && command -v python3 >/dev/null 2>&1 \
   && [ -f tools/metrics/read-events.py ]; then
  EVENTS_TMP="$(mktemp 2>/dev/null)"
  if [ -n "$EVENTS_TMP" ] \
     && python3 tools/metrics/read-events.py "$DETECTIONS" > "$EVENTS_TMP"; then
    EVENTS_VIEW="$EVENTS_TMP"
    trap 'rm -f "$EVENTS_TMP" 2>/dev/null' EXIT
  else
    [ -n "$EVENTS_TMP" ] && rm -f "$EVENTS_TMP" 2>/dev/null
    EVENTS_TMP=""
  fi
fi

echo "━━━ Valor por gate: ¿sigue siendo load-bearing? ━━━"
echo ""

if [ ! -f "$DETECTIONS" ]; then
  echo "Sin telemetría todavía ($DETECTIONS)."
  echo "Los gates escriben aquí vía hook_log_detection. Vuelve tras unas sesiones."
  exit 0
fi

TOTAL="$(grep -c . "$EVENTS_VIEW" 2>/dev/null || true)"; : "${TOTAL:=0}"
LEDGER_TOTAL="$(grep -c . "$LEDGER" 2>/dev/null || true)"; : "${LEDGER_TOTAL:=0}"
echo "Eventos registrados: $TOTAL   ·   findings en el ledger: $LEDGER_TOTAL"
echo ""

# Inventario de gates DECLARADOS: los que el harness dice tener. Se compara
# contra los que han HABLADO alguna vez. La diferencia es la lista de
# preguntas pendientes.
GATES="semgrep check-layers drift-ratchet reviewer-gate canon-enforce
post-edit-verify secret-scan check-review-marker conflict-markers
mutation-score exec-bits reviewer skill-reminder"

printf '  %-22s %8s   %s\n' "GATE" "EVENTOS" "LECTURA"
printf '  %-22s %8s   %s\n' "──────────────────────" "───────" "─────────────────────────────"
for g in $GATES; do
  n="$(grep -c "\"source\":\"$g\"" "$EVENTS_VIEW" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 0 ]; then
    printf '  %-22s %8s   %s\n' "$g" "$n" "activo — está cazando cosas"
  else
    printf '  %-22s %8s   %s\n' "$g" "0" "¿disuasión o mudo? → selftest lo dice"
  fi
done

echo ""
echo "Cómo usar esto (una vez al mes, no cada día):"
echo "  1. Para cada gate con 0 eventos, mira si aparece en"
echo "     \`bash tools/validate-harness.sh --selftest\`."
echo "       · sale y pasa  → DISUASIÓN. Se queda. No toques nada."
echo "       · no sale      → nadie ha demostrado nunca que vea. Añádele su"
echo "                        selftest, o plantéate retirarlo."
echo "  2. Para los gates con MUCHOS eventos, la pregunta es la contraria:"
echo "     si el mismo gate caza lo mismo una y otra vez, el problema no está"
echo "     en el gate — está en que la capa de ARRIBA no lo hace imposible."
echo "     Un detector que dispara constantemente es una petición de tipo,"
echo "     de regla AST o de skill (AGENTS.md §14.1: cázalo más barato)."
echo "  3. Un gate que nunca dispara Y nunca tuvo selftest lleva meses"
echo "     cobrando tiempo sin haber demostrado que existe. Ese es el"
echo "     candidato honesto a retirada — no el que sale caro."
echo ""
echo "Nada de esto se decide solo: el informe hace la pregunta respondible,"
echo "el owner responde. Retirar un gate es una decisión de dueño (§8)."
