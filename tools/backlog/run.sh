#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# backlog/run.sh — trabaja UNA historia en un WORKTREE aislado
# ════════════════════════════════════════════════════════════════════
# El ciclo del PRD 0003, con la práctica 2026 de los orquestadores:
#   next.sh elige → `git worktree add` crea un directorio AISLADO con la rama
#   story/<id>-<slug> → claude -p headless trabaja AHÍ (los MISMOS gates de
#   siempre: TDD, reviewer VERDICT, trinquetes, capas — el worktree tiene su
#   propio .agents/state, así que markers y baselines arrancan limpios) →
#   commits EN LA RAMA → historia a `in-review` → el humano revisa y mergea.
#
# QUÉ GANA EL WORKTREE frente al checkout in-place anterior:
#   · tu copia de trabajo NUNCA cambia de rama ni se toca — puedes seguir
#     trabajando mientras el agente trabaja su historia
#   · el árbol sucio ya no bloquea el run (antes: guard duro; ahora: aviso)
#   · una rama en `in-review` NO se re-trabaja: el runner la salta hasta tu
#     merge (antes "la retomaba" y podía repetir trabajo ya hecho)
#
# SECUENCIAL a propósito: una historia por invocación (política de
# multi-agent-orchestration.md). El "paralelismo" correcto es tener varias
# ramas independientes esperando review, no varios agentes escribiendo a la
# vez. Repite el ciclo un cron/schedule o un humano.
#
# Exit codes:  0 ok/no-op · 1 precondición/infra git · 3 infra (claude
# ausente) · otro: el rc del run de claude (worktree queda para inspección).
#
# Config por entorno:
#   BACKLOG_CLAUDE_FLAGS   flags extra para claude -p (p.ej. --model X)
#   BACKLOG_MAX_TURNS      si se define, añade --max-turns N
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# ── Árbol sucio: ya NO bloquea (el worktree aísla) — solo informa ───
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' || true)"
[ -n "$DIRTY" ] && echo "ℹ️  backlog: tu árbol tiene cambios sin commitear — no estorban: la historia se trabaja en un worktree aislado."

# ── Selección ───────────────────────────────────────────────────────
STORY="$(bash tools/backlog/next.sh)"
[ -z "$STORY" ] && { echo "backlog: sin historias ready — nada que hacer."; exit 0; }

_field() { awk -v k="$2" '/^---[[:space:]]*$/{n++;next} n==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"; }
_branch_field() { # _branch_field <branch> <archivo> <campo> — lee del contenido de la RAMA
  git show "$1:$2" 2>/dev/null \
    | awk -v k="$3" '/^---[[:space:]]*$/{n++;next} n==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}'
}
_set_status() { # _set_status <archivo> <estado>
  sed -i.bak "s/^status: .*/status: $2/" "$1" && rm -f "$1.bak"
}
ID="$(_field "$STORY" id)"; : "${ID:=$(basename "$STORY" | cut -d- -f1)}"
BASE="$(_field "$STORY" base)"; : "${BASE:=develop}"
SLUG="$(basename "$STORY" .md | sed "s/^${ID}-\{0,1\}//")"
BRANCH="story/${ID}${SLUG:+-$SLUG}"
WT=".agents/worktrees/${BRANCH//\//-}"

# ── Guard 1: la historia tiene contrato (criterios de aceptación) ───
# Sin criterios no hay escenarios golden que verificar → el agente tendría
# que INVENTAR el "cuándo está bien", que es justo lo que §1.4 prohíbe.
# Commit con PATHSPEC (solo la historia): con el árbol sucio permitido, un
# `git commit` a secas arrastraría lo que el humano tuviera en el index.
if ! grep -qi "riterios de aceptaci" "$STORY" || ! grep -q "Dado " "$STORY"; then
  _set_status "$STORY" blocked
  git commit -qm "chore(backlog): ${ID} blocked — sin criterios de aceptación verificables" -- "$STORY" 2>/dev/null
  echo "⚠️  backlog: ${STORY} BLOCKED — sin criterios de aceptación (Dado/cuando/entonces)."
  echo "   Una historia sin contrato verificable no se trabaja: se devuelve (AGENTS.md §1.4)."
  exit 0
fi

# ── Guard 2: claude presente ────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo "❌ backlog: el binario \`claude\` no está en PATH — no puedo trabajar la historia." >&2
  echo "   npm i -g @anthropic-ai/claude-code   (y autentícate)" >&2
  exit 3
fi

# ── Rama nueva o retomar — SIEMPRE vía worktree, jamás checkout aquí ─
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  BR_STATUS="$(_branch_field "$BRANCH" "$STORY" status)"
  if [ "$BR_STATUS" = "in-review" ]; then
    echo "⏸  backlog: ${ID} ya está in-review en ${BRANCH} — esperando TU merge; no se re-trabaja."
    echo "   Revisa: git diff ${BASE}...${BRANCH}   · al mergear, pon status: done en la base."
    exit 0
  fi
  echo "⚠️  backlog: la rama $BRANCH ya existe — la retomo donde quedó."
  if [ ! -d "$WT" ]; then
    git worktree add "$WT" "$BRANCH" >/dev/null 2>&1 \
      || { echo "❌ backlog: no pude crear el worktree para retomar $BRANCH." >&2; exit 1; }
  fi
else
  if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
    git rev-parse --verify main >/dev/null 2>&1 && BASE=main || BASE="$(git rev-parse --abbrev-ref HEAD)"
  fi
  git worktree add "$WT" -b "$BRANCH" "$BASE" >/dev/null 2>&1 \
    || { echo "❌ backlog: git worktree add falló (¿worktree huérfano? git worktree prune)." >&2; exit 1; }
fi

# Estado: in-progress, commiteado EN LA RAMA vía el worktree.
( cd "$WT" && _set_status "$STORY" in-progress \
  && git commit -qm "chore(backlog): ${ID} in-progress" -- "$STORY" 2>/dev/null )

# ── El prompt: la historia + el contrato del harness ────────────────
PROMPT="$(cat <<EOF
Trabaja la siguiente historia de usuario de principio a fin. Estás en un
WORKTREE AISLADO sobre la rama ${BRANCH} (creada desde ${BASE}) y SOLO
trabajas aquí — la copia principal del humano no existe para ti.

$(cat "$WT/$STORY")

CONTRATO (no negociable — AGENTS.md es la fuente canónica y sus gates están activos):
1. Lee AGENTS.md y la skill del área que toques (§11) antes de editar.
1b. ACUERDA EL CONTRATO DE REVIEW ANTES DE ESCRIBIR CÓDIGO: invoca al
   sub-agente \`reviewer\` con la palabra CONTRATO y esta historia. Te
   devolverá los riesgos que aplican, qué comprobará y qué sería RED, y
   cerrará con \`CONTRACT: READY\` (sin veredicto y sin marker: correcto,
   aún no hay diff). Pega su respuesta en una sección
   '## Contrato de review' de la historia y commitéala antes de programar.
   Motivo: una review que llega a ciegas al final re-verifica todo en cada
   vuelta; con el contrato acordado, la final es dirigida y mucho más barata.
   Si algo del contrato contradice la historia, es una Open Question para el
   owner (§1.4) — no lo resuelvas tú.
2. TDD estricto: cada criterio de aceptación se convierte PRIMERO en un test
   que falla, luego la implementación mínima, luego refactor (§5).
3. Scope EXCLUSIVO: los archivos que la historia lista (frontmatter \`scope\`
   y cuerpo). Hallazgos fuera de scope → al ledger
   (bash tools/findings/findings.sh add), jamás "de paso" (§8, §10).
4. Antes de cada commit: invoca el sub-agente \`reviewer\` y atiende su
   veredicto. Sin VERDICT GREEN/AMBER real, el commit está bloqueado — no
   intentes rodearlo.
5. Commits atómicos con formato §7, terminando con: Part of STORY-${ID}.
6. PROHIBIDO: git push, merge, tocar otras ramas, --no-verify, --amend.
7. Si un criterio es imposible o ambiguo: NO lo improvises. Documenta el
   bloqueo al final de la historia (sección '## Bloqueos') y termina.
8. Al terminar: resumen de qué hiciste, tests añadidos, y la salida REAL de
   la suite de tests del área.
9. NO TERMINES EL TURNO CON TRABAJO SIN COMMITEAR NI PROCESOS EN VUELO. Si
   lanzaste algo en background (una suite, un build), ESPERA su salida real y
   pégala; "me notificará al terminar" no es un resultado. El runner comprueba
   el árbol al cerrar: si queda algo sin commitear, la historia vuelve a
   in-progress y el run cuenta como NO terminado.
10. Rellena en la historia la sección '## Verificación de criterios': una línea
   por criterio de aceptación, con la ruta del test que lo fija
   (\`ruta/al/test::nombre\`). Si alguno de verdad no es mecanizable, escribe
   \`n/a-manual — <razón>\`. Un criterio "verificado" con un grep pegado en el
   informe no impide la regresión de mañana; el runner lo comprueba y bloquea.
EOF
)"

# ── Registro del run: la salida de claude NO se evapora en la terminal ─
# Cada run queda en .agents/state/backlog/<id>-<ts>.log (gitignored). Es la
# materia prima de tools/harness-report.sh: sin esto, "¿cómo se comportó el
# agente?" solo se puede responder de memoria — y la memoria no es evidencia.
LOG_DIR="$(pwd)/.agents/state/backlog"; mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/${ID}-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "═══ backlog run · story=${STORY} · branch=${BRANCH} · base=${BASE}"
  echo "═══ fecha=$(date -u +%Y-%m-%dT%H:%M:%SZ) · max_turns=${BACKLOG_MAX_TURNS:-∞} · flags=${BACKLOG_CLAUDE_FLAGS:-—}"
} > "$RUN_LOG"

echo "━━━ backlog: trabajando ${STORY} en ${BRANCH} (worktree ${WT}, base ${BASE}) ━━━"
echo "    log del run: ${RUN_LOG}"
set +e
# shellcheck disable=SC2086
( cd "$WT" && claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    ${BACKLOG_MAX_TURNS:+--max-turns "$BACKLOG_MAX_TURNS"} \
    ${BACKLOG_CLAUDE_FLAGS:-} ) 2>&1 | tee -a "$RUN_LOG"
RC=${PIPESTATUS[0]}
set -e 2>/dev/null || true
echo "═══ fin del run · rc=$RC" >> "$RUN_LOG"

# ════════════════════════════════════════════════════════════════════
# UN RUN QUE DEJA TRABAJO SIN COMMITEAR NO HA TERMINADO
# ════════════════════════════════════════════════════════════════════
# Cazado en vivo con la 0007: el agente lanzó la suite en background, dijo "me
# notificará al terminar" y ahí acabó su turno. `claude -p` salió con 0, así
# que esto marcaba `in-review` y salía 0 también. Desde fuera la historia
# parecía terminada — pero 691 líneas del adapter estaban sin commitear, el
# composition root sin cablear, y `git diff base...rama` no mostraba nada de
# eso. Si alguien podaba el worktree, se perdían.
#
# El exit code de un sub-proceso dice "el proceso terminó", no "el trabajo
# está hecho". Lo segundo tiene un hecho observable —el árbol de trabajo— y es
# el que hay que mirar. Mismo principio que §14.2: el veredicto es la salida de
# un comando, nunca una afirmación de quien lo ejecutó.
if [ $RC -eq 0 ]; then
  PENDIENTE="$( ( cd "$WT" && git status --porcelain 2>/dev/null ) || true )"
  if [ -n "$PENDIENTE" ]; then
    # Respaldo ANTES de nada: que la recuperación no dependa de que nadie
    # pode el worktree por costumbre. Va a .agents/state (gitignored), así
    # que sobrevive a `git worktree remove --force`.
    RESPALDO="$LOG_DIR/${ID}-pendiente-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$RESPALDO"
    ( cd "$WT" && git status --porcelain 2>/dev/null | sed 's/^...//' ) \
      | while IFS= read -r f; do
          [ -z "$f" ] && continue
          mkdir -p "$RESPALDO/$(dirname "$f")" 2>/dev/null
          cp "$WT/$f" "$RESPALDO/$f" 2>/dev/null
        done
    ( cd "$WT" && _set_status "$STORY" in-progress \
      && git commit -qm "chore(backlog): ${ID} in-progress — el run acabó con trabajo sin commitear" -- "$STORY" 2>/dev/null )
    {
      echo ""
      echo "❌ backlog: ${ID} NO ha terminado — el run salió con 0 pero dejó trabajo sin commitear:"
      printf '%s\n' "$PENDIENTE" | sed 's/^/     /'
      echo ""
      echo "   La historia queda en 'in-progress' (NO in-review): desde fuera parecería"
      echo "   terminada y \`git diff ${BASE}...${BRANCH}\` no mostraría nada de esto."
      echo "   ⚠️  NO podes el worktree: el trabajo vive en ${WT}"
      echo "   Copia de seguridad: ${RESPALDO}"
      echo "   Revisa, commitea lo que valga y vuelve a lanzar el runner para retomarla."
    } >&2
    exit 4
  fi
  # Y el segundo hecho observable: cada criterio de aceptación cita el test
  # que lo fija. Mismo mecanismo que el `Detector:` de las lecciones, un nivel
  # más arriba — porque un criterio dado por bueno con un `grep` pegado en el
  # informe se cumple hoy y no impide la regresión de mañana.
  if [ -f tools/backlog/criteria-link.sh ]; then
    CRIT_OUT="$( ( cd "$WT" && bash tools/backlog/criteria-link.sh "$STORY" ) 2>&1 )"; CRIT_RC=$?
    if [ "$CRIT_RC" = "1" ]; then
      ( cd "$WT" && _set_status "$STORY" in-progress \
        && git commit -qm "chore(backlog): ${ID} in-progress — criterios sin test que los fije" -- "$STORY" 2>/dev/null )
      {
        echo ""
        printf '%s\n' "$CRIT_OUT" | grep -v '^CRITERIA_SUMMARY'
        echo "   La historia queda en 'in-progress'. El worktree sigue en ${WT}."
      } >&2
      exit 5
    fi
  fi
  ( cd "$WT" && _set_status "$STORY" in-review \
    && git commit -qm "chore(backlog): ${ID} in-review — lista para revisión humana" -- "$STORY" 2>/dev/null )
  if git worktree remove "$WT" >/dev/null 2>&1; then :; else
    echo "ℹ️  el worktree quedó con restos sin commitear en ${WT} — inspecciónalo y luego: git worktree remove --force ${WT}"
  fi
  echo "✅ backlog: ${ID} → in-review. Revisa la rama ${BRANCH} (git diff ${BASE}...${BRANCH}) y mergéala a ${BASE} (merge = humano)."
else
  ( cd "$WT" && _set_status "$STORY" blocked \
    && git commit -qm "chore(backlog): ${ID} blocked — el run terminó con rc=$RC" -- "$STORY" 2>/dev/null )
  echo "⚠️  backlog: ${ID} → blocked (rc=$RC). El worktree queda en ${WT} para inspección (bórralo con git worktree remove --force cuando termines)." >&2
fi
exit $RC
