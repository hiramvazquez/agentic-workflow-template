#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# reviewer-gate.sh — hook PreToolUse Bash (Claude) / beforeShellExecution (Cursor)
# ════════════════════════════════════════════════════════════════════
# Gate de `git commit`. Orden DELIBERADO — no lo reordenes sin actualizar
# `tools/tests/test_ratchets.sh`, que fija estos invariantes:
#
#   1. Detectores mecánicos (drift-ratchet, capas)  → DUROS SIEMPRE.
#      Ni el preset `lite` ni REVIEWER_OVERRIDE los relajan. Un número que
#      se puede aflojar no es un trinquete: es una sugerencia.
#   2. Preset `lite` (uso personal)                 → el marker AVISA.
#   3. Marker de review (tools/check-review-marker) → DURO en `full`,
#      con override AUDITADO.
#
# La lógica de verificación del marker vive en `tools/check-review-marker.sh`
# para que la compartan los 3 anillos (antes solo existía aquí → bastaba
# commitear desde otra terminal para saltárselo).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
CMD="$(hook_command)"
# Solo gateamos `git commit`.
printf '%s' "$CMD" | grep -qE '(^|[^a-z-])git commit' || hook_allow

# ── 1. Detectores mecánicos — DUROS, sin excepción ──────────────────
# Van ANTES del override y del preset a propósito: son objetivos, no opinables.
# Si el conteo subió, subió.
if [ -f tools/drift-ratchet.sh ]; then
  if ! out="$(bash tools/drift-ratchet.sh --check 2>&1)"; then
    hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por drift-ratchet.
El trinquete NO se puede saltar (ni con preset lite ni con REVIEWER_OVERRIDE).
Baja la deuda que introdujiste, o compénsala en otro lado."
  fi
fi
if [ -f tools/check-layers.sh ]; then
  if ! out="$(bash tools/check-layers.sh 2>&1)"; then
    hook_log_detection "check-layers" "pre-commit" "staged" \
      "$(printf '%s' "$out" | sed -nE 's/.*LAYERS_SUMMARY errors=([0-9]+).*/\1/p')"
    hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por violación de capas (AGENTS.md §3).
Las capas son un contrato, no un estilo. Invierte la dependencia o mueve el archivo."
  fi
fi
# Semgrep sobre lo STAGED. Va aquí, y no solo dentro de `check-drift.sh`, porque
# el agregador descarta el exit code por diseño: un semgrep roto o con reglas
# inválidas era invisible en los Anillos 1 y 2 y solo se cazaba en CI. Eso
# contradice §14 ("cázalo en la capa más barata") justo para el detector que
# más barato es de correr. Lo cazó el `reviewer` revisando P1.
if [ -f tools/semgrep-scan.sh ]; then
  out="$(bash tools/semgrep-scan.sh --staged 2>&1)"; rc=$?
  case "$rc" in
    1)  # HALLAZGO real en el código → bloquea, sin excepción.
        hook_log_detection "semgrep" "pre-commit" "staged" \
          "$(printf '%s' "$out" | sed -nE 's/.*SEMGREP_SUMMARY errors=([0-9]+).*/\1/p')"
        hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por hallazgos de semgrep (patrones AST)." ;;
    3)  # El DETECTOR falló (ausente, reglas rotas, crash). Avisa, no bloquea.
        # Bloquear aquí crearía un deadlock: un typo en las reglas impediría
        # incluso el commit que lo arregla (AGENTS.md §4.4). El backstop es CI,
        # donde GATES_REQUIRE_SEMGREP=1 sí lo trata como fallo.
        printf '%s\n' "$out" >&2
        echo "⚠️  reviewer-gate: semgrep no pudo ejecutarse. Commit PERMITIDO (§4.4), pero el" >&2
        echo "   nivel 2 de la pirámide está MUDO hasta que lo arregles. CI sí bloqueará." >&2 ;;
  esac
fi

# ── 2. Marker de review (implementación compartida por los 3 anillos) ─
# El preset lo aplica `check-review-marker.sh`, NO este hook. Cuando la lógica
# de preset vivía aquí, lefthook (Anillo 1) llamaba al script directo y bloqueaba
# igual en `lite`: el Anillo 2 daba luz verde y el commit fallaba después.
# Una regla implementada en dos sitios diverge — vive en uno solo.
if ! out="$(bash tools/check-review-marker.sh --staged 2>&1)"; then
  hook_block "$out"
fi
printf '%s\n' "$out" | grep -q '^⚠️' && { printf '%s\n' "$out" >&2; hook_allow; }

echo "✅ reviewer-gate: detectores verdes + marker válido. Commit permitido." >&2
hook_allow
