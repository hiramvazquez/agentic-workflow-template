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
