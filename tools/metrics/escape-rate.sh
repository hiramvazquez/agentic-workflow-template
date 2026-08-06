#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# escape-rate.sh — ¿cuánto puedo confiar en la IA sin revisión humana?
# ════════════════════════════════════════════════════════════════════
# LA métrica del proyecto. "Detectar no basta — CERRAR" mide el destino de un
# hallazgo; esto mide EN QUÉ FASE se detectó, que es lo que responde a la
# pregunta real: ¿puedo bajar la revisión humana este trimestre?
#
# Es el equivalente al *phase containment* de la ingeniería clásica y primo del
# *change failure rate* de DORA (elite: 0-15%). El principio: un defecto cuesta
# ~10× más en cada fase que avanza sin ser detectado. Si tu escape rate baja,
# tus gates están funcionando. Si es plano, estás añadiendo ceremonia, no calidad.
#
# Fases, de más barata a más cara:
#   in-loop   → lo cazó post-edit-verify / linter / tipos       (coste ~0)
#   gate      → lo cazó canon-enforce / drift / capas / semgrep (coste bajo)
#   review    → lo cazó el reviewer o el security-reviewer      (coste medio)
#   ci        → lo cazó el Anillo 3                             (coste alto)
#   prod      → lo cazó un usuario                              (coste máximo)
#
# El dato sale del ledger: cada finding lleva `source`, que ya identifica quién
# lo encontró. Esto solo lo agrega.
#
#   bash tools/metrics/escape-rate.sh            # resumen
#   bash tools/metrics/escape-rate.sh --json     # para dashboards
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"
MODE="${1:---text}"

[ -f "$LEDGER" ] || { echo "Sin ledger en $LEDGER — nada que medir todavía."; exit 0; }

count_source() { grep -c "\"source\":\"$1\"" "$LEDGER" 2>/dev/null || echo 0; }

# <!-- FILL: mapea los `source` de TU ledger a estas fases. Los de abajo son
#      los que produce el harness por defecto. -->
IN_LOOP=$(( $(count_source "post-edit-verify") + $(count_source "linter") + $(count_source "typecheck") ))
GATE=$((    $(count_source "canon-enforce") + $(count_source "check-drift") + $(count_source "check-layers") + $(count_source "semgrep") ))
REVIEW=$((  $(count_source "reviewer") + $(count_source "security-reviewer") + $(count_source "design-reviewer") + $(count_source "process-judge") ))
CI=$(       count_source "ci" )
PROD=$((    $(count_source "prod") + $(count_source "user-report") + $(count_source "incident") ))
HUMAN=$(    count_source "human-review" )

TOTAL=$((IN_LOOP + GATE + REVIEW + CI + PROD + HUMAN))
[ "$TOTAL" -eq 0 ] && { echo "Ledger sin findings con \`source\` reconocible — nada que medir."; exit 0; }

pct() { [ "$TOTAL" -eq 0 ] && { echo 0; return; }; echo $(( $1 * 100 / TOTAL )); }

# "Escaped" = todo lo que pasó de largo los gates automáticos y necesitó a un
# humano, a CI o —lo peor— a un usuario en producción.
ESCAPED=$((CI + PROD + HUMAN))
ESCAPE_RATE=$(pct $ESCAPED)
AUTOMATED=$((IN_LOOP + GATE + REVIEW))

if [ "$MODE" = "--json" ]; then
  cat <<EOF
{"total":$TOTAL,"in_loop":$IN_LOOP,"gate":$GATE,"review":$REVIEW,"ci":$CI,"human":$HUMAN,"prod":$PROD,"escape_rate_pct":$ESCAPE_RATE,"automated_pct":$(pct $AUTOMATED)}
EOF
  exit 0
fi

cat <<EOF

━━━ Contención por fase (n=$TOTAL findings) ━━━

  in-loop   $(printf '%4d' $IN_LOOP)  $(printf '%3d' "$(pct $IN_LOOP)")%   coste ~0   post-edit-verify, tipos, linter
  gate      $(printf '%4d' $GATE)  $(printf '%3d' "$(pct $GATE)")%   bajo       canon-enforce, drift, capas, semgrep
  review    $(printf '%4d' $REVIEW)  $(printf '%3d' "$(pct $REVIEW)")%   medio      sub-agentes de review
  ─────────────────────────────────────────────────────────────
  ci        $(printf '%4d' $CI)  $(printf '%3d' "$(pct $CI)")%   alto       Anillo 3
  humano    $(printf '%4d' $HUMAN)  $(printf '%3d' "$(pct $HUMAN)")%   alto       revisión manual
  prod      $(printf '%4d' $PROD)  $(printf '%3d' "$(pct $PROD)")%   MÁXIMO     lo encontró un usuario

  ESCAPE RATE: ${ESCAPE_RATE}%   (findings que los gates automáticos NO cazaron)
  Automatizado: $(pct $AUTOMATED)%

Cómo leerlo:
  · La tendencia importa MUCHO más que el valor absoluto. Compáralo mes a mes.
  · Cada finding en 'humano' o 'prod' es una oportunidad concreta: ¿qué detector
    lo habría cazado antes? Créalo y anota la lección (el enlace lección→detector
    lo verifica \`tools/lesson-detector-link.sh\`).
  · Un escape rate que BAJA es la única evidencia real de que puedes reducir la
    revisión humana. Uno plano significa que estás añadiendo ceremonia, no calidad.
  · Si 'prod' > 0, ese caso va SIEMPRE a lessons_learned.md con su detector.

EOF
