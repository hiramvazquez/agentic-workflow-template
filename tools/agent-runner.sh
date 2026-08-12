#!/usr/bin/env bash
# Boundary portable para agentes: run (salida opaca) y review (veredicto parseable).
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 3

MODE="${1:-}"; [ -n "$MODE" ] && shift || true
BACKEND=claude; PROMPT_FILE=""; CWD="$ROOT"; BASE=""; HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --backend|--prompt-file|--cwd|--base|--head)
      [ $# -ge 2 ] || { echo "agent-runner: falta valor para $1" >&2; exit 3; }
      case "$1" in
        --backend) BACKEND="$2" ;; --prompt-file) PROMPT_FILE="$2" ;; --cwd) CWD="$2" ;;
        --base) BASE="$2" ;; --head) HEAD_REF="$2" ;;
      esac
      shift 2 ;;
    *) echo "agent-runner: argumento desconocido: $1" >&2; exit 3 ;;
  esac
done
case "$MODE" in run|review) ;; *) echo "agent-runner: usa run|review" >&2; exit 3 ;; esac
case "$BACKEND" in ''|*[!A-Za-z0-9_-]*) echo "agent-runner: backend inválido" >&2; exit 3 ;; esac
ADAPTER="$ROOT/tools/agent-backends/$BACKEND.sh"
[ -x "$ADAPTER" ] || { echo "agent-runner: backend unsupported: $BACKEND" >&2; exit 3; }

resolve_inside() {
  python3 - "$ROOT" "$1" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve(); value=Path(sys.argv[2])
path=(value if value.is_absolute() else root/value).resolve(strict=True)
try: path.relative_to(root)
except ValueError: raise SystemExit(1)
print(path)
PY
}
PROMPT_ABS="$(resolve_inside "$PROMPT_FILE" 2>/dev/null)" \
  || { echo "agent-runner: prompt ausente/fuera del repo" >&2; exit 3; }
CWD_ABS="$(resolve_inside "$CWD" 2>/dev/null)" \
  || { echo "agent-runner: cwd ausente/fuera del repo" >&2; exit 3; }
[ -d "$CWD_ABS" ] || { echo "agent-runner: cwd no es directorio" >&2; exit 3; }

if [ "$MODE" = review ]; then
  for ref in "$BASE" "$HEAD_REF"; do
    [ -n "$ref" ] && [[ "$ref" != -* ]] \
      && git -C "$CWD_ABS" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1 \
      || { echo "agent-runner: ref review inválida" >&2; exit 3; }
  done
fi

CAPS="$($ADAPTER capabilities 2>/dev/null)" \
  || { echo "agent-runner: backend no declara capacidades" >&2; exit 3; }
case "$MODE:$CAPS" in
  run:*run=true*) ;;
  review:*review=true*read_only=true*) ;;
  *) echo "agent-runner: backend unsupported para $MODE ($CAPS)" >&2; exit 3 ;;
esac

if [ "$MODE" = run ]; then
  exec "$ADAPTER" run "$PROMPT_ABS" "$CWD_ABS"
fi

OUT="$(mktemp)"; ERR="$(mktemp)"; trap 'rm -f "$OUT" "$ERR"' EXIT
"$ADAPTER" review "$PROMPT_ABS" "$CWD_ABS" "$BASE" "$HEAD_REF" >"$OUT" 2>"$ERR"
RC=$?
[ "$RC" = 0 ] || { cat "$ERR" >&2; exit "$RC"; }
RESULT="$(cat "$OUT")"
printf '%s\n' "$RESULT"
. "$ROOT/scripts/agent-hooks/lib/verdict.sh"
VERDICT="$(verdict_parse "$RESULT")"
FINDINGS="$(verdict_findings "$RESULT")"
SCOPE="$(verdict_scope "$RESULT")"
[ -n "$FINDINGS" ] && [ -n "$SCOPE" ] \
  || { echo "agent-runner: review sin FINDINGS/SCOPE válidos" >&2; exit 1; }
case "$VERDICT:$FINDINGS" in GREEN:0|AMBER:*) exit 0 ;; RED:*) exit 1 ;; GREEN:*) echo "agent-runner: GREEN contradice FINDINGS=$FINDINGS" >&2; exit 1 ;; *) echo "agent-runner: review sin VERDICT válido" >&2; exit 1 ;; esac
