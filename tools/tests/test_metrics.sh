#!/usr/bin/env bash
# Eventos son actividad/latencia; findings son defectos durables. Estos tests
# fijan que las dos poblaciones jamás vuelvan a compartir denominador.

_metrics_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics" "$d/tools/findings" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/tools/metrics/read-events.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/metrics-report.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/escape-rate.sh" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/gate-value.sh" "$d/tools/metrics/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

test_reviewer_gate_registra_una_deteccion_y_duracion_en_ms() {
  grep -Fq 'hook_log_detection "reviewer-gate" "budget-warning" "pre-commit" 1 "$(( (GATE_T1 - GATE_T0) * 1000 ))" gate' \
    "$PROJECT_ROOT/scripts/agent-hooks/reviewer-gate.sh" \
    || { echo "    reviewer-gate aún pasa segundos como n en vez de duration_ms"; return 1; }
}

_case_fuente_ausente_no_aprueba_en_vacio() {
  bash tools/metrics/escape-rate.sh --json >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    escape-rate sin ledger no devolvió exit 3"; return 1; }
  bash tools/metrics/gate-value.sh --json >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    gate-value sin fuentes no devolvió exit 3"; return 1; }
}
test_fuente_ausente_es_no_pude_medir_no_reporte_vacio() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics"
  cp "$PROJECT_ROOT/tools/metrics/read-events.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/metrics-report.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/escape-rate.sh" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/gate-value.sh" "$d/tools/metrics/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; _case_fuente_ausente_no_aprueba_en_vacio )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_fuente_corrupta_no_aprueba_en_vacio() {
  printf '%s\n' \
    '{"id":"f-valido","status":"closed","severity":"high","source":"reviewer","createdAt":"2026-08-10T00:00:00Z"}' \
    'not json' > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema_version":2,"event_id":"evt-valido","ts":"2026-08-10T00:00:00Z","source":"reviewer","phase":"phase7","detections":[{"rule":"r1"}],"duration_ms":10}' \
    'not json' > .agents/state/metrics/detections.jsonl
  local out
  out="$(bash tools/metrics/escape-rate.sh --json 2>/dev/null)"; local escape_rc=$?
  [ "$escape_rc" = "3" ] || { echo "    escape-rate corrupto devolvió $escape_rc"; return 1; }
  [ -z "$out" ] || { echo "    escape-rate corrupto emitió JSON de éxito: $out"; return 1; }

  out="$(python3 tools/metrics/read-events.py .agents/state/metrics/detections.jsonl 2>/dev/null)"
  local reader_rc=$?
  [ "$reader_rc" = "3" ] || { echo "    read-events corrupto devolvió $reader_rc"; return 1; }
  [ -z "$out" ] || { echo "    read-events corrupto emitió stream parcial: $out"; return 1; }

  # gate-value debe fallar por cualquiera de sus dos fuentes corruptas.
  : > tools/findings/ledger.jsonl
  out="$(bash tools/metrics/gate-value.sh --json 2>/dev/null)"; local gate_rc=$?
  [ "$gate_rc" = "3" ] || { echo "    gate-value corrupto devolvió $gate_rc"; return 1; }
  [ -z "$out" ] || { echo "    gate-value corrupto emitió JSON de éxito: $out"; return 1; }
}
test_jsonl_corrupto_es_exit3_no_poblacion_cero() {
  _metrics_sandbox _case_fuente_corrupta_no_aprueba_en_vacio
}

_case_lector_normaliza_v1_y_preserva_v2() {
  printf '%s\n' \
    '{"ts":"2026-08-01T00:00:00Z", "source": "semgrep", "rule":"x", "area":"a", "n":2}' \
    '{"schema":2,"event_id":"evt-real","ts":"2026-08-02T00:00:00Z","phase":"review","source":"reviewer","duration_ms":41,"commit":"abc","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  python3 tools/metrics/read-events.py .agents/state/metrics/detections.jsonl > normalized.jsonl || return 1
  python3 - <<'PY'
import json
legacy, current = [json.loads(line) for line in open("normalized.jsonl", encoding="utf-8")]
assert legacy["schema"] == 1 and legacy["event_id"] is None
assert legacy["triage"] == "unknown" and legacy["phase"] == "gate"
assert legacy["duration_ms"] is None and legacy["commit"] is None
assert current["schema"] == 2 and current["event_id"] == "evt-real"
assert current["phase"] == "review" and current["duration_ms"] == 41
PY
}
test_lector_acepta_jsonl_v1_y_v2_y_v1_queda_unknown() {
  _metrics_sandbox _case_lector_normaliza_v1_y_preserva_v2
}

_case_metricas_consumen_stream_mixto() {
  : > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"ts":"2026-08-01T00:00:00Z", "source": "semgrep", "rule":"x", "area":"a", "n":2}' \
    '{"schema":2,"event_id":"evt-real","ts":"2026-08-02T00:00:00Z","phase":"review","source":"reviewer","duration_ms":41,"commit":"abc","triage":"unknown","n":3}' \
    > .agents/state/metrics/detections.jsonl
  local escape gate
  escape="$(bash tools/metrics/escape-rate.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  gate="$(bash tools/metrics/gate-value.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$escape" "$gate" <<'PY'
import json, sys
escape, gate = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert escape["total"] == 0 and escape["findings_total"] == 0
assert gate["events_total"] == 2 and gate["detections_total"] == 5
assert gate["legacy_events"] == 1
assert gate["gates"]["semgrep"]["events"] == 1
assert gate["gates"]["reviewer"]["events"] == 1
PY
}
test_escape_rate_y_gate_value_aceptan_stream_mixto_v1_v2() {
  _metrics_sandbox _case_metricas_consumen_stream_mixto
}

_case_gate_value_stream_vacio() {
  : > .agents/state/metrics/detections.jsonl
  : > tools/findings/ledger.jsonl
  local out
  out="$(METRICS_TODAY=2026-08-12 bash tools/metrics/gate-value.sh --json)" || return 1
  python3 - "$out" <<'PY'
import json, sys
report = json.loads(sys.argv[1])
assert report["events_total"] == 0 and report["detections_total"] == 0
assert report["window"] == {"since":"2026-07-14", "until":"2026-08-12"}
assert report["latency_coverage_pct"] is None
assert report["false_positives"] is None
PY
}
test_gate_value_reporta_cero_una_sola_vez_con_stream_vacio() {
  _metrics_sandbox _case_gate_value_stream_vacio
}

_case_ventana_default_es_utc_no_timezone_del_host() {
  : > .agents/state/metrics/detections.jsonl
  : > tools/findings/ledger.jsonl
  local east west
  east="$(TZ=Pacific/Kiritimati bash tools/metrics/gate-value.sh --json)" || return 1
  west="$(TZ=Etc/GMT+12 bash tools/metrics/gate-value.sh --json)" || return 1
  python3 - "$east" "$west" <<'PY'
import json, sys
east, west = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert east["window"] == west["window"]
PY
}
test_ventana_default_usa_dia_utc_en_cualquier_timezone_del_host() {
  _metrics_sandbox _case_ventana_default_es_utc_no_timezone_del_host
}

_case_escape_rate_cuenta_findings_unicos_en_ventana() {
  printf '%s\n' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    '{"id":"f-human","createdAt":"2026-08-11","status":"open","source":"human-review, semgrep","source_event_ids":[]}' \
    '{"id":"f-unknown","createdAt":"2026-08-12","status":"open","source":"herramienta-propia, semgrep","source_event_ids":[]}' \
    '{"id":"f-old","createdAt":"2026-07-01","status":"fixed","source":"prod","source_event_ids":[]}' \
    > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-untriaged","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":20,"commit":"a","triage":"unknown","n":9}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/escape-rate.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["window"] == {"since":"2026-08-01", "until":"2026-08-31"}
assert r["findings_total"] == 3 and r["classified"] == 2 and r["unknown"] == 1
assert r["total"] == 2 and r["gate"] == 1 and r["human"] == 1
assert r["escaped"] == 1 and r["escape_rate_pct"] == 50 and r["automated_pct"] == 50
PY
}
test_escape_rate_no_suma_eventos_y_cuenta_ids_unicos_en_ventana() {
  _metrics_sandbox _case_escape_rate_cuenta_findings_unicos_en_ventana
}

_case_gate_value_mide_eventos_con_denominadores_honestos() {
  printf '%s\n' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"ts":"2026-08-05T00:00:00Z","source":"semgrep","rule":"legacy","area":"a","n":2}' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":100,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:01Z","phase":"gate","source":"semgrep","duration_ms":999,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-2","ts":"2026-08-11T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":300,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-3","ts":"2026-08-12T00:00:00Z","phase":"review","source":"reviewer","duration_ms":null,"commit":"c","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-old","ts":"2026-07-01T00:00:00Z","phase":"prod","source":"prod","duration_ms":500,"commit":"d","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/gate-value.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["events_total"] == 4 and r["detections_total"] == 5
assert r["legacy_events"] == 1
assert r["promoted_events"] == 1 and r["untriaged_events"] == 3
assert r["false_positives"] is None and r["fp_rate_pct"] is None
assert r["latency_samples"] == 2 and r["latency_coverage_pct"] == 50
s = r["gates"]["semgrep"]
assert s["events"] == 3 and s["detections"] == 4
assert s["promoted"] == 1 and s["untriaged"] == 2
assert s["latency_samples"] == 2 and s["avg_duration_ms"] == 200
assert s["p95_duration_ms"] == 300
review = r["gates"]["reviewer"]
assert review["events"] == 1 and review["latency_samples"] == 0
assert review["avg_duration_ms"] is None
PY
}
test_gate_value_deduplica_event_id_y_no_llama_fp_a_unknown() {
  _metrics_sandbox _case_gate_value_mide_eventos_con_denominadores_honestos
}

_case_gate_value_valida_timestamp_completo() {
  : > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema":2,"event_id":"evt-offset","ts":"2026-08-10T23:30:00-05:00","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-utc","ts":"2026-08-11T04:30:00Z","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-invalid","ts":"2026-08-10NOT-A-TIME","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-number","ts":123,"phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-date-only","ts":"2026-08-10","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-naive","ts":"2026-08-10T12:00:00","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/gate-value.sh --since 2026-08-11 --until 2026-08-11 --json 2>warnings.log)" || return 1
  local warnings
  warnings="$(grep -Fc 'timestamp inválido; se excluye de la métrica' warnings.log || true)"
  [ "$warnings" = "4" ] \
    || { echo "    se esperaban 4 señales de timestamp inválido y hubo $warnings"; return 1; }
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["events_total"] == 2 and r["detections_total"] == 2
assert r["invalid_dates"] == 4
assert r["gates"]["semgrep"]["events"] == 2
PY
}
test_gate_value_valida_timestamp_completo_no_solo_prefijo_fecha() {
  _metrics_sandbox _case_gate_value_valida_timestamp_completo
}
