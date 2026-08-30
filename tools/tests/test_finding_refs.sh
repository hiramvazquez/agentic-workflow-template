#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Dos checks sobre la CREDIBILIDAD del ledger
# ════════════════════════════════════════════════════════════════════
# El ledger solo sirve si lo que dice se puede comprobar. Dos formas concretas
# de que deje de servir sin que nadie lo note:
#
#   1. `check-finding-refs.sh`     — la doc cita un id que no existe. Lee como
#      cerrado, y nadie vuelve a abrir el tema. El hallazgo se evaporó CON EL
#      ASPECTO de haberse cerrado.
#   2. `check-version-claims.sh`   — un hallazgo declara una herramienta incapaz
#      citando al gestor de paquetes. `brew` sirve el último RELEASE, no lo que
#      soporta el proyecto: la conclusión negativa puede llevar meses siendo
#      falsa, y se auto-preserva porque desalienta la comprobación que la
#      refutaría.
#
# Los dos son detectores sobre TEXTO, que es el terreno donde este harness ya
# ha pisado cuatro veces la misma mina — de ahí que los guards de FALSO
# POSITIVO de abajo pesen más que los casos de detección.

_fr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/findings" "$d/docs"
  cp "$PROJECT_ROOT/tools/check-finding-refs.sh"   "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-version-claims.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_led() { printf '%s\n' "$@" > tools/findings/ledger.jsonl; }
_j()   { printf '{"id":"%s","title":"%s","area":"x","severity":"low","tier":"auto-fix","status":"open","detail":"%s","source":"%s","resolution":"%s","links":[],"createdAt":"2026-01-01","updatedAt":"2026-01-01"}' \
          "$1" "${2:-t}" "${3:-}" "${4:-}" "${5:-}"; }

# ════════════════════════════════════════════════════════════════════
# check-finding-refs.sh
# ════════════════════════════════════════════════════════════════════

_case_id_fantasma_se_caza() {
  _led "$(_j f-existe)"
  printf 'Ver `f-existe` y también `f-no-existe`.\n' > docs/notas.md
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un id fantasma NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *f-no-existe*) : ;; *)
    echo "    no nombró el id fantasma:"; printf '%s\n' "$out" | sed 's/^/      /'; return 1 ;; esac
  case "$out" in *f-existe:*|*"- docs/notas.md: \`f-existe\`"*)
    echo "    acusó a un id que SÍ existe"; return 1 ;; esac
}
test_un_id_de_finding_que_no_existe_bloquea() { _fr_sandbox _case_id_fantasma_se_caza; }

# ── FALSO POSITIVO nº1: la subcadena de otra palabra ────────────────
# Este es el caso REAL con el que nació el check. Un `grep -o 'f-[a-z-]*'` sobre
# el texto crudo casa `f-nature` dentro de `check-diff-nature`: el detector se
# dispara con el texto que HABLA de un archivo en vez de con una cita. Cuatro
# veces en este repo; la quinta la caza este test.
_case_subcadena_no_es_cita() {
  _led "$(_j f-real)"
  cat > docs/notas.md <<'MD'
El gate `check-diff-nature` mira la naturaleza del diff, y `tools/check-drift.sh`
lo agrega. Nada de esto cita un hallazgo. Ver `f-real` para el histórico.
MD
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: una subcadena dentro de otro nombre contó como cita (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_subcadena_dentro_de_otro_nombre_no_es_una_cita() {
  _fr_sandbox _case_subcadena_no_es_cita
}

# ── FALSO POSITIVO nº2: los ejemplos de uso del CLI ─────────────────
# `tools/findings/README.md` documenta `close f-xxxx --resolution ...` dentro de
# un bloque de código. Acusar a la doc del propio CLI de citar un fantasma sería
# el estreno perfecto: el detector suspendiendo al manual que lo explica.
_case_ejemplos_del_cli_no_cuentan() {
  _led "$(_j f-real)"
  cat > docs/notas.md <<'MD'
Uso:

```bash
bash tools/findings/findings.sh close f-xxxx --resolution "commit abc"
bash tools/findings/findings.sh close `f-de-mentira` --resolution "x"
```

Y un placeholder suelto: `f-xxxx`.
MD
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: los ejemplos del CLI contaron como citas (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_los_ejemplos_de_uso_no_se_confunden_con_citas() {
  _fr_sandbox _case_ejemplos_del_cli_no_cuentan
}

_case_sin_ledger_es_exit3() {
  # "No pude mirar" ≠ "todo bien" (§14.3). Un repo recién adoptado sin ledger
  # no puede leerse como "las citas resuelven": no hay contra qué resolverlas.
  rm -f tools/findings/ledger.jsonl
  printf 'Ver `f-lo-que-sea`.\n' > docs/notas.md
  bash tools/check-finding-refs.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    sin ledger no devolvió exit 3"; return 1; }
}
test_sin_ledger_dice_que_no_pudo_mirar() { _fr_sandbox _case_sin_ledger_es_exit3; }

# ════════════════════════════════════════════════════════════════════
# check-version-claims.sh
# ════════════════════════════════════════════════════════════════════

_case_version_sin_repo_bloquea() {
  _led "$(_j f-nivel4 "El nivel 4 no se puede medir" \
          "muter 16 no parsea typed throws de Swift 6, y brew no sirve otra." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    una afirmación de versión sin repo NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *f-nivel4*) : ;; *)
    echo "    no nombró el hallazgo"; printf '%s\n' "$out" | sed 's/^/      /'; return 1 ;; esac
  case "$out" in *"gestor de paquetes"*) : ;; *)
    echo "    no señaló que citar al gestor de paquetes es justo lo que no basta"; return 1 ;; esac
}
test_declarar_una_herramienta_incapaz_sin_citar_el_repo_bloquea() {
  _fr_sandbox _case_version_sin_repo_bloquea
}

_case_con_repo_pasa() {
  _led "$(_j f-nivel4 "El nivel 4 no se puede medir" \
          "muter 16 no parsea typed throws; el repositorio (https://github.com/muter-mutation-testing/muter) lo arregla en main sin release." )"
  bash tools/check-version-claims.sh >/dev/null 2>&1 \
    || { echo "    citar el repositorio no fue suficiente para pasar"; return 1; }
}
test_citar_el_repositorio_satisface_el_check() { _fr_sandbox _case_con_repo_pasa; }

_case_excepcion_declarada() {
  # Hay herramientas sin repositorio público. Forzar una URL inventada sería
  # peor que no pedir nada: la excepción se DECLARA, como `n/a-manual`.
  _led "$(_j f-x "..." "la herramienta interna 3 no soporta el flag" "" "n/a-repo — binario propietario, no hay fuente que mirar")"
  bash tools/check-version-claims.sh >/dev/null 2>&1 \
    || { echo "    la excepción declarada n/a-repo no se respetó"; return 1; }
}
test_la_excepcion_n_a_repo_se_respeta() { _fr_sandbox _case_excepcion_declarada; }

# ── FALSO POSITIVO nº1: una OBSERVACIÓN no es una afirmación de no-existencia ──
# "jq 1.6 se comporta así" se verifica CORRIENDO jq: la copia que tienes basta
# como evidencia y pedir una URL sería ruido puro. Solo la afirmación de que
# NO EXISTE una versión capaz necesita mirar la fuente, porque es justo lo que
# tu copia no puede decirte. Sin esta distinción el check saltaría con cada
# número de versión del ledger y moriría por la ley del 10% en su primera semana.
_case_observacion_de_version_no_dispara() {
  _led "$(_j f-jq "El guard estaba inerte en jq 1.6" \
          "jq 1.6 devuelve 0 donde jq 1.7 devuelve 1; el guard nunca saltaba. Medido corriendo ambas." )" \
       "$(_j f-node "Fijamos node 18 en CI" "node 18.20 es la version del runner." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: una observación sobre versiones exigió citar un repo (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  case "$out" in *"afirmaciones=0"*) : ;; *)
    echo "    contó como afirmación algo que solo describe lo observado: $out"; return 1 ;; esac
}
test_una_observacion_sobre_versiones_no_exige_repositorio() {
  _fr_sandbox _case_observacion_de_version_no_dispara
}

# ── FALSO POSITIVO nº2: "no parsea" sin herramienta ni versión ──────
# El ledger dice, de un hallazgo del harness: "si no parsean, avisa y sale 0".
# Habla de hooks, no de la versión de nada. Un detector que casara el verbo
# suelto acusaría a media mitad del ledger.
_case_verbo_suelto_no_dispara() {
  _led "$(_j f-brick "Un hook roto brickeaba al agente" \
          "run-hook.sh valida con bash -n el hook y sus libs antes de exec; si no parsean, avisa y sale 0." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: 'no parsean' sin herramienta ni versión disparó (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_verbo_de_incapacidad_sin_version_no_dispara() {
  _fr_sandbox _case_verbo_suelto_no_dispara
}

# ── El detector, contra el artefacto REAL del repo ──────────────────
# La ley que este harness ya tiene escrita: **el primer fallo de una pieza que
# procesa un artefacto del repo aparece contra ESE artefacto** (le pasó al
# merge de settings, que nació roto y sus seis tests sintéticos lo aprobaron).
# Estos dos checks leen el ledger y la doc de VERDAD; los fixtures de arriba no
# sustituyen correrlos contra ellos.
test_los_dos_checks_corren_limpios_contra_el_repo_real() {
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-finding-refs falla contra la doc real del repo (exit $rc):"
    printf '%s\n' "$out" | tail -6 | sed 's/^/      /'; return 1; }
  out="$(cd "$PROJECT_ROOT" && bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-version-claims falla contra el ledger real del repo (exit $rc):"
    printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# EL CORPUS DE PROSA AJENA (tools/findings/fixtures/)
# ════════════════════════════════════════════════════════════════════
# `check-version-claims` se validó contra el ledger del template —38 entradas,
# disparó en 1, y era la defectuosa— y pareció cirugía. El primer adoptante lo
# corrió contra el suyo (61 entradas, prosa española densa, historias y
# criterios numerados) y disparó 3 veces con DOS falsos positivos: 67%, muy por
# encima del 10% que el propio detector cita como criterio de diseño.
#
# La lección, que es la del ciclo anterior un piso más arriba:
#   **"contra el artefacto real" incluye el artefacto real de OTRO.**
#   Quien escribe el detector escribe, sin querer, el corpus que lo aprueba.
#
# Estos dos tests son el mecanismo. El BUENO es el que importa: es el guard de
# falsos positivos de toda la capa, y sus entradas `[adoptante]` son texto real
# copiado literal — su valor está en no haberlo escrito nosotros.
_FIX="tools/findings/fixtures"

test_el_corpus_de_prosa_ajena_no_produce_ni_un_hallazgo() {
  local f="$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl"
  [ -f "$f" ] || { echo "    falta el corpus BUENO ($_FIX/ledger-bueno.jsonl)"; return 1; }
  local out rc
  out="$(cd "$PROJECT_ROOT" && FINDINGS_LEDGER="$_FIX/ledger-bueno.jsonl" \
         bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO sobre prosa que no escribimos nosotros (exit $rc):"
    printf '%s\n' "$out" | grep '^  - ' | sed 's/^/      /'
    echo "    Recuerda el reparto: 'no tiene' en español es CARECER, no 'no soporta';"
    echo "    y <palabra> <número> casa con 'criterio 6', 'la 0006', 'Los 3 casts'."
    return 1; }
  case "$out" in *"afirmaciones=0"*) : ;; *)
    echo "    contó afirmaciones donde no las hay: $out"; return 1 ;; esac
}

test_el_corpus_malo_dispara_en_todas_sus_formas() {
  # El guard del guard: arreglar los falsos positivos no puede vaciar el
  # detector. Cada forma que caza tiene su línea aquí.
  local f="$PROJECT_ROOT/$_FIX/ledger-malo.jsonl" n
  [ -f "$f" ] || { echo "    falta el corpus MALO ($_FIX/ledger-malo.jsonl)"; return 1; }
  n="$(grep -c '"id"' "$f" 2>/dev/null || echo 0)"
  local out; out="$(cd "$PROJECT_ROOT" && FINDINGS_LEDGER="$_FIX/ledger-malo.jsonl" \
                    bash tools/check-version-claims.sh 2>&1)"
  case "$out" in *"afirmaciones=$n"*) : ;; *)
    echo "    el corpus MALO tiene $n entradas y el detector no las cazó todas:"
    printf '%s\n' "$out" | head -2 | sed 's/^/      /'
    echo "    Una forma que deja de dispararse es un agujero, no una mejora."
    return 1 ;; esac
}

test_el_corpus_ajeno_lleva_los_textos_que_produjeron_el_fallo() {
  # Un corpus que se reescribe "para que quede mejor" deja de reproducir nada.
  # Los dos textos que el adoptante midió tienen que seguir ahí, literales.
  local f="$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl"
  grep -q 'no tiene test que lo verifique' "$f" 2>/dev/null \
    || { echo "    desapareció del corpus el FP 'criterio 6 ... no tiene test'"; return 1; }
  grep -q 'no tiene alternativa' "$f" 2>/dev/null \
    || { echo "    desapareció del corpus el FP 'Los 3 casts ... no tiene alternativa'"; return 1; }
}

# ── El caso que PARECE del corpus bueno y va en el malo ─────────────
# Un hallazgo que CITA una afirmación de versión como ejemplo. Se propuso
# exentarlo —citar ≠ afirmar— invocando dos precedentes reales: el git-guard no
# salta con `grep "git commit --no-verify" doc.md`, y la matriz de Bash desnuda
# las cadenas entrecomilladas. Pero esos dos se apoyan en una gramática EXTERNA
# (el shell no ejecuta lo entrecomillado, y quien lo dictamina es su parser, no
# nuestro criterio). En prosa no hay tal gramática: las comillas son estilo, y
# exentarlas regalaría una primitiva de evasión — envuelve la afirmación en
# comillas y pasa. Este test fija la decisión para que nadie la "arregle" luego.
test_una_afirmacion_de_version_citada_como_ejemplo_sigue_disparando() {
  local f="$PROJECT_ROOT/$_FIX/ledger-malo.jsonl"
  grep -q 'f-malo-citada-como-ejemplo' "$f" 2>/dev/null \
    || { echo "    el caso 'citada como ejemplo' desapareció del corpus MALO"; return 1; }
  grep -q 'f-malo-citada-como-ejemplo' "$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl" 2>/dev/null \
    && { echo "    el caso 'citada como ejemplo' se movió al corpus BUENO."
         echo "    Eso exenta lo entrecomillado, y en prosa las comillas las controla"
         echo "    el evaluado: sería una primitiva de evasión, no una lectura mejor."
         return 1; }
  return 0
}

# ════════════════════════════════════════════════════════════════════
# El ledger cita en PROSA, y esa prosa no la miraba nadie
# ════════════════════════════════════════════════════════════════════
# Incidente real: un id inventado (`f-1a1cbb7f`) vivió DOS HORAS commiteado en
# los campos `detail` y `source` de dos findings, se propagó entre tres agentes
# y ninguno lo detectó. Este check daba `citas=79 fantasma=0` todo el tiempo.
#
# No fallaba por descuido: fallaba por DOS filtros independientes, y el primero
# basta para explicarlo.
#   1. Solo recorre ficheros `.md`, y el render del ledger NO vuelca `detail`
#      ni `source` al markdown. El texto nunca llegaba a la superficie mirada.
#   2. Y exige backticks, que es deliberado (ver cabecera): es lo que distingue
#      CITAR de HABLAR DE, y evita el modo de fallo que ya mató a
#      `check-version-claims.sh` al 67% de FP.
#
# Por eso el arreglo NO es "escanear detail/source buscando ids". Eso
# reintroduciría el filtro 2 justo donde más prosa sobre findings se escribe:
# un `detail` que discute legítimamente otro finding empezaría a disparar.
#
# Lo que se hace es más estrecho y no toca esa exención: en `detail`/`source`
# se reportan SOLO los ids que NO RESUELVEN. La distinción citar/mencionar solo
# importa para ids REALES — un `f-` que no existe es un defecto lo escribas
# como cita o como mención, porque no hay motivo legítimo para nombrar algo que
# no existe. Falsos positivos ~0 por construcción.

_case_detail_no_se_escanea_y_es_deliberado() {
  # EL LIMITE DECLARADO. `detail` NO se escanea, y este test existe para que
  # ese limite este ESCRITO y no se descubra por sorpresa.
  #
  # Se probo escanearlo y se midio: sobre el ledger real daba 3 reportes, 0
  # defectos, 100% de falsos positivos. Los tres eran findings que DOCUMENTAN
  # un incidente de id fantasma, y para documentarlo tienen que nombrar el id
  # invalido. No es una categoria rara: cada leccion que este harness convierte
  # en finding crea otra. Escanear los campos narrativos es reintroducir la ley
  # de la cabecera —«si un detector puede dispararse con el texto que HABLA de
  # la cosa, no esta mirando la cosa»— justo donde mas prosa hay.
  #
  # Se acepta a sabiendas: un detector ruidoso no se tolera, se desactiva
  # entero, y con el se perderia tambien la deteccion en `source` que SI es
  # precisa. Si algun dia se amplia, este test debe caer con su justificacion.
  _led "$(_j f-existe t 'CAUSA RAIZ de f-1a1cbb7f: el modulo no usa Coordinator.')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    detail dejo de ser terreno neutral: un id no resuelto ahi bloqueo (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_id_no_resuelto_en_detail_no_bloquea_a_proposito() {
  _fr_sandbox _case_detail_no_se_escanea_y_es_deliberado
}

_case_abreviatura_de_id_real_no_es_fantasma() {
  # Los ids con slug se citan en prosa por su prefijo (`f-wf04` en vez de
  # `f-wf04-archivos-sobre-el-limite`). Medido: 5 de los 9 primeros reportes
  # del escaneo eran justo eso — un 78% de FP, el mismo numero con el que murio
  # check-version-claims.sh. Se resuelven por prefijo antes de acusar.
  _led "$(_j f-existe t '' 'analisis derivado de f-wf04, owner')" \
       "$(_j f-wf04-archivos-sobre-el-limite)"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: una abreviatura de un id REAL se conto como fantasma (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_una_abreviatura_de_id_real_no_es_fantasma() {
  _fr_sandbox _case_abreviatura_de_id_real_no_es_fantasma
}

_case_id_fantasma_en_source_se_caza() {
  _led "$(_j f-existe t '' 'analisis de causa raiz de f-1a1cbb7f, owner')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un id fantasma en el source del ledger NO bloqueó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_id_fantasma_en_el_source_del_ledger_bloquea() {
  _fr_sandbox _case_id_fantasma_en_source_se_caza
}

_case_mencion_a_id_real_en_prosa_no_dispara() {
  # LA EXENCIÓN QUE NO SE PUEDE PERDER. Un `detail` que menciona otro finding
  # REAL, sin backticks, es prosa legítima y frecuentísima — es como se escriben
  # los findings de este repo. Si esto disparase, el check se volvería ruidoso
  # exactamente donde más se escribe, y un detector ruidoso se desactiva entero.
  _led "$(_j f-existe t '' 'derivado de f-otro-real, ver su resolucion')" \
       "$(_j f-otro-real)"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: mencionar un id REAL en prosa disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_mencionar_un_id_real_en_prosa_no_dispara() {
  _fr_sandbox _case_mencion_a_id_real_en_prosa_no_dispara
}

_case_subcadena_en_prosa_del_ledger_no_dispara() {
  # El mismo falso positivo que ya mató a check-version-claims, pero en el
  # campo nuevo: `f-nature` vive dentro de `check-diff-nature.sh`. Si el
  # escaneo de prosa no exige frontera, el detector vuelve a dispararse con el
  # texto que HABLA de un archivo.
  _led "$(_j f-existe t '' 'Reportado por check-diff-nature.sh sobre el diff staged')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: una subcadena dentro de un nombre de archivo disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_subcadena_en_la_prosa_del_ledger_no_dispara() {
  _fr_sandbox _case_subcadena_en_prosa_del_ledger_no_dispara
}

_case_prefijo_exige_frontera_de_guion() {
  # Sin el guion en `real.startswith(fid + "-")`, `f-abc` resolvería contra
  # `f-abcdef12` —otro finding DISTINTO— y un id inventado quedaría absuelto
  # por parecerse al principio de uno real. El reviewer cazó que esa frontera
  # estaba declarada en comentario pero no la mataba ningún test.
  _led "$(_j f-abcdef12 t '' 'derivado de f-abc, owner')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    'f-abc' se absolvió por parecerse al principio de 'f-abcdef12' (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_el_prefijo_exige_frontera_de_guion() {
  _fr_sandbox _case_prefijo_exige_frontera_de_guion
}

_case_placeholder_tambien_exento_en_source() {
  # La exención de placeholders existe para los ejemplos de uso. Aplicaba a los
  # `.md` desde siempre, pero al campo nuevo no la cubría ningún test: quitarla
  # dejaba los 19 en verde.
  _led "$(_j f-existe t '' 'ejemplo de uso: findings.sh close f-xxxx --resolution ...')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    FALSO POSITIVO: un placeholder en source se contó como fantasma (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_un_placeholder_en_source_no_es_fantasma() {
  _fr_sandbox _case_placeholder_tambien_exento_en_source
}

_case_el_contrato_mantiene_fantasma_dentro_de_citas() {
  # `fantasma ⊆ citas` es la relación que el contrato de stdout sugiere. El
  # loop nuevo sumaba a `fantasma` sin sumar a `citas`, así que un ledger con
  # un fantasma y sin ningún .md imprimía `citas=0 fantasma=1` — un resumen que
  # se contradice a sí mismo.
  _led "$(_j f-existe t '' 'derivado de f-no-existe-jamas, owner')"
  local out; out="$(bash tools/check-finding-refs.sh 2>&1)"
  local citas fantasma
  citas="$(printf '%s' "$out" | sed -n 's/.*citas=\([0-9]*\).*/\1/p' | head -1)"
  fantasma="$(printf '%s' "$out" | sed -n 's/.*fantasma=\([0-9]*\).*/\1/p' | head -1)"
  [ "${citas:-0}" -ge "${fantasma:-0}" ] \
    || { echo "    el resumen se contradice: citas=$citas fantasma=$fantasma"; return 1; }
}
test_el_resumen_nunca_reporta_mas_fantasmas_que_citas() {
  _fr_sandbox _case_el_contrato_mantiene_fantasma_dentro_de_citas
}

_case_resolution_tampoco_se_escanea() {
  # LÍMITE DECLARADO, gemelo del de `detail`. `resolution` es campo NARRATIVO:
  # ahí se explica cómo se cerró un finding, y citar el id inválido que motivó
  # el cierre es legítimo. De hecho el FP medido que descartó escanear los tres
  # campos vivía justo aquí (`f-id-de-finding-fantasma.resolution` nombrando
  # `f-nature` como ejemplo).
  #
  # Estaba declarado en comentario pero sin test, así que nada impedía que
  # alguien lo ampliara "ya que detail se mide". Ahora hay un rojo que lo para.
  _led "$(_j f-existe t '' '' 'cerrado; era el mismo caso que f-1a1cbb7f, que nunca existio')"
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    resolution dejó de ser terreno neutral (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_id_no_resuelto_en_resolution_no_bloquea_a_proposito() {
  _fr_sandbox _case_resolution_tampoco_se_escanea
}
