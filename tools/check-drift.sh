#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-drift.sh — detector mecánico de "drift" (anti-patrones de TU proyecto)
# ════════════════════════════════════════════════════════════════════
# Esqueleto genérico. Cada check es un grep/find que cuenta violaciones de una
# convención. El total alimenta el drift-ratchet (el techo solo baja).
#
# Contrato de salida (lo parsea drift-ratchet.sh):
#   - líneas de hallazgo con prefijo ❌ (error) o ⚠️ (warning)
#   - última línea EXACTA:  DRIFT_SUMMARY errors=<N> warns=<M>
#
# <!-- FILL: añade los checks de TUS convenciones (patrón de pantalla, capas,
#      tamaños, design system, etc.). Abajo van 2 ejemplos universales activos. -->
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

ERRORS=0; WARNS=0
err() { echo "❌ $1"; ERRORS=$((ERRORS+1)); }
warn(){ echo "⚠️  $1"; WARNS=$((WARNS+1)); }

# Dónde buscar código (ajusta a tus carpetas).
SRC_DIRS="${DRIFT_SRC_DIRS:-ios android web src}"
EXISTING=""; for d in $SRC_DIRS; do [ -d "$d" ] && EXISTING="$EXISTING $d"; done

# ── Check universal 1: archivos por encima del hard limit (400 líneas) ──
HARD=${DRIFT_FILE_HARD:-400}
if [ -n "$EXISTING" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    n=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ "${n:-0}" -gt "$HARD" ] && err "Archivo > $HARD líneas: $f ($n líneas)"
  done < <(find $EXISTING -type f \( -name '*.swift' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \) 2>/dev/null)
fi

# ── Check universal 2: marcador de secreto redundante (defensa en capas) ──
if [ -n "$EXISTING" ]; then
  HITS=$(grep -rEln "(service_role|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20,})" $EXISTING 2>/dev/null || true)
  [ -n "$HITS" ] && while IFS= read -r h; do err "Posible secreto hardcoded: $h"; done <<< "$HITS"
fi

# <!-- FILL: tus checks. Ejemplos a adaptar:
# - "ViewModel llama a Repository directo" (debe ir por Logic)
# - "color/spacing hardcoded fuera del design system"
# - "lógica que ramifica sobre texto en lenguaje natural (i18n)"
# - "NavigationStack fuera del Coordinator"
# Patrón:  HITS=$(grep -rEln '<patrón>' $EXISTING); [ -n "$HITS" ] && err/warn "..."
# -->

echo ""
echo "DRIFT_SUMMARY errors=$ERRORS warns=$WARNS"
# exit 0 siempre: el GATE lo aplica drift-ratchet (delta), no este script.
exit 0
