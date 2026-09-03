#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El lector del DENOMINADOR: qué miró cada detector, y qué no
# ════════════════════════════════════════════════════════════════════
# PRD 0008 fase 1. Los siete detectores escriben `runs.jsonl` desde el
# 2026-09-02 con `targets` y `exit` por ejecución, y hasta ahora no lo leía
# nadie: "detectar no basta, CERRAR" (§1.1) incumplido por el propio harness.
#
# Sin denominador, "cero detecciones" significa tres cosas que ningún dato
# separa: disuasión (miró objetivos reales y no halló nada), sin objetivos
# (corrió sin nada que mirar) y no corrió. La primera es un éxito; la segunda
# alimenta un trinquete que SOLO BAJA con una medición falsa (f-6b761f06).
#
# LO QUE ESTE LECTOR NO HACE, y está declarado en el PRD: la columna de
# "disparos" NO sale de un JOIN con detections.jsonl, porque hoy los
# vocabularios de `source` son disjuntos — ese log solo lo escriben los hooks.
# La línea se DERIVA contando, y si el conteo es 0 lo dice CON el conteo: si un
# día un detector empieza a emitir detecciones, el informe deja de decir n/a
# solo. Escribir "n/a" a mano lo dejaría mintiendo para siempre.

_dr_sandbox() { # <función> — repo con el lector y un runs.jsonl controlado
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/tools/metrics/detector-runs.sh" "$d/tools/metrics/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/metrics/detector_runs.py" "$d/tools/metrics/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/metrics/read-events.py"   "$d/tools/metrics/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_dr_run() { # <source> <targets|null> <exit>
  printf '{"schema":1,"kind":"run","ts":"2026-09-03T10:00:00Z","source":"%s","targets":%s,"exit":%s,"duration_s":1,"commit":"abc"}\n' \
    "$1" "$2" "$3" >> .agents/state/metrics/runs.jsonl
}
_dr_leer() { bash tools/metrics/detector-runs.sh 2>&1; }

# ── 1. Distingue "miró 140" de "no miró nada" ───────────────────────
# El golden del PRD. Los dos salen exit 0 y con su SUMMARY en cero; lo único
# que los separa es el denominador.
_case_distingue_los_dos_ceros() {
  for _ in 1 2 3 4 5; do _dr_run check-layers 0 0; done
  for _ in 1 2 3;       do _dr_run check-exec-bits 140 0; done
  local out; out="$(_dr_leer)"
  printf '%s' "$out" | grep -q 'check-layers' || { echo "    no listó check-layers"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q '140' || { echo "    no reportó los 140 objetivos de check-exec-bits"; return 1; }
  # Y lo que de verdad importa: el que no miró nada tiene que estar SEÑALADO,
  # no solo listado con un 0 que se lee igual que "limpio".
  printf '%s' "$out" | grep -qi 'cero objetivos\|sin objetivos' || {
    echo "    5 corridas con CERO objetivos aparecen como una fila más:"
    printf '%s\n' "$out" | sed 's/^/      /'
    echo "    Sin señalarlo, ese 0 se lee igual que 'miré y está limpio' — que es"
    echo "    exactamente la ambigüedad que este lector existe para matar."
    return 1; }
}
test_distingue_mirar_cero_de_mirar_muchos() { _dr_sandbox _case_distingue_los_dos_ceros; }

# ── 2. Ausente o corrupto → exit 3, y lo DICE (§14.3) ───────────────
# "No pude mirar" no es "miré y está limpio". Un informe que sale 0 con la tabla
# en ceros porque el log no existe es el pecado que este harness persigue.
_case_no_pude_mirar() {
  local out rc
  out="$(_dr_leer)"; rc=$?
  [ "$rc" = "3" ] || { echo "    con runs.jsonl AUSENTE salió $rc (esperaba 3)"; return 1; }
  printf '%s' "$out" | grep -qi 'no pude mirar\|ausente\|no existe' || {
    echo "    salió 3 pero sin explicar por qué: [$out]"; return 1; }
  printf 'esto no es json\n' > .agents/state/metrics/runs.jsonl
  out="$(_dr_leer)"; rc=$?
  [ "$rc" = "3" ] || { echo "    con runs.jsonl CORRUPTO salió $rc (esperaba 3)"; return 1; }
}
test_ausente_o_corrupto_sale_3_y_lo_declara() { _dr_sandbox _case_no_pude_mirar; }

# ── 3. `targets: null` NO es 0 ──────────────────────────────────────
# "No lo declaró" y "declaró que miró cero" son estados distintos. Colapsarlos
# reintroduce la ambigüedad que el campo existe para eliminar — semgrep-scan
# deja null a propósito en los modos donde el alcance lo decide semgrep.
_case_null_no_es_cero() {
  _dr_run semgrep-scan null 0
  _dr_run semgrep-scan null 1
  # El caso MIXTO es el que de verdad separa los dos estados, y es real:
  # semgrep-scan declara un número en --staged y `null` en los modos donde el
  # alcance lo decide semgrep. Sin esta corrida, un mutante que trate `null`
  # como número cualquiera SOBREVIVE, porque con solo nulls el resultado es
  # idéntico — lo demostró un mutante dirigido (`if False:` en la rama del null).
  # El ORDEN importa: con el null primero, un mutante que ignore la rama del
  # null da el mismo resultado (la asignación tolera el None) y sobrevive. Con
  # el NÚMERO primero, ese mutante intenta comparar 7 con None. Lo descubrí
  # lanzándolo: la primera versión de este caso lo dejaba vivo.
  _dr_run check-drift 7 0
  _dr_run check-drift null 0
  local out; out="$(_dr_leer)"
  printf '%s' "$out" | grep -E '^\s*check-drift' | grep -q '7' || {
    echo "    un detector con una corrida SIN declarar y otra con 7 objetivos no"
    echo "    reporta el 7 — el null se está tragando la medición real:"
    printf '%s\n' "$out" | grep check-drift | sed 's/^/      /'
    return 1; }
  # …y la corrida sin declarar tiene que APARECER como tal. Es la segunda
  # huella observable de tratar el null como un número cualquiera: si se
  # colapsan, esta nota desaparece sin que la tabla cambie.
  printf '%s' "$out" | grep -A2 -i 'sin declarar' | grep -q 'check-drift' || {
    echo "    check-drift tuvo una corrida SIN declarar objetivos y no aparece en la"
    echo "    nota de 'sin declarar' — los dos estados se están colapsando:"
    printf '%s\n' "$out" | tail -4 | sed 's/^/      /'
    return 1; }
  printf '%s' "$out" | grep -q 'semgrep-scan' || { echo "    no listó semgrep-scan"; return 1; }
  printf '%s' "$out" | grep -qE 'semgrep-scan.*(—|n/a|sin declarar)' || {
    echo "    'targets: null' se muestra como si fuera 0:"
    printf '%s\n' "$out" | grep semgrep | sed 's/^/      /'
    echo "    'no lo declaró' y 'declaró cero' son estados distintos."
    return 1; }
}
test_targets_null_no_se_confunde_con_cero() { _dr_sandbox _case_null_no_es_cero; }

# ── 4. La línea de disparos se DERIVA, con su conteo ────────────────
# Escribir "n/a" a mano dejaría el informe mintiendo el día que un detector
# emita su primera detección. Se cuenta, y el conteo se enseña.
_case_disparos_derivados() {
  _dr_run check-layers 3 0
  local out; out="$(_dr_leer)"
  printf '%s' "$out" | grep -qi 'disparos' || { echo "    no menciona los disparos"; return 1; }
  printf '%s' "$out" | grep -E 'disparos' | grep -qE '\(0 |: 0|0 filas' || {
    echo "    la línea de disparos no enseña el CONTEO del que sale su n/a:"
    printf '%s\n' "$out" | grep -i disparos | sed 's/^/      /'
    echo "    Sin el conteo, es una afirmación escrita a mano que caducará sola."
    return 1; }
}
test_la_linea_de_disparos_se_deriva() { _dr_sandbox _case_disparos_derivados; }

# ── 5. La agregación es el MÁXIMO, no el último valor ───────────────
# Mutante que sobrevivió al review: cambiar `max(...)` por "el último declarado"
# pasaba los cuatro tests, porque ningún fixture tenía DOS números distintos
# para el mismo detector. Y no es teórico: en el log real de este repo
# semgrep-scan declara [10, 5, 5, 2, 5, 10, 7], así que MAX da 10 y "último" da 7.
#
# El máximo es la agregación correcta porque la pregunta que decide
# keep/tune/retire es "¿tuvo ALGUNA VEZ algo que mirar?": un detector que miró
# 145 una vez no es candidato a retirarse aunque las otras 79 corridas fueran
# sobre un árbol vacío.
_case_agrega_por_maximo() {
  _dr_run check-drift 10 0
  _dr_run check-drift 3 0
  local out; out="$(_dr_leer)"
  printf '%s' "$out" | grep -E '^\s*check-drift' | grep -q '10' || {
    echo "    con objetivos [10, 3] el informe no muestra 10 — no está agregando"
    echo "    por máximo, así que un detector que SÍ tuvo objetivos puede aparecer"
    echo "    como candidato a retirarse:"
    printf '%s\n' "$out" | grep check-drift | sed 's/^/      /'
    return 1; }
}
test_agrega_los_objetivos_por_maximo() { _dr_sandbox _case_agrega_por_maximo; }

# ── 6. Un detections.jsonl corrupto se DICE, no se cuenta como cero ──
# La otra rama que el review encontró sin ejercitar: con el log de detecciones
# roto, el informe pasaba de "no pude contarlos" a "n/a (0 filas)" — una
# afirmación FALSA y silenciosa, que es el pecado que este lector combate.
_case_detecciones_corruptas_se_declaran() {
  _dr_run check-layers 5 0
  printf 'esto tampoco es json\n' > .agents/state/metrics/detections.jsonl
  local out; out="$(_dr_leer)"
  printf '%s' "$out" | grep -i 'disparos' | grep -qi 'no pude contarlos\|corrupto' || {
    echo "    con detections.jsonl CORRUPTO la línea de disparos no lo declara:"
    printf '%s\n' "$out" | grep -i disparos | sed 's/^/      /'
    echo "    Decir 'n/a (0 filas)' cuando no se pudo contar es afirmar un cero"
    echo "    que nadie midió."
    return 1; }
}
test_detections_corrupto_se_declara_no_se_cuenta_cero() {
  _dr_sandbox _case_detecciones_corruptas_se_declaran
}

# ── 7. Sin permiso de lectura → exit 3, no un traceback ─────────────
# Tercera forma de "no pude mirar" que el review reprodujo con `chmod 000`: el
# fichero EXISTE (así que no cae en la rama de ausente) y PermissionError es
# OSError, no ValueError — el script escupía un traceback y salía 1,
# incumpliendo el contrato de exit 3 que su propio docstring promete.
_case_sin_permiso_sale_3() {
  _dr_run check-layers 5 0
  chmod 000 .agents/state/metrics/runs.jsonl
  local out rc
  out="$(_dr_leer)"; rc=$?
  chmod 644 .agents/state/metrics/runs.jsonl 2>/dev/null || true
  # root ignora los permisos: si se pudo leer igual, el caso no aplica aquí.
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'check-layers'; then
    echo "    (saltado: este usuario puede leer un fichero con chmod 000)"
    return 0
  fi
  [ "$rc" = "3" ] || {
    echo "    sin permiso de lectura salió $rc (esperaba 3, el contrato de §14.3):"
    printf '%s\n' "$out" | tail -3 | sed 's/^/      /'
    return 1; }
  printf '%s' "$out" | grep -qi 'no pude mirar' || {
    echo "    salió 3 pero sin declararlo"; return 1; }
}
test_sin_permiso_de_lectura_sale_3() { _dr_sandbox _case_sin_permiso_sale_3; }
