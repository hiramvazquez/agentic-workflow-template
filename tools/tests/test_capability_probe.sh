#!/usr/bin/env bash
# Probes funcionales: presente no equivale a operativo.

_probe_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/tools/semgrep/fixtures" "$d/bin"
  [ -f "$PROJECT_ROOT/tools/probe-capability.sh" ] && cp "$PROJECT_ROOT/tools/probe-capability.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  printf 'rules: []\n' > "$d/tools/semgrep/rules/dummy.yaml"
  printf 'print("fixture")\n' > "$d/tools/semgrep/fixtures/python-malo.py"
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    PATH="$d/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_json_status() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'; }

_case_missing() {
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    missing salió $rc: $out"; return 1; }
  assert_eq "missing" "$(_json_status "$out")"
}
test_binario_ausente_es_missing_no_operational() { _probe_sandbox _case_missing; }

_case_broken_x509() {
  stub bin/semgrep '#!/usr/bin/env bash\necho "X509: NO_CERTIFICATE_OR_CRL_FOUND" >&2\nexit 1\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    broken salió $rc: $out"; return 1; }
  assert_eq "broken" "$(_json_status "$out")" || return 1
  assert_contains "$out" 'X509'
}
test_binario_presente_que_crashea_es_broken_con_diagnostico() { _probe_sandbox _case_broken_x509; }

_case_operational() {
  # FALSO POSITIVO: la salud se prueba con un fixture malo; no se infiere de
  # `command -v`, de `--version` ni de una salida limpia sobre input vacío.
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''{"results":[{"path":"x","start":{"line":1},"check_id":"probe","extra":{"severity":"ERROR","message":"ok"}}],"errors":[]}\n'\''\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "0" ] || { echo "    operational salió $rc: $out"; return 1; }
  assert_eq "operational" "$(_json_status "$out")" || return 1
  printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["commit"]
assert d["platform"]
assert d["checked_at"].endswith("Z")
' >/dev/null
}
test_probe_que_ve_fixture_es_operational() { _probe_sandbox _case_operational; }

_case_unknown() {
  local out rc
  out="$(bash tools/probe-capability.sh desconocida 2>/dev/null)"; rc=$?
  [ "$rc" = "3" ] || { echo "    capability desconocida salió $rc: $out"; return 1; }
  assert_eq "unknown" "$(_json_status "$out")"
}
test_capability_desconocida_es_clasificador_incapaz_exit3() { _probe_sandbox _case_unknown; }

_case_json_seguro() {
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''crash "con comillas"\ny salto\n'\'' >&2\nexit 2\n'
  local out
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)" || true
  printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null
}
test_diagnostico_multilinea_sigue_siendo_json_valido() { _probe_sandbox _case_json_seguro; }
