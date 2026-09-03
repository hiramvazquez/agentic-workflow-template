#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# install-harness.sh — traer el harness a un proyecto SIN destruirlo
# ════════════════════════════════════════════════════════════════════
# `docs/ADOPTION.md` §1 Caso B —el camino NORMAL, un proyecto que ya existe—
# documentaba `cp -R /tmp/awt/. .` sobre la raíz del adoptante. Medido el
# 2026-09-02 sobre un proyecto de juguete: de 6 a 27 entradas en la raíz, y
# README.md, LICENSE, CODEOWNERS y .editorconfig PISADOS por los del template.
# El código fuente sobrevivía, así que el daño era de identidad y
# configuración — pero un LICENSE sustituido en silencio no es cosmético.
#
# La única mitigación era "revisa el diff antes de commitear", una frase en la
# guía. Prosa, no mecanismo. Esto es el mecanismo.
#
#   bash scripts/install-harness.sh /ruta/a/mi-proyecto
#
# ── Las tres clases, y por qué ──────────────────────────────────────
#   MAQUINARIA  se sobrescribe siempre. Es del harness; si el adoptante la
#               editó, su edición se pierde en el siguiente upgrade igual —
#               por eso §8 exige aprobación del owner para tocarla.
#   SEMILLA     se copia SOLO SI NO EXISTE. El template la da para arrancar y
#               a partir de ahí es del adoptante: sus reglas, sus skills, sus
#               conf. Pisarla en una reinstalación borraría su trabajo.
#   NUNCA       no se toca jamás. Identidad del proyecto (README, LICENSE,
#               CODEOWNERS, .editorconfig) y ejemplos del template que no
#               tienen nada que hacer en el repo de otro (ios/ android/ web/).
#
# El inventario de MAQUINARIA no se escribe aquí: sale de `SYNC_PATHS` y
# `SYNC_GLOBS` de `tools/upgrade.sh`, que ya lo sabía para los upgrades. Una
# regla implementada dos veces diverge, y divergir aquí significa que instalar
# y actualizar traigan cosas distintas.
set -uo pipefail

# La raíz del TEMPLATE se resuelve desde la ubicación de este script, no del
# cwd: si no, instalar desde otro directorio copiaría el árbol equivocado.
# (Es la lección de f-6b761f06, el detector que salía verde mirando una raíz
# sin fuentes.)
TPL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
DEST="${1:-}"

if [ -z "$DEST" ]; then
  echo "uso: bash scripts/install-harness.sh <ruta-al-proyecto>" >&2
  exit 2
fi
[ -d "$DEST" ] || { echo "❌ install-harness: '$DEST' no es un directorio." >&2; exit 2; }
DEST="$(cd "$DEST" 2>/dev/null && pwd)" || { echo "❌ install-harness: no pude entrar en '$1'." >&2; exit 2; }
[ "$DEST" = "$TPL" ] && { echo "❌ install-harness: el destino es el propio template." >&2; exit 2; }

# ── MAQUINARIA: leída de upgrade.sh, la fuente única ────────────────
_inventario() { # <nombre-de-variable> → su valor en upgrade.sh
  grep -m1 "^$1=" "$TPL/tools/upgrade.sh" 2>/dev/null | cut -d'"' -f2
}
SYNC_PATHS="$(_inventario SYNC_PATHS)"
SYNC_GLOBS="$(_inventario SYNC_GLOBS)"
if [ -z "$SYNC_PATHS" ]; then
  echo "❌ install-harness: no pude leer SYNC_PATHS de tools/upgrade.sh." >&2
  echo "   Sin el inventario no sé qué es maquinaria, y adivinarlo es cómo se" >&2
  echo "   pisa el trabajo del adoptante. Abortado a propósito." >&2
  exit 3
fi

# Los directorios que EXIGE cada cliente en la raíz. No son negociables: si
# `.claude/` no está en la raíz, Claude Code no lee los hooks.
CLIENTES=".claude/agents .claude/commands .claude/rules .cursor .codex .github .claude-plugin"

# `.claude/skills` es un SYMLINK a `.agents/skills`, y sin el Claude Code no
# carga ninguna skill: el hook `skill-reminder` se queda sin nada que exigir y
# la matriz §11 deja de existir en la practica. No entra por `_copiar` porque
# `cp -R` de un symlink copiaria el DESTINO (duplicando las skills en dos
# arboles que divergirian) en vez de recrear el enlace.
#
# Lo encontro el review instalando en un directorio vacio y corriendo
# validate-harness sobre el resultado: "⚠️ .claude/skills ausente — skills/agents
# no cargaran ahi". El test 3 no lo cazo porque solo comprobaba que `.claude`
# existiera como directorio; su mutante (quitar `.claude/rules` de esta lista)
# dejaba los 6 tests en verde.
_enlazar_skills() {
  local dst="$DEST/.claude/skills"
  [ -e "$dst" ] || [ -L "$dst" ] && return 0
  [ -d "$DEST/.agents/skills" ] || return 0
  mkdir -p "$DEST/.claude" 2>/dev/null
  ln -s "../.agents/skills" "$dst" 2>/dev/null \
    || cp -R "$DEST/.agents/skills" "$dst" 2>/dev/null   # FS sin symlinks: copia, y validate-harness lo dira
}

# ── SEMILLAS: solo si no existen ────────────────────────────────────
SEMILLAS="AGENTS.md CLAUDE.md .agents/skills .claude/settings.json
tools/preset tools/layers.conf tools/skill-matrix.conf tools/verify.conf
tools/drift-ratchet.json tools/mutation-ratchet.json
docs/process/lessons_learned.md docs/process/current_execution_map.md
docs/process/prds/_template.md .gitleaks.toml"
# `backlog/_template.md` NO va aqui: ya es MAQUINARIA via SYNC_PATHS. Estaba en
# las dos listas y ganaba la maquinaria (su bucle corre antes), asi que el
# script se lo atribuia como "ya existia, es tuyo" un fichero que acababa de
# crear dos lineas antes — y con contenido real del adoptante lo sobrescribia
# mientras el mensaje decia lo contrario. Justo la mentira que este script
# existe para no contar. Lo impide ahora `_verificar_clasificacion`.
# `tools/architecture.conf` NO va aquí: el template trae `architecture.conf.example`
# (ya en SYNC_PATHS) y el `.conf` real lo crea el adoptante. Lo destapó el propio
# aviso de "el template no traía esta ruta" en la primera corrida — el instalador
# encontró un error en su propio inventario antes que yo.

# ── NUNCA: ni con --force. La identidad del proyecto no es del harness ──
# `ios/ android/ web/` van aquí porque el template los trae con un AGENTS.md
# de EJEMPLO: en un proyecto con ios/ real caían dentro de su código, y en uno
# backend-only creaban tres carpetas fantasma.
# shellcheck disable=SC2034  # documenta la política; el copiado es por lista blanca
NUNCA="README.md LICENSE CODEOWNERS .editorconfig .gitignore ios android web enterprise docs/ADOPTION.md"

# Una ruta en DOS clases es un bug, no una preferencia: la que corra primero
# gana y el informe miente sobre la otra. Se comprueba al arrancar, porque una
# clasificacion incoherente hace que TODO lo que el script diga sea dudoso.
_verificar_clasificacion() {
  local dobles="" m
  for m in $SYNC_PATHS $CLIENTES; do
    case " $SEMILLAS " in *" $m "*) dobles="$dobles $m" ;; esac
  done
  [ -z "$dobles" ] && return 0
  echo "❌ install-harness: estas rutas estan clasificadas como MAQUINARIA y como SEMILLA:$dobles" >&2
  echo "   Gana la que corre primero y el informe mentiria sobre la otra. Abortado." >&2
  exit 3
}
_verificar_clasificacion

COPIADOS=0; RESPETADOS=""; AUSENTES=""; FALLARON=""

_copiar() { # _copiar <ruta-relativa> <siempre|si-falta>
  local rel="$1" modo="$2" src="$TPL/$1" dst="$DEST/$1"
  [ -e "$src" ] || { AUSENTES="$AUSENTES $rel"; return 0; }
  if [ "$modo" = "si-falta" ] && [ -e "$dst" ]; then
    RESPETADOS="$RESPETADOS $rel"; return 0
  fi
  # El exit code se MIRA. La primera version tragaba los errores con 2>/dev/null
  # e incrementaba COPIADOS igual, asi que una colision fichero-vs-directorio
  # —un `scripts` que ya existe como ARCHIVO en el proyecto— dejaba sin instalar
  # toda la maquinaria y el script decia "✅ maquinaria instalada (68 rutas)" con
  # exit 0. Lo encontro el review de la ronda 2 con ese repro exacto. Es el mismo
  # pecado que este instalador existe para eliminar —reportar un exito que no
  # ocurrio— cometido por la via de I/O en vez de la de clasificacion.
  local ok=1
  mkdir -p "$(dirname "$dst")" 2>/dev/null || ok=0
  if [ "$ok" = "1" ]; then
    if [ -d "$src" ]; then cp -R "$src/." "$dst/" 2>/dev/null || ok=0
    else cp "$src" "$dst" 2>/dev/null || ok=0; fi
  fi
  if [ "$ok" = "1" ]; then COPIADOS=$((COPIADOS+1)); else FALLARON="$FALLARON $rel"; fi
}

echo "━━━ instalando el harness en $DEST ━━━"
for p in $SYNC_PATHS; do _copiar "$p" siempre; done
for g in $SYNC_GLOBS; do
  for f in "$TPL"/$g; do
    [ -e "$f" ] || continue
    _copiar "${f#$TPL/}" siempre
  done
done
for p in $CLIENTES; do _copiar "$p" siempre; done
for p in $SEMILLAS;  do _copiar "$p" si-falta; done
_enlazar_skills

if [ -n "$FALLARON" ]; then
  # Salir 1, no 0: una instalacion incompleta que dice "listo" manda al adoptante
  # a correr un harness que no esta. El caso real es una colision
  # fichero-vs-directorio, y el mensaje tiene que nombrarla.
  echo "❌ install-harness: NO pude copiar estas rutas:" >&2
  for f in $FALLARON; do echo "      $f" >&2; done
  echo "   Causa tipica: en el destino ya existe un ARCHIVO donde va un DIRECTORIO" >&2
  echo "   (o al reves). Resuelvelo y vuelve a correrlo. La instalacion esta" >&2
  echo "   INCOMPLETA: no sigas al bootstrap." >&2
  exit 1
fi
echo "   ✅ maquinaria instalada ($COPIADOS rutas)"
if [ -n "$RESPETADOS" ]; then
  # Declararlo NO es cortesía: saltarse un fichero en silencio deja al
  # adoptante con una versión vieja creyendo que está al día.
  echo ""
  echo "   🔒 Ya existían y NO se tocaron (son tuyos):"
  for r in $RESPETADOS; do echo "      $r"; done
  echo "      Si quieres la versión del template, compárala a mano:"
  echo "      diff <(cat \"$TPL/<ruta>\") <ruta>"
fi
if [ -n "$AUSENTES" ]; then
  echo ""
  echo "   ⚠️  El template no traía estas rutas (¿inventario desactualizado?):"
  for a in $AUSENTES; do echo "      $a"; done
fi
cat <<EOF

   Lo que NO se ha tocado, a propósito: README.md, LICENSE, CODEOWNERS,
   .editorconfig y .gitignore son la identidad de TU proyecto. Y los ejemplos
   ios/ android/ web/ del template no se copian: en un proyecto con ios/ real
   caerían dentro de tu código.

   Siguiente paso:  bash scripts/bootstrap.sh   (dentro de tu proyecto)
EOF
exit 0
