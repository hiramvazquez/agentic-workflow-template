#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# verify-run.sh — corre build+tests y deja EVIDENCIA firmada del diff
# ════════════════════════════════════════════════════════════════════
# El agujero que cierra, y es de los grandes: `check-review-marker.sh` liga el
# review a `sha256(diff staged)` — un review de otro diff no vale. Pero NINGUNA
# ejecución de build o de tests estaba ligada a ese mismo diff. Se podía
# commitear un árbol que ninguna ejecución registrada llegó a compilar, con
# todos los gates en verde. El invariante nº1 ("el veredicto lo deriva el
# sistema de una ejecución real") estaba aplicado al reviewer y no a los tests,
# que es donde más caro sale.
#
# Este script es el que EJECUTA, así que es el que puede firmar. El modelo no
# escribe este marker en ningún caso — igual que el de review, se acepta solo
# con `source: tool`.
#
#   bash tools/verify-run.sh            # corre y, si pasa, firma el diff staged
#   bash tools/verify-run.sh --ci       # corre y NO firma (en CI no hay marker)
#   bash tools/verify-run.sh --cmd-only # NO corre: solo dice si hay comando
#                                       # cableado (exit 0) o no (exit 3). Lo
#                                       # usan session-start y validate-harness
#                                       # para reportar el nivel 3 sin gastar
#                                       # un build entero en cada arranque.
#
# Exit: 0 verde (marker escrito) · 1 el build/los tests FALLARON ·
#       3 no pude verificar (sin comando cableado, o el árbol no permite firmar)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:-}"
CONF="${VERIFY_CONF:-tools/verify.conf}"
MARKER=".agents/state/markers/verify_run.txt"

# ── El comando: env > conf. Sin comando NO se inventa nada ──────────
CMD="${VERIFY_CMD:-}"
if [ -z "$CMD" ] && [ -f "$CONF" ]; then
  CMD="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
fi
case "$CMD" in ''|'<tu-comando-aqui>'|*'FILL'*) CMD="" ;; esac
if [ -z "$CMD" ]; then
  {
    echo "⚠️  verify-run: no hay comando de build+tests cableado ($CONF)."
    echo "   Mientras siga así, NADA ata una ejecución verde al diff que commiteas:"
    echo "   los otros niveles pueden estar en verde con el build ROTO."
    echo "   Cablea una línea en $CONF (o exporta VERIFY_CMD)."
  } >&2
  exit 3          # "no pude mirar" (§14.3): local avisa, CI bloquea
fi
[ "$MODE" = "--cmd-only" ] && { echo "VERIFY_CMD_OK $CMD"; exit 0; }

# ── ¿Sobre QUÉ va a correr? El árbol de trabajo, no el índice ───────
# Por eso hay que exigir que no haya modificaciones sin stagear en archivos
# trackeados: si las hay, lo que se compila NO es lo que se va a commitear, y
# firmar ese resultado sería exactamente la mentira que este marker existe para
# impedir. El flujo correcto es el mismo que ya exige §13 para el review:
#   stagea → verifica → commitea (en comandos separados).
if [ "$MODE" != "--ci" ]; then
  SUCIO="$(git diff --name-only 2>/dev/null || true)"
  if [ -n "$SUCIO" ]; then
    {
      echo "❌ verify-run: hay cambios SIN STAGEAR en archivos trackeados:"
      printf '%s\n' "$SUCIO" | sed 's/^/     /'
      echo ""
      echo "   El build corre sobre el árbol de trabajo, así que lo que se"
      echo "   verificaría NO es lo que vas a commitear. Firmar eso sería la"
      echo "   mentira que este marker existe para impedir."
      echo "   Stagea lo que vayas a commitear y vuelve a correr."
    } >&2
    exit 3
  fi
fi

STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"

echo "━━━ verify-run: $CMD"
set +e
sh -c "$CMD"
RC=$?
set -e 2>/dev/null || true

if [ "$RC" -ne 0 ]; then
  echo ""
  echo "❌ verify-run: el comando salió con $RC. NO firmo nada." >&2
  echo "   (Un marker escrito tras un fallo convertiría el gate en un sello.)" >&2
  exit 1
fi

[ "$MODE" = "--ci" ] && { echo "✅ verify-run: verde (modo CI, sin marker)."; exit 0; }

mkdir -p "$(dirname "$MARKER")"
{
  printf 'source: tool\n'
  printf 'tool: verify-run.sh\n'
  printf 'cmd: %s\n' "$CMD"
  printf 'exit: 0\n'
  printf 'head: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
  printf 'staged_sha: %s\n' "$STAGED_SHA"
  printf 'at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MARKER"

echo "✅ verify-run: verde. Evidencia firmada contra este diff staged (${STAGED_SHA:0:12}…)."
echo "   Si vuelves a tocar algo staged, el marker deja de valer y hay que re-correr."
exit 0
