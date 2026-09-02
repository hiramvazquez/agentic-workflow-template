#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# detector-run.sh — cada detector declara que CORRIÓ y contra CUÁNTO
# ════════════════════════════════════════════════════════════════════
# La telemetría del harness guardaba solo DETECCIONES, y solo de los hooks:
# de 507 líneas de detections.jsonl, ni una la escribió un detector. Con eso,
# tres estados producen el mismo cero y ningún dato los separa:
#
#   (a) DISUASIÓN     — corrió, miró objetivos reales, no halló nada.
#   (b) SIN OBJETIVOS — corrió sin nada que mirar. Es f-6b761f06: un
#       `LAYERS_SUMMARY errors=0` desde una raíz sin fuentes, que además
#       alimenta un trinquete que SOLO BAJA — una medición falsa fija el
#       suelo en cero de forma permanente.
#   (c) NO CORRIÓ     — nadie lo invocó.
#
# `gate-value.sh` ya dice honestamente que no distingue (a) y remite al
# selftest; pero el selftest responde "¿ve en un sandbox?", no "¿corrió sobre
# trabajo real y contra cuántos objetivos?". Eso solo lo sabe el detector, y
# por eso el registro se emite DENTRO de él: un caller no puede saber
# `targets`. Esa es toda la tesis de este archivo.
#
# ── Por qué un trap EXIT y no una llamada al final ──────────────────
# Los detectores tienen entre 3 y 14 salidas (`semgrep-scan.sh`: 14), y las
# TEMPRANAS son justamente las del estado (b). Instrumentar "antes del último
# exit" dejaría fuera la ruta que motiva todo esto, y olvidar una de catorce
# es cuestión de tiempo. Un trap EXIT no puede olvidarse ninguna.
#
# ── Invariante nº1: esto JAMÁS puede cambiar el exit del detector ───
# Un gate instrumentado que deja de bloquear es peor que uno sin telemetría.
# El handler captura `$?` primero, hace todo su trabajo con la escritura
# blindada, y devuelve ese mismo código. Lo fijan
# `test_detector_runs.sh::test_la_instrumentacion_no_altera_el_exit_code`,
# `::test_sin_el_lib_el_detector_sigue_funcionando` y
# `::test_un_log_no_escribible_no_rompe_el_detector`.
#
# ── Fichero SEPARADO de detections.jsonl, a propósito ───────────────
# `metrics-report.py` cuenta CADA fila de ese log como detección
# (`gate["detections"] += n`). Mezclar los registros de ejecución inflaría
# métricas que ya se consumen, y obligaría a todo consumidor futuro a
# filtrar para siempre. Son dos cosas distintas y viven en dos ficheros.
#
# Uso, en el detector:
#     . tools/lib/detector-run.sh 2>/dev/null || true
#     detector_run_init check-layers
#     ...
#     detector_targets "$N"     # cuando SEPA cuántos objetivos tiene
#
# JSON a mano, sin jq ni python3, igual que scripts/agent-hooks/lib/io.sh:
# una máquina sin runtime puede perder telemetría, nunca romper el gate.

_DET_NAME=""; _DET_TARGETS="null"; _DET_T0=0; _DET_PREV=""; _DET_CLEANUP=""

# Un detector que necesita limpiar temporales REGISTRA la limpieza aqui en vez
# de instalar su propio `trap ... EXIT`. Motivo medido: `detector_run_init` va
# arriba del todo —tiene que estar, o las salidas tempranas no se registran— y
# un `trap` puesto despues lo PISA sin avisar. Paso de verdad con
# check-source-sets y semgrep-scan: quedaron mudos y sin ningun error visible.
# El guardian mecanico de esta clase es
# test_detector_runs.sh::test_todos_los_detectores_registran_su_ejecucion, que
# recorre los detectores REALES; este helper solo hace que sea facil acertar.
detector_run_cleanup() {
  _DET_CLEANUP="${_DET_CLEANUP:+$_DET_CLEANUP; }${1:-}"
}

# El detector declara cuántos objetivos vio. Mientras no lo llame, `targets`
# queda en `null` — que NO es 0: "no lo declaró" y "miró cero cosas" son
# estados distintos, y confundirlos sería inventar la medición que este
# archivo existe para hacer honesta.
detector_targets() {
  case "${1:-}" in
    ''|*[!0-9]*) _DET_TARGETS="null" ;;
    *) _DET_TARGETS="$1" ;;
  esac
}

_det_escape() { printf '%s' "${1:-}" | tr -d '\000-\037\\"' ; }

_det_on_exit() {
  local rc=$?
  (
    set +e
    local dir log ts commit dur
    log="${DETECTOR_RUNS_LOG:-.agents/state/metrics/runs.jsonl}"
    dir="${log%/*}"
    [ "$dir" = "$log" ] || mkdir -p "$dir" 2>/dev/null || exit 0
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    # `git rev-parse HEAD || echo unknown` NO vale: en un repo SIN COMMITS ese
    # comando imprime "HEAD" en stdout Y sale 128, asi que el `||` anadia su
    # propio texto y el campo quedaba "HEADunknown". La forma correcta —la misma
    # que usa scripts/agent-hooks/lib/io.sh— es ramificar sobre el exit de la
    # sustitucion. Lo cazo test_el_registro_lleva_el_esquema_completo, que
    # existe porque el review probo que nadie miraba este campo.
    if ! commit="$(git rev-parse HEAD 2>/dev/null)" || [ -z "$commit" ]; then
      commit="unknown"
    fi
    dur=$(( SECONDS - _DET_T0 ))
    [ "$dur" -ge 0 ] 2>/dev/null || dur=0
    # `duration_s`, no `duration_ms`: `date +%s%N` no existe en BSD/macOS, así
    # que la resolución real es el segundo. Un campo en ms relleno con ceros
    # sería precisión inventada — el mismo pecado, más pequeño.
    printf '{"schema":1,"kind":"run","ts":"%s","source":"%s","targets":%s,"exit":%s,"duration_s":%s,"commit":"%s"}\n' \
      "$(_det_escape "$ts")" "$(_det_escape "$_DET_NAME")" \
      "$_DET_TARGETS" "$rc" "$dur" "$(_det_escape "$commit")" >> "$log" 2>/dev/null
  ) >/dev/null 2>&1 || true
  # El trap que el detector ya tuviera corre DESPUÉS: dos reales
  # (check-source-sets, semgrep-scan) limpian temporales con él, y pisarlo
  # dejaría basura en cada corrida. Va después y no antes para que la
  # telemetría no dependa de que un trap ajeno termine bien.
  [ -n "$_DET_PREV" ] && { eval "$_DET_PREV" || true; }
  [ -n "$_DET_CLEANUP" ] && { eval "$_DET_CLEANUP" || true; }
  return $rc
}

detector_run_init() {
  _DET_NAME="${1:-desconocido}"
  _DET_T0=$SECONDS
  # Señales: sin esto, un detector MATADO se registraba como `exit:0`.
  # Reproducido en la ronda 1 del review: al morir por una señal no atrapada
  # mientras esperaba un comando en primer plano, bash nunca actualiza `$?` con
  # esa espera interrumpida, así que el trap EXIT leía el 0 del último comando
  # que sí terminó. El llamador veía el 143 correcto —el gating nunca estuvo
  # roto— pero el REGISTRO decía "corrió limpio y no encontró nada", que es
  # exactamente el estado del que este fichero existe para distinguirlo. Un
  # detector abortado por timeout de CI o por un watchdog quedaba indistinguible
  # de uno verde. Atrapar la señal y salir con 128+n hace que el trap EXIT lea
  # el codigo real, y ademas conserva la convencion del shell.
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  local prev
  prev="$(trap -p EXIT 2>/dev/null)"
  if [ -n "$prev" ]; then
    prev="${prev#trap -- }"
    prev="${prev% EXIT}"
    case "$prev" in "'"*"'") prev="${prev#\'}"; prev="${prev%\'}" ;; esac
    _DET_PREV="$prev"
  fi
  trap _det_on_exit EXIT
}
