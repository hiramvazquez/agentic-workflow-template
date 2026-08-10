#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-exec-bits.sh — un script sin bit +x se commitea una sola vez
# ════════════════════════════════════════════════════════════════════
# Historia real, y por eso esto es un GATE y no un aviso: los archivos que
# llegan al repo por FUERA de git (un puente, un `cp`, una descarga, un
# editor remoto) pierden los permisos. Durante días eso se leyó como "ruido
# menor" — hasta que un commit del propio harness incluyó SEIS
# `mode change 100755 => 100644`. Ahí dejó de ser ruido: quedó en la
# historia, y el siguiente que clone recibe scripts no ejecutables.
#
# validate-harness §9 ya lo AVISA. Avisar no impidió que ocurriera. Un
# problema que reaparece cinco veces no necesita otro aviso: necesita un
# gate — que es literalmente la doctrina del harness aplicada a sí mismo
# («todo comentario de review que se repite es un bug en tu tooling»).
#
# EXCEPCIÓN DELIBERADA — las librerías que se SOURCEAN (`scripts/**/lib/`)
# no se ejecutan: su bit +x sería mentira sobre cómo se usan. Excluirlas no
# es una concesión, es la regla correcta. Sin esta exención el gate tendría
# falsos positivos permanentes y acabaría desactivado (ley del 10%, §14).
#
# Contrato: exit 0 = todo correcto · 1 = hay .sh staged sin +x.
# Contrato de stdout:  EXECBITS_SUMMARY missing=<N>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

MODE="${1:---staged}"

_candidates() {
  if [ "$MODE" = "--all" ]; then
    git ls-files '*.sh' 2>/dev/null
  else
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.sh$' || true
  fi
}

BAD=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in */lib/*) continue ;; esac   # se sourcean, no se ejecutan
  [ -x "$f" ] || BAD="${BAD}${f}"$'\n'
done < <(_candidates)

N="$(printf '%s' "$BAD" | grep -c . || true)"
echo "EXECBITS_SUMMARY missing=${N:-0}"
[ "${N:-0}" -eq 0 ] && exit 0

{
  echo "❌ exec-bits: ${N} script(s) .sh sin bit de ejecución:"
  printf '%s' "$BAD" | sed 's/^/   · /'
  echo "   Suele significar que el archivo llegó por FUERA de git (puente, cp,"
  echo "   descarga): esos caminos no preservan permisos. Si se commitea así,"
  echo "   queda en la historia y todo el que clone recibe scripts no ejecutables."
  echo "   Remedio (y re-stagea):"
  printf '     chmod +x%s\n' "$(printf '%s' "$BAD" | tr '\n' ' ' | sed 's/ $//' | sed 's/^/ /')"
  echo "     git add -u"
} >&2
exit 1
