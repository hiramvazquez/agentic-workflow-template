#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# scope.sh — qué cuenta como PRODUCTO en este repo (fuente única)
# ════════════════════════════════════════════════════════════════════
# La comparten `check-review-marker.sh` y `check-verify-marker.sh`. Antes el
# segundo GREPEABA la línea del primero para no duplicar la lista: funcionaba,
# pero acoplaba dos scripts por el texto de una línea. Aquí vive una vez.
#
# ── Por qué hay dos respuestas y no una ─────────────────────────────
# En un proyecto de app, `tools/` y `scripts/` son ANDAMIO: exigir review por
# tocar un script del harness sería ruido, y el ruido acaba en un
# `REVIEWER_OVERRIDE` de costumbre que apaga el gate de verdad (ley del 10%).
#
# En el repo del PROPIO harness, esos directorios son el PRODUCTO. Medido por un
# adoptante que auditó nuestro historial: **15 commits seguidos sin que el
# reviewer-gate disparara ni una vez**, incluidos el que invirtió la política de
# seguridad de AGENTS.md §6 y el que metió un gate bloqueante nuevo al Anillo 3.
# Salió bien por disciplina del agente (12 invocaciones voluntarias), no por el
# mecanismo. Dicho del modo más incómodo posible: **nuestro propio reviewer-gate
# no había bloqueado un commit en su vida.**
#
# La distinción no es nueva: `check-ring3.sh` ya dice, con estas palabras, "los
# gates completos de un proyecto, o —en el repo del propio harness— la suite que
# verifica los gates, que ahí es exactamente lo mismo". Un gate lo reconocía y
# el otro no.
#
# ── Cómo se decide, sin preguntarle al repo quién cree que es ───────
# Un repo cuyo producto es el harness NO TIENE fuentes de aplicación. Es el
# mismo discriminador que usa `verify-run.sh` para detectar un `verify.conf`
# heredado, y por la misma razón: no depende de un nombre, de un remote ni de
# un flag que alguien pueda poner mal.
_repo_es_el_harness() {
  local p
  p="$(find ios android web src app lib Sources -type f \
        \( -name '*.swift' -o -name '*.kt' -o -name '*.java' -o -name '*.ts' \
           -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
           -o -name '*.rb' -o -name '*.cs' -o -name '*.rs' \) 2>/dev/null | head -1)"
  [ -z "$p" ]
}

# Proyecto de app: el andamio no exige review.
_NON_PRODUCT_APP='^(docs/|ci/|\.github/|tools/|scripts/|backlog/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|lefthook|\.gitleaks|\.semgrepignore|muter\.conf|AGENTS\.md|CLAUDE\.md|GEMINI\.md|(ios|android|web|backend)/AGENTS\.md$)'

# Repo del harness: producto = lo que EJECUTA (tools/, scripts/, ci/, lefthook)
# y lo que es NORMATIVO para los adoptantes (AGENTS.md). Siguen exentos la prosa
# y los REGISTROS: `docs/`, `backlog/`, `README`, y los dos ledgers, que son
# generados o anotados y pedirían un reviewer por cada lección apuntada — eso
# sí sería el ruido que mata el gate.
_NON_PRODUCT_HARNESS='^(docs/|backlog/|enterprise/|\.github/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|\.gitleaks|\.semgrepignore|muter\.conf|CLAUDE\.md|GEMINI\.md|tools/findings/ledger\.jsonl$|(ios|android|web|backend)/AGENTS\.md$)'

scope_non_product() {
  if _repo_es_el_harness; then printf '%s' "$_NON_PRODUCT_HARNESS"
  else printf '%s' "$_NON_PRODUCT_APP"; fi
}
