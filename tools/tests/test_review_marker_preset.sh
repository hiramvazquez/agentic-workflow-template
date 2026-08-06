#!/usr/bin/env bash
# El preset debe comportarse IGUAL desde los 3 anillos.
#
# Regresión que motivó este archivo (PRD 0001 §18 G8): la lógica de preset vivía
# solo en `reviewer-gate.sh` (Anillo 2). Cuando `lefthook.yml` (Anillo 1) empezó a
# invocar `check-review-marker.sh` directamente, el preset `lite` dejó de aplicar
# ahí: el agente recibía luz verde del Anillo 2 y el `git commit` fallaba después.
#
# `test_ratchets.sh::test_lite_avisa_pero_permite_sin_marker` NO lo cazó porque
# solo ejercitaba el camino del Anillo 2. Los 60 tests pasaban con la regresión
# dentro. Lección: **testea cada CAMINO de invocación, no cada función.**

_rm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tools/drift-ratchet.sh"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# Camino Anillo 1 (lefthook): invoca el script DIRECTO.
_anillo1() { WORKFLOW_PRESET="$1" bash tools/check-review-marker.sh --staged >/dev/null 2>&1; echo $?; }
# Camino Anillo 2 (hook): pasa por reviewer-gate.
_anillo2() {
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET="$1" bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

# ── LA REGRESIÓN: los dos caminos deben coincidir ───────────────────
_case_lite_coherente() {
  local a1 a2; a1="$(_anillo1 lite)"; a2="$(_anillo2 lite)"
  # lite: ambos permiten (0 en el script, 0 = allow en el hook).
  [ "$a1" = "0" ] || { echo "    Anillo 1 BLOQUEÓ en preset lite (exit=$a1) — contradice AGENTS.md §13"; return 1; }
  [ "$a2" = "0" ] || { echo "    Anillo 2 bloqueó en preset lite (exit=$a2)"; return 1; }
}
test_lite_permite_en_los_dos_anillos() { _rm_sandbox _case_lite_coherente; }

_case_full_coherente() {
  local a1 a2; a1="$(_anillo1 full)"; a2="$(_anillo2 full)"
  # full: ambos bloquean (1 en el script, 2 = block en el hook).
  [ "$a1" = "1" ] || { echo "    Anillo 1 permitió sin marker en preset full (exit=$a1)"; return 1; }
  [ "$a2" = "2" ] || { echo "    Anillo 2 permitió sin marker en preset full (exit=$a2)"; return 1; }
}
test_full_bloquea_en_los_dos_anillos() { _rm_sandbox _case_full_coherente; }

# ── lite NO relaja lo mecánico (invariante de AGENTS.md §9) ─────────
_case_lite_no_relaja_capas() {
  mkdir -p src/Domain; echo 'import SwiftUI' > src/Domain/Bad.swift; git add src/Domain/Bad.swift
  local rc; rc="$(_anillo2 lite)"
  [ "$rc" = "2" ] || { echo "    preset lite dejó pasar una violación de capas (exit=$rc)"; return 1; }
}
test_lite_no_relaja_las_capas() { _rm_sandbox _case_lite_no_relaja_capas; }

# ── el marker legítimo funciona igual desde ambos caminos ───────────
_case_marker_valido_ambos() {
  cat > .agents/state/markers/reviewer_run.txt <<EOF
agent: reviewer
verdict: GREEN
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
  local a1 a2; a1="$(_anillo1 full)"; a2="$(_anillo2 full)"
  [ "$a1" = "0" ] || { echo "    Anillo 1 rechazó un marker válido (exit=$a1)"; return 1; }
  [ "$a2" = "0" ] || { echo "    Anillo 2 rechazó un marker válido (exit=$a2)"; return 1; }
}
test_marker_valido_pasa_en_ambos_anillos() { _rm_sandbox _case_marker_valido_ambos; }
