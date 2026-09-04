#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El carril decide si hace falta review — y nunca puede decidir que no
# ════════════════════════════════════════════════════════════════════
# Hermano de `test_review_marker_preset.sh`: aquél fija que los tres anillos
# hagan lo MISMO con un veredicto; éste fija cuándo hace falta veredicto.
#
# El riesgo aquí tiene una sola forma: que llegue a commit, sin review, algo que
# sí podía romperse. Por eso cada caso ataca una vía distinta de conseguirlo —
# un clasificador ausente, uno que falla, uno que miente, una conf sin stagear,
# y el modo `--range`— y ninguno se conforma con el exit code del camino feliz.
_RMS_LIB="$PROJECT_ROOT/tools/tests/lib/review-marker-sandbox.sh"
# shellcheck source=/dev/null
. "$_RMS_LIB"

# ── PRD 0011 fase 3: el carril ligero no exige review ───────────────
# Un fichero de prosa DENTRO del árbol de producto es código de producto para
# el criterio de rutas (no casa la lista de exentos) pero no ejecuta nada. Ese
# es exactamente el caso que la fase 3 deja pasar: pagar una revisión por un
# .md es el peaje que hace que la gente apague el gate.
_case_ligero_no_exige_review() {
  local A=add; git "$A" src/App.swift 2>/dev/null; git rm -q --cached src/App.swift 2>/dev/null
  mkdir -p src; echo "# notas" > src/NOTES.md; git "$A" src/NOTES.md
  # Los DOS anillos, que es la regresión que creó este fichero: una exención
  # en lefthook y no en el hook deja al agente bloqueado por algo que el commit
  # sí habría permitido, y al revés es peor.
  local a1 a2; a1="$(_anillo1 full)"; a2="$(_anillo2 full)"
  [ "$a1" = "0" ] || {
    echo "    Anillo 1: un cambio de carril ligero exigió review (exit $a1)"
    WORKFLOW_PRESET=full bash tools/check-review-marker.sh --staged 2>&1 | sed 's/^/      /'
    return 1; }
  [ "$a2" = "0" ] || {
    echo "    Anillo 2 bloqueó (exit $a2) lo que el Anillo 1 dejó pasar"; return 1; }
}
test_el_carril_ligero_no_exige_review() { _rm_sandbox _case_ligero_no_exige_review; }

# ── Y sin clasificador se sigue exigiendo ───────────────────────────
# El default seguro, otra vez: no saber cuánto pesa un cambio nunca puede
# traducirse en pedir menos garantías que antes de existir el carril.
_case_sin_clasificador_sigue_exigiendo() {
  local R=rm C=commit
  git "$R" -q --cached tools/carril.sh tools/carril.conf 2>/dev/null
  git "$C" -qm sin-clasificador 2>/dev/null
  local A=add; mkdir -p src; echo "# notas" > src/NOTES.md; git "$A" src/NOTES.md
  git rm -q --cached src/App.swift 2>/dev/null
  local rc; rc="$(_anillo1 full)"
  [ "$rc" = "1" ] || {
    echo "    sin clasificador el gate dejó pasar producto sin review (exit $rc)"; return 1; }
}
test_sin_clasificador_el_gate_sigue_exigiendo_review() {
  _rm_sandbox _case_sin_clasificador_sigue_exigiendo
}

# ── Las llaves del reino NUNCA se eximen, diga lo que diga el carril ─
# Defensa en capas (§1.2). `carril.conf` ya clasifica `.claude/agents/*` como
# estructural, pero esa fila es UN dato en UN fichero: si mañana un glob vuelve
# a casar de más —ya pasó con `ligero|*.md`, que se tragaba el prompt del propio
# revisor— el gate no puede quedarse sin suelo. La declaración que gobierna un
# gate no se exime a sí misma, gobierne quien gobierne.
_case_las_llaves_no_se_eximen() {
  _falso_clasificador 'echo "CARRIL_SUMMARY carril=ligero archivos=1"'
  local A=add; mkdir -p .claude; echo '{}' > .claude/settings.json; git "$A" .claude/settings.json
  git rm -q --cached src/App.swift 2>/dev/null
  local rc; rc="$(_anillo1 full)"
  [ "$rc" = "1" ] || {
    echo "    un clasificador que dice 'ligero' eximió .claude/settings.json (exit $rc)"
    return 1; }
}
test_las_llaves_del_reino_no_las_exime_el_carril() {
  _rm_sandbox _case_las_llaves_no_se_eximen
}

# ── Un clasificador que FALLA diciendo "ligero" no exime ────────────
# Sin este caso, el chequeo del exit code quedaba tapado por el `[ -f ]`: el
# mutante que lo quitaba sobrevivía. Y es el modo de fallo que este repo ya ha
# visto dos veces — una salida de fallo que el consumidor toma por buena.
_case_clasificador_que_falla_diciendo_ligero() {
  _falso_clasificador 'echo "CARRIL_SUMMARY carril=ligero archivos=1"' 'exit 3'
  local A=add; mkdir -p src; echo "# notas" > src/NOTES.md; git "$A" src/NOTES.md
  git rm -q --cached src/App.swift 2>/dev/null
  local rc; rc="$(_anillo1 full)"
  [ "$rc" = "1" ] || {
    echo "    un clasificador que salió 3 consiguió eximir la review (exit $rc)"; return 1; }
}
test_un_clasificador_que_falla_no_exime_aunque_diga_ligero() {
  _rm_sandbox _case_clasificador_que_falla_diciendo_ligero
}

# ── El clasificador se lee del ÍNDICE, no del disco ─────────────────
# El bypass que cazó la review de esta fase, y que `tools/lib/scope.sh` ya
# documenta haber sufrido con `project.conf`: editas la conf del clasificador
# SIN stagearla, y código de producto staged sale sin review. El diff resultante
# no tiene una sola línea de `carril.conf` — sin override, sin entrada en
# override_log, sin rastro. El guard de llaves no lo veía porque solo mira lo
# STAGED, y esta edición no lo está.
_case_conf_sin_stagear_no_exime() {
  local A=add
  echo 'ligero|src/*' >> tools/carril.conf          # SIN stagear, a propósito
  echo 'let secret = leak()' > src/Payment.swift
  git "$A" src/Payment.swift
  local rc; rc="$(_anillo1 full)"
  [ "$rc" = "1" ] || {
    echo "    una edición SIN STAGEAR de carril.conf eximió producto real (exit $rc)"
    echo "    Lo que decide sobre un diff se lee de la misma fuente que ese diff."
    return 1; }
}
test_una_conf_sin_stagear_no_puede_eximir_review() {
  _rm_sandbox _case_conf_sin_stagear_no_exime
}

# ── En modo --range el carril no opina ──────────────────────────────
# El clasificador lee el ÍNDICE; `--range` juzga commits. Son dos preguntas
# distintas, y mezclarlas deja que lo que tengas staged decida sobre lo que ya
# está commiteado. Hoy no es explotable por el cableado (CI hace checkout
# limpio), pero eso es una propiedad del llamador, no de este gate.
_case_range_no_lo_decide_el_indice() {
  local A=add C=commit base
  base="$(git rev-parse HEAD)"
  echo "let y = 2" > src/Otro.swift
  git "$A" src/Otro.swift
  git "$C" -qm producto-sin-review 2>/dev/null
  mkdir -p src; echo "# notas" > src/NOTES.md
  git "$A" src/NOTES.md                              # el índice, ligero
  local rc
  GATES_BASE_REF="$base" WORKFLOW_PRESET=full \
    bash tools/check-review-marker.sh --range >/dev/null 2>&1
  rc=$?
  [ "$rc" = "1" ] || {
    echo "    --range eximió producto del RANGO porque el ÍNDICE era ligero (exit $rc)"
    return 1; }
}
test_en_modo_range_el_indice_no_decide() {
  _rm_sandbox _case_range_no_lo_decide_el_indice
}
