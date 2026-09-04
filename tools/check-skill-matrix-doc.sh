#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-skill-matrix-doc.sh — la tabla §11 y el conf no pueden divergir
# ════════════════════════════════════════════════════════════════════
# `tools/skill-matrix.conf` es la fuente única: la lee `skill-reminder` en
# runtime y es lo que de verdad BLOQUEA. Su vista humana vive en
# `docs/process/agents-rationale.md` §11 (salió de AGENTS.md en la fase 7 del
# PRD 0009: ese fichero entra en el contexto de cada turno y la tabla no hace
# falta tenerla delante — al bloquear, `skill-reminder` nombra lo que falta).
# Durante meses la cabecera del conf afirmaba que `test_skill_matrix.sh` cazaba
# la divergencia entre ambos. No era cierto: ese test comprueba que las refs
# EXISTAN y sean registrables, nunca compara tabla contra conf. O sea que el
# documento que promete el gate y el archivo que lo ejerce podían separarse sin
# que nada dijera nada — que es exactamente el drift que §9 prohíbe, cometido
# sobre el mecanismo que vigila el drift.
#
# Y no era hipotético: al escribir este detector, la primera pasada encontró
# dos divergencias vivas.
#   · La tabla exigía `architecture/platforms/ios.md` al tocar una View. El conf
#     no lo pedía. El doc ANUNCIABA una defensa que no existía (§14.4).
#   · La tabla tenía una fila `tools/**, ci/**, scripts/agent-hooks/**` →
#     `verification-loop.md`. Ese gate NO PUEDE existir: `skill-reminder`
#     excluye esas rutas a propósito (editar la doc de un área no es editar el
#     código de ese área — falso positivo real, fijado por
#     test_skill_reminder.sh). Era una promesa imposible de cumplir.
#
# ── QUÉ compara, y por qué NO compara los globs ─────────────────────
# Compara el conjunto de REFERENCIAS citadas a cada lado, no los globs. Los
# globs de la tabla agrupan a propósito (`**/*View*.swift, **/*Screen*.swift`
# en una fila) y usan prosa (`<migraciones-db>/**`); exigir igualdad literal
# daría un hallazgo por fila y el detector se desactivaría en una semana (ley
# del 10%, AGENTS §14.2). El conjunto de refs, en cambio, es exacto a los dos
# lados y es lo que importa: qué te obligan a leer.
#
# Las refs de la tabla van abreviadas (`domain/SKILL.md`) y las del conf
# completas (`.agents/skills/domain/SKILL.md`), así que el match es por SUFIJO
# de ruta — nunca por subcadena suelta, que casaría `SKILL.md` con cualquiera.
#
# Contrato de stdout:  MATRIX_DOC_SUMMARY solo_en_doc=<N> solo_en_conf=<M>
#                  o:  MATRIX_DOC_SUMMARY estado=no-pude-mirar   (exit 3)
# La segunda forma existe porque la primera, con ceros, se lee EXACTAMENTE igual
# que una comparación limpia. Este script avisaba citando §14.3 y una línea
# después imprimía `solo_en_doc=0 solo_en_conf=0` — y eso hizo pasar en vacío a
# un test que creía estar comprobando el repo real.
# Exit: 0 coherentes · 1 divergen · 3 no pude mirar (falta un archivo)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# La vista humana de la matriz se movió a `agents-rationale.md` §11: `AGENTS.md`
# entra en el contexto de cada turno y la tabla no hace falta tenerla delante —
# cuando importa, `skill-reminder` bloquea nombrando las refs que faltan. El
# detector sigue a la tabla; si se queda apuntando al fichero viejo, compara
# contra una tabla que ya no existe y delata un drift que no hay
# (`test_el_detector_de_la_matriz_apunta_donde_vive_la_tabla`).
DOC="${SKILL_MATRIX_DOC:-docs/process/agents-rationale.md}"
CONF="${SKILL_MATRIX_CONF:-tools/skill-matrix.conf}"

if [ ! -f "$DOC" ] || [ ! -f "$CONF" ]; then
  {
    echo "⚠️  skill-matrix-doc: falta $( [ -f "$DOC" ] || printf '%s ' "$DOC"; [ -f "$CONF" ] || printf '%s' "$CONF") — no puedo comparar."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "MATRIX_DOC_SUMMARY estado=no-pude-mirar"
  exit 3
fi

# ── Refs de la TABLA (columna 2 solamente) ──────────────────────────
# La columna 1 también trae tokens que acaban en `.md` (`docs/process/prds/
# [0-9]*.md` es un GLOB, no una lectura obligatoria). Leer la fila entera los
# metería como refs fantasma y el detector empezaría su vida con un falso
# positivo — la forma más rápida de que nadie vuelva a mirarlo.
DOC_REFS="$(awk -F'|' '
  /^\| *Path que vas a editar/ { intable = 1; next }
  intable && /^\|[ -]*-+/       { next }
  intable && !/^\|/             { intable = 0 }
  intable && NF >= 3            { print $3 }
' "$DOC" \
  | grep -oE '`[^`]+\.md`' \
  | tr -d '`' \
  | sort -u)"

# ── Refs del CONF (todo lo que hay tras el primer `|`) ──────────────
CONF_REFS="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" \
  | awk -F'|' 'NF >= 2 { print $2 }' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -E '\.md$' \
  | sort -u)"

# ── Match por SUFIJO de ruta, en ambas direcciones ──────────────────
_casa() { # _casa <ref-corta> <ref-larga>
  [ "$1" = "$2" ] && return 0
  case "$2" in */"$1") return 0 ;; esac
  return 1
}

SOLO_DOC=""; SOLO_CONF=""
while IFS= read -r d; do
  [ -z "$d" ] && continue
  _hit=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    _casa "$d" "$c" && { _hit=1; break; }
  done <<< "$CONF_REFS"
  [ "$_hit" = "0" ] && SOLO_DOC="${SOLO_DOC}${d}"$'\n'
done <<< "$DOC_REFS"

while IFS= read -r c; do
  [ -z "$c" ] && continue
  _hit=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    _casa "$d" "$c" && { _hit=1; break; }
  done <<< "$DOC_REFS"
  [ "$_hit" = "0" ] && SOLO_CONF="${SOLO_CONF}${c}"$'\n'
done <<< "$CONF_REFS"

N_DOC="$(printf '%s' "$SOLO_DOC" | grep -c . || true)"
N_CONF="$(printf '%s' "$SOLO_CONF" | grep -c . || true)"

# ── Y los CONJUNTOS por fila, que es lo que el conjunto global no ve ─
# Comparar solo la unión de referencias deja pasar el error que más importa:
# intercambiar dos lecturas entre filas no cambia la unión, pero le dice al
# agente que edite una View leyendo la skill de dominio (`f-8b74d177`).
#
# Comparar pares `glob → refs` uno a uno NO es posible ni deseable: los globs de
# la tabla AGRUPAN a propósito (una fila humana cubre varias del conf, y esa
# agrupación es lo que la hace legible). Lo que sí tiene que coincidir es el
# conjunto de COMBINACIONES: cada combinación de lecturas que el conf exige
# existe como fila de la tabla, y ninguna fila inventa una que el conf no pida.
_conjunto_canonico() { # <texto de la fila> → refs del conf, ordenadas, en una línea
  local refs canon="" r c
  refs="$(printf '%s' "$1" | grep -oE '[A-Za-z0-9_./-]+\.md' | sort -u)"
  local n elegida
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    n=0; elegida=""
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      # Canoniza contra el conf: la tabla abrevia (`domain/SKILL.md`) y el conf
      # escribe la ruta entera. Sin esto, dos escrituras del mismo fichero
      # contarían como referencias distintas.
      _casa "$r" "$c" && { n=$((n + 1)); elegida="$c"; }
    done <<< "$CONF_REFS"
    if [ "$n" -gt 1 ]; then
      # AMBIGUA: casa por sufijo con VARIAS refs del conf. Quedarse con la
      # primera daba verde sobre una tabla que no dice a cuál se refiere —
      # `SKILL.md` a secas casa con architecture/, domain/ y security/. Se
      # emite un token que no existe en ningún conjunto del conf, así que la
      # fila queda descuadrada y el mensaje lo nombra.
      canon="${canon}ambigua:${r}"$'\n'
    elif [ -n "$elegida" ]; then
      canon="${canon}${elegida}"$'\n'
    fi
  done <<< "$refs"
  printf '%s' "$canon" | grep -v '^$' | sort -u | tr '\n' ' '
}

# Sin `case` aquí: bash 3.2 (el de macOS) rompe al parsear un `case` dentro de
# `$( )` — el `)` del patrón le cierra la sustitución. Da un error de sintaxis
# en tiempo de ejecución, no al cargar, así que el script "corría" y comparaba
# basura. Un prefijo recortado dice lo mismo y es portable.
CONF_SETS="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" | while IFS= read -r linea; do
  refs="${linea#*|}"
  [ "$refs" = "$linea" ] && continue
  _conjunto_canonico "$refs" && echo
done | grep -v '^ *$' | sort -u)"

DOC_SETS="$(awk -F'|' '
  /^\| *Path que vas a editar/ { intable = 1; next }
  intable && /^\|[ -]*-+/       { next }
  intable && !/^\|/             { intable = 0 }
  intable && NF >= 3            { print $3 }
' "$DOC" | while IFS= read -r fila; do
  _conjunto_canonico "$fila" && echo
done | grep -v '^ *$' | sort -u)"

SETS_SOLO_DOC="$(comm -23 <(printf '%s\n' "$DOC_SETS") <(printf '%s\n' "$CONF_SETS") | grep -v '^$' || true)"
SETS_SOLO_CONF="$(comm -13 <(printf '%s\n' "$DOC_SETS") <(printf '%s\n' "$CONF_SETS") | grep -v '^$' || true)"
N_SETS_DOC="$(printf '%s' "$SETS_SOLO_DOC" | grep -c . || true)"
N_SETS_CONF="$(printf '%s' "$SETS_SOLO_CONF" | grep -c . || true)"

echo "MATRIX_DOC_SUMMARY solo_en_doc=${N_DOC:-0} solo_en_conf=${N_CONF:-0} combinaciones_descuadradas=$(( ${N_SETS_DOC:-0} + ${N_SETS_CONF:-0} ))"

if [ "${N_DOC:-0}" -eq 0 ] && [ "${N_CONF:-0}" -eq 0 ] \
   && [ "${N_SETS_DOC:-0}" -eq 0 ] && [ "${N_SETS_CONF:-0}" -eq 0 ]; then
  exit 0
fi

{
  echo "❌ skill-matrix: la tabla de $DOC §11 y $CONF NO dicen lo mismo."
  if [ "${N_DOC:-0}" -gt 0 ]; then
    echo ""
    echo "   La TABLA exige leer esto y el conf NO lo pide (defensa anunciada"
    echo "   que no existe — el peor de los dos sentidos, §14.4):"
    printf '%s' "$SOLO_DOC" | sed 's/^/     · /'
    echo "   Arréglalo AÑADIÉNDOLO al conf, no borrándolo de la tabla: si estaba"
    echo "   escrito es porque alguien lo consideró obligatorio."
  fi
  if [ "${N_CONF:-0}" -gt 0 ]; then
    echo ""
    echo "   El CONF bloquea por esto y la tabla no lo menciona (el agente se"
    echo "   choca con un gate que su documentación no anuncia):"
    printf '%s' "$SOLO_CONF" | sed 's/^/     · /'
    echo "   Añádelo a la tabla de §11 ($DOC) en este mismo commit."
  fi
  if [ "${N_SETS_CONF:-0}" -gt 0 ]; then
    echo ""
    echo "   El conf exige estas COMBINACIONES de lecturas y ninguna fila de la"
    echo "   tabla las anuncia — un adoptante en ese stack se choca con un gate"
    echo "   que su documentación no menciona:"
    printf '%s\n' "$SETS_SOLO_CONF" | sed 's/^/     · /'
  fi
  if [ "${N_SETS_DOC:-0}" -gt 0 ]; then
    echo ""
    if printf '%s' "$SETS_SOLO_DOC" | grep -q 'ambigua:'; then
      echo "   La tabla usa una referencia AMBIGUA: casa por sufijo con varias"
      echo "   del conf y no dice a cuál se refiere. Escríbela con directorio"
      echo "   suficiente para que sea única:"
      printf '%s\n' "$SETS_SOLO_DOC" | grep 'ambigua:' \
        | tr ' ' '\n' | grep '^ambigua:' | sed 's/^ambigua:/     · /' | sort -u
    fi
    echo "   La tabla anuncia estas combinaciones y el conf no las pide en"
    echo "   ninguna fila (defensa fingida, o refs movidas de fila):"
    printf '%s\n' "$SETS_SOLO_DOC" | sed 's/^/     · /'
  fi
  echo ""
  echo "   Recuerda cuál manda: el conf es la fuente única (lo ejecuta"
  echo "   skill-reminder); la tabla es su vista humana."
} >&2
exit 1
