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
# process-judge también emite el contrato: su veredicto vacía la cola de
# juicio (judge-queue) y deja su propio marker — pero NUNCA el canónico del
# reviewer (guardado más abajo): juzgar el proceso no desbloquea commits.
case "$AGENT" in
  reviewer|security-reviewer|design-reviewer|process-judge) : ;;
  *) hook_allow ;;
esac

MSG="$(hook_last_message)"
[ -z "$MSG" ] && hook_allow   # sin mensaje que parsear → no inventamos nada

VERDICT="$(verdict_parse "$MSG")"
SCOPE="$(verdict_scope "$MSG")";     : "${SCOPE:=(sin scope declarado)}"
FINDINGS="$(verdict_findings "$MSG")"; : "${FINDINGS:=?}"

# ── MODO CONTRATO: cierre legítimo SIN veredicto y SIN marker ──────
# El reviewer invocado antes de que exista el código no puede emitir un
# veredicto (no hay nada que juzgar) y NO debe escribir marker: si lo
# hiciera, pedir el contrato desbloquearía el commit del código que aún no
# se ha escrito — justo el agujero que el invariante nº1 existe para tapar.
# Sale por aquí, arriba del bloqueo por "sin veredicto", y termina limpio.
if [ -z "$VERDICT" ] && [ -n "$(contract_parse "$MSG")" ]; then
  hook_context "$EV" "📋 Contrato de review acordado para «${SCOPE}» — ANTES de escribir código.
No se ha escrito marker (no lo hay que escribir: aún no existe el diff).
Guarda el contrato en la sección '## Contrato de review' de la historia y
commitéalo: la review final lo leerá y verificará contra él en vez de
explorar desde cero, que es lo que hace cara cada vuelta."
  hook_allow
fi

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

# ── Telemetría: cada review es un dato de contención (nivel 9) ──────
# Registra CUÁNTO encontró la fase de review — la fuente principal del bucket
# actividad `review` de gate-value; su finding durable alimenta escape-rate.
# Best-effort: jamás afecta al flujo.
_N="$FINDINGS"; case "$_N" in ''|'?'|*[!0-9]*) [ "$VERDICT" = "GREEN" ] && _N=0 || _N=1 ;; esac
[ "${_N:-0}" -gt 0 ] && hook_log_detection "$AGENT" "verdict-$VERDICT" "$SCOPE" "$_N"

# ── process-judge: camino propio, y TERMINA aquí ────────────────────
# Un juicio es un juicio con cualquier veredicto (un RED del juez significa
# "el proceso fue malo", no "el juicio no ocurrió"): escribe su marker y vacía
# la cola SIEMPRE. Y jamás sigue hacia el camino del marker del reviewer —
# juzgar el proceso no desbloquea commits.
if [ "$AGENT" = "process-judge" ]; then
  DIR="$(hook_state_dir)/markers"; mkdir -p "$DIR"
  {
    printf 'ts: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'agent: process-judge\nverdict: %s\nfindings: %s\nscope: %s\nsource: hook\n' \
      "$VERDICT" "$FINDINGS" "$SCOPE"
    # session: la usa session-end.sh para no re-encolar la sesión ya juzgada.
    # Sin este campo el dedup era código muerto: grepeaba el SID en un marker
    # que nunca lo contenía (hallazgo del reviewer en la review de este diff).
    printf 'session: %s\n' "$(hook_session_id)"
  } > "$DIR/process-judge_run.txt"
  : > "$(hook_state_dir)/judge-queue.txt" 2>/dev/null || true
  hook_context "$EV" "⚖️  Juicio de proceso registrado: $VERDICT (${FINDINGS} hallazgos) — «${SCOPE}».
Cola de juicio vaciada. Si el juez reportó hallazgos, van al ledger
(\`bash tools/findings/findings.sh add ...\`), no solo a la prosa (AGENTS.md §10)."
fi

# El sha del diff que se está juzgando AHORA. Se calcula antes de bifurcar
# porque lo necesitan los dos caminos: el RED para dejar huella, y el
# GREEN/AMBER para comprobar contra ella.
_DIR="$(hook_state_dir)/markers"; mkdir -p "$_DIR"
_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
_STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
_HIST="$(hook_state_dir)/review-history.jsonl"
_LAST_RED="$_DIR/last_red.txt"

_apuntar_historia() { # _apuntar_historia <veredicto> <nota>
  printf '{"ts":"%s","agent":"%s","verdict":"%s","findings":"%s","scope":"%s","head":"%s","staged_sha":"%s","nota":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT" "$1" "$FINDINGS" \
    "$(printf '%s' "$SCOPE" | tr '"' "'" | tr -d '\n')" "$_HEAD" "$_STAGED_SHA" "$2" \
    >> "$_HIST" 2>/dev/null || true
}

# ── RED → sin marker, PERO CON HUELLA ──────────────────────────────
# Un RED no dejaba rastro: ni el diff ni sus hallazgos. Consecuencia medida en
# un proyecto real — 36 RED, 9 AMBER y CERO GREEN en todo el historial, con
# secuencias RED→RED→GREEN sobre archivos cuyo mtime era anterior al primer
# RED: ni un byte cambió entre veredictos. La lectura benigna era la correcta
# ahí (los RED pedían registrar gaps en el ledger, §10), y ese es justo el
# problema: **el harness no podía distinguirla de un verdict-shopping.**
# Guardando el sha del diff también en RED, la diferencia pasa a ser mecánica.
if ! verdict_is_markable "$VERDICT"; then
  _apuntar_historia "$VERDICT" "sin marker; commit sigue bloqueado"
  {
    printf 'ts: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'agent: %s\nverdict: %s\nfindings: %s\nscope: %s\nhead: %s\nstaged_sha: %s\nsource: hook\n' \
      "$AGENT" "$VERDICT" "$FINDINGS" "$SCOPE" "$_HEAD" "$_STAGED_SHA"
  } > "$_LAST_RED"
  hook_context "$EV" "🔴 \`$AGENT\` emitió VERDICT: $VERDICT ($FINDINGS hallazgos) sobre «${SCOPE}».

NO se escribió marker de review — el commit sigue BLOQUEADO por el reviewer-gate.
Queda huella del diff juzgado (${_STAGED_SHA:0:12}…): si el próximo veredicto es
GREEN sobre ESE MISMO diff, el sistema lo rechazará — un verde sobre un código
que no cambió no es una remediación, es un reintento.
Atiende los hallazgos, STAGEA el arreglo, y vuelve a invocar \`$AGENT\`."
fi

# ── Un GREEN sobre el MISMO diff que acaba de ser RED no es remediación ──
# Es el invariante nº1 llevado a su conclusión: si el veredicto lo deriva el
# sistema de una ejecución real, dos ejecuciones sobre la MISMA entrada no
# pueden dar salidas opuestas sin que algo haya cambiado. O el primero estaba
# mal o el segundo lo está, y en ninguno de los dos casos toca desbloquear.
# Escape auditado —mismo patrón que REVIEWER_OVERRIDE— para el caso legítimo:
# un RED resuelto por argumentación y no por código.
if [ -f "$_LAST_RED" ] && [ -n "$_STAGED_SHA" ]; then
  _RED_SHA="$(grep -E '^staged_sha:' "$_LAST_RED" 2>/dev/null | head -1 | sed -E 's/^staged_sha:[[:space:]]*//')"
  _RED_HEAD="$(grep -E '^head:' "$_LAST_RED" 2>/dev/null | head -1 | sed -E 's/^head:[[:space:]]*//')"
  if [ "$_RED_SHA" = "$_STAGED_SHA" ] && [ "$_RED_HEAD" = "$_HEAD" ]; then
    if [ "${REVIEW_SAME_DIFF_OVERRIDE:-0}" = "1" ]; then
      printf '[%s] same-diff-override en %s · agent=%s · reason=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_HEAD" "$AGENT" \
        "${REVIEW_SAME_DIFF_REASON:-(SIN RAZÓN — esto es un smell)}" \
        >> "$_DIR/override_log.txt" 2>/dev/null || true
      _apuntar_historia "$VERDICT" "override same-diff"
    else
      _apuntar_historia "$VERDICT" "RECHAZADO: mismo diff que el RED anterior"
      hook_context "$EV" "🛑 \`$AGENT\` emitió $VERDICT sobre EXACTAMENTE el mismo diff que acaba de
recibir un RED (${_STAGED_SHA:0:12}…, head=$_HEAD). NO se ha escrito marker.

Entre los dos veredictos no cambió ni un byte de lo staged, así que esto no es
una remediación: o el RED estaba mal o lo está este. Si arreglaste algo, STAGÉALO
y vuelve a revisar — el arreglo tiene que estar en el diff que se juzga (incluido
el ledger, si el hallazgo pedía registrarlo).
Si de verdad el RED se resolvió con un argumento y no con código:
  REVIEW_SAME_DIFF_OVERRIDE=1 REVIEW_SAME_DIFF_REASON=\"...\"   (queda auditado)"
    fi
  fi
fi

# ── GREEN / AMBER → el sistema escribe el marker ───────────────────
DIR="$_DIR"; HEAD="$_HEAD"; STAGED_SHA="$_STAGED_SHA"
_apuntar_historia "$VERDICT" "marker escrito"

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
