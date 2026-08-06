#!/usr/bin/env bash
# Invariantes de los RATCHETS (trinquetes). Un ratchet que se puede aflojar
# no es un ratchet: es una sugerencia. Estos tests fijan la DIRECCIÓN.
#
# Cierra el finding f-8145599c del ledger: "falta test del invariante
# drift-ratchet-antes-de-bypass-lite".

# Copia el harness a un repo temporal para poder stubear sus piezas.
# (Los hooks derivan PROJECT_ROOT de su propio dirname, así que copiar funciona.)
_harness_sandbox() { # _harness_sandbox <función-a-ejecutar-dentro>
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT"/tools/*.sh "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT"/tools/*.json "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# ════════════════════════════════════════════════════════════════════
# f-8145599c — el preset `lite` relaja el MARKER, jamás el RATCHET.
# ════════════════════════════════════════════════════════════════════
_case_lite_no_relaja_ratchet() {
  # Stub: el ratchet SIEMPRE falla (simula deuda que subió).
  printf '#!/usr/bin/env bash\necho "❌ ratchet: subió"\nexit 1\n' > tools/drift-ratchet.sh
  # Cambio staged de código de producto (no docs/tooling → sí requiere gate).
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  # Preset lite + intento de commit.
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=lite bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  # DEBE bloquear (exit 2) aunque el preset sea lite.
  [ "$rc" = "2" ] || { echo "    lite dejó pasar un ratchet roto (exit=$rc, esperaba 2)"; return 1; }
}
test_ratchet_duro_incluso_en_preset_lite() {
  _harness_sandbox _case_lite_no_relaja_ratchet
}

_case_override_no_relaja_ratchet() {
  # REVIEWER_OVERRIDE es un escape hatch para el MARKER (juicio humano),
  # nunca para un detector mecánico. Un número objetivo no se negocia.
  printf '#!/usr/bin/env bash\necho "❌ ratchet: subió"\nexit 1\n' > tools/drift-ratchet.sh
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="urgencia" \
      bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "2" ] || { echo "    el override saltó el ratchet (exit=$rc, esperaba 2)"; return 1; }
}
test_override_no_relaja_el_ratchet() {
  _harness_sandbox _case_override_no_relaja_ratchet
}

_case_override_si_relaja_marker() {
  printf '#!/usr/bin/env bash\nexit 0\n' > tools/drift-ratchet.sh
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=full REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="urgencia" \
      bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el override no permitió commitear sin marker"; return 1; }
  # …y queda AUDITADO.
  grep -q "urgencia" .agents/state/markers/override_log.txt 2>/dev/null \
    || { echo "    el override no quedó registrado en override_log.txt"; return 1; }
}
test_override_relaja_marker_pero_queda_auditado() {
  _harness_sandbox _case_override_si_relaja_marker
}

# ════════════════════════════════════════════════════════════════════
# El marker debe venir del SISTEMA (source: hook), no del modelo.
# ════════════════════════════════════════════════════════════════════
_case_marker_manual_no_vale() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  # Marker fabricado "a mano" (lo que el modelo podía hacer antes).
  cat > .agents/state/markers/reviewer_run.txt <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
verdict: GREEN
scope: me reviso a mí mismo
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: manual-override
EOF
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un marker manual fue aceptado como review"; return 1; }
}
test_marker_manual_es_rechazado() {
  _harness_sandbox _case_marker_manual_no_vale
}

_case_marker_de_hook_si_vale() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  cat > .agents/state/markers/reviewer_run.txt <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
agent: reviewer
verdict: GREEN
scope: gates
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un marker legítimo del hook fue rechazado"; return 1; }
}
test_marker_de_hook_es_aceptado() {
  _harness_sandbox _case_marker_de_hook_si_vale
}

_case_marker_stale_por_diff() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  cat > .agents/state/markers/reviewer_run.txt <<EOF
agent: reviewer
verdict: GREEN
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
  # …y AHORA se cuela algo más en el staging, después de la review.
  echo "let colado = 2" > src/Sneaky.swift; git add src/Sneaky.swift
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    se aceptó un marker cuyo diff ya no coincide"; return 1; }
}
test_marker_caduca_si_cambia_el_diff_staged() {
  _harness_sandbox _case_marker_stale_por_diff
}

_case_lite_si_relaja_marker() {
  # Ratchet OK, pero SIN marker de reviewer.
  printf '#!/usr/bin/env bash\nexit 0\n' > tools/drift-ratchet.sh
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=lite bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  # En lite, la falta de marker AVISA pero deja pasar.
  [ "$rc" = "0" ] || { echo "    lite bloqueó por marker ausente (exit=$rc, esperaba 0)"; return 1; }
}
test_lite_avisa_pero_permite_sin_marker() {
  _harness_sandbox _case_lite_si_relaja_marker
}

_case_full_bloquea_sin_marker() {
  printf '#!/usr/bin/env bash\nexit 0\n' > tools/drift-ratchet.sh
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    full dejó commitear sin marker"; return 1; }
}
test_full_bloquea_sin_marker() {
  _harness_sandbox _case_full_bloquea_sin_marker
}

_case_solo_docs_no_requiere_gate() {
  printf '#!/usr/bin/env bash\nexit 0\n' > tools/drift-ratchet.sh
  mkdir -p docs; echo "# hola" > docs/x.md; git add docs/x.md
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m docs"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un cambio solo-docs fue bloqueado"; return 1; }
}
test_cambio_solo_docs_pasa() {
  _harness_sandbox _case_solo_docs_no_requiere_gate
}

# ════════════════════════════════════════════════════════════════════
# Mutation ratchet — el piso SOLO SUBE (dirección opuesta al de drift).
# ════════════════════════════════════════════════════════════════════
_case_mutacion_bajo_el_piso_falla() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=55 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un score por debajo del piso NO falló"; return 1; }
}
test_mutacion_por_debajo_del_piso_falla() {
  _harness_sandbox _case_mutacion_bajo_el_piso_falla
}

_case_mutacion_sobre_el_piso_pasa() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=65 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un score por encima del piso falló"; return 1; }
}
test_mutacion_por_encima_del_piso_pasa() {
  _harness_sandbox _case_mutacion_sobre_el_piso_pasa
}

_case_mutacion_update_no_baja() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  # --update con un score PEOR no debe bajar el piso.
  MUTATION_SCORE_OVERRIDE=40 bash tools/mutation-score.sh --update >/dev/null 2>&1
  grep -q '"min_score": *60' tools/mutation-ratchet.json \
    || { echo "    --update BAJÓ el piso: $(cat tools/mutation-ratchet.json)"; return 1; }
}
test_mutacion_update_nunca_baja_el_piso() {
  _harness_sandbox _case_mutacion_update_no_baja
}

_case_mutacion_update_si_sube() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=78 bash tools/mutation-score.sh --update >/dev/null 2>&1
  grep -q '"min_score": *78' tools/mutation-ratchet.json \
    || { echo "    --update no subió el piso: $(cat tools/mutation-ratchet.json)"; return 1; }
}
test_mutacion_update_sube_el_piso() {
  _harness_sandbox _case_mutacion_update_si_sube
}
