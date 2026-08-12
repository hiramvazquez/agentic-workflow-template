#!/usr/bin/env bash
# Backend hermético para tests. Su comportamiento viene de fixtures, no de red/modelos.
set -uo pipefail
case "${1:-}" in
  capabilities) echo 'run=true review=true read_only=true subagents=true hooks=true' ;;
  run)
    if [ -n "${FAKE_RUN_SCRIPT:-}" ]; then exec bash "$FAKE_RUN_SCRIPT" "${2:-}" "${3:-}"
    else cat "${2:-/dev/null}"
    fi
    ;;
  review)
    if [ -n "${FAKE_REVIEW_SCRIPT:-}" ]; then exec bash "$FAKE_REVIEW_SCRIPT" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    fi
    printf '%s\n' "${FAKE_REVIEW_RESULT:-VERDICT: GREEN
FINDINGS: 0
SCOPE: fake}" ;;
  *) exit 3 ;;
esac
