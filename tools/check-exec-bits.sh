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
# MODOS:
#   --staged  (default)  audita lo staged y BLOQUEA. Contrato estricto.
#   --all                audita el repo entero (validate-harness §9).
#   --fix                repara y re-stagea, con AVISO visible. Es el que usa
#                        lefthook, y la razón es doctrinal, no comodidad:
#
# Un gate debe bloquear cuando la respuesta correcta requiere JUICIO. Aquí no
# lo requiere: el remedio es `chmod +x` sobre unos archivos concretos, es
# determinista y no tiene alternativas. Obligar a un humano a teclear lo que
# la máquina puede hacer sola es fricción sin valor — la misma lógica por la
# que un formateador formatea en vez de quejarse. Lo que NO se pierde es la
# señal: cada reparación se anuncia a gritos, porque el bit que falta es el
# síntoma de un canal de entrega que pierde permisos, y ese sí es un dato que
# el humano tiene que ver. Reparar en silencio sería el error opuesto.
#
# Contrato: exit 0 = todo correcto (o reparado en --fix) · 1 = hay .sh sin +x.
# Contrato de stdout:  EXECBITS_SUMMARY missing=<N>
set -uo pipefail
# El lib se resuelve desde la UBICACION de este script, antes del `cd`: tomarlo
# relativo a la raiz del repo dejaria de encontrarlo en cuanto el harness viva
# en un subdirectorio (la leccion de f-6b761f06).
_DET_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/detector-run.sh"
# shellcheck source=tools/lib/detector-run.sh
. "$_DET_LIB" 2>/dev/null || true
command -v detector_run_init >/dev/null 2>&1 && detector_run_init check-exec-bits

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:---staged}"

_candidates() {
  if [ "$MODE" = "--all" ]; then
    git ls-files '*.sh' 2>/dev/null
  else
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.sh$' || true
  fi
}

BAD=""; TARGETS=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  TARGETS=$((TARGETS+1))
  case "$f" in */lib/*) continue ;; esac   # se sourcean, no se ejecutan
  # Un symlink NO es un script al que le falta su bit: el bit vive en el
  # target, y ese target, si está trackeado, ya es candidato por su cuenta.
  # Excluirlos AQUÍ y no en la reparación evita el problema de raíz: marcar
  # un symlink como 100755 lo deja como un "ejecutable" cuyo contenido es una
  # ruta. Lo cazó el review sobre el arreglo anterior.
  if [ -L "$f" ]; then continue; fi
  [ -x "$f" ] || BAD="${BAD}${f}"$'\n'
done < <(_candidates)

N="$(printf '%s' "$BAD" | grep -c . || true)"
# En --staged lo normal es targets=0 (el commit no toca ningun .sh) y eso es
# correcto; el dato sirve para no leer ese missing=0 como "los revise todos".
command -v detector_targets >/dev/null 2>&1 && detector_targets "$TARGETS"
echo "EXECBITS_SUMMARY missing=${N:-0}"
[ "${N:-0}" -eq 0 ] && exit 0

# ── --fix: repara EL MODO, y AVISA (nunca en silencio) ──────────────
# Solo toca archivos que YA estaban staged, y de ellos solo el bit de modo.
#
# Antes hacía `git add -- "$f"`, que stagea el CONTENIDO ENTERO del árbol: si lo
# que hay en disco difiere de lo staged, se colaba en el índice sin que nadie lo
# hubiera añadido. Pasó el 2026-09-03 — un sub-agente mutó un fichero durante una
# verificación, eso le quitó el bit +x, y este gate reparó Y re-stageó con el
# mutante dentro. El sha del diff staged se movió sin un solo `git add`, y todo el
# sistema de evidencia del harness se apoya en que ese sha sea lo que el autor
# puso ahí. `update-index --chmod` cambia el modo en el índice sin tocar el blob.
if [ "$MODE" = "--fix" ]; then
  # NUNCA escribe en el índice. Repara el bit en DISCO y, si el modo staged
  # sigue mal, FALLA con la instrucción exacta.
  #
  # La versión anterior hacía `git add` tras el `chmod`, y se eligió así por un
  # motivo medido: sin auto-stagear, el gate bloqueó dos commits seguidos por lo
  # mismo. Se invierte esa decisión a la vista de lo que costó — `git add`
  # stagea el CONTENIDO entero, así que este gate llegó a meter en el índice un
  # mutante que nadie había añadido y a mover el `sha256(diff staged)` solo. Y
  # los tres intentos de corregir el modo del índice sin tocar el contenido
  # produjeron un hallazgo cada uno: `--chmod` refresca el blob igual que `add`,
  # `--cacheinfo` con el modo a mano corrompe un symlink, y el guard del symlink
  # mira el disco mientras el blob sale del índice, que pueden divergir en TIPO.
  #
  # La conclusión es la del P3 del PRD 0010: un gate corrector modifica solo lo
  # que declara, o se limita a avisar. Aquí declara el bit del disco. El índice
  # lo toca el humano, porque decidir qué contenido entra es suyo.
  REPARADOS=""; NO_TOCADOS=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if chmod +x "$f" 2>/dev/null; then
      REPARADOS="${REPARADOS}${f}"$'\n'
    else
      NO_TOCADOS="${NO_TOCADOS}${f}"$'\n'
    fi
  done < <(printf '%s' "$BAD")
  N_REP="$(printf '%s' "$REPARADOS" | grep -c . || true)"

  # ¿Queda algún modo mal EN EL ÍNDICE? Solo se mira; no se corrige.
  PENDIENTES=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    _modo="$(git ls-files -s -- "$f" 2>/dev/null | head -1 | awk '{print $1}')"
    [ "$_modo" = "100644" ] && PENDIENTES="${PENDIENTES}${f}"$'\n'
  done < <(printf '%s' "$BAD")

  {
    if [ "${N_REP:-0}" -gt 0 ]; then
      echo "🔧 exec-bits: puesto el bit +x en disco a ${N_REP} script(s):"
      printf '%s' "$REPARADOS" | sed 's/^/   · /'
      echo "   NO es cosmético: significa que llegaron por FUERA de git (puente,"
      echo "   cp, descarga) y ese canal pierde permisos. Si el aviso se repite en"
      echo "   cada commit, arregla el CANAL, no los archivos."
    fi
    if [ -n "$NO_TOCADOS" ]; then
      echo "⚠️  exec-bits: el chmod FALLÓ en estos (¿permisos?). A mano:"
      printf '%s' "$NO_TOCADOS" | sed 's/^/   · /'
    fi
  } >&2

  if [ -n "$PENDIENTES" ]; then
    {
      echo "❌ exec-bits: el modo en el ÍNDICE sigue sin el bit de ejecución."
      printf '%s' "$PENDIENTES" | sed 's/^/   · /'
      echo "   El bit ya está puesto en disco; falta llevarlo al índice, y eso lo"
      echo "   haces TÚ: stagear decide qué contenido entra en el commit, y esa"
      echo "   decisión no es de un gate (PRD 0010 P3)."
      echo "   Remedio:"
      echo "     git add -u"
    } >&2
    exit 1
  fi
  exit 0
fi

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
