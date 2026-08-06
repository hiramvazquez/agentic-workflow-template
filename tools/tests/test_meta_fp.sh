#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# META-DETECTOR: todo detector tiene tests de FALSO POSITIVO
# ════════════════════════════════════════════════════════════════════
# La lección más repetida del PRD 0001, ahora mecanizada. Tres detectores se
# auto-detectaron nada más nacer (skill-reminder bloqueó editar su propia doc;
# canon-enforce marcó como secreto al archivo que define qué es un secreto;
# shell-hygiene matcheó sus propios comentarios). El patrón fue tan
# consistente que quedó como regla:
#
#   **El primer falso positivo de un detector casi siempre aparece en el
#     repo del propio detector. Escribe sus tests de FP el mismo día.**
#
# Como toda lección, o tiene detector o es prosa (AGENTS.md §10). Este es su
# detector: un MANIFIESTO explícito detector→archivo de tests, exigiendo que
# el archivo exista y contenga al menos un caso marcado "FALSO POSITIVO".
#
# Manifiesto explícito y no heurística de nombres: un meta-detector con
# falsos positivos sería una ironía demasiado cara.

# detector :: archivo de tests que cubre sus FALSOS POSITIVOS
# <!-- FILL: al añadir un detector nuevo, añade su línea AQUÍ y sus tests de
#      FP en el archivo — en el MISMO cambio. Si este test te trajo hasta
#      este comentario, ese es exactamente el momento. -->
MANIFEST="
scripts/agent-hooks/skill-reminder.sh        :: test_skill_reminder.sh
scripts/agent-hooks/canon-enforce.sh         :: test_canon_enforce.sh
scripts/agent-hooks/reviewer-gate.sh         :: test_ratchets.sh
scripts/agent-hooks/session-end.sh           :: test_judge_queue.sh
tools/check-layers.sh                        :: test_layers.sh
tools/check-drift.sh                         :: test_drift_aggregation.sh
tools/check-review-marker.sh                 :: test_review_marker_preset.sh
tools/semgrep-scan.sh                        :: test_fail_closed.sh
tools/mutation-score.sh                      :: test_fail_closed.sh
tools/lesson-detector-link.sh                :: test_lessons.sh
tools/findings/findings.sh                   :: test_findings_cli.sh
"

test_todo_detector_tiene_tests_de_falso_positivo() {
  local bad=""
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed 's/#.*//')"
    [ -z "${line// /}" ] && continue
    local det tf
    det="$(printf '%s' "$line" | awk -F' *:: *' '{print $1}' | sed 's/ *$//')"
    tf="$(printf '%s' "$line"  | awk -F' *:: *' '{print $2}' | sed 's/ *$//')"
    [ -z "$det" ] || [ -z "$tf" ] && continue

    if [ ! -f "$PROJECT_ROOT/$det" ]; then
      bad="${bad}      $det: el detector del manifiesto ya no existe (limpia la línea)"$'\n'
      continue
    fi
    if [ ! -f "$PROJECT_ROOT/tools/tests/$tf" ]; then
      bad="${bad}      $det → tools/tests/$tf NO EXISTE"$'\n'
      continue
    fi
    if ! grep -qi "falso positivo" "$PROJECT_ROOT/tools/tests/$tf" 2>/dev/null; then
      bad="${bad}      $det → $tf no contiene ningún caso marcado 'FALSO POSITIVO'"$'\n'
    fi
  done <<< "$MANIFEST"

  [ -z "$bad" ] && return 0
  echo "    Detectores sin tests de falso positivo verificables:"
  printf '%s' "$bad"
  echo "    Regla (PRD 0001, repetida 3 veces en carne propia): el primer FP de un"
  echo "    detector aparece en el repo del propio detector. Los tests de FP se"
  echo "    escriben el MISMO día que el detector, no cuando alguien se queje."
  return 1
}

# El propio manifiesto no puede quedarse vacío por un error de formato.
test_el_manifiesto_no_esta_vacio() {
  local n
  n="$(printf '%s\n' "$MANIFEST" | grep -c '::' || true)"
  [ "${n:-0}" -ge 8 ] || { echo "    el manifiesto tiene $n entradas (esperaba ≥8) — ¿se rompió el formato?"; return 1; }
}
