#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El instalador NO puede destruir la identidad del proyecto que adopta
# ════════════════════════════════════════════════════════════════════
# `docs/ADOPTION.md` §1 Caso B —el camino NORMAL, un proyecto que ya existe—
# documentaba `cp -R /tmp/awt/. .` sobre la raíz del adoptante. Reproducido el
# 2026-09-02 sobre un proyecto de juguete: de 6 a 27 entradas en la raíz, y
# README.md, LICENSE, CODEOWNERS y .editorconfig **PISADOS** por los del
# template. El código fuente no se tocaba, así que el daño era de identidad y
# configuración — pero un LICENSE sustituido en silencio es un problema legal,
# no cosmético.
#
# La única mitigación era la frase "revisa el diff antes de commitear" en la
# propia guía: prosa, no mecanismo. Estos tests son el mecanismo.
#
# El inventario de qué es maquinaria NO se duplica: sale de `SYNC_PATHS` /
# `SYNC_GLOBS` de `tools/upgrade.sh`, que ya lo sabía para los upgrades. Una
# regla implementada dos veces diverge, y aquí divergir significa que instalar
# y actualizar traigan cosas distintas.

_ih_proyecto() { # <función> — un proyecto AJENO que ya existe, con su identidad
  local d; d="$(mktemp -d)"
  mkdir -p "$d/proy/ios/MiApp" "$d/proy/docs"
  printf '# Mi App\nLlevo tres años con esto.\n'   > "$d/proy/README.md"
  printf 'MIT License\n\nCopyright (c) 2023 Mi Empresa\n' > "$d/proy/LICENSE"
  printf '* @mi-equipo\n'                          > "$d/proy/CODEOWNERS"
  printf 'root = true\nindent_size = 2\n'          > "$d/proy/.editorconfig"
  printf 'let x = 1\n'                             > "$d/proy/ios/MiApp/App.swift"
  printf '# Mis docs\n'                            > "$d/proy/docs/README.md"
  ( cd "$d/proy" || exit 1; git init -q . 2>/dev/null; PROY="$d/proy" "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_ih_instalar() { bash "$PROJECT_ROOT/scripts/install-harness.sh" "$PROY" 2>&1; }

# ── 1. La identidad del proyecto es INTOCABLE ───────────────────────
# El hallazgo entero, hecho test. Estos cuatro ficheros dicen de quién es el
# proyecto; el harness no tiene nada que opinar sobre ellos.
_case_no_pisa_la_identidad() {
  local antes_readme antes_lic antes_owners antes_edit
  antes_readme="$(cat README.md)"; antes_lic="$(cat LICENSE)"
  antes_owners="$(cat CODEOWNERS)"; antes_edit="$(cat .editorconfig)"
  _ih_instalar >/dev/null 2>&1
  [ "$(cat README.md)"     = "$antes_readme" ] || { echo "    el instalador PISÓ el README.md del proyecto"; return 1; }
  [ "$(cat LICENSE)"       = "$antes_lic"    ] || { echo "    el instalador PISÓ el LICENSE del proyecto (esto es un problema legal, no cosmético)"; return 1; }
  [ "$(cat CODEOWNERS)"    = "$antes_owners" ] || { echo "    el instalador PISÓ el CODEOWNERS del proyecto"; return 1; }
  [ "$(cat .editorconfig)" = "$antes_edit"   ] || { echo "    el instalador PISÓ el .editorconfig del proyecto"; return 1; }
}
test_no_pisa_la_identidad_del_proyecto() { _ih_proyecto _case_no_pisa_la_identidad; }

# ── 2. No deja ficheros del harness dentro del código ajeno ─────────
# El template trae ios/AGENTS.md, android/AGENTS.md y web/AGENTS.md como
# EJEMPLOS. En un proyecto con un ios/ real caían dentro de su código; en uno
# backend-only, creaban ios/ android/ web/ de la nada.
_case_no_contamina_el_codigo() {
  _ih_instalar >/dev/null 2>&1
  [ ! -f ios/AGENTS.md ] || { echo "    dejó ios/AGENTS.md dentro del directorio de código del proyecto"; return 1; }
  [ ! -d android ] || { echo "    creó android/ en un proyecto que no lo tenía"; return 1; }
  [ ! -d web ]     || { echo "    creó web/ en un proyecto que no lo tenía"; return 1; }
  [ -f ios/MiApp/App.swift ] || { echo "    borró código del proyecto"; return 1; }
}
test_no_deja_ficheros_del_harness_dentro_del_codigo() { _ih_proyecto _case_no_contamina_el_codigo; }

# ── 3. …pero SÍ instala el harness, o no sirve de nada ──────────────
# Guard del falso negativo: un instalador que no pisa nada porque no copia
# nada pasaría los dos tests de arriba.
_case_si_instala_la_maquinaria() {
  _ih_instalar >/dev/null 2>&1
  # Los SUBPATHS de .claude, no solo el directorio. La primera versión pedía
  # `.claude` y ya está: el review demostró con un mutante —quitar
  # `.claude/rules` de la lista de clientes— que los 6 tests seguían en verde.
  # Un test que comprueba el contenedor no comprueba el contenido.
  local falta=""
  for p in tools/check-layers.sh tools/tests/run-tests.sh scripts/agent-hooks/reviewer-gate.sh \
           ci lefthook.yml AGENTS.md \
           .claude/agents .claude/commands .claude/rules .claude/settings.json \
           .cursor .codex .github; do
    [ -e "$p" ] || falta="$falta $p"
  done
  [ -z "$falta" ] || { echo "    el instalador NO trajo:$falta"; return 1; }
}
test_si_instala_la_maquinaria_del_harness() { _ih_proyecto _case_si_instala_la_maquinaria; }

# ── 4. Una SEMILLA existente se respeta, una ausente se pone ────────
# AGENTS.md, las skills y los .conf son semillas: el template los da para
# empezar y a partir de ahí son del adoptante. Pisarlos en una reinstalación
# borraría sus reglas.
_case_semilla_existente_se_respeta() {
  printf '# MIS reglas, ya adaptadas\n' > AGENTS.md
  _ih_instalar >/dev/null 2>&1
  grep -q 'MIS reglas' AGENTS.md || { echo "    pisó un AGENTS.md que el proyecto ya tenía adaptado"; return 1; }
}
test_una_semilla_existente_no_se_pisa() { _ih_proyecto _case_semilla_existente_se_respeta; }

# ── 5. Lo que respeta lo DICE ───────────────────────────────────────
# Saltarse un fichero en silencio deja al adoptante con una versión vieja y sin
# saberlo. El mismo pecado que el harness persigue: no basta con no hacer daño,
# hay que declarar lo que se decidió.
_case_declara_lo_que_respeto() {
  printf '# MIS reglas\n' > AGENTS.md
  local out; out="$(_ih_instalar)"
  printf '%s' "$out" | grep -q 'AGENTS.md' || {
    echo "    respetó AGENTS.md pero no lo dijo — el adoptante no sabe que su copia es la vieja"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_declara_las_semillas_que_respeto() { _ih_proyecto _case_declara_lo_que_respeto; }

# ── 6. Idempotente ──────────────────────────────────────────────────
# Reinstalar es lo que hace un adoptante que no está seguro de si funcionó. Si
# la segunda pasada cambia algo, el instalador tiene estado oculto.
_case_idempotente() {
  _ih_instalar >/dev/null 2>&1
  local h1 h2
  h1="$(find . -path ./.git -prune -o -type f -print 2>/dev/null | sort | xargs shasum 2>/dev/null | shasum | awk '{print $1}')"
  _ih_instalar >/dev/null 2>&1
  h2="$(find . -path ./.git -prune -o -type f -print 2>/dev/null | sort | xargs shasum 2>/dev/null | shasum | awk '{print $1}')"
  [ "$h1" = "$h2" ] || { echo "    la segunda instalación cambió el árbol: hay estado oculto"; return 1; }
}
test_instalar_dos_veces_no_cambia_nada() { _ih_proyecto _case_idempotente; }

# ── 7. El symlink de skills, sin el que Claude Code no carga NADA ───
# Hallazgo RED del review, reproducido instalando en un directorio vacío y
# corriendo validate-harness sobre el resultado: "⚠️ .claude/skills ausente —
# skills/agents no cargarán ahí". Sin ese enlace, el hook `skill-reminder` se
# queda sin nada que exigir y la matriz §11 deja de existir en la práctica: el
# adoptante cree tener el harness entero y le falta el nivel que obliga a leer
# antes de editar.
#
# No se comprueba solo que el path exista: se comprueba que RESUELVA a las
# skills. Un enlace roto existe y no sirve.
_case_instala_el_enlace_de_skills() {
  _ih_instalar >/dev/null 2>&1
  [ -e .claude/skills ] || { echo "    no instaló .claude/skills — Claude Code no cargará ninguna skill y skill-reminder se queda sin nada que exigir"; return 1; }
  [ -d .claude/skills ] || { echo "    .claude/skills existe pero no resuelve a un directorio (¿enlace roto?)"; return 1; }
  local _hay=0; for _s in .claude/skills/*; do [ -e "$_s" ] && { _hay=1; break; }; done
  [ "$_hay" = "1" ] || { echo "    .claude/skills resuelve pero está VACÍO"; return 1; }
}
test_instala_el_enlace_de_skills() { _ih_proyecto _case_instala_el_enlace_de_skills; }

# ── 8. Ninguna ruta puede estar en DOS clases ───────────────────────
# El otro RED del review. `backlog/_template.md` estaba como MAQUINARIA (vía
# SYNC_PATHS) y como SEMILLA a la vez; ganaba la maquinaria porque su bucle
# corre antes, y el informe lo declaraba "🔒 ya existía, es tuyo" sobre un
# fichero que el propio script acababa de crear. Con contenido real del
# adoptante era peor: se lo sobrescribía mientras el mensaje decía lo
# contrario. Un informe que miente es peor que no tenerlo.
_case_ninguna_ruta_en_dos_clases() {
  local out; out="$(_ih_instalar)"
  # En un proyecto donde NADA del harness existía, el informe no puede decir
  # que respetó algo: todo lo que hay lo puso él.
  printf '%s' "$out" | grep -q 'Ya existían y NO se tocaron' && {
    echo "    en una instalación LIMPIA el informe dice haber respetado ficheros del adoptante:"
    printf '%s\n' "$out" | sed -n '/Ya existían/,+4p' | sed 's/^/      /'
    echo "    Eso solo puede pasar si una ruta está en dos clases y la primera la creó."
    return 1; }
  return 0
}
test_ninguna_ruta_esta_en_dos_clases() { _ih_proyecto _case_ninguna_ruta_en_dos_clases; }

# ── 9. Un fallo de copia NO puede reportarse como éxito ─────────────
# Hallazgo bloqueante de la ronda 2, con su repro exacto: si en el destino ya
# existe un ARCHIVO donde el harness quiere un DIRECTORIO (un `scripts` de una
# línea, por ejemplo), `cp` falla, el script tragaba el error con `2>/dev/null`,
# incrementaba el contador igual y decía "✅ maquinaria instalada (68 rutas)"
# con exit 0 — mandando al adoptante a `bash scripts/bootstrap.sh`, que no
# existe. Es el mismo pecado que este instalador combate, cometido por la vía
# de I/O en vez de la de clasificación.
_case_un_fallo_de_copia_no_es_exito() {
  : > scripts            # un ARCHIVO donde va el directorio de la maquinaria
  local out rc
  out="$(_ih_instalar)"; rc=$?
  [ "$rc" != "0" ] || {
    echo "    con scripts/ imposible de crear, el instalador salió 0 (éxito):"
    printf '%s\n' "$out" | tail -4 | sed 's/^/      /'
    echo "    El adoptante se va al bootstrap con la maquinaria a medias."
    return 1; }
  printf '%s' "$out" | grep -q 'scripts' || {
    echo "    falló pero no nombró la ruta que no pudo copiar"; return 1; }
}
test_un_fallo_de_copia_no_se_reporta_como_exito() {
  _ih_proyecto _case_un_fallo_de_copia_no_es_exito
}
