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
# Lib resuelto desde la UBICACION del script, antes del `cd` (leccion f-6b761f06).
_DET_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/detector-run.sh"
# shellcheck source=tools/lib/detector-run.sh
. "$_DET_LIB" 2>/dev/null || true
command -v detector_run_init >/dev/null 2>&1 && detector_run_init semgrep-scan

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

# ⚠️ El corpus de fixtures se filtra AQUÍ, en la lista de targets, y no con
# `.semgrepignore` ni con `--exclude`. Los dos se aplican a las rutas que
# semgrep DESCUBRE; una ruta pasada como target explícito —que es exactamente
# lo que hace este modo— gana a ambos y se escanea igual.
# Lo cazó el hook al commitear el propio corpus: los seis anti-patrones del
# fixture MALO, escritos para ser detectados, bloquearon el commit como si
# fueran código de producto. Y el test que lo cubría comprobaba que la línea
# estuviera en `.semgrepignore` — la declaración, no el efecto.
# El test del corpus invoca `semgrep scan` DIRECTO, así que sigue viéndolos:
# lo que se filtra es el camino por el que el corpus sería deuda del proyecto,
# nunca el camino por el que se verifica.
FIXTURES_DIR="${SEMGREP_FIXTURES:-tools/semgrep/fixtures}"

_staged_targets() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    case "$f" in "$FIXTURES_DIR"/*) continue ;; esac
    printf '%s\n' "$f"
  done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
}

# En los modos que NO son --staged, `TARGETS` queda vacio a proposito y semgrep
# decide el alcance sobre el repo entero. Por eso ahi el registro de ejecucion
# deja `targets:null`: "no lo declare" es la verdad, y poner un numero seria
# inventar la medicion que este registro existe para hacer honesta.
TARGETS=()
if [ "$MODE" = "--staged" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    TARGETS+=("$f")
  done < <(_staged_targets)
  # Antes del corte por lista vacia: un scan sin objetivos tiene que registrarse
  # como targets=0, que es justo el estado que su SUMMARY en cero no distingue.
  command -v detector_targets >/dev/null 2>&1 && detector_targets "${#TARGETS[@]}"
  [ ${#TARGETS[@]} -eq 0 ] && { echo "SEMGREP_SUMMARY errors=0 warns=0"; exit 0; }
fi
TARGET_SNAPSHOT="$(printf '%s\n' "${TARGETS[@]}")"

# Fase 9: optimización transparente y conservadora. Si la caché falta, está
# corrupta o no puede calcular su identidad, el detector REAL corre igual.
# Solo un 0/0 staged se guarda; exits 1/3 y warnings de parseo jamás entran.
CACHE_KEY=""
CACHE_ALLOWED=0
if [ "$MODE" = "--staged" ] && [ -x tools/gate-cache.sh ] \
   && git diff --quiet -- "${TARGETS[@]}"; then
  CACHE_ALLOWED=1
  SEMGREP_BIN="$(command -v semgrep 2>/dev/null || true)"
  CACHE_KEY="$(bash tools/gate-cache.sh key semgrep-staged "$RULES_DIR" "$SEMGREP_BIN" "${TARGETS[@]}" 2>/dev/null)" || CACHE_KEY=""
  if [ -n "$CACHE_KEY" ]; then
    CACHED="$(bash tools/gate-cache.sh get "$CACHE_KEY" 2>/dev/null)"; CACHE_RC=$?
    if [ "$CACHE_RC" = "0" ]; then
      CURRENT_KEY="$(bash tools/gate-cache.sh key semgrep-staged "$RULES_DIR" "$SEMGREP_BIN" "${TARGETS[@]}" 2>/dev/null)" || CURRENT_KEY=""
      if [ "$CURRENT_KEY" = "$CACHE_KEY" ] && git diff --quiet -- "${TARGETS[@]}" \
         && [ "$(_staged_targets)" = "$TARGET_SNAPSHOT" ]; then
        printf '%s\n' "$CACHED"
        exit 0
      fi
    fi
  fi
fi

# Un proveedor consultado durante la identidad puede mutar el índice. El scan
# real debe recibir la lista posterior, y esa mutación invalida la publicación.
CURRENT_TARGET_SNAPSHOT="$(_staged_targets)"
if [ "$MODE" = "--staged" ] && [ "$CURRENT_TARGET_SNAPSHOT" != "$TARGET_SNAPSHOT" ]; then
  TARGETS=()
  while IFS= read -r f; do [ -n "$f" ] && TARGETS+=("$f"); done <<< "$CURRENT_TARGET_SNAPSHOT"
  command -v detector_targets >/dev/null 2>&1 && detector_targets "${#TARGETS[@]}"
  TARGET_SNAPSHOT="$CURRENT_TARGET_SNAPSHOT"
  CACHE_ALLOWED=0
  CACHE_KEY=""
fi

OUT="$(mktemp)"
# La limpieza se REGISTRA en vez de instalar un `trap ... EXIT` propio: ese trap
# pisaba el del registro de ejecucion y dejaba mudo a este detector. El
# fallback conserva el comportamiento exacto si el lib no esta.
if command -v detector_run_cleanup >/dev/null 2>&1; then
  detector_run_cleanup 'rm -f "$OUT"'
else
  trap 'rm -f "$OUT"' EXIT
fi

# --error hace que semgrep salga !=0 con findings; lo gestionamos nosotros.
# `--no-git-ignore` a propósito (queremos ver archivos no trackeados), pero
# eso NO desactiva `.semgrepignore`, que es donde declaramos las COPIAS del
# proyecto que viven dentro del repo (worktrees del backlog, la copia
# `_mutated` de muter). Sin ese archivo, los avisos de PartialParsing salían
# mezclados con código ajeno al cambio — y un aviso ruidoso se deja de leer.
# El `--exclude` cubre el modo de descubrimiento (--all); el filtro de targets
# de arriba cubre --staged. Hacen falta los dos porque semgrep decide distinto
# según de dónde venga la ruta.
# ── Watchdog: un scan que se cuelga NO puede llevarse el turno ───────
# Pasó de verdad: la telemetría del 2026-09-04 tiene una corrida de 936 s con
# exit=143 (SIGTERM). Quince minutos y medio colgada, matada desde fuera, y sin
# que nadie se enterara — el único rastro era esa línea del log. Ese incidente
# solo es el 44% del coste que la ventana de valor atribuía a este gate.
#
# La cabecera de arriba ya defiende del cuelgue del version-check; el scan en sí
# no tenía esa defensa, y es el mismo modo de fallo. Un cuelgue es peor que un
# crash: el crash es rápido y deja rastro; el cuelgue no dice nada mientras se
# come el turno, el pre-commit o el job de CI.
#
# NO se usa `timeout`: macOS no lo trae. El patrón es el mismo perro guardián
# que `tools/tests/run-tests.sh`.
#
# La pareja de limpieza de abajo es ASIMÉTRICA, y el reparto está comprobado con
# mutantes: `pkill -P` es la mitad que hace el trabajo —quitarla mata el test de
# huérfanos— y `kill "$_SG_WD"` es puramente defensiva: quitarla sola no mata
# ningún test, porque al morir su `sleep` la subshell termina por su cuenta.
# Se conserva igual, por un motivo que ningún test alcanza: entre matar al
# `sleep` y matar a su subshell hay una ventana en la que el guardián podría
# despertar y disparar su `kill -9` contra un PID que `wait` ya reaped — y que
# el sistema puede haber reciclado. El orden es el del precedente, esa cautela
# incluida. Lo corrigió la review: la version anterior de este comentario decia
# que ninguna mitad mataba nada, y sobre-representaba la redundancia.
#
# El `>/dev/null 2>&1` del guardián NO es lo que evita que un llamador por
# sustitución —`check-drift.sh` hace `< <(bash tools/semgrep-scan.sh)`— se
# quede esperando: aquí el guardián siempre muere antes de que el script
# retorne, así que su mutante sobrevive. Se deja porque cuesta cero y cubre el
# orden que `run-tests.sh` sí sufrió, pero es seguro barato, no el mecanismo.
#
# El default es holgado a propósito: la corrida legítima más lenta observada en
# la ventana fue de 11 s. 120 s no recorta ningún scan real, solo corta cuelgues.
SEMGREP_TIMEOUT_SECS="${SEMGREP_TIMEOUT_SECS:-120}"
# Un plazo que no sea un numero de segundos hace que `sleep` falle AL INSTANTE,
# el guardian pasa directo a su `kill -9`, y el scan real muere sin haber tenido
# ninguna oportunidad — reportado como TIMEOUT. Falla del lado seguro (exit 3,
# nunca "limpio"), pero la razon seria FALSA: culparia a un cuelgue que no
# ocurrio en vez de senalar el typo. Y "el hueco se declara con su razon, y esa
# razon tiene que ser VERDADERA" es §14.3, la regla que justifica el mensaje de
# timeout de mas abajo. Lo cazo la review de este mismo cambio, con su repro.
#
# Se AVISA y se sigue con el default en vez de bloquear: un error de config no
# puede trabar al dev (§14.3, primer corolario).
case "$SEMGREP_TIMEOUT_SECS" in
  ''|*[!0-9]*|0)
    echo "⚠️  semgrep: SEMGREP_TIMEOUT_SECS='$SEMGREP_TIMEOUT_SECS' no son segundos; uso 120." >&2
    SEMGREP_TIMEOUT_SECS=120 ;;
esac
semgrep scan \
  --config "$RULES_DIR" \
  --json --quiet --no-git-ignore \
  --metrics=off \
  --exclude="$FIXTURES_DIR" \
  ${TARGETS[0]+"${TARGETS[@]}"} \
  > "$OUT" 2>/dev/null &
_SG_PID=$!
( sleep "$SEMGREP_TIMEOUT_SECS"; kill -9 "$_SG_PID" 2>/dev/null ) >/dev/null 2>&1 &
_SG_WD=$!
wait "$_SG_PID" 2>/dev/null; _SG_RC=$?
pkill -P "$_SG_WD" -x sleep 2>/dev/null   # -x sleep: si el pid se recicló, no matamos a un inocente
kill "$_SG_WD" 2>/dev/null; wait "$_SG_WD" 2>/dev/null

# Muerte por señal (128+n). El guard de JSON vacío de abajo también lo cazaría
# —$OUT queda vacío o a medias— pero culparía a un crash, y la razón del hueco
# tiene que ser VERDADERA (§14.3). Un timeout se declara como timeout.
if [ "${_SG_RC:-0}" -ge 128 ]; then
  {
    echo "❌ semgrep: el scan NO terminó en ${SEMGREP_TIMEOUT_SECS}s — TIMEOUT, el detector no pudo mirar."
    echo "   No es 'sin hallazgos': es un scan que se quedó esperando y lo cortó el watchdog."
    echo "   Sube el margen con SEMGREP_TIMEOUT_SECS=<segundos> si tu repo es grande de verdad,"
    echo "   pero mira antes si semgrep está esperando a la red: esta clase de cuelgue ya"
    echo "   costó una corrida de 936 s el 2026-09-04."
  } >&2
  echo "SEMGREP_SUMMARY errors=0 warns=0"
  exit 3          # fallo de INFRAESTRUCTURA: el llamador decide (local avisa, CI bloquea)
fi

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
# ⚠️ EL `[ ! -s ]` VA PRIMERO Y NO ES REDUNDANTE — es el guard entero.
# `jq -e .` sobre un archivo VACÍO devuelve exit 0 en jq 1.6 y exit 4 en jq 1.7.
# O sea que en jq 1.6 (Ubuntu 22.04, muchos Homebrew) esta protección estaba
# INERTE: un semgrep que revienta dejaba $OUT vacío, jq decía "válido", y el
# scan salía `errors=0 warns=0` con exit 0. Verde sobre un scan que no corrió,
# en unas máquinas sí y en otras no — el peor sabor de bug, porque el test que
# lo cubría pasaba en el portátil de quien lo escribió. Se cazó corriendo la
# suite en OTRA máquina con jq 1.6.
# (La basura no-JSON sí la cazan las dos versiones: 4 y 5. La divergencia es
# exclusivamente el archivo vacío, que es justo el síntoma de "no corrió".)
if [ ! -s "$OUT" ] || ! jq -e . "$OUT" >/dev/null 2>&1; then
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

SUMMARY="SEMGREP_SUMMARY errors=${ERRORS:-0} warns=${WARNS:-0}"
echo "$SUMMARY"
[ "${ERRORS:-0}" -gt 0 ] && exit 1
if [ "$CACHE_ALLOWED" = "1" ] && [ -n "$CACHE_KEY" ] \
   && [ "${WARNS:-0}" = "0" ] && [ "${PARSE_WARNS:-0}" = "0" ]; then
  FINAL_KEY="$(bash tools/gate-cache.sh key semgrep-staged "$RULES_DIR" "$SEMGREP_BIN" "${TARGETS[@]}" 2>/dev/null)" || FINAL_KEY=""
  if [ "$FINAL_KEY" = "$CACHE_KEY" ] && git diff --quiet -- "${TARGETS[@]}" \
     && [ "$(_staged_targets)" = "$TARGET_SNAPSHOT" ]; then
    bash tools/gate-cache.sh put "$CACHE_KEY" "$SUMMARY" >/dev/null 2>&1 || true
  fi
fi
exit 0
