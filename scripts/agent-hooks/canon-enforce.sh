#!/usr/bin/env bash
# Hook Stop (Claude) / stop (Cursor) — BLOQUEANTE ante violaciones de reglas
# irrompibles que un grep rápido (<1s) puede cazar. Bloquea el cierre de turno
# (exit 2) hasta que se arregle. Solo checks baratos; lo pesado va en check-drift.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

VIOLATIONS=()

# <!-- FILL: añade aquí los "checks irrompibles" baratos de TU proyecto.
#      Patrón: grep por el anti-pattern; si aparece, push a VIOLATIONS.
#      Ejemplos (descomenta/adapta a tu stack): -->
#
# # Secretos olvidados en código (defensa redundante al gitleaks):
# LEAKS=$(grep -rEln "(service_role|sk-[A-Za-z0-9]{20}|BEGIN [A-Z ]*PRIVATE KEY)" \
#   --include=*.swift --include=*.kt --include=*.ts src 2>/dev/null || true)
# [ -n "$LEAKS" ] && VIOLATIONS+=("❌ Posible secreto hardcoded en: $LEAKS")
#
# # Almacenamiento inseguro de datos sensibles:
# INSECURE=$(grep -rEln "UserDefaults.*token|localStorage.setItem.*token" src 2>/dev/null || true)
# [ -n "$INSECURE" ] && VIOLATIONS+=("⚠️  Token en storage inseguro: $INSECURE")

[ ${#VIOLATIONS[@]} -eq 0 ] && exit 0

MSG=""
for v in "${VIOLATIONS[@]}"; do MSG+="$v"$'\n'; done
# Solo bloquea ante ❌; ⚠️ son warnings informativos.
if printf '%s' "$MSG" | grep -q "❌"; then
  hook_block "🛑 CANON ENFORCE — cierre bloqueado por reglas irrompibles:"$'\n\n'"$MSG"
fi
printf '%s' "$MSG"
exit 0
