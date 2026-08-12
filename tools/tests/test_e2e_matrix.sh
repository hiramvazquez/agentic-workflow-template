#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_matrix.sh — la MATRIZ E2E del PRD 0004 (fase 10)
# ════════════════════════════════════════════════════════════════════
# Fase 10 no añade comportamiento: INTEGRA. Cada escenario golden del PRD
# 0004 §9 tiene aquí exactamente un test —`test_golden_NN_…`— y el vínculo
# lo fija una máquina: `test_matriz_e2e_cubre_los_diez_escenarios_golden`
# lee la lista del PRD y exige un test por escenario. Sin eso, la "Definition
# of Done" diría "los escenarios golden pasan" y nadie podría comprobarlo:
# sería exactamente el tipo de afirmación operativa sin evidencia que este
# PRD existe para eliminar.
#
# QUÉ ES ESTO Y QUÉ NO ES. Los tests unitarios de cada fase viven en su
# propio archivo (test_capabilities, test_capability_probe, test_backlog,
# test_gate_cache, test_metrics…) y siguen siendo la red fina: bordes,
# falsos positivos, contratos de exit. Esta matriz cruza FRONTERAS de script
# —manifiesto→documento, probe→health-check, historia→worktree→scope→review,
# evento→ledger→métrica, gate→caché→gate, y el Anillo 3 entero— porque un
# harness puede tener todas sus piezas verdes y estar roto en las costuras.
# Donde un escenario ya está demostrado end-to-end en otro archivo, el test
# de aquí lo dice y añade la pata que faltaba, en vez de repetirla.
#
# HERMÉTICA POR CONSTRUCCIÓN: ni `claude` ni `semgrep` reales. Los proveedores
# entran por stubs en un `bin/` del sandbox y el PATH se fija a mano, así que
# el resultado no depende de lo que tenga instalado la máquina. El único smoke
# contra el entorno real es el del escenario 10, y lo que exige no es un
# estado concreto sino que estado y exit code sean el MISMO hecho — un entorno
# roto puede reportarse roto, pero nunca verde.

# ── Sandbox con la maquinaria real, no con recortes ──────────────────
# Un E2E que copia solo los tres scripts que va a llamar no prueba la
# integración: prueba el recorte que hizo quien escribió el test. Aquí va la
# maquinaria entera (tools sin su propia suite, scripts, ci, .github) sobre un
# repo git nuevo.
_e2e_repo() { # _e2e_repo <función>
  local d rc; d="$(mktemp -d)"
  cp -R "$PROJECT_ROOT/tools" "$d/tools" 2>/dev/null
  rm -rf "$d/tools/tests"
  cp -R "$PROJECT_ROOT/scripts" "$d/scripts" 2>/dev/null
  cp -R "$PROJECT_ROOT/ci" "$d/ci" 2>/dev/null
  mkdir -p "$d/.github/workflows" "$d/docs/process" "$d/backlog"
  cp "$PROJECT_ROOT/.github/workflows/harness-ci.yml" "$d/.github/workflows/" 2>/dev/null
  cp "$PROJECT_ROOT/AGENTS.md" "$d/AGENTS.md" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    git add -A >/dev/null 2>&1
    git commit -qm "seed: maquinaria del harness" >/dev/null 2>&1
    "$1"
  )
  rc=$?
  rm -rf "$d"
  return $rc
}

# Historia de backlog con scope explícito (frontmatter = única fuente).
_e2e_story() { # _e2e_story <archivo> <id> <scope>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia E2E $2
status: ready
depends_on: []
base: develop
scope: |
  $3
---
## Criterios de aceptación
1. Dado el runner autónomo cuando termina la historia entonces queda evidencia ligada al diff.

## Verificación de criterios
1. n/a-manual — historia del propio harness, sin producto que verificar
EOF
}

# Líneas de lectura OBLIGATORIA de un doc de lecciones: todo lo anterior al
# índice mecanizado (el índice es una vista generada; AGENTS.md manda parar
# ahí). Misma definición que usa el límite de 250 líneas en test_lessons.sh.
_e2e_contexto_obligatorio() { # _e2e_contexto_obligatorio <doc>
  local corte
  corte="$(grep -n '^## Lecciones mecanizadas (índice)$' "$1" | head -1 | cut -d: -f1)"
  if [ -n "$corte" ]; then
    printf '%s\n' "$((corte - 1))"
  else
    grep -c '' "$1"
  fi
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 1 — manifiesto → bloques generados, sin tocar la prosa
# ════════════════════════════════════════════════════════════════════
# Los unitarios cubren cada modo por separado. Lo que se cruza aquí es el
# CICLO de vida completo sobre un documento con prosa antes y después del
# bloque: install → check limpio → el manifiesto cambia → drift → write →
# check limpio, con la prosa intacta en las dos orillas.
_case_g1_ciclo_manifiesto_documento() {
  mkdir -p docs
  cat > tools/capabilities.json <<'JSON'
{"schema":1,
 "documents":["docs/OPS.md"],
 "capabilities":{
   "ring3":{"title":"CI ejecuta los gates","provider":"ci/run-gates.sh",
            "required_in_full":true,"required_in_lite":false}
 }}
JSON
  printf 'prosa de arriba que nadie generó\n' > docs/OPS.md
  bash tools/render-capabilities.sh --install >/dev/null 2>&1 \
    || { echo "    --install falló sobre un documento sin markers"; return 1; }
  printf '\nprosa de abajo que nadie generó\n' >> docs/OPS.md
  bash tools/render-capabilities.sh --check >/dev/null 2>&1 \
    || { echo "    --check no quedó limpio inmediatamente tras --install"; return 1; }

  sed -i.bak 's/"required_in_lite":false/"required_in_lite":true/' tools/capabilities.json \
    && rm -f tools/capabilities.json.bak
  local err rc
  err="$(bash tools/render-capabilities.sh --check 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "    un bloque desactualizado devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$err" "docs/OPS.md" || return 1

  bash tools/render-capabilities.sh --write >/dev/null 2>&1 \
    || { echo "    --write falló"; return 1; }
  bash tools/render-capabilities.sh --check >/dev/null 2>&1 \
    || { echo "    tras --write el bloque seguía en drift"; return 1; }
  grep -q 'prosa de arriba' docs/OPS.md && grep -q 'prosa de abajo' docs/OPS.md \
    || { echo "    el renderer se comió prosa libre fuera de los markers"; return 1; }
}
test_golden_01_manifiesto_gobierna_los_bloques_generados() {
  _e2e_repo _case_g1_ciclo_manifiesto_documento
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 2 — un binario que revienta nunca produce verde, en NINGÚN consumidor
# ════════════════════════════════════════════════════════════════════
# La pata nueva es la cadena: el mismo semgrep roto visto por el probe
# (broken), por el scanner (exit 3 = "no pude mirar", jamás 0) y por el
# arranque (Nivel 2 ROTO). Tres consumidores, un solo hecho.
_case_g2_semgrep_roto_en_toda_la_cadena() {
  mkdir -p bin
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho "Fatal error: X509 trust anchors: CA store vacío" >&2\nexit 2\n'
  local hermetic="$PWD/bin:/usr/bin:/bin"

  local probe rc
  probe="$(PATH="$hermetic" bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] || { echo "    el probe de un binario roto devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$probe" '"status":"broken"' || return 1
  assert_contains "$probe" 'X509' || return 1

  # El scanner: 3 = el detector no pudo mirar. Nunca 0. (Sin jq en el PATH
  # hermético el camino es el otro exit 3 del mismo contrato: ambos dicen
  # "no corrí", que es lo que este escenario fija.)
  PATH="$hermetic" bash tools/semgrep-scan.sh --all >/dev/null 2>&1
  rc=$?
  [ "$rc" = 3 ] || { echo "    un semgrep roto dejó el scanner en exit $rc (esperaba 3)"; return 1; }

  local report
  report="$(PATH="$hermetic" bash scripts/agent-hooks/session-start.sh --report 2>&1 </dev/null)"
  assert_contains "$report" "Nivel 2 ROTO" || return 1
}
test_golden_02_binario_roto_no_es_verde_en_ningun_consumidor() {
  _e2e_repo _case_g2_semgrep_roto_en_toda_la_cadena
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 3 — un path fuera de scope no llega a in-review
# ════════════════════════════════════════════════════════════════════
# `test_backlog_scope.sh` prueba el checker; esto prueba al ORQUESTADOR
# usándolo: worktree real, commit real dentro de la rama, y el estado que ve
# un humano al final.
_case_g3_scope_creep_no_cierra() {
  _e2e_story 0001-scope.md 0001 'src/**'
  git add -A && git commit -qm "historia 0001" >/dev/null 2>&1
  stub fake-run.sh '#!/usr/bin/env bash\nset -uo pipefail\nmkdir -p src fuera\nprintf "dentro\\n" > src/dentro.txt\nprintf "creep\\n" > fuera/creep.txt\ngit add -A\nbash tools/agent-backends/fake-evidence.sh approve || exit 10\nGIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$PWD/tools/agent-backends/fake-hooks" git -c user.email=a@a -c user.name=a commit -qm "feat: con creep" >/dev/null 2>&1\n'

  FAKE_RUN_SCRIPT="$PWD/fake-run.sh" FAKE_AUTONOMY_EVIDENCE="$PWD/evidence.log" \
    bash tools/backlog/run.sh --backend fake >/dev/null 2>&1
  local rc=$? estado
  [ "$rc" = 6 ] || { echo "    scope creep devolvió $rc (esperaba 6)"; return 1; }
  estado="$(git show story/0001-scope:backlog/0001-scope.md 2>/dev/null | grep '^status:')"
  case "$estado" in
    *in-review*) echo "    la historia llegó a in-review con un path fuera de scope"; return 1 ;;
    *in-progress*) : ;;
    *) echo "    estado inesperado tras el scope creep: $estado"; return 1 ;;
  esac
}
test_golden_03_scope_fuera_de_contrato_no_llega_a_in_review() {
  _e2e_repo _case_g3_scope_creep_no_cierra
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 4 — sin detector de ciclos se dice `unsupported`, no "sin ciclos"
# ════════════════════════════════════════════════════════════════════
# La pata nueva es el consumidor: `validate-harness` tiene que repetir el
# estado declarado, no traducirlo a silencio (que es como se lee "todo bien").
_case_g4_ausencia_no_es_arquitectura_limpia() {
  local out rc
  out="$(bash tools/architecture-check.sh all 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "    sin config el clasificador devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$out" '"status":"missing"' || return 1

  cat > tools/architecture.conf <<'JSON'
{"schema":1,"capabilities":{
  "architecture_cycles":{"status":"unsupported","reason":"el stack no trae detector de ciclos"},
  "architecture_complexity":{"status":"unsupported","reason":"sin adapter de complejidad"}}}
JSON
  out="$(bash tools/architecture-check.sh all 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "    unsupported explícito devolvió $rc (esperaba 0)"; return 1; }
  assert_contains "$out" '"status":"unsupported"' || return 1
  assert_contains "$out" 'ARCHITECTURE_SUMMARY operational=0 unsupported=2 missing=0 broken=0' || return 1

  local vh
  vh="$(PATH="/usr/bin:/bin" bash tools/validate-harness.sh 2>&1 </dev/null)"
  assert_contains "$vh" "architecture_cycles unsupported" || return 1
  case "$vh" in
    *"architecture_cycles operational"*)
      echo "    el consumidor convirtió unsupported en operativo"; return 1 ;;
  esac
}
test_golden_04_stack_sin_detector_declara_unsupported() {
  _e2e_repo _case_g4_ausencia_no_es_arquitectura_limpia
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 5 — autonomía completa contra un CLI de proveedor STUB
# ════════════════════════════════════════════════════════════════════
# `test_backlog.sh` ya demuestra el ciclo con `fake.sh`. Lo que faltaba —y es
# lo que pide el PRD §10— es el mismo ciclo a través de `claude.sh` con el CLI
# stubbeado, y una verificación que nadie hacía: que la review del adapter sea
# READ-ONLY DE VERDAD (plan + herramientas de lectura), no read-only declarado.
_case_g5_ciclo_autonomo_con_claude_stub() {
  _e2e_story 0002-autonomia.md 0002 'src/**'
  git add -A && git commit -qm "historia 0002" >/dev/null 2>&1
  mkdir -p bin

  # jq hermético: el adapter tiene rama con y sin jq, y cuál corre no puede
  # depender de dónde instaló jq esta máquina. En este flujo el único
  # consumidor de jq es claude.sh.
  stub bin/jq '#!/usr/bin/env bash\npython3 -c "import json,sys; print(json.load(sys.stdin).get(\"result\",\"\"))"\n'

  cat > bin/claude <<'STUB'
#!/usr/bin/env bash
# Stub hermético del CLI: ni red ni modelo. Registra su argv para que el test
# pueda comprobar el contrato con el que lo invocó el adapter.
set -uo pipefail
printf '%s\n' "$*" >> "$CLAUDE_ARGV_LOG"
case " $* " in
  *" --permission-mode plan "*)
    printf '{"result":"VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: e2e-claude-stub"}\n'
    exit 0 ;;
esac
# Rama `run`: el prompt portable tiene que traer la historia concatenada.
case "$*" in
  *"id: 0002"*) : ;;
  *) echo "stub: el prompt de run no traía la historia" >&2; exit 8 ;;
esac
mkdir -p src
printf 'implementacion\n' > src/feature.txt
git add -A
bash tools/agent-backends/fake-evidence.sh approve || exit 10
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
  GIT_CONFIG_VALUE_0="$PWD/tools/agent-backends/fake-hooks" \
  git -c user.email=a@a -c user.name=a commit -qm "feat: e2e" >/dev/null 2>&1 || exit 11
STUB
  chmod +x bin/claude

  local rc estado argv_log="$PWD/claude-argv.log" evidencia="$PWD/evidence.log"
  : > "$argv_log"
  PATH="$PWD/bin:/usr/bin:/bin" CLAUDE_ARGV_LOG="$argv_log" \
    FAKE_AUTONOMY_EVIDENCE="$evidencia" \
    bash tools/backlog/run.sh >/dev/null 2>&1
  rc=$?
  [ "$rc" = 0 ] || { echo "    el ciclo autónomo con claude stub falló (rc=$rc)"; return 1; }
  estado="$(git show story/0002-autonomia:backlog/0002-autonomia.md 2>/dev/null | grep '^status:')"
  case "$estado" in *in-review*) : ;; *) echo "    no cerró en in-review ($estado)"; return 1 ;; esac
  ls .agents/state/backlog/0002-review-*.log >/dev/null 2>&1 \
    || { echo "    la review final no dejó evidencia persistida"; return 1; }

  # Evidencia ligada al MISMO staged SHA: review antes del commit, no después.
  local aprobado commiteado
  aprobado="$(grep '^approved:' "$evidencia" | tail -1)"
  commiteado="$(grep '^committed:' "$evidencia" | tail -1)"
  [ -n "$aprobado" ] || { echo "    no hubo review previa al commit de producto"; return 1; }
  [ "${aprobado#approved:}" = "${commiteado#committed:}" ] \
    || { echo "    review y commit no quedaron ligados al mismo staged SHA"; return 1; }

  # La review del adapter es read-only DEMOSTRADO, no declarado.
  local linea_review
  linea_review="$(grep -- '--permission-mode plan' "$argv_log" | tail -1)"
  [ -n "$linea_review" ] || { echo "    el adapter no invocó la review en modo plan"; return 1; }
  assert_contains "$linea_review" '--output-format json' || return 1
  assert_contains "$linea_review" '--allowedTools' || return 1
  # `*Edit*` cubre también `acceptEdits`: cualquier permiso de escritura en la
  # invocación de review rompe el contrato read_only que el backend declara.
  case "$linea_review" in
    *Edit*|*Write*)
      echo "    la review pidió herramientas de escritura: $linea_review"; return 1 ;;
  esac

  # Y el mismo contrato de review, en CI, sin proveedor instalado.
  PATH="/usr/bin:/bin" AI_REVIEW_REQUIRED=1 GATES_BASE_REF=HEAD~1 \
    bash ci/ai-review.sh --backend fake >/dev/null 2>&1 \
    || { echo "    ai-review con backend fake falló sin claude en PATH"; return 1; }
  grep -q 'VERDICT: GREEN' .agents/state/ci/ai-review.md 2>/dev/null \
    || { echo "    ai-review no dejó veredicto parseable"; return 1; }
}
test_golden_05_autonomia_completa_contra_cli_stub() {
  _e2e_repo _case_g5_ciclo_autonomo_con_claude_stub
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 6 — el mismo defecto, detectado dos veces, cuenta una
# ════════════════════════════════════════════════════════════════════
# La pata nueva: la promoción pasa por el CLI real del ledger (dos `add` con
# `--source-event` distintos) y las DOS métricas se leen sobre el resultado.
_case_g6_defecto_unico_en_dos_detecciones() {
  : > tools/findings/ledger.jsonl
  mkdir -p .agents/state/metrics docs/process
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{"schema":2,"event_id":"ev-alpha","ts":"%s","phase":"gate","source":"semgrep","duration_ms":12,"commit":"abc1234","triage":"unknown"}\n' "$ts"
    printf '{"schema":2,"event_id":"ev-beta","ts":"%s","phase":"gate","source":"semgrep","duration_ms":18,"commit":"abc1234","triage":"unknown"}\n' "$ts"
  } > .agents/state/metrics/detections.jsonl

  bash tools/findings/findings.sh add --title "adapter sin timeout" --area data \
    --source semgrep --source-event ev-alpha >/dev/null 2>&1 \
    || { echo "    el ledger rechazó la primera detección"; return 1; }
  bash tools/findings/findings.sh add --title "adapter sin timeout" --area data \
    --source semgrep --source-event ev-beta >/dev/null 2>&1 \
    || { echo "    el ledger rechazó la segunda detección del mismo defecto"; return 1; }

  local n; n="$(grep -c . tools/findings/ledger.jsonl | tr -d ' ')"
  [ "$n" = 1 ] || { echo "    dos detecciones del mismo defecto crearon $n findings"; return 1; }

  local escape gate
  escape="$(bash tools/metrics/escape-rate.sh --days 1 --json 2>/dev/null)" \
    || { echo "    escape-rate no pudo leer el ledger"; return 1; }
  assert_contains "$escape" '"findings_total":1' || return 1
  assert_contains "$escape" '"gate":1' || return 1

  # Y los eventos siguen contando como ACTIVIDAD: dos eventos, un defecto.
  gate="$(bash tools/metrics/gate-value.sh --days 1 --json 2>/dev/null)" \
    || { echo "    gate-value no pudo leer la telemetría"; return 1; }
  assert_contains "$gate" '"events_total":2' || return 1
  assert_contains "$gate" '"promoted_events":2' || return 1
}
test_golden_06_mismo_defecto_se_cuenta_una_sola_vez() {
  _e2e_repo _case_g6_defecto_unico_en_dos_detecciones
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 7 — rotar reduce el contexto SIN perder la garantía
# ════════════════════════════════════════════════════════════════════
# El riesgo de la rotación no es archivar poco: es archivar y que la lección
# deje de estar verificada. Por eso el test encadena rotate y
# lesson-detector-link, que es quien responde "¿sigue garantizada?".
_case_g7_rotacion_conserva_la_garantia() {
  mkdir -p docs/process tools/tests
  stub tools/tests/test_ficticio.sh '#!/usr/bin/env bash\n: # detector citado por la lección mecanizada\n'
  cat > docs/process/lessons_learned.md <<'EOF'
# Lecciones aprendidas

## Lecciones del harness

### [2026-01-01] Una lección ya mecanizada
- **Qué pasó:** el gate no miraba el índice, solo el árbol.
- **Regla:** mira el índice también.
- **Detector:** `tools/tests/test_ficticio.sh`
- **Área:** tools/

### [2026-01-02] Una lección de juicio
- **Qué pasó:** el agente eligió un default en vez de preguntar.
- **Regla:** Open Question > suposición silenciosa.
- **Detector:** n/a-manual — es criterio, no patrón mecanizable
- **Área:** proceso
EOF
  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    el corpus de partida ya no pasaba el vínculo lección→detector"; return 1; }

  # La medida es la del propio proyecto: el contexto OBLIGATORIO termina donde
  # empieza el índice (AGENTS.md manda leer solo hasta ahí). Contar el archivo
  # entero mediría otra cosa — el índice es una vista, no lectura obligatoria.
  local antes despues
  antes="$(_e2e_contexto_obligatorio docs/process/lessons_learned.md)"
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 \
    || { echo "    la rotación falló"; return 1; }
  despues="$(_e2e_contexto_obligatorio docs/process/lessons_learned.md)"
  [ "$despues" -lt "$antes" ] \
    || { echo "    rotar no redujo el contexto obligatorio ($antes → $despues líneas)"; return 1; }

  grep -q 'Una lección de juicio' docs/process/lessons_learned.md \
    || { echo "    la rotación archivó una lección n/a-manual (juicio no mecanizado)"; return 1; }
  grep -q 'es criterio, no patrón mecanizable' docs/process/lessons_learned.md \
    || { echo "    la lección viva perdió su cuerpo"; return 1; }
  grep -q 'el gate no miraba el índice' docs/process/lessons_archive.md 2>/dev/null \
    || { echo "    la lección mecanizada no llegó al archivo"; return 1; }
  grep -q 'el gate no miraba el índice' docs/process/lessons_learned.md \
    && { echo "    la lección mecanizada sigue en el contexto obligatorio"; return 1; }

  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    tras rotar, el vínculo lección→detector dejó de verificarse"; return 1; }
}
test_golden_07_rotacion_reduce_contexto_sin_perder_garantia() {
  _e2e_repo _case_g7_rotacion_conserva_la_garantia
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 8 — la caché acelera el mismo diff y jamás inventa detección
# ════════════════════════════════════════════════════════════════════
# `test_gate_cache.sh` fija la corrección de la clave. Aquí se mide lo que el
# PRD §10 promete y nadie medía: que un hit NO paga el coste del scanner, que
# es de donde sale la reducción de tiempo en gates repetidos.
#
# ⚠️ POR QUÉ LA ASERCIÓN ES SOBRE LA DIFERENCIA Y NO SOBRE EL RATIO. La versión
# anterior exigía `hit ≤ 0,7 × miss`. Ese ratio depende del overhead fijo de la
# máquina (arranque de python, git), no solo de la caché: en un runner lento
# —overhead 3 s, scan 2 s— un hit perfecto da 3/5 = 60% y el test se pondría
# rojo sin que hubiera nada roto. Un test que falla por contención de CPU se
# desactiva en una semana (ley del 10%, AGENTS.md §14.2), y con él se pierde la
# señal real. La diferencia `miss - hit`, en cambio, está acotada POR EL FIXTURE
# —el stub duerme una cantidad conocida— y no por la velocidad del host.
# La garantía dura sigue siendo el conteo de invocaciones, que es determinista.
_case_g8_cache_acelera_y_no_finge() {
  command -v jq >/dev/null 2>&1 \
    || { echo "    la matriz E2E exige jq (dependencia dura del harness)"; return 1; }
  mkdir -p bin src
  local calls="$PWD/semgrep-calls.log"; : > "$calls"
  # El scan duerme 3 s; `--version` (que la caché consulta para su key) no.
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho scan >> "$SEMGREP_CALLS"\nsleep 3\nprintf "{\\"results\\":[],\\"errors\\":[]}\\n"\nexit 0\n'
  printf 'contenido\n' > src/a.txt
  git add src/a.txt

  local t0 t1 miss hit salida
  t0="$(date +%s)"
  salida="$(PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged 2>/dev/null)"
  [ "$?" = 0 ] || { echo "    el primer scan no salió limpio"; return 1; }
  t1="$(date +%s)"; miss=$((t1 - t0))
  assert_contains "$salida" 'SEMGREP_SUMMARY errors=0 warns=0' || return 1

  t0="$(date +%s)"
  salida="$(PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged 2>/dev/null)"
  [ "$?" = 0 ] || { echo "    el segundo scan (hit) no salió limpio"; return 1; }
  t1="$(date +%s)"; hit=$((t1 - t0))
  assert_contains "$salida" 'SEMGREP_SUMMARY errors=0 warns=0' || return 1
  [ "$(grep -c . "$calls")" = 1 ] \
    || { echo "    el mismo diff volvió a invocar al scanner ($(grep -c . "$calls") veces)"; return 1; }
  # El fixture duerme 3 s en el scan; con resolución de 1 s, un hit que se
  # saltó ese scan mide como mínimo 1 s menos que el miss, en cualquier host.
  [ $((miss - hit)) -ge 1 ] \
    || { echo "    el hit pagó el coste del scanner (miss=${miss}s hit=${hit}s)"; return 1; }

  # Cambia el diff → la evidencia vieja no vale.
  printf 'otro contenido\n' > src/a.txt
  git add src/a.txt
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$(grep -c . "$calls")" = 2 ] \
    || { echo "    un diff distinto reutilizó la caché"; return 1; }

  # Un hallazgo real NUNCA se cachea: dos corridas, dos scans.
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho scan >> "$SEMGREP_CALLS"\nprintf "{\\"results\\":[{\\"path\\":\\"src/a.txt\\",\\"start\\":{\\"line\\":1},\\"check_id\\":\\"e2e\\",\\"extra\\":{\\"severity\\":\\"ERROR\\",\\"message\\":\\"hallazgo\\"}}],\\"errors\\":[]}\\n"\nexit 0\n'
  : > "$calls"
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un hallazgo ERROR no bloqueó"; return 1; }
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$(grep -c . "$calls")" = 2 ] \
    || { echo "    un exit 1 quedó cacheado: el segundo scan no corrió"; return 1; }
}
test_golden_08_cache_acelera_sin_perder_deteccion() {
  _e2e_repo _case_g8_cache_acelera_y_no_finge
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 9 — el Anillo 3 llama a TODO lo que promete
# ════════════════════════════════════════════════════════════════════
# `ci/run-gates.sh` era el único entrypoint del harness sin test propio: la
# promesa "el preset full no reduce ningún gate" vivía en prosa. Aquí cada
# gate es un stub que firma su paso, así que el conjunto invocado es un hecho
# observable — y un gate ausente sigue siendo fallo, no silencio.
_case_g9_anillo3_invoca_todos_los_gates() {
  mkdir -p bin
  local log="$PWD/gates.log"; : > "$log"
  local recorder='#!/usr/bin/env bash\necho NOMBRE >> "$GATE_LOG"\nexit 0\n'
  local nombre
  for nombre in tools/tests/run-tests.sh tools/secret-scan.sh tools/semgrep-scan.sh \
                tools/check-layers.sh tools/drift-ratchet.sh tools/verify-run.sh \
                tools/mutation-score.sh tools/check-review-marker.sh ci/ai-review.sh \
                tools/lesson-detector-link.sh tools/check-finding-refs.sh \
                tools/check-version-claims.sh tools/metrics/escape-rate.sh; do
    stub "$nombre" "${recorder/NOMBRE/$nombre}"
  done
  stub bin/gitleaks '#!/usr/bin/env bash\nexit 0\n'

  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  local rc=$? faltan=""
  [ "$rc" = 0 ] || { echo "    run-gates con todos los gates en verde salió $rc"; return 1; }
  for nombre in tools/tests/run-tests.sh tools/secret-scan.sh tools/semgrep-scan.sh \
                tools/check-layers.sh tools/drift-ratchet.sh tools/verify-run.sh \
                tools/mutation-score.sh tools/check-review-marker.sh ci/ai-review.sh \
                tools/lesson-detector-link.sh tools/check-finding-refs.sh \
                tools/check-version-claims.sh; do
    grep -qxF "$nombre" "$log" || faltan="$faltan $nombre"
  done
  [ -z "$faltan" ] || { echo "    el Anillo 3 no invocó:$faltan"; return 1; }

  # Un gate en rojo tumba el anillo entero.
  : > "$log"
  stub tools/check-layers.sh '#!/usr/bin/env bash\necho tools/check-layers.sh >> "$GATE_LOG"\nexit 1\n'
  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un gate en rojo no tumbó a run-gates"; return 1; }

  # Y un gate AUSENTE tampoco es verde (§14.3: fail-closed en CI).
  : > "$log"
  stub tools/check-layers.sh '#!/usr/bin/env bash\necho tools/check-layers.sh >> "$GATE_LOG"\nexit 0\n'
  rm -f tools/semgrep-scan.sh
  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un gate ausente pasó por gate aprobado"; return 1; }
}
test_golden_09_preset_full_no_reduce_ningun_gate() {
  _e2e_repo _case_g9_anillo3_invoca_todos_los_gates
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 10 — dos plataformas, y un smoke real que no puede mentir
# ════════════════════════════════════════════════════════════════════
# Las dos mitades del escenario: (a) la promesa de macOS+Linux es una matriz
# real en el workflow, no una frase en un doc; (b) el smoke contra el entorno
# de ESTA máquina no exige un estado concreto —puede faltar semgrep, puede
# estar roto— pero sí que estado y exit code sean el mismo hecho. Un verde
# solo puede salir de un probe que corrió y detectó su fixture.
test_golden_10_dos_plataformas_y_smoke_sin_falso_verde() {
  local wf="$PROJECT_ROOT/.github/workflows/harness-ci.yml"
  [ -f "$wf" ] || { echo "    no hay workflow que ejecute la suite"; return 1; }
  local matriz
  matriz="$(awk '/^ *os: \[/{print; exit}' "$wf")"
  case "$matriz" in
    *ubuntu*macos*|*macos*ubuntu*) : ;;
    *) echo "    la matriz de OS no cubre Linux y macOS: ${matriz:-ausente}"; return 1 ;;
  esac
  grep -q 'bash tools/tests/run-tests.sh' "$wf" \
    || { echo "    la matriz de OS no ejecuta la suite del harness"; return 1; }

  local probe rc estado
  probe="$(PROBE_TIMEOUT_SECS=20 bash "$PROJECT_ROOT/tools/probe-capability.sh" semgrep 2>/dev/null)"
  rc=$?
  estado="$(printf '%s' "$probe" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null \
    || echo unknown)"
  case "$estado:$rc" in
    operational:0|missing:1|broken:1|unknown:3) : ;;
    *)
      echo "    el smoke real emparejó mal estado y exit ($estado:$rc): un falso verde es posible"
      return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
# EL VÍNCULO — la matriz no puede quedarse atrás del PRD
# ════════════════════════════════════════════════════════════════════
# Sin esto, añadir un escenario golden 11 dejaría la "Definition of Done" en
# verde sin cubrirlo: la lista y su demostración divergen en silencio, que es
# el modo de fallo que este PRD persigue. La fuente es el PRD; el test solo
# comprueba que exista un `test_golden_NN_` por escenario declarado.
test_matriz_e2e_cubre_los_diez_escenarios_golden() {
  local prd="$PROJECT_ROOT/docs/process/prds/0004-reconciliar-workflow-agentico.md"
  local archivo="$PROJECT_ROOT/tools/tests/test_e2e_matrix.sh"
  [ -f "$prd" ] || { echo "    falta el PRD 0004: la matriz no tiene contra qué cuadrar"; return 1; }
  local total
  total="$(awk '/^## 9\. Escenarios golden/{s=1;next} /^## 10\./{s=0} s && /^[0-9]+\./{n++} END{print n+0}' "$prd")"
  [ "${total:-0}" -gt 0 ] \
    || { echo "    no pude leer los escenarios golden del PRD (¿cambió el encabezado §9?)"; return 1; }

  local i=1 n faltan=""
  while [ "$i" -le "$total" ]; do
    n="$(printf '%02d' "$i")"
    grep -q "^test_golden_${n}_" "$archivo" || faltan="$faltan $n"
    i=$((i + 1))
  done
  [ -z "$faltan" ] || { echo "    escenarios golden del PRD sin test E2E:$faltan"; return 1; }

  local tiene
  tiene="$(grep -c '^test_golden_[0-9][0-9]_' "$archivo")"
  [ "$tiene" = "$total" ] \
    || { echo "    la matriz declara $tiene tests golden y el PRD $total escenarios"; return 1; }
}
