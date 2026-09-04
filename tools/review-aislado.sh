#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# review-aislado.sh — la revisión no toca el árbol del autor
# ════════════════════════════════════════════════════════════════════
# Bloqueante de V1. Lo motivó un incidente real del 2026-09-04: un sub-agente
# reviewer mutó un fichero durante su verificación, eso le quitó el bit +x,
# `check-exec-bits` lo reparó Y lo re-stageó con el mutante dentro, y el
# `sha256(diff staged)` se movió sin que nadie hiciera `git add`. Todo el sistema
# de evidencia de este harness se apoya en que ese sha sea lo que el autor puso.
#
# `.agents/mutation.lock` no bastaba: declara una intención, no impide nada.
#
# Y el aislamiento nativo de la tool Agent tampoco sirve TAL CUAL — se probó el
# mismo día: su worktree sale de HEAD con el árbol limpio, así que el reviewer no
# ve el diff que debe revisar y no puede emitir veredicto. Por eso aquí el
# worktree se crea Y SE LE APLICA el diff staged: el revisor ve exactamente lo
# mismo que el autor, en un árbol que no es el suyo.
#
#   preparar   crea el worktree con el diff aplicado e imprime su ruta
#   verificar  comprueba que el diff del AUTOR no se movió durante la revisión
#   limpiar    borra el worktree y su registro
#
# Contrato de stdout (preparar): última línea = la ruta del worktree.
# Exit: 0 bien · 1 el diff del autor se movió (revisión inválida) · 3 no pude.
set -uo pipefail

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "⚠️  review-aislado: esto no es un repo git (§14.3)." >&2; exit 3; }
RAIZ="$(git rev-parse --show-toplevel)"; cd "$RAIZ" || exit 3

ESTADO="$RAIZ/.agents/state/review-aislado"
WT_REF="$ESTADO/worktree"      # dónde vive el worktree de esta revisión
SHA_REF="$ESTADO/sha-antes"    # el sha del diff staged al empezar

_sha_staged() { git diff --cached | shasum -a 256 | awk '{print $1}'; }

case "${1:-}" in

  preparar)
    if [ -z "$(git diff --cached --name-only 2>/dev/null)" ]; then
      echo "⚠️  review-aislado: no hay nada staged — nada que revisar." >&2
      exit 3
    fi
    mkdir -p "$ESTADO"
    # NO se auto-limpia una revisión previa. Antes sí, silenciando stderr, bajo el
    # supuesto de que si el estado existe es basura huérfana. Pero una sesión
    # interrumpida —justo el evento que motivó esta herramienta— deja ese estado
    # puesto, y la siguiente revisión se llevaba por delante el worktree de la
    # primera. Peor: también sobreescribía el sha de referencia, así que si el
    # diff no había cambiado, el `verificar` de la primera PASABA aunque su
    # worktree hubiera sido destruido a mitad. La corrupción silenciosa que esto
    # existe para impedir, un nivel más abajo. Lo cazó la primera review hecha
    # con este mismo mecanismo.
    if [ -f "$WT_REF" ]; then
      {
        echo "❌ review-aislado: ya hay una revisión EN CURSO."
        echo "   worktree: $(cat "$WT_REF" 2>/dev/null)"
        echo "   No se toca: podría ser una revisión viva, o una sesión que se"
        echo "   interrumpió. Destruirla en silencio invalidaría su verificación"
        echo "   sin que nadie se entere."
        echo "   Si de verdad sobra:  bash tools/review-aislado.sh limpiar"
      } >&2
      exit 3
    fi
    WT="$(mktemp -d "${TMPDIR:-/tmp}/review-aislado.XXXXXX")"
    rm -rf "$WT"   # `git worktree add` lo quiere inexistente
    if ! git worktree add --detach --quiet "$WT" HEAD 2>/dev/null; then
      echo "⚠️  review-aislado: no pude crear el worktree." >&2; exit 3
    fi
    # El diff staged se APLICA ahí, con --index para que quede staged también:
    # el revisor tiene que ver `git diff --cached` idéntico al del autor, no un
    # árbol sucio. Sin esto el worktree sale limpio y no hay nada que revisar.
    # `--binary` no es opcional: sin él, `git diff --cached` emite "Binary files
    # differ" en vez de un patch, y como `git apply` es atómico el worktree entero
    # falla. Fallaría alto y limpio —no deja una copia parcial creyéndose
    # completa— pero ningún commit que tocara un binario podría revisarse nunca.
    if ! git diff --cached --binary | git -C "$WT" apply --index --whitespace=nowarn 2>/dev/null; then
      git worktree remove --force "$WT" 2>/dev/null
      echo "⚠️  review-aislado: el diff staged no aplica limpio en el worktree." >&2
      exit 3
    fi
    printf '%s\n' "$WT" > "$WT_REF"
    _sha_staged > "$SHA_REF"
    printf '%s\n' "$WT"
    ;;

  verificar)
    [ -f "$SHA_REF" ] || { echo "⚠️  review-aislado: no hay revisión preparada." >&2; exit 3; }
    ANTES="$(cat "$SHA_REF")"; AHORA="$(_sha_staged)"
    if [ "$ANTES" != "$AHORA" ]; then
      {
        echo "❌ review-aislado: el diff staged del AUTOR cambió durante la revisión."
        echo "   antes:  ${ANTES:0:16}…"
        echo "   ahora:  ${AHORA:0:16}…"
        echo "   La revisión queda INVÁLIDA y no se intenta continuar: lo revisado"
        echo "   ya no es lo que se va a commitear. Algo escribió en tu índice —"
        echo "   un gate que repara, otra sesión, o un sub-agente sin aislar."
      } >&2
      exit 1
    fi
    ;;

  limpiar)
    if [ -f "$WT_REF" ]; then
      WT="$(cat "$WT_REF")"
      [ -n "$WT" ] && git worktree remove --force "$WT" 2>/dev/null
      [ -n "$WT" ] && rm -rf "$WT" 2>/dev/null
    fi
    rm -f "$WT_REF" "$SHA_REF"
    git worktree prune 2>/dev/null
    ;;

  *)
    echo "uso: review-aislado.sh preparar|verificar|limpiar" >&2; exit 3 ;;
esac
