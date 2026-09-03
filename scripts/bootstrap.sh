#!/usr/bin/env bash
# bootstrap.sh — deja el cascarón listo para TU proyecto.
#   1. Reemplaza el placeholder <PROJECT>/<project> por tu nombre real.
#   2. (Opcional) elimina las plataformas que no uses.
#   3. Crea el symlink CLAUDE.md → AGENTS.md si prefieres esa vía.
#
# Idempotente y conservador: **no borra nada**. Propone.
#
# Decia "pregunta antes de borrar nada" y era falso: borraba sin preguntar. El
# 2026-09-03 un sub-agente lo ejecuto contra el repo del template y se llevo por
# delante android/AGENTS.md y web/AGENTS.md. Decision del owner (PRD 0008, OQ-5):
# no se ejecuta destruccion por respuesta a un prompt. Ahora IMPRIME el comando.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "═══ Bootstrap del Agentic Workflow Template ═══"

# ── Precondicion: ¿estoy en el TEMPLATE? (PRD 0008, OQ-8) ───────────
# El repo del template tiene solo `origin`. Las DOS rutas de adopcion crean un
# remote llamado `template` ANTES de llegar aqui: el Caso A renombrando
# (`git remote rename origin template`) y el Caso B anadiendolo. Asi que su
# ausencia significa "estoy en el template, o me salte el paso documentado", y
# las dos llevan al mismo sitio: abortar.
#
# NO se compara la ruta contra la del template, que fue la primera idea: ese
# truco funciona en install-harness.sh porque alli hay origen Y destino, y aqui
# solo hay uno — la comparacion analoga seria siempre verdadera y abortaria
# tambien en el Caso A, que es el unico uso legitimo del script.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "❌ bootstrap: esto no es un repo git. Clona el template, no lo descargues como zip." >&2
  exit 2
fi
if ! git remote 2>/dev/null | grep -qx 'template'; then
  cat >&2 <<'EOF'
❌ bootstrap: no hay ningun remote llamado `template`, asi que esto parece el
   repo del TEMPLATE y no tu proyecto. Abortado antes de tocar nada.

   El 2026-09-03 un agente ejecuto este script sobre el template y borro
   ficheros; esta precondicion existe por eso.

   Si de verdad estas adoptando, te falta el paso que docs/ADOPTION.md §1 pone
   ANTES de este:
     Caso A (proyecto nuevo):  git remote rename origin template
     Caso B (proyecto que ya existe):  git remote add template <url-del-template>
EOF
  exit 2
fi

read -r -p "Nombre del proyecto (kebab-case, ej. acme-app): " PROJECT
[ -z "$PROJECT" ] && { echo "Nombre vacío, aborto."; exit 1; }
# Title-case PORTABLE (BSD/macOS + GNU): mayúscula inicial de cada segmento '-'.
# NO usar `sed \U`: es extensión GNU; en BSD/macOS produce basura como "UacmeUapp".
PROJECT_TITLE=""
IFS='-' read -ra _parts <<< "$PROJECT"
for _p in "${_parts[@]}"; do
  [ -z "$_p" ] && continue
  PROJECT_TITLE="${PROJECT_TITLE}$(printf '%s' "${_p:0:1}" | tr '[:lower:]' '[:upper:]')${_p:1}"
done

# ── Reemplazo de placeholders: el alcance lo decide GIT (PRD 0008, OQ-11) ──
# Antes: `grep -rlZ --exclude-dir=.git … .`, que recorria el arbol entero —
# node_modules/, .venv/, vendor/ incluidos. La respuesta no es una lista de
# exclusiones (habria que mantenerla y quedaria desfasada) sino preguntarle a
# git que considera parte del proyecto:
#   --cached                     lo que ya rastrea
#   --others --exclude-standard  lo recien copiado y aun sin commitear,
#                                respetando el .gitignore del adoptante
# Lo segundo es imprescindible: en el Caso B bootstrap corre justo despues del
# instalador y los ficheros del harness todavia no estan commiteados.
#
# Limite declarado: quien NO ignore node_modules/ sigue expuesto, porque
# entonces esos ficheros son parte de su repo por decision suya.
echo "→ Reemplazando <PROJECT> → $PROJECT_TITLE y <project> → $PROJECT ..."
# ⚠️ NADA de `grep -lZ` aqui. En GNU, -Z hace que -l separe los nombres por NUL
# y el `read -d ''` los consume; en BSD/macOS -Z NO emite NUL (verificado con
# `od -c`: separa por \n). El codigo anterior combinaba las dos cosas, asi que
# en macOS el bucle daba CERO iteraciones y el script imprimia "Reemplazando…"
# sin reemplazar nada — su funcion principal, rota en silencio, para todo
# adoptante de macOS. Es la misma familia que el orden de `stat` (una opcion que
# en GNU hace una cosa y en BSD otra, fallando hacia el silencio).
#
# `git ls-files -z` SI emite NUL de forma portable, y el grep va por fichero.
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  grep -q -e '<PROJECT>' -e '<project>' "$f" 2>/dev/null || continue
  sed -i.bak -e "s/<PROJECT>/$PROJECT_TITLE/g" -e "s/<project>/$PROJECT/g" "$f"
  rm -f "$f.bak"
done < <(git ls-files -z --cached --others --exclude-standard 2>/dev/null)

# ── Plataformas: se PROPONEN, no se borran (PRD 0008, OQ-5) ─────────
# Este bucle hacia `rm -rf` de lo no listado. Y el radio era mayor de lo que
# parecia: `install-harness.sh` clasifica ios/ android/ web/ entre las rutas que
# NUNCA copia, asi que en una adopcion Caso B cualquiera de esos directorios que
# este script encuentre es del ADOPTANTE. Son los cuatro elementos, no solo
# `backend` — que ademas el template ni siquiera trae.
#
# Ahora imprime el comando y no lo ejecuta. Eso elimina de raiz la heuristica de
# "¿este ios/ es del template o tuyo?" y sus falsos positivos: nivel 0
# (imposibilitar) en vez de nivel 2 (detectar).
echo "→ Plataformas disponibles: ios android web backend"
read -r -p "¿Cuáles usas? (separadas por espacio): " PLATFORMS
_SOBRAN=""
for p in ios android web backend; do
  if ! echo " $PLATFORMS " | grep -q " $p "; then
    [ -d "$p" ] && _SOBRAN="$_SOBRAN $p"
  fi
done
if [ -n "$_SOBRAN" ]; then
  echo ""
  echo "  ⚠️  Estos directorios existen y NO los listaste:$_SOBRAN"
  echo "     NO se borran. Míralos antes: si son tuyos, tienen tu código dentro;"
  echo "     si son los ejemplos del template, solo llevan un AGENTS.md."
  echo ""
  echo "     Si confirmas que sobran, el comando es:"
  echo "         rm -rf$_SOBRAN"
  echo ""
fi

# Preset de gates (full=equipo, bloquean · lite=personal, avisan).
echo "→ Preset de gates: full (equipo) | lite (personal, gates blandos avisan en vez de bloquear)."
read -r -p "¿Preset? [full/lite] (default full): " PRESET
case "$PRESET" in lite) _p=lite ;; *) _p=full ;; esac
printf '%s\n# full (equipo, gates bloquean) | lite (personal, gates avisan). Lo lee io.sh (hook_preset).\n' "$_p" > tools/preset
echo "  - preset = $_p"

# Vía Claude: import vs symlink.
echo "→ CLAUDE.md ya importa AGENTS.md con '@AGENTS.md'. Si prefieres symlink:"
echo "    rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md"

echo ""
echo "✅ Bootstrap listo. Siguientes pasos:"
echo "   1. lefthook install                   ← sin esto el Anillo 1 está DORMIDO"
echo "      brew install lefthook gitleaks semgrep   (o pip/apt equivalente)"
echo "   2. grep -rn 'FILL:' .   ← rellena lo de tu stack"
echo "   3. lee docs/ADOPTION.md"
