#!/usr/bin/env bash
# git-guard (reviewer-gate §0): la garantía DURA de las prohibiciones de flags
# de AGENTS.md §7. El Anillo 0 (permissions.deny con comodín intermedio) no
# está garantizado por la sintaxis documentada — el guard sí ve el comando
# completo. Estos tests fijan: bloqueos duros en AMBOS presets, la protección
# del sha staged (add+commit / -am), y los falsos positivos que NO deben pasar
# (texto que solo MENCIONA un comando prohibido).

_gg_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT"/tools/*.sh "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT"/tools/*.json "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    # Detectores en verde para aislar el guard del resto del gate.
    stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
    stub tools/check-layers.sh '#!/usr/bin/env bash\nexit 0\n'
    rm -f tools/semgrep-scan.sh tools/check-review-marker.sh 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_gate() { # _gate <preset> <comando> → exit code del hook
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"}}" \
    | WORKFLOW_PRESET="$2" bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

_case_no_verify_bloqueado_en_lite() {
  local rc; rc="$(_gate 'git commit --no-verify -m x' lite)"
  [ "$rc" = "2" ] || { echo "    --no-verify pasó en lite (exit $rc) — debe ser duro en AMBOS presets"; return 1; }
}
test_no_verify_bloqueado_incluso_en_lite() { _gg_sandbox _case_no_verify_bloqueado_en_lite; }

_case_amend_bloqueado() {
  local rc; rc="$(_gate 'git commit --amend -m x' full)"
  [ "$rc" = "2" ] || { echo "    --amend pasó (exit $rc)"; return 1; }
}
test_amend_bloqueado() { _gg_sandbox _case_amend_bloqueado; }

_case_env_prefijo_sigue_gateado() {
  # REVIEWER_OVERRIDE=1 git commit … es el uso DOCUMENTADO del override: el
  # prefijo VAR=val no puede hacer invisible el commit para el gate.
  local rc; rc="$(_gate 'REVIEWER_OVERRIDE=1 git commit --no-verify -m x' full)"
  [ "$rc" = "2" ] || { echo "    el prefijo VAR=val ocultó el commit al guard (exit $rc)"; return 1; }
}
test_prefijo_de_variables_no_oculta_el_commit() { _gg_sandbox _case_env_prefijo_sigue_gateado; }

_case_add_y_commit_bloqueado_en_full() {
  local rc; rc="$(_gate 'git add -A && git commit -m x' full)"
  [ "$rc" = "2" ] || { echo "    add+commit en una línea pasó en full (exit $rc)"; return 1; }
}
test_add_mas_commit_bloqueado_en_full() { _gg_sandbox _case_add_y_commit_bloqueado_en_full; }

_case_add_y_commit_avisa_en_lite() {
  local rc; rc="$(_gate 'git add -A && git commit -m x' lite)"
  [ "$rc" = "0" ] || { echo "    add+commit bloqueó en lite (exit $rc, esperaba aviso)"; return 1; }
}
test_add_mas_commit_solo_avisa_en_lite() { _gg_sandbox _case_add_y_commit_avisa_en_lite; }

_case_commit_am_bloqueado_en_full() {
  local rc; rc="$(_gate 'git commit -am x' full)"
  [ "$rc" = "2" ] || { echo "    commit -am pasó en full (exit $rc) — stagea implícito y evade el sha"; return 1; }
}
test_commit_am_bloqueado_en_full() { _gg_sandbox _case_commit_am_bloqueado_en_full; }

_case_clean_f_bloqueado() {
  # El hueco de f-3c027a85: clean -f no lo cubría NADIE (el deny era inerte).
  local rc; rc="$(_gate 'git clean -fd' lite)"
  [ "$rc" = "2" ] || { echo "    git clean -fd pasó (exit $rc) — borra untracked sin recuperación"; return 1; }
}
test_clean_f_bloqueado_incluso_en_lite() { _gg_sandbox _case_clean_f_bloqueado; }

_case_clean_n_pasa() {
  # FALSO POSITIVO guard: el dry-run es EL camino recomendado — no puede bloquearse.
  local rc; rc="$(_gate 'git clean -n' full)"
  [ "$rc" = "0" ] || { echo "    git clean -n (dry-run) fue bloqueado (exit $rc)"; return 1; }
}
test_clean_dry_run_pasa() { _gg_sandbox _case_clean_n_pasa; }

# ── FALSOS POSITIVOS (⅓ de la suite, regla test_meta_fp) ────────────
_case_grep_que_menciona_no_verify_pasa() {
  local rc; rc="$(_gate 'grep -r \\"git commit --no-verify\\" docs/' full)"
  [ "$rc" = "0" ] || { echo "    un grep que MENCIONA --no-verify fue bloqueado (exit $rc)"; return 1; }
}
test_mencionar_no_verify_en_otro_comando_pasa() { _gg_sandbox _case_grep_que_menciona_no_verify_pasa; }

_case_comando_no_git_pasa() {
  local rc; rc="$(_gate 'echo git commit --amend es mala idea' full)"
  [ "$rc" = "0" ] || { echo "    un echo inocente fue bloqueado (exit $rc)"; return 1; }
}
test_texto_con_git_commit_en_argumentos_pasa() { _gg_sandbox _case_comando_no_git_pasa; }

_case_commit_normal_no_choca_con_guard() {
  # Un commit limpio y separado no debe tropezar con el guard (los detectores
  # están stubeados en verde y no hay check-review-marker en el sandbox).
  local rc; rc="$(_gate 'git commit -m \\"feat(x): y\\"' lite)"
  [ "$rc" = "0" ] || { echo "    un commit normal fue bloqueado por el guard (exit $rc)"; return 1; }
}
test_commit_normal_pasa_el_guard() { _gg_sandbox _case_commit_normal_no_choca_con_guard; }

# ── El guard que bloquea deja rastro medible (f-2bd11525) ───────────
# El fix de telemetría de la fase 3 instrumentó UNA de las tres primitivas de
# `lib/io.sh`, y la que quedó fuera —`hook_block`— es justo la del git-guard.
# Consecuencia: bloqueaba `--no-verify` a diario y en la ventana de medición
# figuraba con CERO eventos, que es exactamente lo que la fase 3 decía haber
# arreglado. El reviewer lo reprodujo en sandbox; esto lo fija.
#
# Va aquí y no en test_metrics.sh a propósito: allí se prueba la primitiva
# aislada, aquí el hook REAL de punta a punta. El bug vivía en la distancia
# entre ambas cosas.
_case_git_guard_registra_su_bloqueo() {
  local rc; rc="$(_gate 'git commit --no-verify -m x' full)"
  [ "$rc" = "2" ] || { echo "    el guard no bloqueó (exit $rc) — test inválido"; return 1; }
  local ev=".agents/state/metrics/detections.jsonl"
  [ -s "$ev" ] || {
    echo "    el git-guard BLOQUEÓ y no registró nada. Quien mida este gate en"
    echo "    una ventana futura verá cero eventos y lo leerá como 'nadie lo"
    echo "    intentó', cuando bloquea a diario (f-2bd11525)."
    return 1; }
  grep -q '"source":"reviewer-gate"' "$ev" || {
    echo "    registró el bloqueo pero no como reviewer-gate: sin fuente correcta"
    echo "    gate-value lo atribuye a otro gate."
    sed 's/^/      /' "$ev"; return 1; }
}
test_el_git_guard_registra_cuando_bloquea() { _gg_sandbox _case_git_guard_registra_su_bloqueo; }

_case_bloqueo_de_reset_hard_tambien_se_registra() {
  # `reset --hard` no pasa por el camino de commit: es otro call-site de la
  # misma primitiva. Si la instrumentación hubiera vuelto a ponerse por
  # call-site, este saldría mudo.
  local rc; rc="$(_gate 'git reset --hard HEAD~1' full)"
  [ "$rc" = "2" ] || { echo "    reset --hard no bloqueó (exit $rc) — test inválido"; return 1; }
  grep -q '"source":"reviewer-gate"' ".agents/state/metrics/detections.jsonl" 2>/dev/null || {
    echo "    reset --hard bloqueó sin registrar: la instrumentación cubre unos"
    echo "    call-sites y no otros, que es el bug original con otra cara."
    return 1; }
}
test_reset_hard_bloqueado_tambien_se_registra() { _gg_sandbox _case_bloqueo_de_reset_hard_tambien_se_registra; }

# ════════════════════════════════════════════════════════════════════
# Una CONTINUACIÓN DE LÍNEA no puede partir una prohibición en dos
# ════════════════════════════════════════════════════════════════════
# Bypass reproducido en vivo el 2026-09-02, con marker VÁLIDO y preset full.
# El hook parte el comando con `tr ';&|' '\n'` y lo lee con `read -r seg`, así
# que los saltos de línea del propio comando también separan segmentos. Con una
# continuación de shell, el subcomando queda en un segmento y sus flags en otro,
# y NINGUNO contiene los dos: el guard no ve nada que prohibir.
#
# Medido: el mismo commit con --no-verify daba exit 2 en una línea y exit 0
# —"detectores verdes + marker válido. Commit permitido"— partido en dos. La
# prohibición nº1 de §7 se evadía pulsando Enter, y no hay capa detrás: este
# guard existe porque permissions.deny no puede expresarla (f-3c027a85).
#
# Se probaron dos flags a propósito: el defecto está en el BUCLE, así que
# alcanza a todas las prohibiciones por igual, no solo a la más famosa.
# El sandbox BORRA check-review-marker.sh, asi que sin esto cualquier `git
# commit` devuelve 2 —el hook falla al invocar un script que no esta— y el test
# pasaria sin distinguir el guard del marker. Con el marker en verde, un commit
# permitido sale 0 y solo una prohibicion real saca 2. La asercion de control
# de abajo es la que demuestra que el sandbox sabe decir que si.
_gg_marker_verde() { stub tools/check-review-marker.sh '#!/usr/bin/env bash\nexit 0\n'; }

_case_continuacion_no_parte_no_verify() {
  _gg_marker_verde
  local ctrl; ctrl="$(_gate 'git commit \\\n  -m x' full)"
  [ "$ctrl" = "0" ] || { echo "    control: un commit multilínea LEGÍTIMO fue bloqueado (exit $ctrl) — el sandbox no distingue"; return 1; }
  local rc; rc="$(_gate 'git commit \\\n  --no-verify -m x' full)"
  [ "$rc" = "2" ] || { echo "    --no-verify tras una continuación de línea ATRAVESÓ el guard (exit $rc)"; return 1; }
}
test_una_continuacion_de_linea_no_evade_no_verify() {
  _gg_sandbox _case_continuacion_no_parte_no_verify
}

_case_continuacion_no_parte_amend() {
  _gg_marker_verde
  local rc; rc="$(_gate 'git commit \\\n  --amend -m x' full)"
  [ "$rc" = "2" ] || { echo "    --amend tras una continuación de línea ATRAVESÓ el guard (exit $rc)"; return 1; }
  # El detector de `-a/-am` es OTRO sitio del hook (un grep sobre el comando
  # entero, no el bucle de segmentos) y tenía el mismo punto ciego: grep razona
  # por líneas. Se comprueba aquí para que el arreglo cubra los dos.
  rc="$(_gate 'git commit \\\n  -am x' full)"
  [ "$rc" = "2" ] || { echo "    -am tras una continuación de línea ATRAVESÓ el detector de staging implícito (exit $rc)"; return 1; }
}
test_una_continuacion_de_linea_no_evade_amend() {
  _gg_sandbox _case_continuacion_no_parte_amend
}

# ── FALSO POSITIVO guard: unir continuaciones no puede inventar comandos ──
# Al pegar las líneas, dos segmentos inocentes pasan a ser uno. Si eso hiciera
# aparecer un `git` en posición de comando donde no lo había, el arreglo sería
# peor que el bug: un guard que bloquea comandos legítimos se desactiva entero.
_case_unir_no_inventa_prohibiciones() {
  _gg_marker_verde
  local rc
  rc="$(_gate 'echo "documentando git commit --no-verify" \\\n  >> notas.md' full)"
  [ "$rc" = "0" ] || { echo "    un echo multilínea que MENCIONA el flag fue bloqueado (exit $rc)"; return 1; }
  rc="$(_gate 'ls -la \\\n  tools/' full)"
  [ "$rc" = "0" ] || { echo "    un comando multilínea inocente fue bloqueado (exit $rc)"; return 1; }
}
test_unir_continuaciones_no_inventa_prohibiciones() {
  _gg_sandbox _case_unir_no_inventa_prohibiciones
}
