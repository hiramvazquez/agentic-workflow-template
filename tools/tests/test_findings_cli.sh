#!/usr/bin/env bash
# CLI portable del ledger (findings.sh, shell+python3) + eventos de detección.
#
# Por qué existe: findings.ts exige Deno/Node y esta máquina no los tiene → el
# ledger era INOPERABLE localmente, y por eso 9 findings llevaban días en un
# pending-import.json. Un inventario al que no se puede escribir no es un
# inventario: es un archivo.
#
# Invariante heredado de findings.ts que estos tests fijan: add/import NUNCA
# resucitan un estado terminal (fixed/accepted/wontfix/duplicate).

_fcli_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/findings" "$d/docs/process" "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/tools/findings/findings.sh" "$d/tools/findings/" 2>/dev/null
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh" "$d/scripts/agent-hooks/lib/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_cli() { bash tools/findings/findings.sh "$@"; }

# ── add / list ──────────────────────────────────────────────────────
_case_add_y_list() {
  _cli add --id f-t1 --title "Algo roto" --area "src/x.sh" --severity low --tier auto-fix --source test >/dev/null 2>&1 \
    || { echo "    add falló"; return 1; }
  grep -q '"id": *"f-t1"' tools/findings/ledger.jsonl 2>/dev/null || grep -q '"id":"f-t1"' tools/findings/ledger.jsonl \
    || { echo "    el finding no quedó en el ledger"; return 1; }
  _cli list --status open 2>/dev/null | grep -q "f-t1" || { echo "    list --status open no lo muestra"; return 1; }
}
test_add_escribe_y_list_muestra() { _fcli_sandbox _case_add_y_list; }

_case_add_sin_id_genera_hash() {
  _cli add --title "Sin id" --area "a/b" --source test >/dev/null 2>&1
  grep -q '"id": *"f-' tools/findings/ledger.jsonl || grep -q '"id":"f-' tools/findings/ledger.jsonl \
    || { echo "    no generó id con prefijo f-"; return 1; }
}
test_add_sin_id_genera_uno() { _fcli_sandbox _case_add_sin_id_genera_hash; }

# ── close ───────────────────────────────────────────────────────────
_case_close() {
  _cli add --id f-t2 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t2 --resolution "arreglado en test" >/dev/null 2>&1 || { echo "    close falló"; return 1; }
  grep -q '"status": *"fixed"' tools/findings/ledger.jsonl || grep -q '"status":"fixed"' tools/findings/ledger.jsonl \
    || { echo "    close no marcó fixed"; return 1; }
  _cli list --status open 2>/dev/null | grep -q "f-t2" && { echo "    sigue apareciendo como open"; return 1; }
  return 0
}
test_close_marca_fixed() { _fcli_sandbox _case_close; }

# ── EL INVARIANTE: un estado terminal no resucita ───────────────────
_case_terminal_no_resucita() {
  _cli add --id f-t3 --title "Ya resuelto" --area x --source test >/dev/null 2>&1
  _cli close f-t3 --resolution done >/dev/null 2>&1
  # Un gate lo re-detecta (o un import viejo vuelve a llegar):
  _cli add --id f-t3 --title "Ya resuelto" --area x --source otro-gate >/dev/null 2>&1
  local n_open; n_open="$(_cli list --status open 2>/dev/null | grep -c f-t3 || true)"
  [ "${n_open:-0}" = "0" ] || { echo "    un add RESUCITÓ un finding cerrado"; return 1; }
  grep -q '"status": *"fixed"' tools/findings/ledger.jsonl || grep -q '"status":"fixed"' tools/findings/ledger.jsonl \
    || { echo "    el estado terminal se perdió"; return 1; }
}
test_add_no_resucita_estado_terminal() { _fcli_sandbox _case_terminal_no_resucita; }

# ── import: idempotente ─────────────────────────────────────────────
_case_import_idempotente() {
  cat > batch.json <<'EOF'
[{"id":"f-i1","title":"Uno","area":"a","severity":"low","tier":"owner-decision","status":"open","source":"t","detail":"d","effort":"S","links":[]},
 {"id":"f-i2","title":"Dos","area":"b","severity":"high","tier":"auto-fix","status":"fixed","source":"t","detail":"d","resolution":"ya","effort":"S","links":[]}]
EOF
  _cli import batch.json >/dev/null 2>&1 || { echo "    import falló"; return 1; }
  _cli import batch.json >/dev/null 2>&1
  local total; total="$(wc -l < tools/findings/ledger.jsonl | tr -d ' ')"
  [ "$total" = "2" ] || { echo "    import repetido duplicó entradas (total=$total, esperaba 2)"; return 1; }
  # El que venía fixed se importa fixed (no se abre).
  _cli list --status open 2>/dev/null | grep -q f-i2 && { echo "    un import abrió un finding que venía fixed"; return 1; }
  return 0
}
test_import_es_idempotente_y_respeta_estados() { _fcli_sandbox _case_import_idempotente; }

# ── render: la vista se regenera y avisa de no editarla ─────────────
_case_render() {
  _cli add --id f-t4 --title "Visible" --area x --severity high --tier owner-decision --source test >/dev/null 2>&1
  _cli render >/dev/null 2>&1 || { echo "    render falló"; return 1; }
  [ -f docs/process/findings-ledger.md ] || { echo "    no generó la vista"; return 1; }
  grep -q "f-t4" docs/process/findings-ledger.md || { echo "    la vista no incluye el finding"; return 1; }
  grep -qi "no editar" docs/process/findings-ledger.md || { echo "    la vista no avisa de que es generada"; return 1; }
}
test_render_genera_la_vista() { _fcli_sandbox _case_render; }

# ── eventos de detección (hook_log_detection) ───────────────────────
_case_evento_se_appendea() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PROJECT_ROOT="$(pwd)" hook_log_detection "canon-enforce" "secreto" "src/x.swift" 2 || { echo "    log_detection devolvió error"; return 1; }
  local f=".agents/state/metrics/detections.jsonl"
  [ -f "$f" ] || { echo "    no creó el archivo de eventos"; return 1; }
  grep -q '"source": *"canon-enforce"' "$f" || grep -q '"source":"canon-enforce"' "$f" \
    || { echo "    el evento no registró el source"; return 1; }
}
test_evento_de_deteccion_se_registra() { _fcli_sandbox _case_evento_se_appendea; }

_case_evento_jamas_rompe() {
  # FALSO POSITIVO del peor tipo posible: la TELEMETRÍA rompiendo un GATE.
  # Sin python3 en el PATH, log_detection debe seguir devolviendo 0.
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PATH="/nonexistent" PROJECT_ROOT="$(pwd)" hook_log_detection "x" "y" "z" 1
  [ "$?" = "0" ] || { echo "    la telemetría rota devolvió error (rompería el gate que la llama)"; return 1; }
}
test_telemetria_rota_jamas_rompe_al_gate() { _fcli_sandbox _case_evento_jamas_rompe; }
