#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# backlog/run.sh — trabaja UNA historia: rama nueva + claude -p + gates
# ════════════════════════════════════════════════════════════════════
# El ciclo del PRD 0003:
#   next.sh elige → rama story/<id>-<slug> desde la base → claude -p headless
#   con la historia + el contrato del harness → los MISMOS gates de siempre
#   (TDD, reviewer VERDICT, trinquetes, capas) → commits EN LA RAMA →
#   historia a `in-review` → el humano revisa y mergea (el merge es SIEMPRE
#   humano; este script jamás pushea ni mergea).
#
# SECUENCIAL a propósito: una historia por invocación (política de
# multi-agent-orchestration.md). El "paralelismo" correcto es tener varias
# ramas independientes esperando review, no varios agentes escribiendo a la
# vez. Repite el ciclo un cron/schedule o un humano.
#
# Exit codes:  0 ok/no-op · 1 precondición (árbol sucio) · 3 infra (claude
# ausente) · otro: el rc del run de claude (la rama queda para inspección).
#
# Config por entorno:
#   BACKLOG_CLAUDE_FLAGS   flags extra para claude -p (p.ej. --model X)
#   BACKLOG_MAX_TURNS      si se define, añade --max-turns N
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# ── Guard 1: árbol limpio (no pisamos trabajo de nadie) ─────────────
# Solo cuentan las modificaciones TRACKED: un archivo nuevo sin trackear (una
# historia recién pegada en backlog/, p. ej.) viaja con el checkout sin riesgo
# — y al commitearse en la rama de su historia, desaparece de la base hasta el
# merge, que es exactamente el ciclo de vida que queremos.
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' || true)"
if [ -n "$DIRTY" ]; then
  echo "❌ backlog: hay cambios TRACKED sin commitear — no arranco una historia encima de trabajo a medias." >&2
  exit 1
fi

# ── Selección ───────────────────────────────────────────────────────
STORY="$(bash tools/backlog/next.sh)"
[ -z "$STORY" ] && { echo "backlog: sin historias ready — nada que hacer."; exit 0; }

_field() { awk -v k="$2" '/^---[[:space:]]*$/{n++;next} n==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"; }
_set_status() { # _set_status <archivo> <estado>
  sed -i.bak "s/^status: .*/status: $2/" "$1" && rm -f "$1.bak"
}
ID="$(_field "$STORY" id)"; : "${ID:=$(basename "$STORY" | cut -d- -f1)}"
BASE="$(_field "$STORY" base)"; : "${BASE:=develop}"
SLUG="$(basename "$STORY" .md | sed "s/^${ID}-\{0,1\}//")"
BRANCH="story/${ID}${SLUG:+-$SLUG}"

# ── Guard 2: la historia tiene contrato (criterios de aceptación) ───
# Sin criterios no hay escenarios golden que verificar → el agente tendría
# que INVENTAR el "cuándo está bien", que es justo lo que §1.4 prohíbe.
if ! grep -qi "riterios de aceptaci" "$STORY" || ! grep -q "Dado " "$STORY"; then
  _set_status "$STORY" blocked
  git add "$STORY" && git commit -qm "chore(backlog): ${ID} blocked — sin criterios de aceptación verificables" 2>/dev/null
  echo "⚠️  backlog: ${STORY} BLOCKED — sin criterios de aceptación (Dado/cuando/entonces)."
  echo "   Una historia sin contrato verificable no se trabaja: se devuelve (AGENTS.md §1.4)."
  exit 0
fi

# ── Guard 3: claude presente ────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo "❌ backlog: el binario \`claude\` no está en PATH — no puedo trabajar la historia." >&2
  echo "   npm i -g @anthropic-ai/claude-code   (y autentícate)" >&2
  exit 3
fi

# ── Rama desde la base ──────────────────────────────────────────────
ORIG="$(git rev-parse --abbrev-ref HEAD)"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  git rev-parse --verify main >/dev/null 2>&1 && BASE=main || BASE="$ORIG"
fi
git checkout -q "$BASE"
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  echo "⚠️  backlog: la rama $BRANCH ya existe — la retomo donde quedó."
  git checkout -q "$BRANCH"
else
  git checkout -qb "$BRANCH"
fi

# Estado: in-progress, commiteado EN LA RAMA (trazabilidad sin tocar la base).
_set_status "$STORY" in-progress
git add "$STORY" && git commit -qm "chore(backlog): ${ID} in-progress" 2>/dev/null

# ── El prompt: la historia + el contrato del harness ────────────────
PROMPT="$(cat <<EOF
Trabaja la siguiente historia de usuario de principio a fin. Estás en la rama
${BRANCH} (creada desde ${BASE}) y SOLO trabajas aquí.

$(cat "$STORY")

CONTRATO (no negociable — AGENTS.md es la fuente canónica y sus gates están activos):
1. Lee AGENTS.md y la skill del área que toques (§11) antes de editar.
2. TDD estricto: cada criterio de aceptación se convierte PRIMERO en un test
   que falla, luego la implementación mínima, luego refactor (§5).
3. Scope EXCLUSIVO: los archivos que la historia lista (frontmatter `scope`
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
EOF
)"

echo "━━━ backlog: trabajando ${STORY} en ${BRANCH} (base ${BASE}) ━━━"
set +e
# shellcheck disable=SC2086
claude -p "$PROMPT" \
  --permission-mode acceptEdits \
  ${BACKLOG_MAX_TURNS:+--max-turns "$BACKLOG_MAX_TURNS"} \
  ${BACKLOG_CLAUDE_FLAGS:-}
RC=$?
set -e 2>/dev/null || true

# ── Cierre de estado (en la rama) y vuelta a la base ────────────────
if [ $RC -eq 0 ]; then
  _set_status "$STORY" in-review
  git add "$STORY" && git commit -qm "chore(backlog): ${ID} in-review — lista para revisión humana" 2>/dev/null
  echo "✅ backlog: ${ID} → in-review. Revisa la rama ${BRANCH} y mergéala a ${BASE} (merge = humano)."
else
  _set_status "$STORY" blocked
  git add "$STORY" && git commit -qm "chore(backlog): ${ID} blocked — el run terminó con rc=$RC" 2>/dev/null
  echo "⚠️  backlog: ${ID} → blocked (rc=$RC). La rama ${BRANCH} queda para inspección." >&2
fi
git checkout -q "$ORIG" 2>/dev/null || true
exit $RC
