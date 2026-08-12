#!/usr/bin/env bash
# Contratos separados run/review; el backend fake prueba el boundary sin proveedor.
_ar_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/agent-backends" "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/tools/agent-runner.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/agent-backends/fake.sh" "$d/tools/agent-backends/"
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh" "$d/scripts/agent-hooks/lib/"
  ( cd "$d" && git init -q . && git config user.email t@t.t && git config user.name t \
    && echo seed > seed && git add seed && git commit -qm seed && printf 'prompt\n' > prompt.md && "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_run_opaco() {
  # FALSO POSITIVO: `run` puede imprimir cualquier texto, incluso la palabra
  # VERDICT; solo `review` interpreta ese contrato.
  local out
  out="$(bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD")" \
    || return 1
  assert_eq prompt "$out"
}
test_run_no_interpreta_stdout_como_veredicto() { _ar_repo _case_run_opaco; }

_case_review_green() {
  FAKE_REVIEW_RESULT=$'texto\nVERDICT: GREEN\nFINDINGS: 0\nSCOPE: test' \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" >/dev/null
}
test_review_green_parseable_pasa() { _ar_repo _case_review_green; }

_case_review_sin_veredicto() {
  FAKE_REVIEW_RESULT='todo bien' bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_review_sin_veredicto_falla() { _ar_repo _case_review_sin_veredicto; }

_case_review_incompleta() {
  FAKE_REVIEW_RESULT='VERDICT: GREEN' bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_review_exige_findings_y_scope() { _ar_repo _case_review_incompleta; }

_case_green_con_hallazgos() {
  FAKE_REVIEW_RESULT=$'VERDICT: GREEN\nFINDINGS: 2\nSCOPE: x' \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_green_con_findings_es_contrato_contradictorio() { _ar_repo _case_green_con_hallazgos; }

_case_run_propaga_fallo() {
  printf '#!/usr/bin/env bash\nexit 7\n' > fail.sh; chmod +x fail.sh
  FAKE_RUN_SCRIPT="$PWD/fail.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 7 ]
}
test_run_propaga_exit_del_backend() { _ar_repo _case_run_propaga_fallo; }

_case_flag_truncado() {
  bash tools/agent-runner.sh run --backend >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_flag_sin_valor_es_error_de_contrato() { _ar_repo _case_flag_truncado; }

_case_paths_fuera() {
  bash tools/agent-runner.sh run --backend fake --prompt-file /etc/hosts --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_prompt_fuera_del_repo_se_rechaza() { _ar_repo _case_paths_fuera; }

_case_backend_inyectado() {
  bash tools/agent-runner.sh run --backend '../fake' --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_backend_es_allowlist_no_path() { _ar_repo _case_backend_inyectado; }
