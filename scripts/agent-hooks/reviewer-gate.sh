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
GATE_T0="$(date +%s 2>/dev/null || echo 0)"

# ── 0. GIT-GUARD: prohibiciones de flags — la garantía DURA del Anillo 0 ─
# permissions.deny con comodín intermedio (`git commit:*--no-verify*`) no está
# garantizado por la sintaxis documentada de Claude Code, y un deny que no
# matchea es invisible. ESTE guard sí ve el comando completo y bloquea
# determinísticamente (AGENTS.md §7).
#
# Análisis por SEGMENTO (split en ;|&) exigiendo `git` en POSICIÓN DE COMANDO
# (con prefijos VAR=val permitidos): así `REVIEWER_OVERRIDE=1 git commit` se
# gatea, pero `grep "git commit --no-verify" doc.md` NO — el texto que MENCIONA
# un comando prohibido no es el comando (falso positivo real de la v1; ley del
# 10%). Límite conocido: `git -C /ruta commit` no se detecta como commit.
# Duro en ambos presets: son prohibiciones absolutas, no gates de calidad.
_GIT_CMD_RE='^[[:space:]]*\(*[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+'
_seg_is_git_sub() { # _seg_is_git_sub <segmento> <subcomando>
  printf '%s' "$1" | grep -qE "${_GIT_CMD_RE}(-[^[:space:]]+[[:space:]]+)*$2([[:space:]]|\$)"
}
IS_COMMIT=0; HAS_ADD=0
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  if _seg_is_git_sub "$seg" commit; then
    IS_COMMIT=1
    case "$seg" in
      *--no-verify*) hook_block "🛑 git-guard: \`--no-verify\` está PROHIBIDO (AGENTS.md §7). Los hooks de git son el Anillo 1; saltárselos deja el commit sin gates. Si un gate te bloquea injustamente, arregla el gate — no lo evadas." ;;
      *--amend*)     hook_block "🛑 git-guard: \`--amend\` requiere orden EXPLÍCITA del owner (AGENTS.md §7). Reescribir historia publicada rompe a los demás; crea un commit nuevo." ;;
    esac
  fi
  if _seg_is_git_sub "$seg" push; then
    case "$seg" in
      *--force*|*" -f"*) hook_block "🛑 git-guard: \`push --force\` está PROHIBIDO (AGENTS.md §7)." ;;
    esac
  fi
  if _seg_is_git_sub "$seg" reset; then
    case "$seg" in
      *--hard*) hook_block "🛑 git-guard: \`reset --hard\` destruye trabajo sin recuperación. Usa \`git stash\` o pide aprobación al owner." ;;
    esac
  fi
  _seg_is_git_sub "$seg" add && HAS_ADD=1
done <<< "$(printf '%s' "$CMD" | tr ';&|' '\n')"

# Solo gateamos `git commit`.
[ "$IS_COMMIT" -eq 1 ] || hook_allow

# ── 0b. El marker liga sha256(diff STAGED): add+commit en una línea lo evade ─
# El gate corre ANTES de ejecutar el comando completo, así que con
# `git add X && git commit` validaríamos el staged ANTERIOR al add — y se
# commitearía contenido distinto del validado. Lo mismo con `commit -a/-am`,
# que stagea implícitamente en el momento del commit. Flujo correcto:
# stagea → invoca al reviewer → commitea (documentado en ADOPTION §8).
# Bloquea en full, avisa en lite (fricción vs seguridad, igual que el marker).
if [ "$HAS_ADD" -eq 1 ]; then
  hook_block_or_warn "🛑 reviewer-gate: \`git add\` y \`git commit\` en el MISMO comando evaden la validación del diff staged (el gate corre antes del add). Sepáralo: stagea primero, revisa, y commitea en un comando aparte."
fi
if printf '%s' "$CMD" | grep -qE 'git commit[^;|&]*(\s-a[m]?(\s|$)|--all)'; then
  hook_block_or_warn "🛑 reviewer-gate: \`git commit -a/-am\` stagea en el momento del commit — el marker de review liga el sha del diff que YA estaba staged, no ese. Stagea explícito, revisa, y commitea sin \`-a\`."
fi

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
        # incluso el commit que lo arregla (AGENTS.md §14.3). El backstop es CI,
        # donde GATES_REQUIRE_SEMGREP=1 sí lo trata como fallo.
        printf '%s\n' "$out" >&2
        echo "⚠️  reviewer-gate: semgrep no pudo ejecutarse. Commit PERMITIDO (§14.3), pero el" >&2
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

# ── Presupuesto de tiempo: un PreToolUse que agota su timeout NO bloquea ─
# (el gate desaparece en silencio). Si consumimos >½ del presupuesto (90s en
# settings.json), se deja rastro para que el humano lo vea y ajuste.
GATE_T1="$(date +%s 2>/dev/null || echo 0)"
if [ "$GATE_T1" -gt 0 ] && [ "$GATE_T0" -gt 0 ] && [ $((GATE_T1 - GATE_T0)) -gt 45 ]; then
  echo "⚠️  reviewer-gate tardó $((GATE_T1 - GATE_T0))s (presupuesto 90s). Si llega al timeout, el gate NO bloquea — se salta en silencio. Acota DRIFT_SRC_DIRS o sube el timeout en settings.json." >&2
  hook_log_detection "reviewer-gate" "budget-warning" "pre-commit" "$((GATE_T1 - GATE_T0))"
fi

echo "✅ reviewer-gate: detectores verdes + marker válido. Commit permitido." >&2
hook_allow
