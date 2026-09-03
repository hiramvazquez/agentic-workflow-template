#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# La SERIE y su resumen semanal: lo que se versiona
# ════════════════════════════════════════════════════════════════════
# PRD 0009 fase 5. La otra mitad de `test_dora.sh`, partida cuando ese fichero
# cruzó el hard limit de 400 líneas (§4) — por la misma junta que el código:
# `dora.py` mide, `dora_rollup.py` agrega.
#
# Lo que se prueba aquí tiene una diferencia de grado con lo de al lado: el
# crudo es local y volátil, pero `docs/process/metrics-weekly.md` **se
# commitea**. Un error aquí no se queda en pantalla, entra en el repositorio —
# y de hecho entró: la tasa de fallo salía medida y sin columna, porque el
# agregador filtraba por tipo y el productor guardaba texto.

_DORA_LIB="$PROJECT_ROOT/tools/tests/lib/dora-sandbox.sh"
# shellcheck source=/dev/null
. "$_DORA_LIB"

# ── 4. La serie es append-only ──────────────────────────────────────
# Es lo que la convierte en serie y no en foto. Si una corrida pisa a la
# anterior, no hay histórico que comparar.
_case_serie_append_only() {
  _dora >/dev/null 2>&1
  local n1; n1="$(grep -c . .agents/state/metrics/series.jsonl 2>/dev/null || echo 0)"
  [ "$n1" = "1" ] || { echo "    la primera corrida no dejó UNA fila (dejó $n1)"; return 1; }
  _dora >/dev/null 2>&1
  local n2; n2="$(grep -c . .agents/state/metrics/series.jsonl 2>/dev/null || echo 0)"
  [ "$n2" = "2" ] || { echo "    la segunda corrida no APENDIÓ (filas: $n2, esperaba 2)"; return 1; }
}
test_la_serie_es_append_only() { _dora_sandbox _case_serie_append_only; }

# ── 5. El rollup semanal es idempotente ─────────────────────────────
# Decisión del owner (OQ-2): el crudo local, el resumen semanal commiteado. Si
# correrlo dos veces duplica la semana, el fichero commiteado se llena de ruido
# y acaba ignorado — que es como mueren estos ficheros.
_case_rollup_idempotente() {
  _dora >/dev/null 2>&1
  bash tools/metrics/dora.sh --rollup >/dev/null 2>&1
  local h1; h1="$(shasum docs/process/metrics-weekly.md 2>/dev/null | awk '{print $1}')"
  bash tools/metrics/dora.sh --rollup >/dev/null 2>&1
  local h2; h2="$(shasum docs/process/metrics-weekly.md 2>/dev/null | awk '{print $1}')"
  [ -n "$h1" ] || { echo "    --rollup no generó docs/process/metrics-weekly.md"; return 1; }
  [ "$h1" = "$h2" ] || {
    echo "    correr --rollup dos veces cambia el fichero: duplica la semana."
    echo "    Un fichero commiteado que crece con ruido acaba ignorado."
    return 1; }
}
test_el_rollup_semanal_es_idempotente() { _dora_sandbox _case_rollup_idempotente; }

# ── 7. Las columnas del rollup salen de los datos ───────────────────
# Si la lista de columnas se escribe a mano, renombrar una métrica no rompe
# nada: solo deja su columna en n/a para siempre. Un hueco que parece legítimo
# es el drift más caro que hay.
_case_columnas_derivadas() {
  mkdir -p .agents/state/metrics
  printf '{"ts":"2026-09-01T10:00:00Z","kind":"dora","metricas":{"metrica bautizada hoy":4.2}}\n' \
    > .agents/state/metrics/series.jsonl
  bash tools/metrics/dora.sh --rollup >/dev/null 2>&1
  grep -q 'metrica bautizada hoy' docs/process/metrics-weekly.md 2>/dev/null || {
    echo "    el rollup ignoró una métrica que SÍ está en la serie:"
    sed -n '10,20p' docs/process/metrics-weekly.md 2>/dev/null | sed 's/^/      /'
    echo "    Con la lista de columnas a mano, renombrar una métrica la esconde."
    return 1; }
  grep -q '4.2' docs/process/metrics-weekly.md || {
    echo "    salió la columna pero no su valor"; return 1; }
}
test_las_columnas_del_rollup_salen_de_los_datos() { _dora_sandbox _case_columnas_derivadas; }

# ── 8. Todo lo MEDIDO llega al rollup ───────────────────────────────
# El rollup solo agrega números, así que una métrica medida pero guardada como
# cadena desaparece de la tabla commiteada — y desaparece EXACTAMENTE igual que
# una que no se pudo medir. Es el mismo hueco silencioso de la columna a mano,
# reapareciendo por el tipo del valor. Pasó de verdad: la tasa de fallo salía
# "0%" en pantalla y no tenía columna en el fichero versionado.
_case_medido_llega_al_rollup() {
  cat > tools/metrics/escape-rate.sh <<'FAKE'
#!/usr/bin/env bash
echo "ESCAPE RATE: 7% (3/41 findings clasificados)"
FAKE
  chmod +x tools/metrics/escape-rate.sh
  _dora >/dev/null 2>&1
  local medidas; medidas="$(python3 -c "
import json,sys
fila=json.loads(open('.agents/state/metrics/series.jsonl').read().splitlines()[0])
malas=[k for k,v in fila['metricas'].items() if v is not None and not isinstance(v,(int,float))]
print(' '.join(malas))")"
  [ -z "$medidas" ] || {
    echo "    métricas medidas que NO son numéricas: $medidas"
    echo "    El rollup solo agrega números: estas desaparecen de la tabla"
    echo "    commiteada igual que si no se hubieran podido medir."
    return 1; }
  bash tools/metrics/dora.sh --rollup >/dev/null 2>&1
  grep -q 'tasa de fallo' docs/process/metrics-weekly.md || {
    echo "    'tasa de fallo' está medida pero no tiene columna en el rollup"
    return 1; }
}
test_todo_lo_medido_llega_al_rollup() { _dora_sandbox _case_medido_llega_al_rollup; }

# ── 13. Y el rollup declara la fila que no pudo datar ───────────────
# Aquí el descarte llega al fichero VERSIONADO: una fila con `ts` ilegible se
# caía de la agregación y el commiteado no lo decía.
_case_rollup_declara_descartes() {
  mkdir -p .agents/state/metrics
  { printf '{"ts":"2026-09-01T10:00:00Z","kind":"dora","metricas":{"m":1}}\n'
    printf '{"ts":"el martes","kind":"dora","metricas":{"m":9}}\n'
  } > .agents/state/metrics/series.jsonl
  local out; out="$(bash tools/metrics/dora.sh --rollup 2>&1)"
  printf '%s' "$out" | grep -q '1 fila' || {
    echo "    el rollup se comió una fila sin decirlo: $out"; return 1; }
  grep -qi 'sin datar\|descartada' docs/process/metrics-weekly.md || {
    echo "    el fichero VERSIONADO no declara la fila descartada"; return 1; }
}
test_el_rollup_declara_lo_que_no_pudo_datar() { _dora_sandbox _case_rollup_declara_descartes; }
