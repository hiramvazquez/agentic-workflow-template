#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Las reglas del nivel 2 tienen corpus, no una promesa
# ════════════════════════════════════════════════════════════════════
# La cabecera de swift.yaml decía que las reglas «se ejecutaron contra fixtures
# reales (positivo y negativo) antes de commitearse». Una comprobación manual
# hecha una vez no es un detector: `swift-force-cast` marcaba el `as?` SEGURO
# igual que el `as!` peligroso —el parser de Swift los normaliza al mismo
# nodo— y con el trinquete en 0 hacía imposible escribir un adapter de
# URLSession correcto. El detector castigaba lo que su propio mensaje aconseja.
#
# Lo revelador: el arreglo ya existía doce líneas más arriba, en
# `swift-force-try`, con un comentario describiendo el mismo defecto. Se
# arregló un caso y no se buscó el hermano. Estos tests son el hermano.

_sr_disponible() {
  command -v semgrep >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}
_sr_ids() { # _sr_ids <fixture> → check_ids encontrados, uno por línea
  SEMGREP_ENABLE_VERSION_CHECK=0 semgrep scan \
    --config "$PROJECT_ROOT/tools/semgrep/rules" \
    --json --quiet --metrics=off --no-git-ignore \
    "$PROJECT_ROOT/$1" 2>/dev/null \
    | jq -r '.results[]? | .check_id' | sed 's/.*\.//' | sort -u
}

test_el_fixture_bueno_no_produce_ni_un_hallazgo() {
  # EL TEST QUE IMPORTA. El fixture bueno contiene las formas SEGURAS que se
  # parecen a las prohibidas (`as?`, `try await`, `try?`, task groups, Logger).
  # Cualquier regla que se pase de lista se estrella aquí el mismo día.
  _sr_disponible || { echo "    (saltado: semgrep o jq ausentes — el nivel 2 ya se reporta MUDO)"; return 0; }
  local hallazgos; hallazgos="$(_sr_ids tools/semgrep/fixtures/swift-bueno.swift)"
  [ -z "$hallazgos" ] && return 0
  echo "    FALSO POSITIVO del nivel 2: estas reglas marcan código SEGURO:"
  printf '%s\n' "$hallazgos" | sed 's/^/      · /'
  echo "    Un detector que castiga lo que su propio mensaje recomienda no se"
  echo "    arregla bajando el trinquete: se arregla acotando la regla"
  echo "    (patterns + pattern-regex, como swift-force-try)."
  return 1
}

test_el_fixture_malo_dispara_todas_las_reglas() {
  # La otra cara: una regla que deja de cazar lo suyo (por un typo, por un
  # cambio del parser) queda MUDA sin que nada lo diga.
  _sr_disponible || { echo "    (saltado: semgrep o jq ausentes)"; return 0; }
  local esperadas="swift-force-cast swift-force-try swift-gcd-legado swift-primitivas-de-lock-manuales swift-print-en-produccion swift-thread-sleep"
  local encontradas r faltan=""
  encontradas="$(_sr_ids tools/semgrep/fixtures/swift-malo.swift)"
  for r in $esperadas; do
    printf '%s\n' "$encontradas" | grep -qx "$r" || faltan="$faltan $r"
  done
  [ -z "$faltan" ] && return 0
  echo "    Reglas MUDAS (no cazaron su propio caso malo):$faltan"
  echo "    Encontradas: $(printf '%s' "$encontradas" | tr '\n' ' ')"
  return 1
}

test_toda_regla_de_swift_tiene_su_caso_en_los_fixtures() {
  # Sin esto, el corpus se queda atrás: se añade una regla, nadie añade su
  # caso, y los dos tests de arriba siguen en verde sobre una cobertura vieja.
  # Mismo fallo que el manifiesto de test_meta_fp: la lista medía lo recordado.
  local id faltan=""
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    grep -q "$id" "$PROJECT_ROOT/tools/semgrep/fixtures/swift-malo.swift" 2>/dev/null \
      || faltan="$faltan $id"
  done < <(grep -oE '^  - id: [a-z0-9-]+' "$PROJECT_ROOT/tools/semgrep/rules/swift.yaml" | awk '{print $3}')
  [ -z "$faltan" ] && return 0
  echo "    Reglas de swift.yaml sin caso en el fixture malo:$faltan"
  echo "    Añade su caso malo Y su caso bueno en el mismo commit que la regla."
  return 1
}

# ════════════════════════════════════════════════════════════════════
# El corpus NO puede bloquear un commit — y esto se prueba CORRIENDO el gate
# ════════════════════════════════════════════════════════════════════
# La primera versión de este test comprobaba que `tools/semgrep/fixtures/`
# estuviera en `.semgrepignore`. Estaba. Y aun así, al commitear el corpus, el
# hook `semgrep-staged` bloqueó con los seis anti-patrones del fixture MALO:
# `.semgrepignore` se aplica cuando semgrep DESCUBRE rutas, y en `--staged` se
# le pasan como TARGETS explícitos. La declaración estaba puesta y no surtía
# efecto — testeé lo que el archivo dice, no lo que el gate hace.
# Por eso ahora el test STAGEA el fixture y corre el gate de verdad.
_sr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  cp -R "$PROJECT_ROOT/tools/semgrep/rules" "$d/tools/semgrep/"
  cp -R "$PROJECT_ROOT/tools/semgrep/fixtures" "$d/tools/semgrep/"
  ( cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_el_corpus_no_bloquea_un_commit() {
  _sr_disponible || { echo "    (saltado: semgrep o jq ausentes)"; return 0; }
  git add -A tools/semgrep/fixtures >/dev/null 2>&1
  local out rc; out="$(bash tools/semgrep-scan.sh --staged 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    stagear el CORPUS bloquea el commit (exit $rc):"
    printf '%s\n' "$out" | sed 's/^/      /'
    echo "    Los fixtures son código escrito para ser detectado. Si cuentan en el"
    echo "    scan del proyecto, el trinquete nace inflado y nadie puede commitearlos."
    return 1; }
}
test_stagear_el_corpus_no_bloquea_el_commit() { _sr_sandbox _case_el_corpus_no_bloquea_un_commit; }

# Y el mecanismo que de verdad lo consigue, declarado aparte para que nadie lo
# quite creyéndolo redundante: el corpus se filtra de la LISTA DE TARGETS.
# Ni `.semgrepignore` ni `--exclude` sirven aquí — los dos se aplican a rutas
# que semgrep descubre, y una ruta pasada como target explícito gana a ambos.
test_el_corpus_se_filtra_de_los_targets_no_por_ignore() {
  grep -q 'case "\$f" in "\$FIXTURES_DIR"/\*) continue ;; esac' "$PROJECT_ROOT/tools/semgrep-scan.sh" 2>/dev/null \
    || { echo "    semgrep-scan.sh ya no filtra el corpus de la lista de targets."
         echo "    .semgrepignore y --exclude NO bastan: no se aplican a rutas pasadas"
         echo "    como targets explícitos, que es lo que hace el modo --staged."; return 1; }
}

test_el_selftest_elige_un_fixture_MALO_no_el_primero_del_directorio() {
  # El selftest de validate-harness cogía `ls tools/semgrep/fixtures/* | head -1`
  # dando por hecho que todo lo de ahí dispara alguna regla. En cuanto el
  # directorio tuvo un README y un fixture BUENO —que por definición da cero—
  # empezó a coger uno de esos y a declarar el nivel 2 MUDO estando sano.
  # Un selftest con falsos positivos se ignora entero, y deja de proteger justo
  # de aquello para lo que existe.
  grep -q 'fixtures/\*-malo\.\*' "$PROJECT_ROOT/tools/validate-harness.sh" 2>/dev/null \
    || { echo "    validate-harness no selecciona un fixture *-malo.*: cualquier archivo"
         echo "    nuevo en tools/semgrep/fixtures/ puede volver a romper el selftest"; return 1; }
  ls "$PROJECT_ROOT"/tools/semgrep/fixtures/*-malo.* >/dev/null 2>&1 \
    || { echo "    no hay ningún fixture *-malo.*: el selftest de semgrep se queda sin corpus"; return 1; }
}
