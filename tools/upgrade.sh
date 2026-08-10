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

# ════════════════════════════════════════════════════════════════════
# DOS TOPOLOGÍAS, y durante meses solo se contempló una
# ════════════════════════════════════════════════════════════════════
# La cabecera de este script decía "tu proyecto nació de un clone del
# template". Falso para el camino de adopción que la PROPIA doc recomienda
# (docs/ADOPTION.md): copiar el harness DENTRO de un proyecto que ya existe
# — que es lo normal, porque la app suele existir antes que el harness.
# Esos dos repos tienen historias NO RELACIONADAS y `git merge` se niega.
# Resultado: el camino de upgrade estaba roto justo para la ruta de adopción
# principal, y se descubrió el día que hizo falta usarlo de verdad.
#
#   MODO MERGE  · hay ancestro común (clone del template) → merge de 3 vías.
#   MODO SYNC   · sin ancestro común (adopción por copia) → se traen los
#                 paths de MAQUINARIA y se REPORTA el resto. Nunca se toca
#                 contenido del proyecto: eso sigue siendo tuyo por defecto.
#
# En MODO SYNC se registra el SHA del template en `tools/.template-sync`.
# Con ese registro, la próxima vez se puede aplicar solo el DELTA real
# (`git apply --3way`), que produce conflictos únicamente donde ambos lados
# tocaron lo mismo — un merge de 3 vías de facto, sin ancestro compartido.
MERGE_BASE_OK=0
git merge-base HEAD "$REMOTE/$BRANCH" >/dev/null 2>&1 && MERGE_BASE_OK=1

# Maquinaria: se sincroniza. Es el harness, y su fuente de verdad es el
# template (si la personalizaste, tu arreglo necesita SU test — lección del
# archivo-por-fuera-de-upgrade; la verificación de abajo es la red).
SYNC_PATHS="scripts ci lefthook.yml tools/tests tools/semgrep/rules tools/metrics .github/workflows"
SYNC_GLOBS="tools/*.sh tools/findings/*.sh tools/findings/*.ts"
SYNC_RECORD="tools/.template-sync"

_report_no_sincronizado() {
  # Honestidad: lo que el template cambió y NO se ha tocado aquí. Sin esta
  # lista, "upgrade OK" leería como "traído todo", que es justo la clase de
  # falsa confianza que este harness persigue.
  local base="$1" changed
  changed="$(git diff --name-only "$base" "$REMOTE/$BRANCH" 2>/dev/null \
    | grep -vE '^(scripts/|ci/|tools/tests/|tools/semgrep/rules/|tools/metrics/|\.github/workflows/)' \
    | grep -vE '^tools/[A-Za-z0-9_-]+\.sh$' \
    | grep -vE '^tools/findings/[A-Za-z0-9_-]+\.(sh|ts)$' || true)"
  [ -z "$changed" ] && return 0
  echo ""
  echo "📋 El template también cambió esto, y NO lo he tocado (es tuyo o es a juicio):"
  printf '%s\n' "$changed" | sed 's/^/   · /'
  echo "   Míralo con:  git diff HEAD $REMOTE/$BRANCH -- <archivo>"
  echo "   Incorpora a mano solo lo que te interese. Tu contenido no se pisa nunca."
}

if [ "$MERGE_BASE_OK" = "1" ]; then
  # ── MODO MERGE (historia compartida) ──────────────────────────────
  if ! git merge --no-ff --no-edit "$REMOTE/$BRANCH" \
        -m "chore(template): upgrade desde $REMOTE/$BRANCH" 2>/tmp/upgrade-merge-err.$$; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    if [ -z "$CONFLICTS" ]; then
      # NO son conflictos: el merge falló por otra cosa. Decir "resuelve los
      # conflictos" sin conflictos manda al humano a buscar lo que no existe
      # — un diagnóstico equivocado cuesta más que ninguno.
      echo ""
      echo "❌ upgrade: el merge FALLÓ (y no por conflictos: no hay archivos en conflicto)." >&2
      sed 's/^/   /' /tmp/upgrade-merge-err.$$ >&2 2>/dev/null
      rm -f /tmp/upgrade-merge-err.$$
      git merge --abort 2>/dev/null
      echo "   El árbol se dejó como estaba (merge --abort)." >&2
      exit 1
    fi
    rm -f /tmp/upgrade-merge-err.$$
    echo ""
    echo "⚠️  upgrade: conflictos — ambos tocasteis las mismas líneas. Archivos:"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
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
  rm -f /tmp/upgrade-merge-err.$$
else
  # ── MODO SYNC (adopción por copia: historias no relacionadas) ─────
  echo ""
  echo "━━━ MODO SYNC: tu repo y el template NO comparten historia ━━━"
  echo "   (normal si adoptaste copiando el harness a un proyecto que ya existía)"
  BASE_REC=""
  [ -f "$SYNC_RECORD" ] && BASE_REC="$(awk 'NR==1{print $1; exit}' "$SYNC_RECORD" 2>/dev/null)"
  if [ -n "$BASE_REC" ] && git cat-file -e "$BASE_REC^{commit}" 2>/dev/null; then
    echo "   Base registrada: $BASE_REC — aplico solo el DELTA de maquinaria."
    # shellcheck disable=SC2086  # los globs DEBEN expandirse aquí
    if git diff "$BASE_REC" "$REMOTE/$BRANCH" -- $SYNC_PATHS $SYNC_GLOBS > /tmp/upgrade.patch.$$ 2>/dev/null \
       && [ -s /tmp/upgrade.patch.$$ ]; then
      if git apply --3way --whitespace=nowarn /tmp/upgrade.patch.$$ 2>/tmp/upgrade-apply-err.$$; then
        echo "   ✓ delta aplicado limpio."
      else
        CONFLICTS="$(git diff --name-only --diff-filter=U)"
        if [ -n "$CONFLICTS" ]; then
          echo ""
          echo "⚠️  upgrade: el delta dejó conflictos (ambos lados tocaron lo mismo):"
          printf '%s\n' "$CONFLICTS" | sed 's/^/   · /'
          echo "   Resuélvelos SIN elegir a ciegas: si tenías un arreglo local en"
          echo "   maquinaria, MERGEA ambos. Un arreglo local sin su test se pierde"
          echo "   en silencio (lección del archivo-por-fuera-de-upgrade)."
          echo "   Luego: git add -A && git commit — y RE-CORRE este script."
          rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
          exit 2
        fi
        echo "❌ upgrade: no pude aplicar el delta de maquinaria:" >&2
        sed 's/^/   /' /tmp/upgrade-apply-err.$$ >&2 2>/dev/null
        rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
        exit 1
      fi
    else
      echo "   (sin cambios de maquinaria desde la base registrada)"
    fi
    rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
  else
    # PRIMERA VEZ sin registro: no hay forma de saber qué cambió cada lado,
    # así que se trae la maquinaria ENTERA y se avisa con todas las letras.
    echo ""
    echo "⚠️  PRIMERA SINCRONIZACIÓN (sin base registrada)."
    echo "   Voy a traer la MAQUINARIA COMPLETA del template. Si tenías arreglos"
    echo "   locales en scripts/ o tools/*.sh, esto los SOBRESCRIBE — revisa el"
    echo "   diff antes de commitear. La red es la verificación de abajo (suite +"
    echo "   selftest): un arreglo local con su test lo delata al fallar."
    echo ""
    for p in $SYNC_PATHS; do
      git checkout "$REMOTE/$BRANCH" -- "$p" 2>/dev/null && echo "   ✓ $p"
    done
    # shellcheck disable=SC2086
    git checkout "$REMOTE/$BRANCH" -- $SYNC_GLOBS 2>/dev/null && echo "   ✓ tools/*.sh"
  fi
  printf '%s  # SHA del template sincronizado por tools/upgrade.sh — no editar a mano\n' \
    "$(git rev-parse "$REMOTE/$BRANCH")" > "$SYNC_RECORD"
  git add -A -- $SYNC_PATHS $SYNC_RECORD 2>/dev/null
  # shellcheck disable=SC2086
  git add -A -- $SYNC_GLOBS 2>/dev/null
  _report_no_sincronizado "${BASE_REC:-$REMOTE/$BRANCH}"
  echo ""
  echo "━━━ Cambios traídos (staged, SIN commitear a propósito) ━━━"
  git diff --cached --stat | tail -20
  echo ""
  echo "   Revísalos y commitea tú:  git commit -m \"chore(template): sync de maquinaria\""
  echo "   Después RE-CORRE este script para la verificación con evidencia."
  exit 2
fi

# ── Verificación: el upgrade no cuenta hasta que la evidencia lo diga ─
# Con --selftest: cada detector debe DEMOSTRAR una detección real tras el
# merge, no solo existir. Es la red contra el modo de fallo más caro de un
# upgrade: un archivo del template que REVIERTE un arreglo local en silencio
# (pasó en vivo con semgrep-scan.sh — un snapshot viejo borró el split de
# .errors[] y solo lo cazó un test que ese arreglo había dejado detrás).
echo ""
echo "━━━ verificando el harness tras el upgrade ━━━"
FAIL=0
bash tools/tests/run-tests.sh >/dev/null 2>&1 || { echo "❌ la suite del harness FALLA tras el merge."; FAIL=1; }
bash tools/validate-harness.sh --selftest >/dev/null 2>&1 || { echo "❌ validate-harness --selftest FALLA tras el merge."; FAIL=1; }
if [ "$FAIL" = "1" ]; then
  echo ""
  echo "   El merge quedó commiteado pero el harness NO está sano. Opciones:"
  echo "   · arregla lo roto ahora (corre los dos comandos de arriba sin >/dev/null y mira), o"
  echo "   · decisión del owner: deshacer con  git reset --hard ORIG_HEAD  (destruye el merge)."
  exit 1
fi
echo "✅ upgrade verificado: suite en verde + validate-harness --selftest OK."
echo "   Repasa 'git show --stat HEAD' y, si un cambio del template pisó un FILL tuyo"
echo "   que git fundió sin conflicto, es un buen momento para revisarlo."
echo ""
echo "   ⚠️  REGLA DE ORO DEL FLUJO INVERSO: si algún archivo del harness te llega"
echo "   por FUERA de este script (copiado a mano, pegado, traído por un puente),"
echo "   corre inmediatamente:  bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest"
echo "   Un archivo que entra sin pasar por aquí se salta esta red — y un arreglo"
echo "   local sin test propio puede quedar revertido EN SILENCIO. Corolario:"
echo "   toda divergencia local deliberada lleva SU test, que es lo que la hace"
echo "   sobrevivir a un cp descuidado (lección 2026-08-09 del primer proyecto)."
exit 0
