#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El carril se DERIVA del diff, y la más severa gana
# ════════════════════════════════════════════════════════════════════
# PRD 0011 fase 1. El workflow cobraba lo mismo por añadir un string que por
# reescribir el motor: suite completa, una revisión y doce gates. Este
# clasificador es lo que permite cobrar en proporción.
#
# Fase 1 a propósito NO cambia nada: deriva e imprime. Decidir qué corre en cada
# carril sin haber medido antes cuántos cambios caen en cada uno sería elegir a
# ciegas — y elegir a ciegas es como se llegó aquí.

_c_sandbox() { # <función> — repo de juguete con el clasificador dentro
  local d; d="$(mktemp -d)" A=add C=commit
  mkdir -p "$d/tools" "$d/docs/process" "$d/scripts/agent-hooks" "$d/ci"
  cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # El fichero base se COMMITEA: dejarlo staged contaminaba todos los casos
    # con un archivo de raíz que cae en `normal`, y dos tests fallaban por el
    # montaje en vez de por lo que probaban.
    echo base > base.txt
    git "$A" base.txt
    git "$C" -qm base 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_c()  { bash tools/carril.sh 2>&1; }
_stage() { local A=add f; for f in "$@"; do mkdir -p "$(dirname "$f")"; echo x >> "$f"; git "$A" "$f"; done; }

# ── 1. Nada que se ejecute → ligero ─────────────────────────────────
_case_docs_es_ligero() {
  _stage docs/process/algo.md
  _c | grep -q 'carril=ligero' || { echo "    un cambio solo de docs no salió ligero: $(_c)"; return 1; }
}
test_solo_docs_es_carril_ligero() { _c_sandbox _case_docs_es_ligero; }

# ── 2. Código que se ejecuta → normal ───────────────────────────────
_case_detector_es_normal() {
  _stage tools/check-algo.sh
  _c | grep -q 'carril=normal' || { echo "    un detector no salió normal: $(_c)"; return 1; }
}
test_un_detector_es_carril_normal() { _c_sandbox _case_detector_es_normal; }

# ── 3. La maquinaria que decide qué se verifica → estructural ───────
# La frontera no es arbitraria: un detector equivocado da un resultado malo,
# pero tocar la maquinaria puede hacer que NINGÚN detector corra, y eso no lo
# caza ningún test del propio detector.
_case_lefthook_es_estructural() {
  _stage lefthook.yml
  _c | grep -q 'carril=estructural' || { echo "    lefthook.yml no salió estructural: $(_c)"; return 1; }
}
test_lefthook_es_carril_estructural() { _c_sandbox _case_lefthook_es_estructural; }

# ── 4. La MÁS SEVERA gana ───────────────────────────────────────────
# Si un solo fichero es estructural, el cambio entero lo es. Al revés —tomar el
# más leve, o el mayoritario— un cambio estructural escondido entre veinte de
# docs se saltaría la suite, que es el único fallo grave que este clasificador
# puede tener.
_case_mezcla_gana_la_severa() {
  _stage docs/process/uno.md docs/process/dos.md lefthook.yml
  _c | grep -q 'carril=estructural' || {
    echo "    mezcla de docs + lefthook no salió estructural: $(_c)"
    echo "    Un estructural escondido entre docs se saltaría la suite."
    return 1; }
}
test_la_mezcla_toma_el_carril_mas_severo() { _c_sandbox _case_mezcla_gana_la_severa; }

# ── 5. AGENTS.md es .md, y aun así es estructural ───────────────────
# Es la fuente canónica de las reglas: cambiarla cambia lo que TODOS los agentes
# hacen. Que case con el patrón de ligero no puede ganarle a que case con el de
# estructural.
_case_agents_md_es_estructural() {
  _stage AGENTS.md
  _c | grep -q 'carril=estructural' || { echo "    AGENTS.md salió como doc cualquiera: $(_c)"; return 1; }
}
test_agents_md_es_estructural_pese_a_ser_md() { _c_sandbox _case_agents_md_es_estructural; }

# ── 6. Lo desconocido cae en normal, no en ligero ───────────────────
# El default tiene que ser el SEGURO. Un fichero que nadie previó no puede
# colarse por el carril que no ejecuta nada.
_case_desconocido_es_normal() {
  _stage src/algo.rs
  _c | grep -q 'carril=normal' || { echo "    un fichero no previsto no cayó en normal: $(_c)"; return 1; }
}
test_lo_no_previsto_cae_en_normal() { _c_sandbox _case_desconocido_es_normal; }

# ── 7. Sin nada staged se DICE, no se inventa un carril ─────────────
_case_sin_nada_staged() {
  local out; out="$(_c)"
  printf '%s' "$out" | grep -q 'carril=ninguno' || {
    echo "    sin nada staged se inventó un carril: $out"; return 1; }
}
test_sin_nada_staged_no_hay_carril() { _c_sandbox _case_sin_nada_staged; }

# ── 8. El conf manda: si se le añade una fila, cambia el veredicto ──
# Sin esto, los patrones podrían estar hardcodeados en el script y el conf sería
# decorado — el mismo drift que ya costó caro en la matriz de skills.
_case_el_conf_manda() {
  _stage src/nuevo.py
  _c | grep -q 'carril=normal' || { echo "    precondición: debía ser normal"; return 1; }
  printf 'estructural|src/nuevo.py\n' >> tools/carril.conf
  _c | grep -q 'carril=estructural' || {
    echo "    añadir una fila al conf NO cambió el veredicto: $(_c)"
    echo "    Entonces los patrones viven en el script y el conf es decorado."
    return 1; }
}
test_el_conf_es_la_fuente_unica() { _c_sandbox _case_el_conf_manda; }

# ── 9. Sin git no puede mirar, y lo dice (§14.3) ────────────────────
_case_sin_git_no_pudo_mirar() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/carril.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/carril.conf" "$d/tools/"
  local rc; ( cd "$d" && bash tools/carril.sh >/dev/null 2>&1 ); rc=$?
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    fuera de un repo git no devolvió 3 sino $rc"; return 1; }
}
test_fuera_de_un_repo_git_devuelve_3() { _case_sin_git_no_pudo_mirar; }
