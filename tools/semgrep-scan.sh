#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# semgrep-scan.sh — análisis estático AST (nivel 2 de la pirámide)
# ════════════════════════════════════════════════════════════════════
# Sustituye a los `grep` de check-drift.sh para todo lo que dependa de
# entender la SINTAXIS. La diferencia práctica:
#
#   grep 'try!'      → matchea el comentario "no uses try!", el string
#                      "try!" y el test que documenta el anti-patrón.
#   semgrep pattern  → matchea solo el nodo real del árbol.
#
# Google midió el umbral en el que un analizador muere por ruido: ~10% de
# falsos positivos. Un detector por grep lo supera con facilidad, y entonces
# no solo lo ignora el humano — el agente aprende a evadirlo.
#
#   bash tools/semgrep-scan.sh              # todo el repo
#   bash tools/semgrep-scan.sh --staged     # solo lo staged (pre-commit)
#
# ── CONTRATO DE EXIT CODE (importa: los llamadores dependen de él) ───
#   0  scan limpio
#   1  HALLAZGOS reales de severidad ERROR   → los llamadores BLOQUEAN
#   3  FALLO DEL PROPIO DETECTOR              → local AVISA, CI bloquea
#      (semgrep ausente · reglas que no cargan · crash sin JSON · jq ausente)
#
# Por qué 3 y no 1: sin esta distinción, un typo en `tools/semgrep/rules/*.yaml`
# bloqueaba TODOS los commits, en ambos presets, sin escape — incluido el commit
# que arreglaría el typo, porque la carga de reglas falla mires lo que mires.
# Eso es un deadlock local y contradice AGENTS.md §14.3 ("un bug del hook nunca
# debe trabar al dev"). "Tu código tiene un problema" y "no pude mirar tu
# código" son cosas distintas y merecen respuestas distintas.
# Lo cazó el `reviewer` en la 3ª ronda de P1 (PRD 0001 §18 G13).
#
# Contrato de stdout:  SEMGREP_SUMMARY errors=<N> warns=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# Sin esto, semgrep intenta un version-check de red al arrancar y en redes
# restringidas se CUELGA (no falla: espera). Misma lección que el bloque
# _ver() de harness-report.sh — un scan que puede colgarse indefinidamente
# convierte cualquier gate que lo invoque en una lotería de timeouts.
export SEMGREP_ENABLE_VERSION_CHECK=0

RULES_DIR="${SEMGREP_RULES:-tools/semgrep/rules}"
MODE="${1:---all}"

# Los avisos de INFRAESTRUCTURA van a stderr, nunca a stdout.
# Motivo: stdout lo agrega `check-drift.sh` contando líneas ❌/⚠️, y una
# herramienta ausente NO es deuda del código. Contarla haría subir el
# trinquete por un motivo falso — exactamente el tipo de falso positivo que
# hace que un equipo desactive el gate entero.
if ! command -v semgrep >/dev/null 2>&1; then
  {
    echo "⚠️  semgrep no está instalado — los detectores AST no corren."
    echo "   Instálalo:  pip install semgrep   ·   brew install semgrep"
    echo "   Sin él dependes de greps frágiles, que producen falsos positivos"
    echo "   y que un agente aprende a evadir."
  } >&2
  echo "SEMGREP_SUMMARY errors=0 warns=0"
  exit 3          # fallo de INFRAESTRUCTURA: el llamador decide (local avisa, CI bloquea)
fi

[ -d "$RULES_DIR" ] || { echo "SEMGREP_SUMMARY errors=0 warns=0"; exit 0; }

TARGETS=()
if [ "$MODE" = "--staged" ]; then
  while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && TARGETS+=("$f"); done \
    < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
  [ ${#TARGETS[@]} -eq 0 ] && { echo "SEMGREP_SUMMARY errors=0 warns=0"; exit 0; }
fi

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT

# --error hace que semgrep salga !=0 con findings; lo gestionamos nosotros.
# `--no-git-ignore` a propósito (queremos ver archivos no trackeados), pero
# eso NO desactiva `.semgrepignore`, que es donde declaramos las COPIAS del
# proyecto que viven dentro del repo (worktrees del backlog, la copia
# `_mutated` de muter). Sin ese archivo, los avisos de PartialParsing salían
# mezclados con código ajeno al cambio — y un aviso ruidoso se deja de leer.
semgrep scan \
  --config "$RULES_DIR" \
  --json --quiet --no-git-ignore \
  --metrics=off \
  ${TARGETS[0]+"${TARGETS[@]}"} \
  > "$OUT" 2>/dev/null || true

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq ausente: no puedo parsear la salida de semgrep." >&2
  echo "SEMGREP_SUMMARY errors=0 warns=0"
  exit 3          # fallo de INFRAESTRUCTURA
fi

# ── Una herramienta que REVIENTA no puede parecer un repo limpio ────
# Si semgrep muere antes de escribir JSON (OOM, flag inválido, binario roto),
# `$OUT` queda vacío y TODOS los `jq` caen a su fallback `0`: el resultado es
# indistinguible de "todo limpio". Es la variante más severa del mismo fallo
# que el de las reglas rotas — no es "una regla no carga", es "la herramienta
# no corrió". Se valida el JSON ANTES de confiar en cualquier conteo derivado.
if ! jq -e . "$OUT" >/dev/null 2>&1; then
  {
    echo "❌ semgrep: no produjo JSON válido — el detector NO corrió."
    echo "   Causas típicas: crash (OOM), flag inválido, binario corrupto."
    echo "   Salida cruda (primeras líneas):"
    head -5 "$OUT" 2>/dev/null | sed 's/^/     /'
    echo "   Un scan que no se ejecutó NO es un scan sin hallazgos."
  } >&2
  echo "SEMGREP_SUMMARY errors=0 warns=0"
  exit 3          # fallo de INFRAESTRUCTURA, no hallazgo de código
fi

# ── Una regla ROTA no puede parecer un repo limpio ──────────────────
# `semgrep scan --json` reporta los fallos de carga/parseo de reglas en la clave
# top-level `.errors[]`, NO en `.results[]`. Si solo se lee `.results[]`, una
# regla inválida produce `errors=0 warns=0` — indistinguible de "todo bien".
# Es el modo de fallo G5 (gate anunciado y mudo) en su versión peor: silencioso
# incluso con la herramienta instalada. Lo cazó el `reviewer` revisando P1.

# MATIZ que costó una adopción real (Pelis, iOS) y que YA SE PERDIÓ UNA VEZ al
# traer este archivo del template: `.errors[]` mezcla DOS cosas muy distintas,
# y tratarlas igual rompe el gate en el sentido contrario — lo declara MUDO
# para siempre en proyectos sanos:
#
#   a) fallo de CARGA de reglas    → level:"error"       → el detector no puede mirar (exit 3)
#   b) PartialParsing de un FUENTE → level:"warn"+path   → semgrep sí corrió; no
#      supo parsear un trozo de UN archivo (las MACROS LIBRES de Swift —
#      #Preview, #Predicate— que su gramática aún no soporta).
#
# (b) NO es "el detector está roto": es "esa porción no se escaneó". Merece
# aviso visible —código no parseado es código no escaneado— pero NO puede
# tumbar el gate entero, o ningún proyecto SwiftUI tendría nivel 2 operativo.
# Lo fija test_las_reglas_de_semgrep_cargan: si esto se revierte, falla.
RULE_ERRORS="$(jq '[.errors[]? | select((.level // "error") == "error")] | length' "$OUT" 2>/dev/null || echo 0)"
PARSE_WARNS="$(jq '[.errors[]? | select((.level // "error") != "error")] | length' "$OUT" 2>/dev/null || echo 0)"

if [ "${PARSE_WARNS:-0}" -gt 0 ]; then
  {
    echo "⚠️  semgrep: $PARSE_WARNS trozo(s) de fuente que NO se pudieron parsear."
    echo "   Semgrep corrió, pero esas porciones NO fueron escaneadas:"
    jq -r '.errors[]? | select((.level // "error") != "error")
           | "   · " + ((.path // "?") | tostring) + " — "
             + ((.message // "?") | gsub("\n"; " ") | .[0:140])' "$OUT" 2>/dev/null
    echo "   En Swift suele ser una macro libre (#Preview). Convención del proyecto:"
    echo "   #Preview SIEMPRE al final del archivo, para que lo no-parseado sea"
    echo "   solo el preview y nunca código de producto (f-2cc1e4c1)."
  } >&2
fi

if [ "${RULE_ERRORS:-0}" -gt 0 ]; then
  {
    echo "❌ semgrep: $RULE_ERRORS error(es) CARGANDO las reglas — el detector está MUDO."
    jq -r '.errors[]? | select((.level // "error") == "error")
           | "   · " + ((.message // .type // "?") | gsub("\n"; " ") | .[0:200])' "$OUT" 2>/dev/null
    echo "   Valídalas:  semgrep --validate --config $RULES_DIR"
    echo "   Un gate que no puede cargar sus reglas NO es un gate que no encuentra nada."
  } >&2
  # Contrato de stdout intacto (stderr no contamina el conteo del trinquete, G2).
  # exit 3 = fallo del DETECTOR, no del código: en local avisa (si no, un typo
  # en las reglas bloquearía hasta el commit que lo arregla), en CI bloquea.
  echo "SEMGREP_SUMMARY errors=0 warns=0"
  exit 3
fi

ERRORS="$(jq '[.results[] | select(.extra.severity == "ERROR")] | length' "$OUT" 2>/dev/null || echo 0)"
WARNS="$(jq  '[.results[] | select(.extra.severity != "ERROR")] | length' "$OUT" 2>/dev/null || echo 0)"

jq -r '.results[] |
  ((if .extra.severity == "ERROR" then "❌" else "⚠️ " end)
   + " " + .path + ":" + (.start.line|tostring)
   + " [" + .check_id + "] " + (.extra.message | gsub("\n"; " ") | .[0:160]))' \
  "$OUT" 2>/dev/null || true

echo "SEMGREP_SUMMARY errors=${ERRORS:-0} warns=${WARNS:-0}"
[ "${ERRORS:-0}" -gt 0 ] && exit 1
exit 0
