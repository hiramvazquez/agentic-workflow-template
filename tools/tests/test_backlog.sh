#!/usr/bin/env bash
# Backlog runner (PRD 0003). El selector decide QUÉ historia trabaja un agente
# sin supervisión — sus falsos positivos son caros en las dos direcciones:
# elegir una historia que no tocaba (deps sin mergear, ejemplos del template)
# o saltarse una legítima.

_bl_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/backlog" "$d/backlog"
  cp "$PROJECT_ROOT/tools/backlog/next.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/run.sh" "$d/tools/backlog/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_story() { # _story <archivo> <id> <status> <deps>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia $2
status: $3
depends_on: [$4]
base: develop
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.
EOF
}

# ── selección básica ────────────────────────────────────────────────
_case_elige_primera_ready() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready ""
  _story 0003-c.md 0003 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    eligió '$out' (esperaba 0002-b.md, la primera ready)"; return 1
}
test_elige_la_primera_ready() { _bl_sandbox _case_elige_primera_ready; }

# ── FALSO POSITIVO guard: ejemplos y terminadas NO se eligen ────────
_case_ignora_ejemplos_y_terminadas() {
  _story 0001-ej.md 0001 ejemplo ""
  _story 0002-done.md 0002 done ""
  _story 0003-rev.md 0003 in-review ""
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    FALSO POSITIVO: eligió '$out' sin haber historias ready"; return 1; }
}
test_ignora_ejemplos_y_no_ready() { _bl_sandbox _case_ignora_ejemplos_y_terminadas; }

# ── dependencias: solo desbloquea el DONE (= mergeado a base) ───────
_case_dep_pendiente_bloquea() {
  _story 0001-a.md 0001 in-review ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    eligió '$out' con su dependencia 0001 aún sin mergear (in-review)"; return 1; }
}
test_dependencia_sin_done_bloquea() { _bl_sandbox _case_dep_pendiente_bloquea; }

_case_dep_done_desbloquea() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    con la dep en done, no eligió 0002 (out='$out')"; return 1
}
test_dependencia_done_desbloquea() { _bl_sandbox _case_dep_done_desbloquea; }

_case_salta_bloqueada_y_toma_siguiente() {
  _story 0001-a.md 0001 ready "0009"     # dep inexistente → no elegible
  _story 0002-b.md 0002 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    no saltó a la siguiente elegible (out='$out')"; return 1
}
test_salta_la_bloqueada_y_toma_la_siguiente() { _bl_sandbox _case_salta_bloqueada_y_toma_siguiente; }

_case_sin_backlog_silencio() {
  rm -rf backlog
  bash tools/backlog/next.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    sin backlog/ devolvió error (debe ser no-op apto para cron)"; return 1; }
}
test_sin_backlog_es_noop() { _bl_sandbox _case_sin_backlog_silencio; }

# ── guards del runner ───────────────────────────────────────────────
_case_arbol_sucio_aborta() {
  _story 0001-a.md 0001 ready ""
  echo dirty > seed.txt                      # árbol sucio
  bash tools/backlog/run.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "1" ] || { echo "    con árbol sucio no abortó (rc=$rc)"; return 1; }
  grep -q "status: ready" backlog/0001-a.md || { echo "    tocó la historia pese a abortar"; return 1; }
}
test_arbol_sucio_aborta_sin_tocar_nada() { _bl_sandbox _case_arbol_sucio_aborta; }

_case_sin_claude_exit3() {
  _story 0001-a.md 0001 ready ""
  PATH="/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "3" ] || { echo "    sin binario claude no dio exit 3 (rc=$rc)"; return 1; }
  grep -q "status: ready" backlog/0001-a.md || { echo "    la historia cambió de estado sin haberse trabajado"; return 1; }
  git rev-parse --verify story/0001 >/dev/null 2>&1 && { echo "    creó la rama pese a no poder trabajar"; return 1; }
  return 0
}
test_sin_claude_exit3_e_historia_intacta() { _bl_sandbox _case_sin_claude_exit3; }

# ── historia sin criterios de aceptación → blocked, no improvisación ─
_case_sin_criterios_se_bloquea() {
  cat > backlog/0001-vacia.md <<'EOF'
---
id: 0001
titulo: Historia sin criterios
status: ready
depends_on: []
base: develop
---
Hacer algo, ya tal.
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > claude_fake; chmod +x claude_fake
  mkdir -p bin; mv claude_fake bin/claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  grep -q "status: blocked" backlog/0001-vacia.md \
    || { echo "    una historia SIN criterios de aceptación no quedó blocked (§1.4: no se improvisa)"; return 1; }
}
test_historia_sin_criterios_queda_blocked() { _bl_sandbox _case_sin_criterios_se_bloquea; }
