#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# WF-05 (PRD 0005 §6): la DECLARACIÓN gobierna; la evidencia solo verifica
# ════════════════════════════════════════════════════════════════════
# `tools/project.conf` declara `project_kind: harness|application|other`.
# Estos tests fijan la tabla de exits de §6: quién gobierna el criterio de
# producto, cuándo la contradicción declarado-vs-evidencia AVISA, y que el
# exit 3 ocurre SOLO en CI (CI=true o GATES_*). El caso "sin declarar"
# conserva la heurística vieja byte a byte: cero falsos positivos nuevos
# en los adoptantes existentes (gate de cierre de la fase 1b).

_sk_sandbox() { # _sk_sandbox <función> — repo desechable con lib + consumidores
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/lib" "$d/.agents/state/markers"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$d/tools/lib/"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-verify-marker.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    # Entorno determinista: CI/GATES_* se controlan EXPLÍCITAMENTE por caso
    # (en GitHub Actions CI=true viene puesto y cambiaría el resultado).
    unset CI SCOPE_NO_CI_EXIT 2>/dev/null
    local _v; for _v in $(env | sed -n 's/^\(GATES_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_sk_regex() { ( . tools/lib/scope.sh; scope_non_product ) 2>/dev/null; }
_sk_source_stderr() { ( . tools/lib/scope.sh ) 2>&1 >/dev/null; }
_sk_es_prod() { printf '%s\n' "$1" | grep -qvE "$(_sk_regex)"; }
# La declaración se COMMITEA: una declaración real vive trackeada en el repo
# (el checkout de CI solo contiene archivos trackeados — ver el guard del
# conf sin trackear, abajo). Dejarla solo staged la convertiría en producto
# pendiente de review dentro del propio fixture.
_sk_declara() {
  printf 'project_kind: %s\n' "$1" > tools/project.conf
  git add tools/project.conf 2>/dev/null
  git commit -qm "declara project_kind: $1" >/dev/null 2>&1
}

# ── Fila 1: la declaración GOBIERNA (monorepo, el contraejemplo real) ──
# La heurística vieja no mira packages/: sin declaración clasificaba un
# monorepo como harness. Declarado `application`, manda la declaración y
# —golden 4 del PRD— NO hay ni un aviso, porque la evidencia coincide.
_sk_case_monorepo_application() {
  mkdir -p packages/svc/src; printf 'export {}\n' > packages/svc/src/x.ts
  _sk_declara application
  _sk_es_prod packages/svc/src/x.ts || { echo "    el código del monorepo dejó de ser producto"; return 1; }
  _sk_es_prod tools/check-review-marker.sh && { echo "    declarado application, tools/ sigue siendo producto (gobernó la heurística, no la declaración)"; return 1; }
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    monorepo coherente y aun así avisó: [$err]"; return 1; }
  return 0
}
test_monorepo_declarado_application_gobierna_sin_aviso() { _sk_sandbox _sk_case_monorepo_application; }

# ── Fila 3: harness declarado MANDA aunque haya fuentes de app ──────
_sk_case_harness_manda() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  _sk_es_prod tools/check-review-marker.sh || { echo "    declarado harness, tools/ quedó exento (mandó la evidencia)"; return 1; }
}
test_declarado_harness_manda_aunque_haya_fuentes() { _sk_sandbox _sk_case_harness_manda; }

# ── Filas 3 y 4: la contradicción emite SCOPE_SUMMARY + aviso ───────
_sk_case_contradiccion_harness() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"SCOPE_SUMMARY kind=harness evidencia=contradice"*) : ;; *)
    echo "    la contradicción no emitió SCOPE_SUMMARY: [$err]"; return 1 ;; esac
}
test_harness_con_fuentes_emite_scope_summary() { _sk_sandbox _sk_case_contradiccion_harness; }

_sk_case_contradiccion_application() {
  _sk_declara application            # sin una sola fuente de app
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"SCOPE_SUMMARY kind=application evidencia=contradice"*) : ;; *)
    echo "    application sin fuentes no emitió SCOPE_SUMMARY: [$err]"; return 1 ;; esac
  _sk_es_prod tools/check-review-marker.sh && { echo "    la contradicción cambió el criterio (fila 4: manda la declaración)"; return 1; }
  return 0
}
test_application_sin_fuentes_contradice_pero_manda() { _sk_sandbox _sk_case_contradiccion_application; }

# ── exit 3 SOLO en CI, y por los DOS consumidores reales ────────────
_sk_case_ci_exit3_review() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  CI=true bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    en CI la contradicción devolvió $rc (esperaba 3)"; return 1; }
}
test_contradiccion_en_ci_review_marker_exit_3() { _sk_sandbox _sk_case_ci_exit3_review; }

_sk_case_gates_var_exit3() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  GATES_BASE_REF=origin/main bash tools/check-review-marker.sh --range >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    con GATES_* puesto la contradicción devolvió $rc (esperaba 3)"; return 1; }
}
test_contradiccion_con_gates_var_exit_3() { _sk_sandbox _sk_case_gates_var_exit3; }

_sk_case_verify_tambien() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local err rc
  err="$(CI=true bash tools/check-verify-marker.sh 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "3" ] || { echo "    check-verify-marker en CI devolvió $rc (esperaba 3)"; return 1; }
  case "$err" in *"SCOPE_SUMMARY kind=harness evidencia=contradice"*) : ;; *)
    echo "    el segundo consumidor no pasó por la verificación de la lib: [$err]"; return 1 ;; esac
}
test_contradiccion_llega_por_check_verify_marker() { _sk_sandbox _sk_case_verify_tambien; }

# ── FALSO POSITIVO guard: en local la contradicción avisa, NO bloquea ──
_sk_case_local_no_bloquea() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  mkdir -p docs; echo hola > docs/n.md; git add docs/n.md
  bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: sin CI, la contradicción bloqueó un commit exento (exit=$rc)"; return 1; }
}
test_sin_ci_la_contradiccion_avisa_pero_no_bloquea() { _sk_sandbox _sk_case_local_no_bloquea; }

# ── SCOPE_NO_CI_EXIT=1: la vía de CONSULTA (session-start) nunca muere ──
_sk_case_no_ci_exit() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local out
  out="$(CI=true SCOPE_NO_CI_EXIT=1 bash -c '. tools/lib/scope.sh 2>/dev/null; echo VIVO')"
  case "$out" in *VIVO*) : ;; *) echo "    con SCOPE_NO_CI_EXIT=1 el source salió igualmente (mataría a session-start)"; return 1 ;; esac
}
test_scope_no_ci_exit_permite_consultar_sin_morir() { _sk_sandbox _sk_case_no_ci_exit; }

# ── doc-only declarado `other` (AMBER-5): exención amplia, sin aviso ──
_sk_case_doc_only_other() {
  mkdir -p docs/libro; echo capitulo > docs/libro/cap1.md
  _sk_declara other
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    doc-only declarado other avisó: [$err]"; return 1; }
  _sk_es_prod tools/check-review-marker.sh && { echo "    declarado other, tocar el andamio exige review"; return 1; }
  _sk_es_prod docs/libro/cap1.md && { echo "    declarado other, el contenido doc exige review"; return 1; }
  # fila 1: para `other` CUALQUIER evidencia vale — tampoco contradice con fuentes
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    other con fuentes de app avisó (fila 1: cualquiera): [$err]"; return 1; }
  return 0
}
test_doc_only_declarado_other_exime_sin_aviso() { _sk_sandbox _sk_case_doc_only_other; }

# ── La evidencia EXACTA de §6: excluye tools/ scripts/ ci/ docs/ ────
# .agents/ enterprise/ y **/fixtures/ — los .py y fixtures del propio
# harness no convierten a nadie en app (contraejemplos del hallazgo 1).
_sk_case_evidencia_excluye() {
  _sk_declara harness
  mkdir -p tools/x scripts ci docs .agents enterprise web/fixtures
  printf 'x\n' > tools/x/a.py
  printf 'x\n' > scripts/b.ts
  printf 'x\n' > ci/c.js
  printf 'x\n' > docs/d.kt
  printf 'x\n' > .agents/e.go
  printf 'x\n' > enterprise/f.rb
  printf 'x\n' > web/fixtures/g.js         # **/fixtures/ a cualquier profundidad
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    la evidencia contó rutas que §6 excluye: [$err]"; return 1; }
  _sk_es_prod tools/check-review-marker.sh || { echo "    harness declarado dejó de tratar su maquinaria como producto"; return 1; }
}
test_la_evidencia_ignora_las_rutas_excluidas() { _sk_sandbox _sk_case_evidencia_excluye; }

_sk_case_evidencia_ve_monorepo() {
  _sk_declara harness
  mkdir -p packages/svc/src; printf 'export {}\n' > packages/svc/src/x.ts
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"evidencia=contradice"*) : ;; *)
    echo "    la evidencia NO ve un monorepo packages/ (el contraejemplo del hallazgo 1): [$err]"; return 1 ;; esac
}
test_la_evidencia_cubre_monorepos() { _sk_sandbox _sk_case_evidencia_ve_monorepo; }

# ── FALSO POSITIVO guard (cero FPs nuevos): SIN declarar, NADA cambia ──
# Un proyecto de app existente sin tools/project.conf conserva EXACTAMENTE
# el comportamiento actual: mismo regex byte a byte, cero output nuevo, y
# el gate real de punta a punta sigue exento para el andamio.
_sk_case_app_sin_declarar() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    FALSO POSITIVO: sin declarar, la lib ahora habla por commit: [$err]"; return 1; }
  local re esperado
  re="$(_sk_regex)"
  esperado='^(docs/|ci/|\.github/|tools/|scripts/|backlog/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|lefthook|\.gitleaks|\.semgrepignore|muter\.conf|AGENTS\.md|CLAUDE\.md|GEMINI\.md|(ios|android|web|backend)/AGENTS\.md$)'
  [ "$re" = "$esperado" ] || { echo "    el criterio de app sin declarar CAMBIÓ:"; echo "      antes: $esperado"; echo "      ahora: $re"; return 1; }
  printf 'x\n' > tools/nuevo.sh; git add tools/nuevo.sh
  bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: app sin declarar, tocar tools/ exigió review (exit=$rc)"; return 1; }
}
test_app_sin_declarar_conserva_el_comportamiento_actual() { _sk_sandbox _sk_case_app_sin_declarar; }

_sk_case_harness_sin_declarar() {
  local re esperado err
  re="$(_sk_regex)"
  esperado='^(docs/|backlog/|enterprise/|\.github/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|\.gitleaks|\.semgrepignore|muter\.conf|CLAUDE\.md|GEMINI\.md|tools/findings/ledger\.jsonl$|(ios|android|web|backend)/AGENTS\.md$)'
  [ "$re" = "$esperado" ] || { echo "    el criterio harness sin declarar CAMBIÓ"; return 1; }
  err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    FALSO POSITIVO: harness sin declarar avisa por commit (el diagnóstico es de session-start): [$err]"; return 1; }
}
test_harness_sin_declarar_conserva_la_heuristica() { _sk_sandbox _sk_case_harness_sin_declarar; }

# ── FALSO POSITIVO guard: conf COPIADO sin trackear + CI heredado ───
# El escenario real es el selftest de validate-harness en GitHub Actions:
# copia tools/ entero (con project.conf) a un sandbox git nuevo, stagea
# producto de app y espera exit 1 del review-marker. En un checkout REAL de
# CI el conf está siempre trackeado; uno sin trackear delata un sandbox al
# que CI=true le llegó por herencia del entorno — cortar ahí con exit 3
# rompería el selftest (y todo sandbox de suite) por la razón equivocada.
# El AVISO se emite igual; solo el corte exige conf trackeado.
_sk_case_conf_sin_trackear_no_corta() {
  printf 'project_kind: harness\n' > tools/project.conf    # copiado, JAMÁS git add
  mkdir -p app; printf 'let x = 1\n' > app/main.swift; git add app/main.swift
  CI=true bash tools/check-review-marker.sh --staged >/dev/null 2>&1; local rc=$?
  [ "$rc" = "1" ] || { echo "    FALSO POSITIVO: conf sin trackear + CI heredado devolvió $rc (esperaba 1: el gate debe seguir viendo producto sin marker)"; return 1; }
}
test_conf_sin_trackear_con_ci_heredado_no_corta() { _sk_sandbox _sk_case_conf_sin_trackear_no_corta; }
