#!/usr/bin/env bash
# La matriz path→skill vivía en CINCO sitios y "nada se duplica" era mentira.
# Ahora la FUENTE ÚNICA es tools/skill-matrix.conf (skill-reminder la lee en
# runtime). Estos tests fijan: (1) toda ref citada EXISTE — una matriz que
# exige leer archivos inexistentes bloquea el trabajo para siempre; (2) el
# hook consume el conf de verdad; (3) sin conf, el fallback de fábrica sigue.

test_toda_ref_de_la_matriz_existe() {
  [ -f tools/skill-matrix.conf ] || { echo "    tools/skill-matrix.conf no existe"; return 1; }
  local glob refs r bad=0 _old
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { echo "    ref inexistente: $r (glob '$glob')"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}

_smx_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read" "$d/src"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_conf_gobierna_el_gate() {
  # Matriz mínima propia: SOLO los .py exigen leer una ref.
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  mkdir -p docs; echo regla > docs/regla.md
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el conf no gobernó el gate (exit $rc, esperaba 2)"; return 1; }
  # …y con el marker de lectura presente, pasa.
  touch .agents/state/skills-read/docs__regla.md.read
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    con marker presente siguió bloqueando (exit $rc)"; return 1; }
}
test_skill_reminder_lee_el_conf() { _smx_sandbox _case_conf_gobierna_el_gate; }

# FALSO POSITIVO guard: un path que NO casa ningún glob no puede bloquearse.
_case_path_fuera_de_matriz_pasa() {
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/main.go"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    bloqueó un path fuera de la matriz (exit $rc)"; return 1; }
}
test_path_fuera_de_la_matriz_no_bloquea() { _smx_sandbox _case_path_fuera_de_matriz_pasa; }

# ── consistencia matriz ↔ track-reads (bug real, cazado EN VIVO) ────
# Toda ref que la matriz EXIGE leer debe ser REGISTRABLE por track-reads.
# Si no, el flujo es un bucle infinito: el agente lee la skill (obedece),
# el marker no se crea, skill-reminder bloquea, el agente re-lee… Lo cazó
# el agente del primer proyecto real depurando el hook — platforms/*.md
# estaba en la matriz pero no en el filtro del tracker.
_case_refs_registrables() {
  cp "$PROJECT_ROOT/tools/skill-matrix.conf" tools/skill-matrix.conf
  local glob refs r _old bad=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"; [ -z "$r" ] && continue
      rm -rf .agents/state/skills-read
      printf '{"tool_name":"Read","tool_input":{"file_path":"%s/%s"}}' "$PWD" "$r" \
        | bash scripts/agent-hooks/track-reads.sh >/dev/null 2>&1
      [ -f ".agents/state/skills-read/${r//\//__}.read" ] \
        || { echo "    ref '$r' NO registrable por track-reads → skill-reminder bloquearía para siempre"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}
test_toda_ref_es_registrable_por_track_reads() { _smx_sandbox _case_refs_registrables; }

_case_sin_conf_usa_fallback() {
  rm -f tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/PagoLogic.swift"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    sin conf, el fallback de fábrica no gateó (exit $rc)"; return 1; }
}
test_sin_conf_cae_al_fallback_de_fabrica() { _smx_sandbox _case_sin_conf_usa_fallback; }

# ════════════════════════════════════════════════════════════════════
# tabla §11 ↔ conf: el detector que la cabecera decía tener y no tenía
# ════════════════════════════════════════════════════════════════════
# `skill-matrix.conf` afirmaba "la divergencia la caza test_skill_matrix.sh".
# Falso: este archivo comprobaba que las refs EXISTAN y sean registrables,
# nunca comparó tabla contra conf. Una afirmación de cobertura sin detector
# detrás es peor que ninguna: se lee, se cree, y nadie vuelve a mirar.
# (f-4d2b0e51, reportado desde el proyecto adoptante.)

test_la_tabla_y_el_conf_de_ESTE_repo_coinciden() {
  # SIN el fixture: este mira el repo real, y con `SKILL_MATRIX_DOC` apuntando a
  # un fixture inexistente pasaba en vacío — el detector imprimía su resumen en
  # ceros aunque no hubiera podido comparar nada.
  local out; out="$(bash tools/check-skill-matrix-doc.sh 2>&1)"
  case "$out" in *"no puedo comparar"*) : ;;
    *"solo_en_doc=0 solo_en_conf=0"*) return 0 ;; esac
  echo "    la vista humana de la matriz y tools/skill-matrix.conf divergen:"
  printf '%s\n' "$out" | sed 's/^/    /'
  return 1
}

_smd_sandbox() { # doc + conf de juguete, sin tocar el repo real
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-skill-matrix-doc.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
# El fixture escribe la vista humana donde el detector la busca. Se resuelve por
# `SKILL_MATRIX_DOC` en vez de codificar la ruta: cuando la tabla se mudó de
# `AGENTS.md` a `agents-rationale.md`, estos tres tests empezaron a montar el
# fixture en un sitio y el detector a mirar otro — y el resultado no fue un fallo
# claro sino un exit 3 ("no puedo comparar") que se leía como si el caso hubiera
# pasado. Un fixture atado a una ruta literal caduca en silencio.
_SMD_DOC="${SKILL_MATRIX_DOC:-agents-doc.md}"
_smd_doc() { mkdir -p "$(dirname "$_SMD_DOC")"; printf '%s\n' "$1" > "$_SMD_DOC"; }
_smd_conf() { printf '%s\n' "$1" > tools/skill-matrix.conf; }

_case_doc_promete_de_mas() {
  # El sentido GRAVE: el documento exige una lectura que el gate no pide.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift` | `architecture/SKILL.md` + `platforms/ios.md` |'
  _smd_conf '*View*.swift|.agents/skills/architecture/SKILL.md'
  local out; out="$(SKILL_MATRIX_DOC="$_SMD_DOC" bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    una defensa anunciada y NO implementada pasó (exit $rc)"; return 1; }
  case "$out" in *"platforms/ios.md"*) return 0 ;; esac
  echo "    no nombró la ref que sobra en el doc: $out"; return 1
}
test_ref_solo_en_la_tabla_es_defensa_fingida() { _smd_sandbox _case_doc_promete_de_mas; }

_case_conf_bloquea_sin_anunciarlo() {
  # El otro sentido: el gate bloquea por algo que la doc no menciona. Menos
  # grave (falla cerrado), pero el agente se choca con un muro invisible.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift` | `architecture/SKILL.md` |'
  _smd_conf '*View*.swift|.agents/skills/architecture/SKILL.md,.agents/skills/security/SKILL.md'
  local out; out="$(SKILL_MATRIX_DOC="$_SMD_DOC" bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    un gate no anunciado pasó (exit $rc)"; return 1; }
  case "$out" in *"security/SKILL.md"*) return 0 ;; esac
  echo "    no nombró la ref que falta en la tabla: $out"; return 1
}
test_ref_solo_en_el_conf_es_muro_invisible() { _smd_sandbox _case_conf_bloquea_sin_anunciarlo; }

_case_el_glob_de_la_columna_1_no_es_una_ref() {
  # FALSO POSITIVO que habría matado al detector el primer día: la columna de
  # PATHS también trae tokens que acaban en `.md` — `docs/process/prds/[0-9]*.md`
  # es un glob, no una lectura obligatoria. Leer la fila entera lo contaría como
  # ref fantasma y el detector nacería en rojo sin motivo.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `docs/process/prds/[0-9]*.md` | `process/references/prd-lifecycle.md` |'
  _smd_conf 'docs/process/prds/[0-9]*.md|.agents/skills/process/references/prd-lifecycle.md'
  local out; out="$(SKILL_MATRIX_DOC="$_SMD_DOC" bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: contó el glob de la columna 1 como ref ($out)"; return 1; }
}
test_un_glob_que_acaba_en_md_no_cuenta_como_ref() {
  _smd_sandbox _case_el_glob_de_la_columna_1_no_es_una_ref
}

_case_sin_archivos_avisa_no_aprueba() {
  # §14.3: "no pude mirar" (3) nunca puede confundirse con "está limpio" (0).
  _smd_conf '*View*.swift|x.md'
  rm -f "$_SMD_DOC"
  SKILL_MATRIX_DOC="$_SMD_DOC" bash tools/check-skill-matrix-doc.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    sin el doc no devolvió 3 (fallo del detector), sino $?"; return 1; }
}
test_sin_los_archivos_devuelve_3_no_0() { _smd_sandbox _case_sin_archivos_avisa_no_aprueba; }

# ── El detector sigue a la tabla, o compara contra el vacío ─────────
# La vista humana de la matriz salió de `AGENTS.md` a `agents-rationale.md §11`
# (fase 7 del PRD 0009): ese fichero entra en el contexto de cada turno, y la
# tabla no hace falta tenerla delante porque `skill-reminder` bloquea nombrando
# las refs que faltan. Al moverla, el detector se quedaba apuntando al fichero
# viejo — y ahí ya no hay tabla, así que denunciaba un drift inexistente y
# habría acabado desactivado (§14.2). Lo cazó él mismo con exit 1.
test_el_detector_de_la_matriz_apunta_donde_vive_la_tabla() {
  local doc
  doc="$(grep -oE 'SKILL_MATRIX_DOC:-[^}"]+' "$PROJECT_ROOT/tools/check-skill-matrix-doc.sh" \
         | head -1 | sed 's/.*:-//')"
  [ -n "$doc" ] || { echo "  no encontré el DOC por defecto del detector"; return 1; }
  [ -f "$PROJECT_ROOT/$doc" ] || { echo "  el detector apunta a '$doc', que no existe"; return 1; }
  grep -qE '^\| .*SKILL\.md' "$PROJECT_ROOT/$doc" || {
    echo "  '$doc' no contiene ninguna fila de la matriz."
    echo "  El detector compararía el conf contra una tabla vacía y denunciaría"
    echo "  un drift que no existe — un detector con falsos positivos se desactiva."
    return 1; }
  # y que no vuelva a haber DOS tablas divergiendo
  grep -qE '^\| .*SKILL\.md' "$PROJECT_ROOT/AGENTS.md" && {
    echo "  la tabla volvió a AGENTS.md: ahora hay dos, y solo una se compara"
    return 1; }
  return 0
}

# ── "No pude mirar" no puede parecerse a "todo limpio" ──────────────
# El detector avisaba citando §14.3 y una línea después imprimía
# `solo_en_doc=0 solo_en_conf=0`, que es literalmente su salida de éxito. No es
# teórico: hizo pasar en vacío al test que cree comprobar el repo real, y lo
# descubrí porque un fixture mal apuntado dio verde.
test_sin_doc_el_resumen_no_se_parece_a_uno_limpio() {
  local out rc
  out="$(cd "$PROJECT_ROOT" && SKILL_MATRIX_DOC=no-existe-jamas.md \
         bash tools/check-skill-matrix-doc.sh 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "  sin doc no salió 3 sino $rc"; return 1; }
  printf '%s' "$out" | grep -q 'solo_en_doc=0 solo_en_conf=0' && {
    echo "  sin poder mirar imprime su MISMA línea de éxito:"
    printf '%s\n' "$out" | grep MATRIX_DOC_SUMMARY | sed 's/^/    /'
    echo "  Quien parsee esa línea leerá 'limpio' donde hubo un gate ciego (§14.3)."
    return 1; }
  printf '%s' "$out" | grep -q 'MATRIX_DOC_SUMMARY' || {
    echo "  dejó de imprimir su línea de contrato: quien la parsee no verá nada"
    return 1; }
  return 0
}

# ── Las tres fuentes operativas nombran el MISMO fichero ────────────
# Al mover la tabla, el detector la siguió pero su propio comentario de cabecera
# y el del conf se quedaron diciendo "AGENTS.md §11". No rompía ningún gate —son
# comentarios— pero eran instrucciones ACTIVAS: quien siguiera el conf al añadir
# una fila editaría un fichero que ya no tiene tabla, y el detector fallaría
# comparando contra el correcto mientras el trabajo se hizo en el equivocado.
# Lo cazó el review, no la suite.
test_las_fuentes_operativas_nombran_el_mismo_doc() {
  local doc base
  doc="$(grep -oE 'SKILL_MATRIX_DOC:-[^}"]+' "$PROJECT_ROOT/tools/check-skill-matrix-doc.sh" \
         | head -1 | sed 's/.*:-//')"
  [ -n "$doc" ] || { echo "  no encontré el DOC por defecto"; return 1; }
  base="$(basename "$doc")"
  local f
  for f in tools/check-skill-matrix-doc.sh tools/skill-matrix.conf; do
    grep -q "$base" "$PROJECT_ROOT/$f" || {
      echo "  $f no nombra '$base', que es donde el detector busca la tabla."
      echo "  Es una instrucción activa: quien la siga editará el fichero equivocado."
      return 1; }
    grep -qE 'tabla de AGENTS\.md §11|tabla humana de AGENTS' "$PROJECT_ROOT/$f" && {
      echo "  $f sigue mandando a la tabla de AGENTS.md, que ya no la tiene"
      return 1; }
  done
  return 0
}
