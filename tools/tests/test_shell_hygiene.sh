#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Higiene de shell del harness — detector de una clase entera de bug
# ════════════════════════════════════════════════════════════════════
# El bug que motivó este archivo (PRD 0001 §18 G14):
#
#     fail "STALE (HEAD cambió $MARKED_HEAD→$CUR_HEAD)"
#
# Bash consume los bytes de `→` como parte del nombre de variable, así que
# expande `$MARKED_HEAD→` (una variable que no existe). Con `set -u` eso mata
# el script. Lo mismo con `«$SCOPE»`, `$VAR…`, `$VAR·`: cualquier carácter
# tipográfico pegado a una variable sin llaves.
#
# Es un bug especialmente traicionero en un harness ESCRITO EN ESPAÑOL:
# los mensajes usan →, «», …, · de forma natural, y solo explota en la RAMA
# que imprime ese mensaje. En `check-review-marker.sh` esa rama era
# "el marker está stale" — es decir, se rompía justo cuando el gate tenía
# que bloquear. Se descubrió por accidente, al intentar commitear P2.
#
# Estos tests son un DETECTOR, no un caso: barren todos los .sh del harness.

_shell_files() {
  find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/ci" \
       -name '*.sh' -type f 2>/dev/null
}

# ── El bug de G14: $VAR pegado a un carácter no-ASCII ───────────────
test_sin_variables_pegadas_a_caracteres_no_ascii() {
  local hits
  # Se saltan los COMENTARIOS: este mismo archivo documenta el anti-patrón y
  # se detectaba a sí mismo — el falso positivo de G7 otra vez, ahora en el
  # detector recién escrito. Confirma el patrón: el primer falso positivo de
  # un detector aparece en el repo del propio detector.
  hits="$(_shell_files | xargs perl -ne '
      next if /^\s*#/;
      print "$ARGV:$.: $_" if /\$[A-Za-z_]\w*[^\x00-\x7F\s]/;
      close ARGV if eof;
    ' 2>/dev/null)"
  [ -z "$hits" ] && return 0
  echo "    \$VAR pegado a un carácter no-ASCII (bash se lo traga como parte del nombre)."
  echo "    Usa \${VAR} con llaves. Ocurrencias:"
  printf '%s\n' "$hits" | sed 's/^/      /'
  return 1
}

# ── Todos los scripts deben parsear ─────────────────────────────────
test_todos_los_scripts_parsean() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    bash -n "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    scripts con error de sintaxis:"; printf '%s' "$bad"; return 1
}

# ── `set -u` en todos: una variable no definida debe gritar ─────────
test_todos_los_scripts_usan_set_u() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Se saltan los archivos que se SOURCEAN, no se ejecutan: los tests y las
    # librerías de `lib/`. En ellos `set -u` lo impone el llamador; ponerlo
    # dentro cambiaría las opciones del shell del que los carga.
    case "${f##*/}" in test_*.sh) continue ;; esac
    case "$f" in */lib/*) continue ;; esac
    grep -qE '^set -[a-z]*u' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    sin \`set -u\` (una variable vacía por error pasaría silenciosa):"
  printf '%s' "$bad"; return 1
}

# ── Los hooks derivan PROJECT_ROOT de su propio dirname ─────────────
# Si dependieran del cwd, se comportarían distinto según quién los invoque.
test_los_hooks_no_dependen_del_cwd() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -q 'PROJECT_ROOT=' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(find "$PROJECT_ROOT/scripts/agent-hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null)
  [ -z "$bad" ] && return 0
  echo "    hooks sin PROJECT_ROOT derivado de \$0 (dependerían del cwd):"
  printf '%s' "$bad"; return 1
}

# ── Los detectores respetan su contrato de stdout ───────────────────
# El conteo del trinquete se parsea de estas líneas: si un detector deja de
# emitirlas, el trinquete lee 0 y aprueba en silencio (mismo patrón que G2).
test_los_detectores_emiten_su_contrato() {
  local bad=""
  grep -q 'DRIFT_SUMMARY errors=' "$PROJECT_ROOT/tools/check-drift.sh"    2>/dev/null || bad="${bad}      check-drift.sh sin DRIFT_SUMMARY"$'\n'
  grep -q 'LAYERS_SUMMARY errors=' "$PROJECT_ROOT/tools/check-layers.sh"  2>/dev/null || bad="${bad}      check-layers.sh sin LAYERS_SUMMARY"$'\n'
  grep -q 'SEMGREP_SUMMARY errors=' "$PROJECT_ROOT/tools/semgrep-scan.sh" 2>/dev/null || bad="${bad}      semgrep-scan.sh sin SEMGREP_SUMMARY"$'\n'
  grep -q 'MUTATION_SUMMARY score=' "$PROJECT_ROOT/tools/mutation-score.sh" 2>/dev/null || bad="${bad}      mutation-score.sh sin MUTATION_SUMMARY"$'\n'
  [ -z "$bad" ] && return 0
  echo "    detectores que rompieron su contrato de salida:"; printf '%s' "$bad"; return 1
}
