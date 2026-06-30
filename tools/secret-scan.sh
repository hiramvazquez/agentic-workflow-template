#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# secret-scan.sh — wrapper portable sobre gitleaks (Anillo 1 + Anillo 3)
# ════════════════════════════════════════════════════════════════════
# Modos:
#   --staged   solo lo staged (pre-commit, sub-segundo) ← default del hook
#   --range    commits del push actual (pre-push)
#   --history  TODO el historial (nocturno / adopción inicial)
#   --all      árbol de trabajo completo
#
# Usa .gitleaks.toml (config + allowlist) y .gitleaks-baseline.json si existe.
# Si gitleaks no está instalado: avisa cómo instalarlo y NO bloquea (failure-open
# en local; en CI deberías hacerlo obligatorio — ver ci/run-gates.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

MODE="${1:---staged}"

if ! command -v gitleaks >/dev/null 2>&1; then
  cat >&2 <<'EOF'
⚠️  gitleaks no está instalado — secret-scan OMITIDO en local.
   Instálalo:  brew install gitleaks   |   https://github.com/gitleaks/gitleaks
   (En CI el scan SÍ es obligatorio; ver ci/run-gates.sh.)
EOF
  exit 0
fi

BASE=""; [ -f .gitleaks-baseline.json ] && BASE="--baseline-path .gitleaks-baseline.json"

case "$MODE" in
  --staged)  gitleaks git --staged --no-banner --redact $BASE ;;
  --range)   gitleaks git --no-banner --redact $BASE \
               --log-opts="${RANGE:-@{push}..HEAD}" 2>/dev/null \
               || gitleaks git --staged --no-banner --redact $BASE ;;
  --history) gitleaks git --no-banner --redact $BASE ;;
  --all)     gitleaks dir . --no-banner --redact $BASE ;;
  *) echo "uso: secret-scan.sh [--staged|--range|--history|--all]" >&2; exit 2 ;;
esac
rc=$?
[ $rc -ne 0 ] && echo "❌ secret-scan: gitleaks encontró posibles secretos (ver arriba). Rota la credencial y quítala del diff." >&2
exit $rc
