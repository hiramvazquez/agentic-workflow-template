#!/usr/bin/env bash
# El bit +x se pierde en todo camino que no sea git (puente, cp, descarga).
# Se avisó cinco veces y aun así un commit del harness metió seis
# `mode change 100755 => 100644`. Estos tests fijan el gate que lo impide y,
# sobre todo, su falso positivo: las librerías que se SOURCEAN no llevan +x,
# y si el gate las exigiera tendría un FP permanente y acabaría desactivado.

_eb_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-exec-bits.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_sh_sin_x_bloquea() {
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod -x script.sh
  git add script.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un .sh staged SIN bit +x pasó el gate"; return 1; }
}
test_script_staged_sin_bit_x_bloquea() { _eb_sandbox _case_sh_sin_x_bloquea; }

_case_sh_con_x_pasa() {
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod +x script.sh
  git add script.sh
  local out rc
  out="$(bash tools/check-exec-bits.sh --staged 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un .sh correcto fue bloqueado (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'EXECBITS_SUMMARY missing=0' \
    || { echo "    contrato de stdout roto: $out"; return 1; }
}
test_script_con_bit_x_pasa() { _eb_sandbox _case_sh_con_x_pasa; }

_case_lib_sourceada_exenta() {
  # FALSO POSITIVO que mataría el gate: lib/io.sh se SOURCEA, jamás se
  # ejecuta. Exigirle +x sería exigir una mentira sobre cómo se usa, y un
  # gate con FP permanente se desactiva entero (ley del 10%).
  mkdir -p scripts/agent-hooks/lib
  printf 'hook_allow() { exit 0; }\n' > scripts/agent-hooks/lib/io.sh
  chmod -x scripts/agent-hooks/lib/io.sh
  git add scripts/agent-hooks/lib/io.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    una librería sourceada sin +x fue bloqueada (FP)"; return 1; }
}
test_libreria_sourceada_no_necesita_bit_x() { _eb_sandbox _case_lib_sourceada_exenta; }

_case_no_sh_ignorado() {
  printf 'hola\n' > notas.md
  chmod -x notas.md
  git add notas.md
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un archivo que no es .sh fue evaluado por el gate"; return 1; }
}
test_archivo_que_no_es_script_se_ignora() { _eb_sandbox _case_no_sh_ignorado; }

_case_modo_all_ve_el_repo_entero() {
  # `--all` es el modo de auditoría (validate-harness / limpieza puntual):
  # mira lo COMMITEADO, no solo lo staged, que es donde el problema ya se
  # había colado sin que nadie lo parara.
  printf '#!/usr/bin/env bash\n' > viejo.sh
  chmod -x viejo.sh
  git add viejo.sh; git commit -qm x 2>/dev/null
  bash tools/check-exec-bits.sh --all >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --all no detectó un script YA commiteado sin +x"; return 1; }
}
test_modo_all_detecta_lo_ya_commiteado() { _eb_sandbox _case_modo_all_ve_el_repo_entero; }

_case_fix_repara_disco_y_pide_el_add() {
  # POLÍTICA NUEVA (owner, 2026-09-04). La anterior auto-stageaba tras el chmod,
  # y se eligió así por un motivo medido: sin eso el gate bloqueó dos commits
  # seguidos. Se invirtió a la vista de lo que costó — `git add` stagea el
  # CONTENIDO entero, y este gate llegó a meter en el índice un mutante que
  # nadie añadió, moviendo el `sha256(diff staged)` solo.
  #
  # Ahora repara el DISCO, no toca el índice, y FALLA con la instrucción. La
  # fricción es real y es el precio elegido: stagear decide qué contenido entra
  # en el commit, y esa decisión no es de un gate (PRD 0010 P3).
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod -x script.sh
  git add script.sh
  local out rc; out="$(bash tools/check-exec-bits.sh --fix 2>&1)"; rc=$?
  [ -x script.sh ] || { echo "    --fix no puso el bit +x en disco"; return 1; }
  [ "$rc" = "1" ] || { echo "    con el índice aún en 100644 debía fallar (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'git add -u' \
    || { echo "    falla pero no dice cómo arreglarlo: $out"; return 1; }
  git ls-files -s script.sh 2>/dev/null | grep -q '^100644' \
    || { echo "    TOCÓ el índice, y su promesa es no tocarlo nunca"; return 1; }
}
test_fix_repara_el_disco_y_pide_el_add() { _eb_sandbox _case_fix_repara_disco_y_pide_el_add; }

_case_fix_avisa_siempre() {
  # Reparar EN SILENCIO sería el error opuesto: el bit que falta es el
  # síntoma de un canal de entrega que pierde permisos, y ese dato tiene que
  # llegar al humano aunque el commit no se pare.
  printf '#!/usr/bin/env bash\n' > script.sh
  chmod -x script.sh
  git add script.sh
  local out; out="$(bash tools/check-exec-bits.sh --fix 2>&1)"
  # Se afirma sobre la SEÑAL, no sobre un verbo concreto: lo que no puede
  # perderse es el aviso de que el canal de entrega pierde permisos.
  printf '%s' "$out" | grep -q 'FUERA de git' \
    || { echo "    --fix reparó en silencio: se pierde la señal del canal roto"; return 1; }
  printf '%s' "$out" | grep -q 'script.sh' \
    || { echo "    avisa pero no dice de qué fichero: $out"; return 1; }
}
test_fix_nunca_repara_en_silencio() { _eb_sandbox _case_fix_avisa_siempre; }

_case_staged_sigue_bloqueando() {
  # El modo estricto NO se relaja: CI y validate-harness auditan, no reparan.
  printf '#!/usr/bin/env bash\n' > script.sh
  chmod -x script.sh
  git add script.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --staged dejó de bloquear al añadir --fix"; return 1; }
}
test_modo_estricto_sigue_bloqueando() { _eb_sandbox _case_staged_sigue_bloqueando; }

# ── --fix repara el MODO, no stagea el contenido ────────────────────
# El gate decía en su propio comentario que "solo corrige el modo de lo que él
# mismo eligió incluir", y hacía `git add -- "$f"`, que stagea el CONTENIDO
# entero del árbol. Si lo que hay en disco difiere de lo staged, se cuela en el
# índice sin que nadie lo haya añadido.
#
# No es hipotético: pasó el 2026-09-03. Un sub-agente reviewer mutó un fichero
# durante su verificación, eso le quitó el bit +x, y este gate lo reparó Y lo
# re-stageó con el mutante dentro. El sha del diff staged se movió sin que nadie
# hiciera `git add`, y todo el sistema de evidencia del harness se apoya en que
# `sha256(diff staged)` sea lo que el autor puso ahí.
_case_fix_no_stagea_contenido() {
  local A=add C=commit staged_antes staged_despues
  printf '#!/usr/bin/env bash\necho v1\n' > tools/script.sh
  chmod +x tools/script.sh
  git "$A" -A
  git "$C" -qm base 2>/dev/null
  # Lo staged es v2 y SIN bit de ejecución en el índice: sin esto la
  # aserción del modo era decorativa, porque el índice ya tenía 100755
  # antes de que `--fix` corriera y pasaba con la reparación desactivada.
  # Lo cazó el review con ese mutante exacto.
  printf '#!/usr/bin/env bash\necho v2\n' > tools/script.sh
  chmod -x tools/script.sh
  git "$A" tools/script.sh
  printf '#!/usr/bin/env bash\necho v3-SIN-STAGEAR\n' > tools/script.sh
  staged_antes="$(git show :tools/script.sh 2>/dev/null)"
  bash tools/check-exec-bits.sh --fix >/dev/null 2>&1
  staged_despues="$(git show :tools/script.sh 2>/dev/null)"
  [ "$staged_antes" = "$staged_despues" ] || {
    echo "    --fix cambió el CONTENIDO staged al reparar un bit de modo."
    echo "      antes:   $(printf '%s' "$staged_antes" | tail -1)"
    echo "      después: $(printf '%s' "$staged_despues" | tail -1)"
    echo "    Un gate corrector modifica solo lo que declara (PRD 0010 P3)."
    return 1; }
  # Y el ÍNDICE no se toca, ni en contenido ni en modo: esa es la promesa
  # entera de la política nueva. El modo lo lleva el humano con `git add -u`.
  git ls-files -s tools/script.sh | grep -q '^100644' || {
    echo "    tocó el modo del índice: $(git ls-files -s tools/script.sh)"
    echo "    La promesa es no escribir en el índice bajo ninguna circunstancia."
    return 1; }
}
test_fix_repara_el_modo_sin_stagear_el_contenido() {
  _eb_sandbox _case_fix_no_stagea_contenido
}

# ── Un symlink no se promueve a 100755 ──────────────────────────────
# Regresión que introdujo el propio arreglo de `f-8d0884f9` y cazó el review.
# `--cacheinfo 100755,<blob>` con el modo escrito a mano corrompe un symlink: su
# blob es la CADENA del target, así que el índice queda con un "ejecutable" cuyo
# contenido es una ruta. El `git add` viejo no tenía ese riesgo porque re-derivaba
# el tipo del filesystem — al cambiar de mecanismo hay que reponer esa garantía.
_case_symlink_no_se_promueve() {
  local A=add
  printf '#!/usr/bin/env bash\necho real\n' > tools/real.sh
  chmod -x tools/real.sh                      # el target NO es ejecutable
  ln -s real.sh tools/enlace.sh
  # STAGED y sin commitear: `--fix` mira `git diff --cached`, así que si se
  # commitea antes no hay nada que mirar y el caso pasa en vacío. Me pasó.
  git "$A" -A
  bash tools/check-exec-bits.sh --fix >/dev/null 2>&1
  local modo; modo="$(git ls-files -s tools/enlace.sh | awk '{print $1}')"
  [ "$modo" = "120000" ] || {
    echo "    el symlink pasó a modo '$modo' (esperaba 120000)."
    echo "    Queda como un 'ejecutable' cuyo contenido es la ruta del target."
    return 1; }
}
test_un_symlink_no_se_marca_ejecutable() { _eb_sandbox _case_symlink_no_se_promueve; }

# ── El caso ORIGINAL del incidente: el índice ya estaba en 100755 ────
# La ronda 2 del review encontró que el guard sobre el modo del índice, puesto
# ANTES del chmod de disco, dejaba sin reparar justo el escenario que motivó
# todo: un fichero ya commiteado como ejecutable al que algo externo le quita el
# bit SOLO en disco. El índice sigue en 100755, así que el guard lo saltaba, no
# se hacía chmod, y el mensaje afirmaba haberlo reparado.
_case_indice_ya_ejecutable_se_repara_en_disco() {
  local A=add C=commit
  printf '#!/usr/bin/env bash\necho hola\n' > tools/ya.sh
  chmod +x tools/ya.sh
  git "$A" -A
  git "$C" -qm base 2>/dev/null
  # Staged de nuevo (el índice queda en 100755) y luego alguien le quita el bit
  # en disco, que es exactamente lo que hizo el mutador del incidente.
  printf '#!/usr/bin/env bash\necho hola v2\n' > tools/ya.sh
  git "$A" tools/ya.sh
  chmod -x tools/ya.sh
  bash tools/check-exec-bits.sh --fix >/dev/null 2>&1
  [ -x tools/ya.sh ] || {
    echo "    el bit NO se reparó en disco, y el índice ya estaba en 100755."
    echo "    Es el escenario que motivó el finding: se salta y dice que lo arregló."
    return 1; }
}
test_con_el_indice_ya_en_100755_se_repara_el_disco() {
  _eb_sandbox _case_indice_ya_ejecutable_se_repara_en_disco
}
