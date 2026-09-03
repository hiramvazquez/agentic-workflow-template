#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# detector-runs.sh — el DENOMINADOR: qué miró cada detector, y qué no
# ════════════════════════════════════════════════════════════════════
# PRD 0008 fase 1. Wrapper DELGADO a propósito: guarda de python3, contrato de
# exit 3 y `exec`. NO parsea nada — es el patrón que ya usan gate-value.sh y
# escape-rate.sh, y el PRD lo exige explícitamente para que la lógica viva en un
# solo sitio.
#
# Va aparte de metrics-report.py, que está en NO-TOUCH del PRD: ese fichero
# tiene 368 líneas contra un hard limit de 400 (§4), y refactorizarlo a
# dispatcher movería `escape_rate` y `gate_value`, que un gate del Anillo 3 ya
# consume. El wrapper propio, además, viaja solo al adoptante: tools/metrics
# está dentro de SYNC_PATHS.
#
#   bash tools/metrics/detector-runs.sh                    # el log por defecto
#   bash tools/metrics/detector-runs.sh /ruta/runs.jsonl   # uno concreto
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
command -v python3 >/dev/null 2>&1 \
  || { echo "⚠️  detector-runs: python3 ausente — no pude leer JSONL con seguridad." >&2; exit 3; }
exec python3 tools/metrics/detector_runs.py "$@"
