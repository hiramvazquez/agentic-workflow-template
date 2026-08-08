#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-harness.sh — ¿los gates EXISTEN de verdad, o solo lo parecen?
# ════════════════════════════════════════════════════════════════════
# La lección más cara de este harness: sus peores fallos no fueron gates que
# bloquearon mal, sino gates que NUNCA DISPARARON — hooks sobre eventos
# inexistentes, patrones de permisos que no matchean, wrappers con el esquema
# equivocado. Todos fallan hacia el SILENCIO: un gate mudo y uno sano se ven
# igual desde fuera... hasta que corres esto.
#
# Regla operativa: NINGÚN gate cuenta como existente hasta que lo has visto
# bloquear algo una vez. Este script hace (A) todo lo verificable en estático,
# y (B) imprime el checklist EN VIVO de lo que solo una sesión real prueba.
#
#   bash tools/validate-harness.sh          # checks estáticos + checklist
#   bash tools/validate-harness.sh --full   # además corre la suite completa
#
# Salida: exit 1 si algún check estático falla. Correr tras CADA update de
# Claude Code / Cursor / Codex: sus contratos de hooks versionan rápido.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

echo "━━━ validate-harness: checks estáticos ━━━"

# ── 1. Los tres configs de hooks son JSON válido ────────────────────
echo ""
echo "── 1. Sintaxis de configuración ──"
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || { warn "$f ausente"; continue; }
  if python3 -c "import json;json.load(open('$f'))" 2>/dev/null; then
    ok "$f: JSON válido"
  else
    bad "$f: JSON INVÁLIDO — ese cliente ignorará TODOS sus hooks"
  fi
done

# ── 2. Solo eventos que EXISTEN en cada cliente ─────────────────────
# (la lista se comparte con tools/tests/test_hook_events.sh)
echo ""
echo "── 2. Nombres de evento por cliente ──"
python3 - <<'PY' || FAIL=1
import json, sys
SPECS = {
    ".claude/settings.json": ({"SessionStart","UserPromptSubmit","PreToolUse","PostToolUse",
                               "Notification","Stop","SubagentStop","SessionEnd","PreCompact"}, "hooks"),
    ".cursor/hooks.json":    ({"beforeSubmitPrompt","beforeShellExecution","beforeMCPExecution",
                               "beforeReadFile","afterFileEdit","stop"}, "hooks"),
    ".codex/hooks.json":     ({"PreToolUse","PostToolUse"}, "hooks"),
}
rc = 0
for path,(valid,key) in SPECS.items():
    try:
        cfg = json.load(open(path))
    except FileNotFoundError:
        continue
    events = [k for k in cfg.get(key,{}) if not k.startswith("_")]
    ghosts = [e for e in events if e not in valid]
    if ghosts:
        print(f"  ❌ {path}: eventos INEXISTENTES {ghosts} — esos hooks JAMÁS dispararán (gate mudo)")
        rc = 1
    else:
        print(f"  ✅ {path}: {len(events)} eventos, todos válidos")
sys.exit(rc)
PY

# ── 3. Cada comando de hook apunta a un script que existe y parsea ──
echo ""
echo "── 3. Scripts referenciados por los hooks ──"
MISSING=0
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || continue
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -f "$s" ]; then bad "$f referencia $s — NO EXISTE"; MISSING=1
    elif ! bash -n "$s" 2>/dev/null; then bad "$s no parsea (bash -n)"; MISSING=1; fi
  done < <(grep -oE 'scripts/agent-hooks/[A-Za-z0-9_./-]+\.sh' "$f" | sort -u)
done
[ "$MISSING" = "0" ] && ok "todos los scripts de hooks existen y parsean"

# ── 4. Symlinks del contrato multi-cliente ──────────────────────────
echo ""
echo "── 4. Symlinks ──"
for l in .claude/skills .cursor/agents; do
  if [ -L "$l" ] && [ -e "$l" ]; then ok "$l → $(readlink "$l")"
  elif [ -e "$l" ]; then warn "$l existe pero no es symlink"
  else warn "$l ausente (¿clone en un FS sin symlinks?) — skills/agents no cargarán ahí"; fi
done

# ── 5. La matriz de skills: refs existen y cubre tu código ──────────
echo ""
echo "── 5. skill-matrix.conf ──"
if [ -f tools/skill-matrix.conf ]; then
  BADREF=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _oldIFS="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { bad "skill-matrix: ref inexistente '$r' (glob '$glob')"; BADREF=1; }
    done
    IFS="$_oldIFS"
  done < tools/skill-matrix.conf
  [ "$BADREF" = "0" ] && ok "todas las refs de la matriz existen"
else
  bad "tools/skill-matrix.conf AUSENTE — skill-reminder degrada a globs de fábrica"
fi

# ── 6. Dependencias externas de los gates ───────────────────────────
echo ""
echo "── 6. Dependencias ──"
for dep in jq python3 git; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || bad "$dep AUSENTE — varios hooks degradan o fallan"
done
for dep in semgrep gitleaks lefthook; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || warn "$dep ausente — el nivel que lo usa está MUDO (session-start ya lo reporta)"
done
if [ -d .git ] && [ -f lefthook.yml ]; then
  grep -q lefthook .git/hooks/pre-commit 2>/dev/null \
    && ok "Anillo 1 instalado (.git/hooks/pre-commit)" \
    || bad "ANILLO 1 DORMIDO: corre \`lefthook install\`"
fi

# ── 7. La suite del harness existe (y opcionalmente pasa) ───────────
echo ""
echo "── 7. Suite del harness ──"
NT="$(find tools/tests -name 'test_*.sh' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NT:-0}" = "0" ]; then
  bad "0 archivos test_*.sh — canon-enforce CHECK 4 y CI paso 1 aprueban en vacuo"
else
  ok "$NT archivos de test presentes"
  if [ "${1:-}" = "--full" ]; then
    bash tools/tests/run-tests.sh || FAIL=1
  fi
fi

# ── Veredicto estático + checklist en vivo ──────────────────────────
echo ""
echo "━━━ checklist EN VIVO (esto NO se puede verificar en estático) ━━━"
cat <<'LIVE'
En una sesión REAL de Claude Code sobre este repo, verifica una vez por
versión del cliente (y anota la fecha en docs/process/lessons_learned.md):

  □ SessionStart: al abrir la sesión se imprime el health-check.
  □ Anillo 0: pide `git commit --no-verify -m x` → debe DENEGARSE (permissions
    o, en su defecto, git-guard del reviewer-gate). Si lo deniega el guard y
    no permissions, los patrones deny con comodín intermedio están inertes en
    tu versión: elimínalos o corrígelos.
  □ skill-reminder: intenta editar un archivo que case la matriz sin haber
    leído las refs → debe bloquear (preset full).
  □ reviewer-gate: `git commit` sin marker → bloqueado (full) / aviso (lite).
  □ SubagentStop: invoca al sub-agente reviewer; al terminar debe existir
    .agents/state/markers/reviewer_run.txt con `source: hook`.
  □ Compactación: fuerza `/compact`; el turno siguiente debe traer el digest
    reinyectado (SessionStart matcher compact → post-compact.sh) y NO debe
    haberse borrado .agents/state/skills-read/.
  □ Telemetría: .agents/state/metrics/detections.jsonl crece cuando un gate
    detecta algo.

En Codex CLI (si lo usas):
  □ hooks habilitados ([features] codex_hooks) y `git commit --no-verify`
    denegado por el adapter. Si tu versión no soporta hooks de proyecto,
    muévelos a ~/.codex/hooks.json.

En Cursor (si lo usas):
  □ beforeShellExecution deniega `git commit` sin marker (respuesta JSON del
    gate-adapter). Recuerda: sin SubagentStop, el marker se genera con
    scripts/mark-reviewer-run.sh (auditado) o preset lite.
LIVE

echo ""
if [ "$FAIL" = "0" ]; then
  echo "✅ validate-harness: checks estáticos OK. Lo de arriba ↑ solo lo prueba una sesión real."
  exit 0
fi
echo "❌ validate-harness: hay checks estáticos FALLANDO — gates mudos o rotos. Arréglalos antes de confiar."
exit 1
