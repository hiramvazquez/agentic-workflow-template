#!/usr/bin/env bash
# LA MATRIZ DE SKILLS TAMBIÉN VIGILA BASH.
#
# El agujero real: `skill-reminder` cuelga de `PreToolUse Edit|Write`, así que
# escribir con `sed -i`, `tee`, una redirección o `python3 -c` esquivaba la
# matriz §11 por completo. Por ahí se coló una decisión de arquitectura en el
# primer proyecto (el aislamiento de actores del target), sin mala intención:
# el agente usó la herramienta equivocada y nadie miró.
#
# El riesgo de este gate es el OPUESTO al del agujero: si bloquea comandos de
# LECTURA, alguien lo apaga entero y volvemos al punto de partida (ley del
# 10%). Por eso más de la mitad de estos tests son falsos positivos.

_bm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/skills/domain" "$d/app/Domain"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT"/tools/*.sh "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    printf 'full\n' > tools/preset
    printf '# matriz\n**/Domain/**|.agents/skills/domain/SKILL.md\n' > tools/skill-matrix.conf
    printf '# skill\n' > .agents/skills/domain/SKILL.md
    printf 'let x = 1\n' > app/Domain/Movie.swift
    # Detectores en verde: aquí se prueba la matriz, no el resto del gate.
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/drift-ratchet.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/check-layers.sh
    rm -f tools/semgrep-scan.sh tools/check-review-marker.sh 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_bmgate() { # _bmgate <comando> → exit code del hook
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"}}" \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

# ── DETECCIONES: las cuatro formas de escribir esquivando Edit ───────
_case_sed_i_bloquea() {
  local rc; rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    sed -i sobre un archivo de la matriz pasó (exit $rc)"; return 1; }
}
test_sed_in_place_sobre_la_matriz_bloquea() { _bm_sandbox _case_sed_i_bloquea; }

_case_redireccion_bloquea() {
  local rc; rc="$(_bmgate 'echo nuevo > app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    una redirección sobre la matriz pasó (exit $rc)"; return 1; }
}
test_redireccion_sobre_la_matriz_bloquea() { _bm_sandbox _case_redireccion_bloquea; }

_case_tee_bloquea() {
  local rc; rc="$(_bmgate 'echo x | tee app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tee sobre la matriz pasó (exit $rc)"; return 1; }
}
test_tee_sobre_la_matriz_bloquea() { _bm_sandbox _case_tee_bloquea; }

_case_leida_la_skill_pasa() {
  # El camino feliz: si YA leíste la referencia, el comando pasa. Sin esto el
  # gate sería un muro, no un gate.
  mkdir -p .agents/state/skills-read
  : > ".agents/state/skills-read/.agents__skills__domain__SKILL.md.read"
  local rc; rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    con la skill YA leída el comando fue bloqueado (exit $rc)"; return 1; }
}
test_con_la_referencia_leida_el_comando_pasa() { _bm_sandbox _case_leida_la_skill_pasa; }

# ── FALSOS POSITIVOS (más de la mitad de la suite, a propósito) ──────
_case_lectura_pasa() {
  # `cat` NO escribe. Bloquear lecturas es la vía rápida a que apaguen el gate.
  local rc; rc="$(_bmgate 'cat app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    un cat (lectura) fue bloqueado (exit $rc)"; return 1; }
}
test_leer_un_archivo_de_la_matriz_no_bloquea() { _bm_sandbox _case_lectura_pasa; }

_case_grep_pasa() {
  local rc; rc="$(_bmgate 'grep -n let app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    un grep sobre la matriz fue bloqueado (exit $rc)"; return 1; }
}
test_grep_sobre_la_matriz_no_bloquea() { _bm_sandbox _case_grep_pasa; }

_case_devnull_pasa() {
  # `2>/dev/null` es una redirección… a /dev/null. Si el parser la contara
  # como escritura, CUALQUIER comando silenciado dispararía el gate.
  local rc; rc="$(_bmgate 'ls app/Domain/Movie.swift 2>/dev/null')"
  [ "$rc" = "0" ] || { echo "    2>/dev/null se interpretó como escritura (exit $rc)"; return 1; }
}
test_redireccion_a_devnull_no_cuenta_como_escritura() { _bm_sandbox _case_devnull_pasa; }

_case_escribir_fuera_de_la_matriz_pasa() {
  local rc; rc="$(_bmgate 'echo hola > /tmp/apunte.txt')"
  [ "$rc" = "0" ] || { echo "    escribir FUERA de la matriz fue bloqueado (exit $rc)"; return 1; }
}
test_escribir_fuera_de_la_matriz_no_bloquea() { _bm_sandbox _case_escribir_fuera_de_la_matriz_pasa; }

_case_docs_exentos() {
  # Editar documentación NO es editar el código de ese área — el falso
  # positivo original de skill-reminder, que no puede reaparecer por Bash.
  mkdir -p docs
  local rc; rc="$(_bmgate 'echo nota >> docs/apuntes.md')"
  [ "$rc" = "0" ] || { echo "    escribir en docs/ fue bloqueado (exit $rc)"; return 1; }
}
test_escribir_documentacion_no_bloquea() { _bm_sandbox _case_docs_exentos; }
