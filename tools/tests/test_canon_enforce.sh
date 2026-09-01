#!/usr/bin/env bash
# canon-enforce BLOQUEA el cierre de turno. Es el gate más agresivo del harness,
# así que sus falsos positivos son los más caros: bloquean trabajo terminado y
# correcto, y la reacción natural es desactivarlo.
#
# El caso que motivó estos tests: el detector de secretos se bloqueaba A SÍ MISMO,
# porque el archivo que define "esto parece un secreto" contiene, por necesidad,
# algo que parece un secreto. (PRD 0001 §18 G7.)

_ce_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.claude"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_run() { echo '{}' | bash scripts/agent-hooks/canon-enforce.sh >/dev/null 2>&1; echo $?; }

# ── EL FALSO POSITIVO QUE MOTIVÓ ESTE ARCHIVO ───────────────────────
_case_detector_no_se_bloquea_a_si_mismo() {
  # El propio canon-enforce está en el árbol de trabajo (recién copiado y sin
  # commitear) y contiene sus patrones de detección. No debe autodetectarse.
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    el detector de secretos se bloqueó a SÍ MISMO (exit=$rc)"; return 1; }
}
test_el_detector_no_se_detecta_a_si_mismo() { _ce_sandbox _case_detector_no_se_bloquea_a_si_mismo; }

_case_archivo_de_patrones_excluido() {
  # `.claude/security-patterns.yaml` declara los prefijos de credencial. Está
  # LLENO de cosas que parecen secretos, y es correcto que lo esté.
  cat > .claude/security-patterns.yaml <<'EOF'
patterns:
  - rule_name: secreto_por_prefijo
    substrings: ["sk-", "AKIA", "ghp_", "service_role"]
    reminder: "Credencial hardcodeada."
EOF
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    el archivo que DEFINE los patrones fue marcado como secreto (exit=$rc)"; return 1; }
}
test_archivo_de_definicion_de_patrones_excluido() { _ce_sandbox _case_archivo_de_patrones_excluido; }

# ── …pero el gate SIGUE detectando de verdad ────────────────────────
_case_secreto_real_bloquea() {
  mkdir -p src
  printf 'let key = "AKIAIOSFODNN7EXAMPLE"\n' > src/Config.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un secreto REAL en código no bloqueó (exit=$rc)"; return 1; }
}
test_secreto_real_en_codigo_bloquea() { _ce_sandbox _case_secreto_real_bloquea; }

_case_storage_inseguro_bloquea() {
  mkdir -p src
  printf 'UserDefaults.standard.set(authToken, forKey: "token")\n' > src/Store.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un token en storage en claro no bloqueó (exit=$rc)"; return 1; }
}
test_token_en_storage_en_claro_bloquea() { _ce_sandbox _case_storage_inseguro_bloquea; }

_case_violacion_de_capa_bloquea() {
  mkdir -p src/Domain
  printf 'import SwiftUI\n\nstruct User {}\n' > src/Domain/User.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    una violación de capas no bloqueó el cierre (exit=$rc)"; return 1; }
}
test_violacion_de_capas_bloquea_el_cierre() { _ce_sandbox _case_violacion_de_capa_bloquea; }

# ── otros bordes de falso positivo ──────────────────────────────────
_case_ejemplo_en_markdown_no_bloquea() {
  mkdir -p docs
  printf 'Nunca escribas `AKIAIOSFODNN7EXAMPLE` en el código.\n' > docs/guia.md
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un ejemplo en documentación bloqueó (exit=$rc)"; return 1; }
}
test_ejemplo_en_documentacion_no_bloquea() { _ce_sandbox _case_ejemplo_en_markdown_no_bloquea; }

_case_archivo_example_no_bloquea() {
  printf 'API_KEY=sk-ejemplonoesrealsolounplaceholder\n' > .env.example
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un .example bloqueó (exit=$rc)"; return 1; }
}
test_archivo_example_no_bloquea() { _ce_sandbox _case_archivo_example_no_bloquea; }

_case_repo_limpio_no_bloquea() {
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    un repo sin cambios bloqueó el cierre (exit=$rc)"; return 1; }
}
test_repo_limpio_no_bloquea() { _ce_sandbox _case_repo_limpio_no_bloquea; }

# ── CHECK 4: coste acotado sin perder el bloqueo (f-e2a65344) ────────
# CHECK 4 corría la suite ENTERA (5:07 medidos) en cada cierre de turno que
# tocara el harness. Ahora corre `bash -n` + los tests DIRIGIDOS del archivo
# tocado (~2s). Estos tests fijan las DOS mitades: que sigue bloqueando de
# verdad, y que NO vuelve a correrlo todo — porque un filtro que no casa nada
# sale 0 en el runner, así que degradar el mapeo sería un falso verde silencioso.

# Sandbox con una MINI-SUITE controlada: el runner real, y solo los test_*.sh
# que este helper crea. Así "corrió lo dirigido" y "corrió todo" son
# distinguibles: `test_beta` está en ROJO a propósito y nadie debe tocarlo.
_ce_sandbox_suite() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools/tests" "$d/.claude"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/tests/run-tests.sh" "$d/tools/tests/"
  printf '#!/usr/bin/env bash\ntest_alpha_verde() { assert_eq a a; }\n' > "$d/tools/tests/test_alpha.sh"
  printf '#!/usr/bin/env bash\ntest_beta_roja_a_proposito() { assert_eq a b; }\n' > "$d/tools/tests/test_beta.sh"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    # La mini-suite entra en el commit INICIAL a propósito: si `test_beta.sh`
    # llegara sin commitear, contaría como archivo tocado y CHECK 4 lo correría
    # —correctamente— arruinando el experimento. Aquí lo tocado es solo lo que
    # crea cada caso.
    git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_sh_del_harness_que_no_parsea_bloquea() {
  printf '#!/usr/bin/env bash\nif [ 1 = 1 ; then echo roto\n' > scripts/agent-hooks/zzz-roto.sh
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un hook que NO PARSEA no bloqueó el cierre (exit=$rc)"; return 1; }
}
test_sh_del_harness_que_no_parsea_bloquea() { _ce_sandbox _case_sh_del_harness_que_no_parsea_bloquea; }

_case_md_del_harness_no_dispara_el_check() {
  printf 'texto\n' > tools/zzz-nota.md
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    un .md bajo tools/ disparó CHECK 4 (exit=$rc)"; return 1; }
}
test_md_del_harness_no_dispara_el_check() { _ce_sandbox _case_md_del_harness_no_dispara_el_check; }

_case_test_dirigido_en_rojo_bloquea() {
  # `tools/beta.sh` mapea a `test_beta.sh`, que está en rojo.
  printf '#!/usr/bin/env bash\necho beta\n' > tools/beta.sh
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un test DIRIGIDO en rojo no bloqueó (exit=$rc)"; return 1; }
}
test_test_dirigido_en_rojo_bloquea() { _ce_sandbox_suite _case_test_dirigido_en_rojo_bloquea; }

_case_no_corre_la_suite_entera() {
  # `tools/alpha.sh` mapea a `test_alpha.sh` (verde). `test_beta.sh` sigue en
  # ROJO en el mismo directorio: si CHECK 4 volviera a correrlo todo, este
  # cierre saldría 2. Que salga 0 es la prueba de que corrió SOLO lo dirigido.
  printf '#!/usr/bin/env bash\necho alpha\n' > tools/alpha.sh
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    CHECK 4 arrastró tests NO dirigidos (exit=$rc): volvió a la suite entera"; return 1; }
}
test_no_corre_la_suite_entera() { _ce_sandbox_suite _case_no_corre_la_suite_entera; }

_case_sin_test_dirigido_avisa_y_no_bloquea() {
  printf '#!/usr/bin/env bash\necho x\n' > tools/zzz-sin-test.sh
  git add -A 2>/dev/null
  local out rc
  out="$(echo '{}' | bash scripts/agent-hooks/canon-enforce.sh 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un archivo sin test dirigido BLOQUEÓ el cierre (exit=$rc)"; return 1; }
  case "$out" in *"Sin test dirigido"*) ;; *) echo "    deferir la suite fue SILENCIOSO, no avisó. salida: [$out]"; return 1 ;; esac
}
test_sin_test_dirigido_avisa_y_no_bloquea() { _ce_sandbox_suite _case_sin_test_dirigido_avisa_y_no_bloquea; }

_case_conf_del_harness_si_dispara() {
  # Un `.conf` cambia el comportamiento de un gate igual que un `.sh`
  # (`skill-matrix.conf` gobierna `skill-reminder`). `beta.conf` mapea a
  # `test_beta.sh`, que está en rojo: si los .conf no se consideraran, este
  # cierre saldría 0 y el gate sería ciego a su propia configuración.
  printf 'clave=valor\n' > tools/beta.conf
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un .conf del harness no disparó CHECK 4 (exit=$rc)"; return 1; }
}
test_conf_del_harness_si_dispara() { _ce_sandbox_suite _case_conf_del_harness_si_dispara; }

_case_datos_del_harness_no_avisan() {
  # El ledger y los ratchets cambian en casi todos los turnos y no alteran
  # ninguna lógica. Si entraran en el alcance, el aviso saldría siempre — y un
  # aviso que sale siempre no se lee.
  mkdir -p tools/findings
  printf '{"id":"f-x"}\n' > tools/findings/ledger.jsonl
  printf '{"errors":0}\n' > tools/beta.json
  git add -A 2>/dev/null
  local out rc
  out="$(echo '{}' | bash scripts/agent-hooks/canon-enforce.sh 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un cambio de DATOS bloqueó el cierre (exit=$rc)"; return 1; }
  case "$out" in *"Sin test dirigido"*) echo "    los datos del harness generaron aviso; saldría en cada turno"; return 1 ;; esac
}
test_datos_del_harness_no_avisan() { _ce_sandbox_suite _case_datos_del_harness_no_avisan; }
