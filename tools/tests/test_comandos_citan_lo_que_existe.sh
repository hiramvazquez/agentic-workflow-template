#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Un comando que manda ejecutar un script fantasma no falla: se calla
# ════════════════════════════════════════════════════════════════════
# Los cinco `.claude/commands/*.md` le dicen al agente qué ejecutar. Si una de
# esas rutas se renombra, el comando no rompe nada visible — el agente corre
# algo que no existe, no obtiene salida, y sigue. En `/status` eso es lo peor
# posible: el comando existe justamente para que nadie confunda silencio con
# verde, y sería él quien lo confundiera.
#
# Es una rebanada de `f-25df51c3` ("ninguna capa verifica que las rutas citadas
# en la doc existan") acotada a donde más duele: las rutas que un agente va a
# EJECUTAR, no las que un humano va a leer.

_comandos_rutas() { # imprime las rutas de script citadas en los comandos
  grep -oh '[a-z_./-]*\(tools\|scripts\|ci\)/[A-Za-z0-9_./-]*\.\(sh\|py\)' \
    "$PROJECT_ROOT"/.claude/commands/*.md 2>/dev/null | sed 's#^\./##' | sort -u
}

test_los_comandos_no_citan_scripts_fantasma() {
  local faltan="" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ -e "$PROJECT_ROOT/$r" ] || faltan="$faltan $r"
  done <<< "$(_comandos_rutas)"
  [ -z "$faltan" ] || {
    echo "  rutas citadas en .claude/commands/ que NO existen:$faltan"
    echo "  Un agente que ejecuta eso no obtiene error: obtiene nada."
    return 1; }
  # el detector tiene que estar MIRANDO algo, o pasa por vacío
  local n; n="$(_comandos_rutas | grep -c . || echo 0)"
  [ "${n:-0}" -ge 5 ] || {
    echo "  el extractor solo encontró $n rutas: probablemente dejó de casar"
    echo "  y este test está pasando sin mirar nada (§14.3)."
    return 1; }
}

# ── Y /status declara de dónde salen sus cifras de entrega ──────────
# El cableado en sí. Sin esto, `dora.sh` vuelve a ser una herramienta que hay
# que recordar — la observabilidad *pull* que el estudio de paridad marca como
# la brecha frente a la industria.
test_status_cablea_las_metricas_de_entrega() {
  local f="$PROJECT_ROOT/.claude/commands/status.md"
  grep -q 'tools/metrics/dora.sh' "$f" || {
    echo "  /status no invoca tools/metrics/dora.sh"; return 1; }
  grep 'tools/metrics/dora.sh' "$f" | grep -q -- '--sin-serie' || {
    echo "  /status invoca dora.sh SIN --sin-serie: escribiría en la serie,"
    echo "  y el comando se declara de solo lectura."
    return 1; }
}

# ── Un filtro que no casa devuelve vacío, no error ──────────────────
# Pasó al escribir este mismo cableado: la primera versión pedía cuatro espacios
# de indentación donde `Metrica.linea()` emite dos, y `grep` devolvió cero
# líneas sin quejarse. La sección ENTREGA habría salido vacía en cada `/status`
# y nadie lo habría notado — el comando existe justamente para que nadie
# confunda silencio con verde.
#
# Este test ATA el patrón documentado a la salida real de la herramienta: si
# cualquiera de los dos cambia sin el otro, falla aquí y no en pantalla.
test_el_filtro_de_entrega_del_status_casa() {
  local f="$PROJECT_ROOT/.claude/commands/status.md" patron
  patron="$(grep '\*\*Entrega\*\*' "$f" | sed -n "s/.*grep -E '\([^']*\)'.*/\1/p")"
  [ -n "$patron" ] || {
    echo "  no encontré el filtro de Entrega en status.md (¿cambió la viñeta?)"
    return 1; }
  local n
  n="$(cd "$PROJECT_ROOT" && bash tools/metrics/dora.sh --sin-serie 2>/dev/null \
       | grep -cE "$patron")"
  [ "${n:-0}" -ge 6 ] || {
    echo "  el filtro '$patron' recoge $n líneas de la salida de dora; esperaba ≥6"
    echo "  (las seis métricas). Un grep que no casa deja la sección VACÍA en"
    echo "  silencio, que es peor que un error."
    return 1; }
}
