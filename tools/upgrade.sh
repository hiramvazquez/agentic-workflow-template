#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# upgrade.sh — trae las mejoras del TEMPLATE a tu proyecto sin perder lo tuyo
# ════════════════════════════════════════════════════════════════════
# El modelo: tu proyecto nació de un clone del template y AMBOS evolucionan.
# Tus rellenos (FILLs, skills, confs) viven COMMITEADOS en tu historial, así
# que traer novedades es un merge de 3 vías normal: git funde automáticamente
# todo lo que no choque, y solo pide tu juicio donde ambos tocasteis las
# mismas líneas. Este script automatiza el ciclo y — como todo aquí — no da
# el upgrade por bueno hasta que la EVIDENCIA lo diga: tras el merge corre la
# suite del harness y validate-harness.
#
#   bash tools/upgrade.sh <url-del-template>   # primera vez (registra el remote)
#   bash tools/upgrade.sh                      # siguientes veces
#
# Reglas de resolución cuando haya conflicto (imprímelas mentalmente):
#   · MAQUINARIA (scripts/, tools/*.sh, ci/, lefthook.yml, tests) → suele
#     ganar el TEMPLATE: si no la personalizaste, acepta la suya (--theirs).
#   · CONTENIDO TUYO (AGENTS.md §2-3, .agents/skills/, *.conf, layers.conf,
#     docs/process/, backlog/, ratchets) → suele ganar TU versión (--ours);
#     incorpora a mano solo la mejora concreta del template si te interesa.
#   · En duda: mira qué cambió cada lado (git log template/main -- <archivo>).
#
# Exit: 0 upgrade limpio y verificado · 1 precondición/verificación fallida ·
#       2 merge con conflictos (quedan marcados para que los resuelvas)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

REMOTE="template"
URL="${1:-}"

# ── Guard 1: árbol limpio — un merge sobre trabajo a medias es dolor ─
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' || true)"
if [ -n "$DIRTY" ]; then
  echo "❌ upgrade: hay cambios sin commitear. Commitea (o stashea) antes de traer el template." >&2
  exit 1
fi

# ── Guard 2: remote registrado (o registrable) ──────────────────────
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  if [ -z "$URL" ]; then
    echo "❌ upgrade: no existe el remote '$REMOTE'. Primera vez:" >&2
    echo "   bash tools/upgrade.sh https://github.com/<tu-usuario>/agentic-workflow-template.git" >&2
    exit 1
  fi
  git remote add "$REMOTE" "$URL"
  echo "✓ remote '$REMOTE' → $URL"
fi

# ── Fetch + rama por defecto del template (main, master, o TEMPLATE_BRANCH) ─
git fetch -q "$REMOTE" || { echo "❌ upgrade: fetch de $REMOTE falló (¿red? ¿URL?)." >&2; exit 1; }
BRANCH="${TEMPLATE_BRANCH:-}"
if [ -z "$BRANCH" ]; then
  for b in main master; do
    if git rev-parse -q --verify "refs/remotes/$REMOTE/$b" >/dev/null 2>&1; then BRANCH="$b"; break; fi
  done
fi
if [ -z "$BRANCH" ]; then
  echo "❌ upgrade: no encuentro main/master en '$REMOTE'. Indica la rama: TEMPLATE_BRANCH=<rama> bash tools/upgrade.sh" >&2
  exit 1
fi
NEW="$(git rev-list --count HEAD.."$REMOTE/$BRANCH" 2>/dev/null || echo 0)"
if [ "${NEW:-0}" = "0" ]; then
  echo "✅ upgrade: ya estás al día con $REMOTE/$BRANCH."
  exit 0
fi
echo "━━━ upgrade: $NEW commit(s) nuevos en el template ━━━"
git log --oneline HEAD.."$REMOTE/$BRANCH" | sed 's/^/   /'

# ── Merge (sin fast-forward: el upgrade queda como un commit visible) ─
if git merge --no-ff --no-edit "$REMOTE/$BRANCH" -m "chore(template): upgrade desde $REMOTE/$BRANCH"; then
  :
else
  echo ""
  echo "⚠️  upgrade: conflictos — ambos tocasteis las mismas líneas. Archivos:"
  CONFLICTS="$(git diff --name-only --diff-filter=U)"
  while IFS= read -r f; do
    case "$f" in
      scripts/*|ci/*|lefthook.yml|tools/tests/*|tools/*.sh)
        echo "   [maquinaria → suele ganar el TEMPLATE]  $f" ;;
      AGENTS.md|.agents/skills/*|tools/*.conf|tools/preset|tools/*-ratchet.json|docs/process/*|backlog/*)
        echo "   [contenido TUYO → suele ganar TU versión] $f" ;;
      *)
        echo "   [a juicio — mira ambos lados]            $f" ;;
    esac
  done <<< "$CONFLICTS"
  echo ""
  echo "   Resuélvelos (git checkout --ours/--theirs <archivo>, o a mano), luego:"
  echo "   git add -A && git commit  — y RE-CORRE este script para la verificación."
  exit 2
fi

# ── Verificación: el upgrade no cuenta hasta que la evidencia lo diga ─
echo ""
echo "━━━ verificando el harness tras el upgrade ━━━"
FAIL=0
bash tools/tests/run-tests.sh >/dev/null 2>&1 || { echo "❌ la suite del harness FALLA tras el merge."; FAIL=1; }
bash tools/validate-harness.sh >/dev/null 2>&1 || { echo "❌ validate-harness FALLA tras el merge."; FAIL=1; }
if [ "$FAIL" = "1" ]; then
  echo ""
  echo "   El merge quedó commiteado pero el harness NO está sano. Opciones:"
  echo "   · arregla lo roto ahora (corre los dos comandos de arriba sin >/dev/null y mira), o"
  echo "   · decisión del owner: deshacer con  git reset --hard ORIG_HEAD  (destruye el merge)."
  exit 1
fi
echo "✅ upgrade verificado: suite en verde + validate-harness OK."
echo "   Repasa 'git show --stat HEAD' y, si un cambio del template pisó un FILL tuyo"
echo "   que git fundió sin conflicto, es un buen momento para revisarlo."
exit 0
