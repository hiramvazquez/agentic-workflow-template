#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# backlog/next.sh — ¿cuál es la SIGUIENTE historia trabajable?
# ════════════════════════════════════════════════════════════════════
# Imprime la ruta de la primera historia `status: ready` cuyas dependencias
# están TODAS en `done` — y done significa "mergeada a la rama base", porque
# el estado se lee del checkout actual: una dependencia solo desbloquea
# cuando el humano la revisó y mergeó. Eso ordena el grafo sin coordinación.
#
# Sin candidatas (o sin backlog/): imprime nada y sale 0 — apto para cron.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

[ -d backlog ] || exit 0

_field() { # _field <archivo> <campo>  → valor del frontmatter
  awk -v k="$2" '
    /^---[[:space:]]*$/ { n++; next }
    n==1 && $1 == k":" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
  ' "$1" 2>/dev/null
}

for story in backlog/[0-9]*.md; do
  [ -f "$story" ] || continue
  status="$(_field "$story" status)"
  [ "$status" = "ready" ] || continue

  # Dependencias: `depends_on: [0001, 0002]` → cada una debe estar en done.
  deps="$(_field "$story" depends_on | sed -E 's/[][]//g; s/,/ /g')"
  ok=1
  for dep in $deps; do
    dep="${dep// /}"; [ -z "$dep" ] && continue
    dep_done=0
    for df in backlog/${dep}*.md; do
      [ -f "$df" ] || continue
      [ "$(_field "$df" status)" = "done" ] && dep_done=1
    done
    [ "$dep_done" = "1" ] || { ok=0; break; }
  done
  [ "$ok" = "1" ] || continue

  printf '%s\n' "$story"
  exit 0
done
exit 0
