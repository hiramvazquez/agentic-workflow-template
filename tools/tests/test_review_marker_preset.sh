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

_RMS_LIB="$PROJECT_ROOT/tools/tests/lib/review-marker-sandbox.sh"
# shellcheck source=/dev/null
. "$_RMS_LIB"

# ── LA REGRESIÓN: los dos caminos deben coincidir ───────────────────
# FALSO POSITIVO guard: en preset lite el marker AVISA, no bloquea — y debe
# ser así en LOS DOS anillos, o el agente recibe luz verde y el commit falla.
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

# ── meta-doc NO exige marker (falso positivo cazado en vivo) ────────
# AGENTS.md es meta-doc, no producto: no estaba en NON_PRODUCT y un commit de
# solo-reglas exigió marker — y como había un marker VIEJO de otra sesión, el
# error fue el confuso "EXPIRADO" en vez de la exención. Peor aún: un marker
# stale presente hacía el commit de docs MÁS difícil que sin marker.
_case_meta_doc_exento() {
  git reset -q                       # fuera el src/App.swift del sandbox
  echo "## nueva regla" >> AGENTS.md 2>/dev/null || echo "# reglas" > AGENTS.md
  # `.github/workflows/` ESTABA aquí como exento, y se retiró a propósito el
  # 2026-08-22. Chocaban dos criterios y ganó el de seguridad:
  #   · el de antes: "config de CI es meta-doc, exigir marker era un FP".
  #   · el que gana: ese directorio CABLEA el Anillo 3. Y §14.4 dice que TODO el
  #     fail-open local (exit 3 avisa, no bloquea) está justificado *por* la
  #     existencia de ese backstop. Si el workflow que lo invoca se puede vaciar
  #     sin review, el razonamiento de los otros niveles se cae con él.
  # Lo cazó un reviewer al que se le pidió buscar la cuarta vía del bypass de
  # scope. El coste es real —tocar CI ahora pide review— y se acepta.
  git add AGENTS.md
  # …incluso con un marker viejo e inválido presente (el caso real):
  printf 'agent: reviewer\nverdict: GREEN\nsource: hook\n' > .agents/state/markers/reviewer_run.txt
  touch -t 202001010000 .agents/state/markers/reviewer_run.txt 2>/dev/null
  local a1; a1="$(_anillo1 full)"
  [ "$a1" = "0" ] || { echo "    un cambio solo-AGENTS.md exigió marker (exit=$a1)"; return 1; }
}
test_meta_doc_no_exige_marker() { _rm_sandbox _case_meta_doc_exento; }

_case_producto_sigue_gateado() {
  # FALSO NEGATIVO guard: la exención de meta-doc no puede abrir la puerta a
  # un diff MIXTO (reglas + código) — con producto en el diff, se gatea igual.
  echo "## nueva regla" >> AGENTS.md 2>/dev/null || echo "# reglas" > AGENTS.md
  git add AGENTS.md      # src/App.swift ya está staged por el sandbox
  local a1; a1="$(_anillo1 full)"
  [ "$a1" = "1" ] || { echo "    un diff mixto (AGENTS.md + código) NO fue gateado (exit=$a1)"; return 1; }
}
test_diff_mixto_con_producto_sigue_gateado() { _rm_sandbox _case_producto_sigue_gateado; }

# ── un MERGE de rama ya validada NO exige marker nuevo ──────────────
# Bug real del primer merge en vivo: la rama fue GREEN al crearse, y el gate
# pedía marker fresco para el commit de merge → MERGE_HEAD colgado y el owner
# atascado. El merge es acto del owner; sus commits ya pasaron gates al nacer.
_case_merge_no_exige_marker() {
  git checkout -qb story/x
  mkdir -p src; echo "let m = 1" > src/Merged.swift
  git add src/Merged.swift; git commit -qm "feat: en rama (ya revisado allí)"
  git checkout -q develop 2>/dev/null || git checkout -q -
  echo divergencia >> seed.txt; git add seed.txt; git commit -qm "avance en base"
  git merge --no-commit --no-ff story/x >/dev/null 2>&1     # deja MERGE_HEAD
  local a1; a1="$(_anillo1 full)"
  git merge --abort 2>/dev/null
  [ "$a1" = "0" ] || { echo "    el gate exigió marker para un commit de MERGE (exit=$a1) — owner atascado"; return 1; }
}
test_merge_de_rama_validada_no_exige_marker() { _rm_sandbox _case_merge_no_exige_marker; }

# FALSO NEGATIVO guard: sin MERGE_HEAD, producto staged sigue gateado igual
# (lo fijan test_full_bloquea_en_los_dos_anillos y compañía — este comentario
# existe para que nadie "generalice" la exención más allá del merge).

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

# ════════════════════════════════════════════════════════════════════
# En el repo del HARNESS, tools/ y scripts/ son el PRODUCTO
# ════════════════════════════════════════════════════════════════════
# `NON_PRODUCT` exime el andamio para que tocar un script no pida review en un
# proyecto de app — correcto allí. Pero en el repo del propio harness eximía el
# 100% de su contenido. Un adoptante auditó nuestro historial: 15 commits
# seguidos sin que el gate disparara ni una vez, incluidos el que invirtió la
# política de seguridad de AGENTS.md §6 y el que metió un gate bloqueante al
# Anillo 3. Salió bien por disciplina, no por el mecanismo.
_scope_repo() { # _scope_repo <función> — repo temporal con la lib
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/lib"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$d/tools/lib/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_es_producto() { printf '%s\n' "$1" | grep -qvE "$(. tools/lib/scope.sh; scope_non_product)"; }

_case_harness_trata_su_maquinaria_como_producto() {
  # Sin fuentes de app: este repo ES el harness.
  _es_producto tools/upgrade.sh || { echo "    tools/ sigue exento en el repo del harness: su producto"; return 1; }
  _es_producto scripts/agent-hooks/reviewer-gate.sh || { echo "    scripts/ sigue exento"; return 1; }
  _es_producto AGENTS.md || { echo "    AGENTS.md sigue exento: es la fuente normativa que viaja a los adoptantes"; return 1; }
}
test_en_el_repo_del_harness_su_maquinaria_exige_review() {
  _scope_repo _case_harness_trata_su_maquinaria_como_producto
}

# ── FALSO POSITIVO nº1: en un proyecto de APP nada de esto cambia ───
# Exigir review por tocar un doc o un script del andamio en un proyecto real
# sería ruido, y el ruido acaba en un REVIEWER_OVERRIDE de costumbre que apaga
# el gate de verdad. Esta es la mitad del arreglo que evita la ley del 10%.
_case_app_conserva_la_exencion() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _es_producto tools/upgrade.sh && { echo "    FALSO POSITIVO: en un proyecto de app, tocar tools/ exige review"; return 1; }
  _es_producto AGENTS.md && { echo "    FALSO POSITIVO: en un proyecto de app, tocar AGENTS.md exige review"; return 1; }
  _es_producto ios/App/A.swift || { echo "    dejó de considerar producto el código de la app"; return 1; }
  return 0
}
test_en_un_proyecto_de_app_el_andamio_sigue_exento() {
  _scope_repo _case_app_conserva_la_exencion
}

# ── FALSO POSITIVO nº2: apuntar una lección no puede pedir un reviewer ──
# Los ledgers y la prosa siguen exentos incluso aquí. Si cada entrada de
# lecciones exigiera invocar al reviewer, el bucle de aprendizaje —que es el
# mecanismo por el que la review humana DECRECE— se volvería el más caro.
_case_los_registros_siguen_exentos_en_el_harness() {
  _es_producto docs/process/lessons_learned.md \
    && { echo "    apuntar una lección exige review: el bucle de aprendizaje se vuelve el paso más caro"; return 1; }
  _es_producto tools/findings/ledger.jsonl \
    && { echo "    registrar un finding exige review"; return 1; }
  return 0
}
test_en_el_harness_la_prosa_y_los_ledgers_siguen_exentos() {
  _scope_repo _case_los_registros_siguen_exentos_en_el_harness
}

# ════════════════════════════════════════════════════════════════════
# El OVERRIDE auditado también debe existir en LOS DOS anillos
# ════════════════════════════════════════════════════════════════════
# Misma clase que la regresión que abre este archivo, y cazada en vivo el
# 2026-09-02: AGENTS.md §13 documenta el override como la válvula de emergencia.
# `check-review-marker.sh` la implementa leyendo la variable de SU entorno, así
# que por lefthook (Anillo 1) funciona: ahí el prefijo aplica al proceso de git.
# Pero el Anillo 2 corre en OTRO proceso y solo recibe el comando como TEXTO;
# `reviewer-gate.sh` invocaba el script sin exportar nada, así que por la vía
# del agente el override no tenía ningún efecto.
#
# Lo descubrió un agente al agotar el tope de DOS rondas de §13 con un cambio ya
# verificado: se quedó sin salida legítima porque la única documentada no
# existía. Una válvula anunciada que no abre es peor que no tenerla — §14.4.
#
# NOTA para quien edite esto: los comandos de prueba se ARMAN desde variables a
# propósito. Escritos como literales, el git-guard de este mismo hook los lee
# como un commit de verdad y bloquea el turno que escribe el test.
_anillo1_override() {
  REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="test" \
    bash tools/check-review-marker.sh --staged >/dev/null 2>&1; echo $?
}
_anillo2_override() { # <comando completo tal cual lo escribe el agente>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

_case_override_coherente() {
  local a1 a2 gc pfx
  gc="git commit -m x"
  pfx="REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=urgencia"
  a1="$(_anillo1_override)"
  a2="$(_anillo2_override "$pfx $gc")"
  [ "$a1" = "0" ] || { echo "    Anillo 1 ignoró el override documentado en §13 (exit=$a1)"; return 1; }
  [ "$a2" = "0" ] || { echo "    Anillo 2 ignoró el override: la válvula de §13 NO existe por la vía del agente (exit=$a2)"; return 1; }
  # …y queda AUDITADO. Un override silencioso es un gate apagado sin rastro.
  [ -f .agents/state/markers/override_log.txt ] \
    || { echo "    el override no dejó rastro en override_log.txt: sin auditoría no es un override, es un bypass"; return 1; }
  grep -q 'urgencia' .agents/state/markers/override_log.txt \
    || { echo "    la RAZÓN del override no llegó al log (queda '(SIN RAZÓN)'): la auditoría no dice por qué"; return 1; }
}
test_el_override_auditado_funciona_en_los_dos_anillos() { _rm_sandbox _case_override_coherente; }

# ── FALSO POSITIVO guard: mencionar la variable no la activa ────────
# El guard de git ya aprendió esto: `grep "git commit --no-verify" doc.md` NO es
# un commit. Aquí igual — si bastara con que el texto aparezca en cualquier
# parte del comando, escribir la DOCUMENTACIÓN del override apagaría el gate, y
# un gate que se apaga solo al documentarlo es peor que ninguno (ley del 10%).
_case_override_solo_como_prefijo_del_git() {
  local rc gc
  gc="git commit -m x"
  rc="$(_anillo2_override "grep -n REVIEWER_OVERRIDE=1 docs/x.md; $gc")"
  [ "$rc" = "2" ] || { echo "    MENCIONAR REVIEWER_OVERRIDE=1 en otro segmento apagó el gate (exit=$rc)"; return 1; }
  rc="$(_anillo2_override "git commit -m 'documenta REVIEWER_OVERRIDE=1 en la doc'")"
  [ "$rc" = "2" ] || { echo "    REVIEWER_OVERRIDE=1 dentro del MENSAJE de commit apagó el gate (exit=$rc)"; return 1; }
}
test_el_override_solo_cuenta_como_prefijo_del_comando_git() {
  _rm_sandbox _case_override_solo_como_prefijo_del_git
}

# ── …y sobrevive a envolver la línea ────────────────────────────────
# El caso que lo destapó todo: la razón del override es larga, así que se
# escribe con una continuación de shell y el prefijo acaba en una línea distinta
# del `git commit`. El hook leía por líneas, así que el prefijo se perdía y la
# válvula no abría — exactamente cuando más falta hace. Es el mismo defecto de
# parseo que el bypass de §7 (test_git_guard.sh::…no_evade_no_verify); dos
# síntomas, un arreglo.
_case_override_sobrevive_a_la_continuacion() {
  local rc gc pfx
  gc="git commit -m x"
  pfx="REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=urgencia"
  # OJO con el escapado: en comillas dobles `\n` NO es un salto, se queda como
  # dos caracteres, y el JSON llegaba con el prefijo y el `git` en la MISMA
  # linea — el test pasaba sin probar nada (sobrevivio al mutante que quita la
  # union de continuaciones). Hacen falta 6 barras: el shell las deja en 3, y
  # jq decodifica `\\` + `\n` como barra + salto real.
  rc="$(_anillo2_override "$pfx \\\\\\n  $gc")"
  [ "$rc" = "0" ] || { echo "    el override se pierde al envolver la línea (exit=$rc): la válvula no abre justo cuando se necesita"; return 1; }
}
test_el_override_sobrevive_a_una_continuacion_de_linea() {
  _rm_sandbox _case_override_sobrevive_a_la_continuacion
}
