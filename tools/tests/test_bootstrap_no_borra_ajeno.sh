#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# `bootstrap.sh` no puede borrar lo que no puso
# ════════════════════════════════════════════════════════════════════
# PRD 0008 fase 2. El 2026-09-03 un sub-agente lo ejecutó contra el repo del
# template y borró `android/AGENTS.md`, `web/AGENTS.md` y reescribió
# `tools/preset`. La fase 3a ya deniega invocarlo desde un agente, pero ese deny
# es por PREFIJO: no cubre `cd scripts && bash bootstrap.sh` ni un script que lo
# llame por dentro. Esta es la otra mitad.
#
# Decisión del owner (OQ-5, 2026-09-03): **no se ejecuta destrucción por
# respuesta a un prompt.** bootstrap PROPONE el borrado y no lo hace. Eso
# elimina de raíz la heurística "¿este ios/ es del template o del adoptante?" y
# sus falsos positivos — nivel 0 (imposibilitar) en vez de nivel 2 (detectar).
#
# El radio importa y el design-review lo estableció: como `install-harness.sh`
# clasifica `ios android web` entre las rutas que NUNCA copia, en una adopción
# Caso B cualquiera de esos directorios que bootstrap encuentre es del
# adoptante. Son los cuatro elementos del bucle, no solo `backend`.

_bs_proyecto() { # <función> — un proyecto adoptante con código real
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts" "$d/backend/src" "$d/ios/MiApp" "$d/tools"
  cp "$PROJECT_ROOT/scripts/bootstrap.sh" "$d/scripts/"
  printf 'app.listen(3000)\n'        > "$d/backend/src/server.js"
  printf 'let x = 1\n'               > "$d/ios/MiApp/App.swift"
  printf '# <PROJECT>\n'             > "$d/README.md"
  printf 'full\n'                    > "$d/tools/preset"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    # El discriminador de OQ-8: un clon o adoptante SIEMPRE tiene un remote
    # llamado `template` cuando llega a bootstrap — lo crea el Caso A
    # renombrando y el Caso B añadiéndolo, los dos ANTES de este paso.
    git remote add template https://example.invalid/plantilla.git 2>/dev/null
    PROY="$d" "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_bs_correr() { # <respuesta-de-plataformas> → salida del script
  printf 'mi-proyecto\n%s\nfull\n' "$1" | bash scripts/bootstrap.sh 2>&1
}

# ── 1. No borra NADA: propone ───────────────────────────────────────
# El golden del PRD. `backend/` e `ios/` tienen código real del adoptante y no
# se listan; antes desaparecían con su contenido dentro.
_case_no_borra_nada() {
  _bs_correr "web" >/dev/null 2>&1 || true
  [ -f backend/src/server.js ] || { echo "    borró backend/ CON su código dentro"; return 1; }
  [ -f ios/MiApp/App.swift ]   || { echo "    borró ios/ CON su código dentro"; return 1; }
}
test_no_borra_los_directorios_no_listados() { _bs_proyecto _case_no_borra_nada; }

# ── 2. …pero lo DICE, con el comando exacto ─────────────────────────
# Guard del falso negativo: un bootstrap que no borra porque no hace nada
# pasaría el test de arriba. Y si no imprime qué haría, el adoptante que sí
# quiere limpiar se queda sin saber cómo.
_case_propone_el_comando() {
  local out; out="$(_bs_correr "web")"
  printf '%s' "$out" | grep -q 'backend' || {
    echo "    no mencionó backend/ como candidato a quitar:"
    printf '%s\n' "$out" | tail -6 | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'rm -rf' || {
    echo "    no imprimió el comando que el adoptante tendría que correr"; return 1; }
}
test_propone_el_comando_en_vez_de_ejecutarlo() { _bs_proyecto _case_propone_el_comando; }

# ── 3. Abortar si apunta al template (OQ-8) ─────────────────────────
# El incidente del 2026-09-03, hecho test. El discriminador es el remote
# `template`: el repo del template tiene solo `origin`, y las dos rutas de
# adopción crean ese remote ANTES de bootstrapear.
_case_aborta_en_el_template() {
  git remote remove template 2>/dev/null   # ahora parece el template
  local out rc
  out="$(_bs_correr "web")"; rc=$?
  [ "$rc" != "0" ] || {
    echo "    NO abortó al correr sobre algo que parece el propio template (exit 0)"
    printf '%s\n' "$out" | tail -4 | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -qi 'template' || {
    echo "    abortó pero sin explicar por qué; el adoptante no sabe qué hacer"; return 1; }
  # Y no mutó nada antes de abortar.
  grep -q '<PROJECT>' README.md || { echo "    reemplazó placeholders ANTES de la precondición"; return 1; }
}
test_aborta_si_no_hay_remote_template() { _bs_proyecto _case_aborta_en_el_template; }

# ── 4. El sed solo toca lo que git considera del proyecto (OQ-11) ───
# Antes: `grep -rlZ --exclude-dir=.git … .` recorría node_modules/, .venv/ y
# vendor/. La respuesta no es una lista de exclusiones que mantener, sino
# preguntarle a git: --cached (lo que rastrea) + --others --exclude-standard
# (lo recién copiado y sin commitear, respetando el .gitignore del adoptante).
_case_sed_respeta_gitignore() {
  printf 'node_modules/\n' > .gitignore
  mkdir -p node_modules/dep
  printf 'const x = "<PROJECT>"\n' > node_modules/dep/index.js
  _bs_correr "ios android web backend" >/dev/null 2>&1 || true
  grep -q '<PROJECT>' node_modules/dep/index.js || {
    echo "    reescribió un fichero dentro de node_modules/, que el .gitignore del"
    echo "    adoptante excluye — el sed sigue recorriendo lo que no es suyo"; return 1; }
  grep -q 'Mi-proyecto\|MiProyecto' README.md || {
    echo "    …pero tampoco reemplazó el placeholder en README.md, que SÍ es del proyecto:"
    sed -n '1p' README.md | sed 's/^/      /'; return 1; }
}
test_el_sed_respeta_el_gitignore_del_adoptante() { _bs_proyecto _case_sed_respeta_gitignore; }
