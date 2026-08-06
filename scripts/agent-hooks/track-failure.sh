#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# track-failure.sh — hook PostToolUseFailure
# ════════════════════════════════════════════════════════════════════
# Detecta al agente ATASCADO. Un agente que falla el mismo comando 4 veces
# seguidas no está progresando: está reintentando variaciones de una hipótesis
# equivocada, quemando contexto y consolidando el error en el historial.
#
# Un humano se da cuenta al tercer intento. El agente no, porque cada intento
# le parece nuevo. Este hook lleva la cuenta y le dice explícitamente que pare
# y cambie de estrategia — que es exactamente lo que un senior haría.
#
# No bloquea (PostToolUseFailure no puede): informa. Pero informar en el momento
# correcto es la mitad del trabajo.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
STATE="$(hook_state_dir)"; mkdir -p "$STATE"
COUNTER="$STATE/failure-streak.txt"

TOOL="$(hook_tool)"
CMD="$(hook_command)"
# Firma del fallo: la herramienta + los 2 primeros tokens del comando.
# Suficiente para agrupar reintentos de "lo mismo" sin ser sensible a flags.
SIG="$TOOL:$(printf '%s' "$CMD" | awk '{print $1, $2}')"

PREV_SIG=""; PREV_N=0
if [ -f "$COUNTER" ]; then
  PREV_SIG="$(head -1 "$COUNTER" 2>/dev/null)"
  PREV_N="$(sed -n 2p "$COUNTER" 2>/dev/null)"; : "${PREV_N:=0}"
fi

if [ "$SIG" = "$PREV_SIG" ]; then N=$((PREV_N + 1)); else N=1; fi
printf '%s\n%s\n' "$SIG" "$N" > "$COUNTER"

# Umbral: 3 es ruido normal de exploración; 4 ya es un bucle.
[ "$N" -lt 4 ] && hook_allow

# Registra el atasco para el process-judge (evidencia de trayectoria).
printf '[%s] atasco: %s × %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SIG" "$N" \
  >> "$STATE/stuck-log.txt" 2>/dev/null || true

hook_context "PostToolUseFailure" "🔁 ATASCO DETECTADO: \`$SIG\` ha fallado $N veces seguidas.

Reintentar variaciones de la misma hipótesis es el modo de fallo más caro que existe:
quema contexto y consolida el error. Para y haz UNA de estas, en este orden:

1. **Lee el error completo otra vez.** ¿Estás arreglando el síntoma o la causa?
2. **Verifica tus supuestos contra el código/la DB**, no contra tu memoria
   (AGENTS.md §14.5). El supuesto equivocado suele ser el que ni cuestionaste.
3. **Si sigues sin saber: PREGUNTA al owner.** Open Question > suposición
   silenciosa (AGENTS.md §1.4). Preguntar ahora cuesta un mensaje; adivinar
   mal cuesta el resto de la sesión.

No intentes un cuarto enfoque sin haber hecho 1 y 2."
