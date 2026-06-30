#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# ci/run-gates.sh — Anillo 3 (CI), PROVIDER-AGNÓSTICO
# ════════════════════════════════════════════════════════════════════
# Punto de entrada ÚNICO de los gates server-side. Lo invoca CUALQUIER CI
# (GitHub, GitLab, Bitbucket, Azure, Jenkins) o nada. No imponemos proveedor.
#
# Es el backstop que cubre lo que los hooks locales NO pueden:
#   - Codex (no tiene hooks) → su único enforcement es este.
#   - commits humanos con `--no-verify`.
#   - máquinas sin lefthook instalado.
#
# Variables opcionales:
#   GATES_SECRET_MODE   history|range|all  (default: history en CI)
#   GATES_SKIP_TESTS=1  salta el paso de tests (para pipelines de solo-lint)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FAIL=0
step() { echo ""; echo "━━━ $1 ━━━"; }

# 1) Secretos — OBLIGATORIO en CI (a diferencia de local, aquí sí bloquea).
step "1/4 secret-scan (gitleaks)"
if command -v gitleaks >/dev/null 2>&1; then
  bash tools/secret-scan.sh "--${GATES_SECRET_MODE:-history}" || FAIL=1
else
  echo "❌ gitleaks ausente en CI — instálalo en el runner (es obligatorio aquí)."; FAIL=1
fi

# 2) Drift ratchet — el conteo no puede haber subido.
step "2/4 drift-ratchet"
bash tools/drift-ratchet.sh --check || FAIL=1

# 3) Build + tests por-plataforma.
step "3/4 build & tests"
if [ "${GATES_SKIP_TESTS:-0}" = "1" ]; then
  echo "(saltado por GATES_SKIP_TESTS=1)"
else
  # <!-- FILL: invoca el build/test de tu(s) plataforma(s). Ejemplos: -->
  # ./gradlew testDebugUnitTest || FAIL=1
  # xcodebuild -scheme <Scheme> -destination '...' test || FAIL=1
  # npm ci && npm test || FAIL=1
  echo "<!-- FILL: añade build/test de tu stack en ci/run-gates.sh paso 3 -->"
fi

# 4) Contratos / lints específicos del proyecto (opcional).
step "4/4 checks de proyecto"
# <!-- FILL: contract checks, schema validation, etc. -->
echo "(sin checks de proyecto configurados — opcional)"

echo ""
[ "$FAIL" -eq 0 ] && { echo "✅ run-gates: TODOS los gates pasaron."; exit 0; }
echo "❌ run-gates: al menos un gate falló (ver arriba)."; exit 1
