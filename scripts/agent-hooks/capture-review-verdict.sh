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

# ════════════════════════════════════════════════════════════════════
# IDENTIDAD DEL JUICIO + ANTIBUCLE  (se calcula ANTES de cualquier salida)
# ════════════════════════════════════════════════════════════════════
# Este hook corre en SubagentStop, y todo lo que emite —`additionalContext` o
# un `decision: block`— VUELVE AL SUB-AGENTE, que responde; esa respuesta es
# otro SubagentStop, y el hook dispara otra vez. Medido en un adoptante sobre
# un diff de UNA línea: **11 disparos** en una corrida y 12 en la siguiente,
# 35.256 y 67.427 tokens de sub-agente. El propio reviewer diagnosticó su jaula
# en su sexto mensaje: *"Cierro este hilo. El sistema seguirá reenviando el
# mismo recordatorio automático mientras..."*.
#
# Y el daño caro no era el coste: **lo que recibe quien invoca al sub-agente es
# su ÚLTIMO mensaje**, o sea la cola del bucle ("VERDICT: RED" pelado), nunca el
# review. Durante toda una sesión hubo que abrir el `.jsonl` del sub-agente para
# leer cualquier review — design-reviews de 15 hallazgos incluidos.
#
# La vía NO es "escribe solo en el stop final": el hook no puede distinguir el
# final del intermedio, porque todos son SubagentStop. La vía es IDEMPOTENCIA —
# registrar una vez y callar después— y no reinyectar contexto cuando el
# veredicto ya se capturó, que es cuando no hace falta pedirle nada a nadie.
_DIR="$(hook_state_dir)/markers"; mkdir -p "$_DIR"
_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
_STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
_HIST="$(hook_state_dir)/review-history.jsonl"
_LAST_RED="$_DIR/last_red.txt"

# `review-history.jsonl` es el registro que SÍ acumula, así que es la fuente de
# la idempotencia: si ya hay una entrada de este agente, sobre este HEAD y este
# diff, el juicio ya está tomado.
_hist_grep() { # _hist_grep [verdicto] → 0 si ya hay entrada
  [ -f "$_HIST" ] || return 1
  local f; f="$(grep -F "\"agent\":\"$AGENT\"" "$_HIST" 2>/dev/null \
    | grep -F "\"head\":\"$_HEAD\"" | grep -F "\"staged_sha\":\"$_STAGED_SHA\"")"
  [ -n "$f" ] || return 1
  [ -z "${1:-}" ] && return 0
  printf '%s' "$f" | grep -qF "\"verdict\":\"$1\""
}
_ya_registrado()        { _hist_grep "$1"; }   # este agente, este diff, ESTE veredicto
_hay_veredicto_previo() { _hist_grep; }        # este agente, este diff, cualquiera


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
# ...PERO UNA SOLA VEZ. Si este agente ya emitió su veredicto sobre este mismo
# diff, un stop posterior sin veredicto es el agente terminando de hablar, no un
# review sin contrato: exigírselo otra vez fue lo que produjo los mensajes
# [7]-[10] de la secuencia medida, cuatro "VERDICT: RED" pelados generados solo
# para callar al hook. El juicio ya está registrado; aquí no hay nada que pedir.
if [ -z "$VERDICT" ] && _hay_veredicto_previo; then
  hook_allow
fi
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
  # Sin `hook_context`: mismo bucle por la misma puerta. El juicio queda en su
  # marker y la cola vaciada, que es lo que consume `session-end`.
  #
  # ⚠️ EL `exit` ES OBLIGATORIO Y ERA IMPLÍCITO: `hook_context` terminaba con
  # `exit 0`, así que quitarlo dejó este camino CAYENDO al de abajo — el
  # process-judge escribiendo el marker canónico del reviewer, o sea juzgar el
  # proceso desbloqueando commits. Lo cazó `test_verdict.sh` en la primera
  # pasada. Regla que deja: al retirar una llamada que salía del script, la
  # salida se repone EXPLÍCITA en el mismo cambio.
  hook_allow
fi


# Mismo agente, mismo diff, mismo veredicto: ya está todo hecho —marker,
# reporte, historia—. Repetirlo no añade un dato; reescribe el reporte y da otra
# vuelta de bucle. Un veredicto DISTINTO sobre el mismo diff sí sigue adelante:
# ahí abajo vive el rechazo del GREEN-tras-RED, que no se puede saltar.
if _ya_registrado "$VERDICT"; then
  hook_allow
fi
# ── EL REPORTE, no solo el veredicto ───────────────────────────────
# El sistema guardaba QUÉ decidió el review y perdía QUÉ dijo. Los hallazgos
# solo existían en el transcript del sub-agente; en un adoptante hubo que
# parsearlo a mano cuatro veces, y el propio `design-reviewer`, al re-revisar,
# declaró: "no tengo el texto literal de mis 15 hallazgos... el design-review
# no se persiste en ninguna parte" — y tuvo que RECONSTRUIRLOS por inferencia,
# avisando de que un hallazgo absorbido borrando la sección le sería invisible.
# La regla de oro nº1 es "detectar no basta — CERRAR", y aquí el hallazgo se
# evaporaba al terminar el turno: el marker probaba QUE hubo review, nada
# probaba QUÉ dijo ni permitía comprobar si se atendió.
#
# DÓNDE vive, que era la pregunta abierta y la resuelve la doctrina existente:
#   · el CUERPO es artefacto de trabajo → `.agents/state/reviews/`, local y
#     gitignored, junto al marker y con su mismo ciclo de vida.
#   · lo que debe SOBREVIVIR al turno va al LEDGER (§10: reportar = loguear al
#     ledger, no dejarlo en prosa). No se duplica el ledger en disco: se le
#     quita la excusa de no tenerlo a mano.
# Se escribe para TODOS los veredictos, RED incluido — el RED es justamente el
# que tiene hallazgos que atender.
_REVIEWS="$(hook_state_dir)/reviews"
_REPORTE="$_REVIEWS/${_STAGED_SHA:0:12}-${AGENT}.md"
_REPORTE_PREVIO=""
mkdir -p "$_REVIEWS" 2>/dev/null || true
# ¿Ya hubo un review sobre ESTE MISMO diff? Se pregunta a `review-history.jsonl`,
# que ACUMULA, y no al glob de `reviews/`: el nombre del reporte no varía entre
# vueltas del mismo agente sobre el mismo diff, así que el glob —que se excluía a
# sí mismo por nombre exacto— nunca encontraba nada y el aviso solo saltaba si el
# diff lo había juzgado un agente DISTINTO. Medido en un adoptante: re-invocó al
# reviewer sobre el mismo diff sin tocarlo y no llegó ningún aviso.
if [ -f "$_HIST" ]; then
  _REPORTE_PREVIO="$(grep -F "\"staged_sha\":\"$_STAGED_SHA\"" "$_HIST" 2>/dev/null \
    | grep -F "\"head\":\"$_HEAD\"" | tail -1 \
    | sed -nE 's/.*"report":"([^"]*)".*/\1/p')"
fi

{
  printf -- '---\n'
  printf 'ts: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'agent: %s\nverdict: %s\nfindings: %s\nscope: %s\nhead: %s\nstaged_sha: %s\nsource: hook\n' \
    "$AGENT" "$VERDICT" "$FINDINGS" "$SCOPE" "$_HEAD" "$_STAGED_SHA"
  # El puntero al review anterior va DENTRO del reporte, no en un contexto
  # reinyectado: cualquier cosa que este hook emita vuelve al sub-agente y da
  # otra vuelta de bucle. Quien tiene que comparar hallazgo por hallazgo es
  # quien lea este archivo, y aquí lo encuentra.
  if [ -n "$_REPORTE_PREVIO" ]; then
    if [ "$_REPORTE_PREVIO" = "$(hook_rel_path "$_REPORTE" 2>/dev/null || printf '%s' "$_REPORTE")" ]; then
      printf 'previo: (más arriba, en este mismo archivo)\n'
    else
      printf 'previo: %s\n' "$_REPORTE_PREVIO"
    fi
    printf 'comparar: cada hallazgo del previo tiene que estar ATENDIDO o EXPLICADO\n'
  fi
  printf -- '---\n\n'
  printf '%s\n' "$MSG"
} >> "$_REPORTE" 2>/dev/null || true


_apuntar_historia() { # _apuntar_historia <veredicto> <nota>
  printf '{"ts":"%s","agent":"%s","verdict":"%s","findings":"%s","scope":"%s","head":"%s","staged_sha":"%s","report":"%s","nota":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT" "$1" "$FINDINGS" \
    "$(printf '%s' "$SCOPE" | tr '"' "'" | tr -d '\n')" "$_HEAD" "$_STAGED_SHA" \
    "$(hook_rel_path "$_REPORTE" 2>/dev/null || printf '%s' "$_REPORTE")" "$2" \
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
  # Sin `hook_context`, por lo mismo: este texto iba al sub-agente, que ya sabe
  # lo que acaba de escribir. Quien tiene que leer los hallazgos es el agente
  # principal, y los lee en el mensaje final del sub-agente — ahora que ese
  # mensaje vuelve a ser el review y no la cola de un bucle.
  # El `exit` explícito no es cosmético: sin él, un RED cae al camino de abajo y
  # ESCRIBE EL MARKER — un veredicto que bloquea desbloqueando el commit.
  hook_allow
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
      # Sin `hook_context`: el rechazo queda en `review-history.jsonl` con su
      # nota y, sobre todo, en que NO hay marker — el `reviewer-gate` bloquea el
      # commit y ahí sí se lo explica al agente principal, que puede hacer algo.
      # Y el `exit` otra vez: sin él, el GREEN rechazado seguía y escribía el
      # marker, que es exactamente lo que este bloque existe para impedir.
      hook_allow
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

# SIN `hook_context`. Aquí ya no hay nada que pedirle al sub-agente: el
# veredicto está capturado, el marker escrito y el reporte en disco. Cualquier
# cosa que se emita aquí vuelve a ÉL —no al que lo invocó—, le hace responder, y
# esa respuesta se convierte en el último mensaje del sub-agente, que es
# justamente lo que recibe quien lo llamó. Es decir: reinyectar aquí no solo
# costaba una vuelta, SUSTITUÍA el review por el eco del recordatorio.
# Lo que el agente principal necesita saber lo tiene por dos canales que no
# rebotan: el mensaje final REAL del sub-agente y, si intenta commitear sin
# marker válido, el `reviewer-gate`.
