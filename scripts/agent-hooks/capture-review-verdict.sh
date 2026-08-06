#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# capture-review-verdict.sh — hook SubagentStop (matcher: reviewer|security-reviewer)
# ════════════════════════════════════════════════════════════════════
# Antes: `scripts/mark-reviewer-run.sh` lo invocaba el MODELO. Un agente que
# quería commitear solo tenía que ejecutar el script — el reviewer-gate era
# decorativo. Ahora el marker lo escribe el SISTEMA, derivándolo del mensaje
# final REAL del sub-agente (`last_assistant_message` del payload).
#
# ⚠️  ALCANCE REAL DE LA GARANTÍA — léelo antes de confiar en esto.
#
# Este mecanismo defiende contra **error de proceso**: el agente que se olvida
# de invocar al reviewer, que da por buena su propia revisión, o que pierde la
# regla tras una compactación. Ese es el caso abrumadoramente común, y antes
# no estaba cubierto en absoluto.
#
# NO defiende contra un agente adversario o confundido por prompt injection.
# Un agente con acceso a Bash puede escribir `.agents/state/markers/reviewer_run.txt`
# a mano con `source: hook`, y `check-review-marker.sh` lo aceptaría: valida el
# CONTENIDO del archivo, no su PROCEDENCIA. `permissions.deny` cubre la tool
# Write/Edit y el nombre literal del archivo en Bash, pero no una redirección
# construida dinámicamente. En una máquina de un solo usuario, un agente con
# shell puede hacer lo que puede hacer el usuario — no hay arreglo limpio
# dentro de esta arquitectura.
#
# **La defensa contra intención es el ANILLO 3**, no este marker: en CI el
# marker local no viaja, y `ci/ai-review.sh` corre una review independiente en
# una máquina que el agente no controla. Por eso los 3 anillos existen.
#
# Detectado por el propio `reviewer` al revisar este código (PRD 0001 §18 G9).
#
# Comportamiento por veredicto:
#   GREEN / AMBER  → escribe marker (source: hook). El commit se desbloquea.
#   RED            → NO escribe marker + avisa al agente principal. El commit
#                    sigue bloqueado hasta que se atienda y se re-revise.
#   sin contrato   → NO escribe marker + BLOQUEA el cierre del sub-agente,
#                    reinyectando el formato exigido. Ausencia de evidencia
#                    no es evidencia de ausencia.
#
# Failure-open mecánico: si falta jq o el payload es raro, exit 0 (no hay
# marker → el commit sigue bloqueado por el gate; se falla hacia lo seguro).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
# shellcheck source=lib/verdict.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
EV="SubagentStop"
AGENT="$(hook_agent_type)"

# Solo nos importan los sub-agentes que emiten veredicto.
case "$AGENT" in
  reviewer|security-reviewer|design-reviewer) : ;;
  *) hook_allow ;;
esac

MSG="$(hook_last_message)"
[ -z "$MSG" ] && hook_allow   # sin mensaje que parsear → no inventamos nada

VERDICT="$(verdict_parse "$MSG")"
SCOPE="$(verdict_scope "$MSG")";     : "${SCOPE:=(sin scope declarado)}"
FINDINGS="$(verdict_findings "$MSG")"; : "${FINDINGS:=?}"

# ── Sin contrato → bloquear el cierre y reinyectar el formato ───────
if [ -z "$VERDICT" ]; then
  hook_json_block "$EV" "🛑 \`$AGENT\` terminó SIN emitir el contrato de veredicto.

Un review sin veredicto no desbloquea nada: el commit sigue bloqueado.
Termina tu mensaje final con estas tres líneas, cada una en su propia línea:

  VERDICT: GREEN|AMBER|RED
  FINDINGS: <número de hallazgos>
  SCOPE: <qué revisaste, en una línea>

GREEN = sin hallazgos bloqueantes · AMBER = hallazgos menores, atendibles ·
RED = no puede entrar. No uses GREEN por defecto: el veredicto es atribuible."
fi

# ── RED → sin marker, y el agente principal se entera ──────────────
if ! verdict_is_markable "$VERDICT"; then
  hook_context "$EV" "🔴 \`$AGENT\` emitió VERDICT: $VERDICT ($FINDINGS hallazgos) sobre «${SCOPE}».

NO se escribió marker de review — el commit sigue BLOQUEADO por el reviewer-gate.
Atiende los hallazgos y vuelve a invocar \`$AGENT\`. No intentes commitear
ni marcar manualmente: el override queda auditado en override_log.txt."
fi

# ── GREEN / AMBER → el sistema escribe el marker ───────────────────
DIR="$(hook_state_dir)/markers"; mkdir -p "$DIR"
HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"

# El marker canónico que consulta el gate + uno por agente para trazabilidad.
for target in "$DIR/reviewer_run.txt" "$DIR/${AGENT}_run.txt"; do
  # security-reviewer y design-reviewer NO deben poder desbloquear el gate del
  # reviewer: solo `reviewer` escribe el marker canónico.
  if [ "$target" = "$DIR/reviewer_run.txt" ] && [ "$AGENT" != "reviewer" ]; then
    continue
  fi
  cat > "$target" <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
agent: $AGENT
verdict: $VERDICT
findings: $FINDINGS
scope: $SCOPE
head: $HEAD
staged_sha: $STAGED_SHA
source: hook
EOF
done

hook_context "$EV" "✅ Veredicto de \`$AGENT\` registrado por el sistema: $VERDICT (${FINDINGS} hallazgos) — «${SCOPE}».
Marker ligado a head=$HEAD y al diff staged actual. Si cambias lo staged, el marker caduca."
