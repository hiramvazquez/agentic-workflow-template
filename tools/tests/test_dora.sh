#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Las seis métricas: las que se pueden medir aquí, y las que NO
# ════════════════════════════════════════════════════════════════════
# PRD 0009 fase 5. Las cuatro DORA más aceptación y retrabajo son la referencia
# de 2026 porque miden RESULTADOS de entrega, no actividad: son difíciles de
# inflar con líneas de código o tasas de aceptación.
#
# Pero el design-review verificó el `git log` real de este repo —0 merges de 149
# commits, cero despliegues— y demostró que tres de las seis definiciones que el
# PRD traía eran inaplicables aquí. Publicar "frecuencia de entrega: 0/semana"
# en un repo que entrega varias veces al día sería el cero ambiguo que todo este
# trabajo existe para matar, reintroducido en la fase que lo mide.
#
# Así que la regla de este informe es la misma que la del lector de detectores:
# **una métrica sin evento definido en ESTE repo sale `n/a` CON su razón**, nunca
# 0. Un cero que nadie midió es peor que un hueco declarado.

_dora_sandbox() { # <función>
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools/metrics" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/tools/metrics/dora.sh" "$d/tools/metrics/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/metrics/dora.py" "$d/tools/metrics/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/metrics/read-events.py" "$d/tools/metrics/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > a.txt; git "$A" -A 2>/dev/null; git "$C" -qm "primero" 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_dora_review() { # <verdict> <sha>
  printf '{"ts":"2026-09-01T10:00:00Z","agent":"reviewer","verdict":"%s","staged_sha":"%s"}\n' \
    "$1" "$2" >> .agents/state/review-history.jsonl
}
_dora() { bash tools/metrics/dora.sh 2>&1; }

# ── 1. Lo que no se puede medir sale n/a CON su razón ───────────────
# El corazón del asunto. Sin merges no hay lead time, y el campo `area` del
# ledger es texto libre: no hay join para el retrabajo. Las dos tienen que
# DECIRLO, no dar 0.
_case_lo_no_medible_se_declara() {
  local out; out="$(_dora)"
  local m
  for m in "lead time" "retrabajo"; do
    printf '%s' "$out" | grep -i "$m" | grep -qi 'n/a' || {
      echo "    '$m' no sale como n/a:"
      printf '%s\n' "$out" | grep -i "$m" | sed 's/^/      /'
      echo "    Publicar un 0 aquí sería el cero ambiguo que esto viene a matar."
      return 1; }
    printf '%s' "$out" | grep -i "$m" | grep -qE '—|porque|:' || {
      echo "    '$m' sale n/a pero SIN razón; un hueco sin explicar se lee como un fallo"
      return 1; }
  done
}
test_lo_que_no_se_puede_medir_sale_na_con_razon() {
  _dora_sandbox _case_lo_no_medible_se_declara
}

# ── 2. La aceptación se calcula por UNIDAD, no por fila ─────────────
# 'Verde a la primera' es una propiedad de la unidad de trabajo, no del número
# de veredictos: un cambio revisado tres veces cuenta una vez, y cuenta por su
# PRIMER veredicto.
_case_aceptacion_por_unidad() {
  _dora_review RED   aaa
  _dora_review GREEN aaa   # misma unidad, segunda ronda: NO cuenta como verde
  _dora_review GREEN bbb
  local out; out="$(_dora)"
  printf '%s' "$out" | grep -i 'aceptaci' | grep -q '50' || {
    echo "    con 2 unidades (una RED-luego-GREEN, otra GREEN) la tasa debería ser 50%:"
    printf '%s\n' "$out" | grep -i 'aceptaci' | sed 's/^/      /'
    echo "    Contar filas en vez de unidades premia al que revisa más veces."
    return 1; }
}
test_la_aceptacion_se_cuenta_por_unidad_de_trabajo() {
  _dora_sandbox _case_aceptacion_por_unidad
}

# ── 3. Sin `gh` no se cae: declara y sigue ──────────────────────────
# El tiempo de recuperación necesita el estado de CI, que vive en `gh`, no en
# git. Un adoptante sin `gh` no puede quedarse sin las otras cinco.
_case_sin_gh_no_aborta() {
  mkdir -p bin; printf '#!/usr/bin/env bash\nexit 127\n' > bin/gh; chmod +x bin/gh
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/metrics/dora.sh 2>&1)"; rc=$?
  [ "$rc" != "0" ] && { echo "    sin gh el informe entero abortó (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -i 'recuperaci' | grep -qi 'n/a' || {
    echo "    sin gh, el tiempo de recuperación no se declara n/a:"
    printf '%s\n' "$out" | grep -i 'recuperaci' | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -qi 'frecuencia' || {
    echo "    sin gh se perdieron las métricas que NO dependen de gh"; return 1; }
}
test_sin_gh_declara_y_sigue() { _dora_sandbox _case_sin_gh_no_aborta; }

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

# ── 6. La tasa de fallo ARRASTRA su denominador ─────────────────────
# 0% sobre 41 clasificados de 247 no es 0%. Publicar la tasa desnuda sería el
# cero sin denominador que `detector_runs.py` existe para separar.
_case_denominador() {
  # escape-rate falso: solo tiene que imprimir la línea que dora parsea.
  cat > tools/metrics/escape-rate.sh <<'FAKE'
#!/usr/bin/env bash
echo "ESCAPE RATE: 7% (3/41 findings clasificados)"
FAKE
  chmod +x tools/metrics/escape-rate.sh
  local out; out="$(_dora)"
  local l; l="$(printf '%s\n' "$out" | grep -i 'tasa de fallo')"
  printf '%s' "$l" | grep -q '7' || { echo "    no salió la tasa: $l"; return 1; }
  printf '%s' "$l" | grep -q '41' || {
    echo "    la tasa sale SIN su denominador: $l"
    echo "    '7%' a secas oculta que solo 41 de 247 findings están clasificados."
    return 1; }
}
test_la_tasa_de_fallo_arrastra_su_denominador() { _dora_sandbox _case_denominador; }

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

# ── 9. El rojo de un pipeline NO lo recupera el verde de otro ────────
# Lo cazó el review con el `gh run list` real de este repo: hay tres workflows
# activos, y parear "roja → primera verde posterior" sobre la lista MEZCLADA
# emparejaba un rojo de `gate-0a-macos` con un verde de `harness-ci` 27h
# después. No es una recuperación: es un artefacto de mezclar dos pipelines.
# Y el número contaminado ya se había commiteado en metrics-weekly.md.
#
# El fixture está construido para que las dos lecturas den números DISTINTOS:
#   mezclado → 1.0 h sobre 1 par   ·   por workflow → 4.0 h sobre 3 pares
#
# Y los tres intervalos (1h, 4h, 10h) tienen MEDIANA 4 y MEDIA 5 a propósito:
# el review lanzó `median`→`mean` y sobrevivió porque el fixture anterior las
# hacía coincidir. Un fixture simétrico no distingue estadísticos.
_case_recuperacion_por_workflow() {
  mkdir -p bin
  cat > bin/gh <<'FAKE'
#!/usr/bin/env bash
cat <<'JSON'
[{"conclusion":"failure","updatedAt":"2026-09-01T10:00:00Z","name":"alfa"},
 {"conclusion":"failure","updatedAt":"2026-09-01T10:15:00Z","name":"beta"},
 {"conclusion":"success","updatedAt":"2026-09-01T11:00:00Z","name":"alfa"},
 {"conclusion":"failure","updatedAt":"2026-09-01T10:30:00Z","name":"gamma"},
 {"conclusion":"success","updatedAt":"2026-09-01T14:15:00Z","name":"beta"},
 {"conclusion":"success","updatedAt":"2026-09-01T20:30:00Z","name":"gamma"}]
JSON
FAKE
  chmod +x bin/gh
  local l; l="$(PATH="$PWD/bin:$PATH" bash tools/metrics/dora.sh 2>&1 | grep -i 'recuperaci')"
  printf '%s' "$l" | grep -q '4.0' || {
    echo "    esperaba 4.0 h (alfa 1h, beta 4h, gamma 10h → mediana 4), salió:"
    echo "      $l"
    echo "    1.0 h sobre 1 par = el rojo de beta lo cerró el verde de alfa."
    echo "    5.0 h = se usó la MEDIA, no la mediana: un rojo largo la arrastra."
    return 1; }
  printf '%s' "$l" | grep -q 'de 3' || {
    echo "    esperaba 3 pares, uno por workflow; salió: $l"; return 1; }
}
test_la_recuperacion_no_cruza_workflows() { _dora_sandbox _case_recuperacion_por_workflow; }
