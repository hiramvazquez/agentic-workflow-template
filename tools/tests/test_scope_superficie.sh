#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# La superficie de enforcement se mantiene SOLA, desde quien la usa
# ════════════════════════════════════════════════════════════════════
# `scope_siempre_producto()` (tools/lib/scope.sh) lista lo que exige review
# gobierne quien gobierne el repo. Esa lista se quedó corta SEIS veces seguidas
# —project.conf, los scripts del gate, .claude/agents, .gitleaks.toml,
# run-tests.sh…— y cada arreglo tapaba el agujero recién visto sin poder
# demostrar cuándo terminaba. La sexta la encontró un reviewer haciendo a mano
# justo lo que hace este test.
#
# El cambio de forma: en vez de enumerar mejor, se DERIVA la pregunta desde el
# consumidor. Si `lefthook.yml` (Anillo 1) o `ci/run-gates.sh` (Anillo 3)
# invocan un script que puede tumbar el commit o el build, ese script decide si
# algo pasa — y por tanto es producto. Un gate nuevo entra en la lista el día
# que alguien lo cablea, no el día que alguien lo explota.
#
# Lo que este test NO hace, dicho aquí y no descubierto luego — y es la mitad
# del problema, no un detalle:
#
#   · Ve los SCRIPTS que se invocan, no los CONF que esos scripts leen. De las
#     seis vías, habría cazado sola la 3ª y la 6ª (implementaciones), pero NO la
#     5ª (`.gitleaks.toml`, `.semgrepignore`), ni la 4ª (`.claude/agents/`,
#     `.github/workflows/`), ni la 1ª y 2ª (`project.conf`). Esas son datos y
#     cableado, y siguen dependiendo de que alguien las meta en la lista a mano.
#   · Solo mira los dos invocadores canónicos. Un gate que corriera únicamente
#     desde un hook de `scripts/agent-hooks/` no lo vería — aunque ese
#     directorio entero ya está en la superficie, así que el hueco es teórico.
#   · **Solo ve la forma literal `bash <ruta>`.** Una invocación por indirección
#     (`bash "$var"`, un `for` sobre una lista, dos espacios entre `bash` y la
#     ruta, `sh` en vez de `bash`) es invisible. NO es teórico: `ci/run-gates.sh`
#     corría tres gates en un `for ... bash "$_chk"` y el extractor no veía
#     ninguno; salía bien de casualidad, porque los tres empiezan por `check-`.
#     Ese bucle se desenrolló a invocaciones literales, pero **la clase sigue
#     abierta** y vive en su propio finding.
#
#     Hubo aquí una regla que prohibía la indirección por coincidencia de
#     substrings. Se RETIRÓ: un reviewer la evadió con un espacio de más, y daba
#     falso positivo con comentarios de cola. Se quita en vez de parchearla otra
#     vez porque el problema es de parsing y no se resuelve con substrings — la
#     solución real es la inversión a fail-closed del PRD 0006, que deja este
#     detector sin objeto. Mantener una regla que sabemos evadible sería
#     anunciar una defensa que no existe (§14.4).
#
# O sea: esto cierra la clase "gate cableado y no protegido", no la clase
# entera. Se escribe así porque la versión anterior de este arreglo prometía
# "para que no haya quinta" y la quinta llegó en la misma sesión.

_sup_superficie() { ( . tools/lib/scope.sh; scope_siempre_producto ) 2>/dev/null; }

# Los scripts que los dos anillos invocan de verdad, menos los informativos.
# `|| true` es la marca explícita de "esto no decide nada": la usa
# metrics/escape-rate.sh y es la diferencia entre un gate y un informe.
_sup_invocadores() {
  local f linea script
  for f in lefthook.yml ci/run-gates.sh; do
    [ -f "$f" ] || continue
    while IFS= read -r linea; do
      case "$linea" in *"|| true"*) continue ;; esac
      script="$(printf '%s' "$linea" \
        | grep -oE 'bash (tools|scripts|ci)/[A-Za-z0-9_./-]+' | head -1 | sed 's/^bash //')"
      [ -n "$script" ] && printf '%s\n' "$script"
    done < "$f"
  done | sort -u
}

test_todo_gate_invocado_esta_en_la_superficie_de_enforcement() {
  local sup malos="" s
  sup="$(_sup_superficie)"
  [ -n "$sup" ] || { echo "    scope_siempre_producto no devolvió nada"; return 1; }
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    printf '%s\n' "$s" | grep -qE "$sup" || malos="${malos}  $s"$'\n'
  done <<< "$(_sup_invocadores)"
  [ -z "$malos" ] || {
    echo "    estos scripts pueden TUMBAR el commit o el build y NO exigen review:"
    printf '%s' "$malos"
    echo "    Editarlos para que reporten verde no dispararía el reviewer-gate."
    echo "    Añádelos a scope_siempre_producto() en tools/lib/scope.sh."
    return 1; }
}

# El fallo que este test tendría si nadie lo mirara: que el extractor devuelva
# vacío y pase por vacuidad. Ya me ha pasado dos veces hoy con otros tests —un
# test de señales que apuntaba al proceso equivocado y un fixture cuyo vecino
# satisfacía la precondición—, así que aquí se fija el suelo.
test_el_extractor_de_invocadores_no_devuelve_vacio() {
  local n; n="$(_sup_invocadores | grep -c .)"
  [ "${n:-0}" -ge 8 ] || {
    echo "    el extractor encontró $n gates y debería ver al menos 8:"
    _sup_invocadores | sed 's/^/      /'
    echo "    Un extractor vacío hace que el test de arriba pase sin comprobar nada."
    return 1; }
}

# FALSO POSITIVO: un informe no es un gate. `metrics/escape-rate.sh` corre con
# `|| true` a propósito —mide contención, no bloquea— y exigirle review sería
# ruido en el gate que más se ejecuta (ley del 10%, §14.2).
test_un_invocador_informativo_no_cuenta_como_gate() {
  _sup_invocadores | grep -q 'metrics/escape-rate\.sh' && {
    echo "    FALSO POSITIVO: escape-rate.sh corre con '|| true' y se contó como gate"
    return 1; }
  return 0
}

# ── Lo que un gate CONSULTA es superficie, aunque nadie lo invoque ──
# `carril.sh` no lo llama ningún anillo: lo consulta `check-review-marker.sh`
# para decidir si exige review. El extractor de arriba mira `lefthook.yml` y
# `run-gates.sh`, así que nunca lo vería — y en un proyecto adoptante, donde
# `tools/` es andamio exento, stagear un clasificador que diga `ligero` para
# todo dejaba pasar cualquier cosa sin review.
#
# El test se DERIVA de la consulta: si `check-review-marker.sh` deja de leer el
# clasificador, deja de exigirlo. No hay lista a mano que se quede vieja.
test_lo_que_el_gate_consulta_tambien_es_superficie() {
  local sup consultado
  sup="$(_sup_superficie)"
  consultado="$(grep -oE 'tools/carril\.(sh|conf)' tools/check-review-marker.sh 2>/dev/null \
                | sort -u)"
  [ -n "$consultado" ] || return 0   # ya no lo consulta: nada que exigir
  local malos="" c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    printf '%s\n' "$c" | grep -qE "$sup" || malos="${malos}  $c"$'\n'
  done <<< "$consultado"
  [ -z "$malos" ] || {
    echo "    check-review-marker CONSULTA esto para decidir si exige review,"
    echo "    y no exige review para cambiarlo:"
    printf '%s' "$malos"
    echo "    Añádelos a scope_siempre_producto() en tools/lib/scope.sh."
    return 1; }
}

# ── Las copias de respaldo dicen LO MISMO que la fuente ─────────────
# `check-review-marker.sh` y `check-verify-marker.sh` llevan una copia literal
# de la ERE para el caso de que `tools/lib/scope.sh` aún no haya llegado por
# sync. Es deliberado, y por eso mismo puede divergir: al añadir `tools/carril.sh`
# a la superficie hubo que tocar las tres, y encontrarlas fue un `grep` a mano.
# Una regla implementada en tres sitios diverge en cuanto una se olvida — y la
# que se olvide será la que decida en el repo que va con retraso, que es
# exactamente donde menos se mira.
test_las_copias_de_respaldo_no_divergen() {
  local n
  n="$(grep -ho '\^(tools/(check|verify.*scripts/agent-hooks/)' \
        tools/check-review-marker.sh tools/check-verify-marker.sh tools/lib/scope.sh \
        2>/dev/null | sort -u | grep -c .)"
  [ "${n:-0}" = "1" ] || {
    echo "    la superficie de enforcement está escrita de $n formas distintas:"
    grep -n '\^(tools/(check|verify.*scripts/agent-hooks/)' \
      tools/check-review-marker.sh tools/check-verify-marker.sh tools/lib/scope.sh \
      2>/dev/null | cut -c1-120 | sed 's/^/      /'
    echo "    La fuente es tools/lib/scope.sh; las otras dos son respaldo y la copian literal."
    return 1; }
}
