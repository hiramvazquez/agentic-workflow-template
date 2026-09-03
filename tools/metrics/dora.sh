#!/usr/bin/env bash
# Envoltorio delgado de dora.py — las seis métricas de entrega (PRD 0009 §5).
#   bash tools/metrics/dora.sh [--days N]   informe + apéndice a la serie
#   bash tools/metrics/dora.sh --rollup     resumen semanal commiteado
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 3
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || {
  echo "⚠️  dora: no hay python; no puedo ni mirar (§14.3)." >&2; exit 3; }
exec "$PY" tools/metrics/dora.py "$@"
