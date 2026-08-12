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

_case_review_preserva_stderr_en_green() {
  printf '#!/usr/bin/env bash\necho diagnostico-visible >&2\nprintf "VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: stderr\\n"\n' \
    > review-diagnostic.sh; chmod +x review-diagnostic.sh
  local err
  err="$(FAKE_REVIEW_SCRIPT="$PWD/review-diagnostic.sh" \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" 2>&1 >/dev/null)" || return 1
  assert_contains "$err" diagnostico-visible
}
test_review_green_preserva_diagnosticos_stderr() { _ar_repo _case_review_preserva_stderr_en_green; }

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

_case_timeout_propaga_124() {
  printf '#!/usr/bin/env bash\nsleep 30\n' > slow.sh; chmod +x slow.sh
  local started elapsed rc
  started="$(date +%s)"
  FAKE_RUN_SCRIPT="$PWD/slow.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>&1
  rc=$?; elapsed=$(( $(date +%s) - started ))
  [ "$rc" = 124 ] || { echo "    timeout devolvió $rc, no 124"; return 1; }
  [ "$elapsed" -lt 5 ] || { echo "    timeout tardó ${elapsed}s; el watchdog no cortó a tiempo"; return 1; }
}
test_timeout_corta_y_propaga_exit_124() { _ar_repo _case_timeout_propaga_124; }

_case_review_timeout_propaga_124() {
  printf '#!/usr/bin/env bash\nsleep 30\n' > slow-review.sh; chmod +x slow-review.sh
  FAKE_REVIEW_SCRIPT="$PWD/slow-review.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 1 \
    >/dev/null 2>&1
  [ "$?" = 124 ] || { echo "    timeout de review no propagó 124"; return 1; }
}
test_review_tambien_respeta_timeout() { _ar_repo _case_review_timeout_propaga_124; }

_proceso_sigue_vivo() { kill -0 "$1" 2>/dev/null; }

_espera_proceso_muerto() {
  local pid="$1" i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    _proceso_sigue_vivo "$pid" || return 0
    sleep 0.1
  done
  return 1
}

_case_timeout_mata_descendientes() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > child.pid\nwait\n' \
    > tree.sh; chmod +x tree.sh
  FAKE_RUN_SCRIPT="$PWD/tree.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>&1
  local rc=$? child
  [ "$rc" = 124 ] || { echo "    timeout del árbol devolvió $rc"; return 1; }
  child="$(cat child.pid 2>/dev/null)"
  [ -n "$child" ] || { echo "    el fixture no registró al descendiente"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    quedó vivo el descendiente $child que ignoraba TERM"; return 1;
  }
}
test_timeout_no_deja_descendientes() { _ar_repo _case_timeout_mata_descendientes; }

_case_cancelacion_propaga_y_limpia() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > cancel-child.pid\nwait\n' \
    > cancel-tree.sh; chmod +x cancel-tree.sh
  FAKE_RUN_SCRIPT="$PWD/cancel-tree.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 20 >/dev/null 2>&1 &
  local runner=$! child='' i rc
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s cancel-child.pid ] && { child="$(cat cancel-child.pid)"; break; }
    sleep 0.1
  done
  [ -n "$child" ] || { kill -9 "$runner" 2>/dev/null; echo "    el fixture no arrancó"; return 1; }
  kill -TERM "$runner" 2>/dev/null
  wait "$runner"; rc=$?
  [ "$rc" = 143 ] || { echo "    cancelación devolvió $rc, no 143"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    cancelación dejó vivo al descendiente $child"; return 1;
  }
}
test_cancelacion_propaga_143_y_no_deja_descendientes() { _ar_repo _case_cancelacion_propaga_y_limpia; }

_case_cancelacion_review_propaga_y_limpia() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > review-cancel-child.pid\nwait\n' \
    > cancel-review-tree.sh; chmod +x cancel-review-tree.sh
  FAKE_REVIEW_SCRIPT="$PWD/cancel-review-tree.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 20 \
    >/dev/null 2>&1 &
  local runner=$! child='' i rc
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s review-cancel-child.pid ] && { child="$(cat review-cancel-child.pid)"; break; }
    sleep 0.1
  done
  [ -n "$child" ] || { kill -9 "$runner" 2>/dev/null; echo "    el fixture review no arrancó"; return 1; }
  kill -TERM "$runner" 2>/dev/null
  wait "$runner"; rc=$?
  [ "$rc" = 143 ] || { echo "    cancelación review devolvió $rc, no 143"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    cancelación review dejó vivo al descendiente $child"; return 1;
  }
}
test_cancelacion_review_propaga_143_y_no_deja_descendientes() {
  _ar_repo _case_cancelacion_review_propaga_y_limpia
}

_case_flag_truncado() {
  bash tools/agent-runner.sh run --backend >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_flag_sin_valor_es_error_de_contrato() { _ar_repo _case_flag_truncado; }

_case_timeout_invalido() {
  bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD" \
    --timeout nunca >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_timeout_invalido_es_error_de_contrato() { _ar_repo _case_timeout_invalido; }

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
