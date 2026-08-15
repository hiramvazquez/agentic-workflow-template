#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# EL invariante de KMP: commonMain no importa plataforma
# ════════════════════════════════════════════════════════════════════
# El harness modelaba un solo eje —el grafo por directorio de check-layers— y
# KMP añade otro que ese grafo no ve: el de source sets. Un `import android.*`
# en commonMain compila mientras solo construyas Android y revienta semanas
# después, al añadir el target iOS, en el CI de otro y con un error que no
# apunta al import. Es el ~10x por nivel de §14.1 pagado entero.

_ss_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/shared/src/commonMain/kotlin" \
           "$d/shared/src/androidMain/kotlin"
  cp "$PROJECT_ROOT/tools/check-source-sets.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_common() { printf '%s\n' "$@" > shared/src/commonMain/kotlin/Repo.kt; }

_case_import_de_plataforma_en_common_bloquea() {
  _common 'package dominio' 'import android.net.Uri' '' 'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un import de plataforma en commonMain NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *Repo.kt*) : ;; *) echo "    no dijo qué archivo"; return 1 ;; esac
  case "$out" in *expect*) : ;; *) echo "    no apuntó a expect/actual, que es la salida"; return 1 ;; esac
}
test_commonmain_no_puede_importar_plataforma() { _ss_repo _case_import_de_plataforma_en_common_bloquea; }

_case_el_mismo_import_en_androidmain_es_correcto() {
  # Es el punto entero del eje: lo prohibido en commonMain es lo NORMAL en
  # androidMain. Un detector que no distinga los dos source sets prohíbe usar
  # la plataforma en el sitio donde hay que usarla.
  _common 'package dominio' 'expect class Reloj'
  printf '%s\n' 'package dominio' 'import android.net.Uri' 'actual class Reloj' \
    > shared/src/androidMain/kotlin/Reloj.kt
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    || { echo "    FALSO POSITIVO: acusó a androidMain, que es donde SÍ toca importar plataforma"; return 1; }
}
test_androidmain_si_puede_importar_plataforma() { _ss_repo _case_el_mismo_import_en_androidmain_es_correcto; }

# ── FALSO POSITIVO: nombrar un paquete no es importarlo ─────────────
# La mina que este repo ya ha pisado siete veces. Un KDoc que explica por qué NO
# se usa `android.net.Uri`, o una cadena con ese texto, no es un import. El
# anclaje se apoya en la gramática de Kotlin —un import solo vale al principio
# de la línea—, no en nuestro criterio.
_case_mencionar_no_es_importar() {
  _common 'package dominio' \
    '// No uses android.net.Uri aquí: rompe iOS. Ver expect/actual.' \
    '/** Antes esto hacía import android.net.Uri y reventó el target iOS. */' \
    'val doc = "import android.net.Uri"' \
    'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: un comentario/cadena que NOMBRA el paquete contó como import (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_comentario_que_nombra_el_paquete_no_es_un_import() { _ss_repo _case_mencionar_no_es_importar; }

# ── FALSO POSITIVO: un repo sin KMP no puede oír este gate jamás ────
# La mitad de los adoptantes no usa KMP. Un aviso permanente para ellos se
# aprende a ignorar, y con él se ignora el del día que importa (§14.2). "No
# aplica" es un hecho distinto de "no pude mirar" y se dice distinto: exit 0.
_case_repo_sin_kmp_calla() {
  rm -rf shared
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un repo sin KMP no salió 0 (exit $rc)"; return 1; }
  case "$out" in *no-aplica*) : ;; *)
    echo "    no declaró el estado 'no-aplica': $out"; return 1 ;; esac
  case "$out" in *"❌"*) echo "    un repo sin KMP recibió un ERROR"; return 1 ;; esac
}
test_un_repo_sin_kmp_declara_no_aplica_y_no_avisa() { _ss_repo _case_repo_sin_kmp_calla; }

_case_el_conf_solo_puede_ampliar() {
  # Misma dirección que los trinquetes (§9): la lista de prohibidos solo crece.
  # Un conf que pudiera recortarla convertiría el invariante en una sugerencia,
  # y bastaría añadir una línea para dejar de ver la violación de al lado.
  _common 'package dominio' 'import com.miorg.nativo.Cosa' 'class Repo'
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    || { echo "    un import no prohibido bloqueó sin estar en la lista"; return 1; }
  printf '%s\n' '# prohibidos extra de este proyecto' 'com\.miorg\.nativo\.' > tools/source-sets.conf
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    && { echo "    el conf no amplió la lista: el prefijo añadido no bloqueó"; return 1; }
  return 0
}
test_el_conf_amplia_la_lista_de_prohibidos() { _ss_repo _case_el_conf_solo_puede_ampliar; }
