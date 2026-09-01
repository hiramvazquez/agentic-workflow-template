#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# canon-enforce.sh — hook Stop / stop — BLOQUEANTE
# ════════════════════════════════════════════════════════════════════
# Reglas IRROMPIBLES que un check barato (<1s) puede cazar. Bloquea el cierre
# de turno (exit 2) hasta que se arregle.
#
# ⚠️  Antes este archivo estaba ENTERAMENTE COMENTADO: un no-op que el
# SessionStart anunciaba como gate activo. Un gate fail-open presentado como
# duro es peor que no tener gate — da falsa confianza. Ahora trae checks
# universales ACTIVOS por defecto; los específicos de tu stack van en §CHECK 5.
#
# Reparto de responsabilidades:
#   canon-enforce (aquí) → barato, universal, absoluto. Bloquea siempre.
#   check-drift/ratchet  → caro, por proyecto, delta contra baseline.
#   post-edit-verify     → por archivo, informativo, no bloquea.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

VIOLATIONS=()
err()  { VIOLATIONS+=("❌ $1"); }
warn() { VIOLATIONS+=("⚠️  $1"); }

# Solo miramos lo que cambió en el árbol de trabajo: un turno no debe pagar
# por deuda preexistente (para eso está el ledger).
# Parsing del porcelain SIN awk '{print $NF}': ese tomaba el último token, que
# rompe con espacios en el nombre ("mi archivo.swift" → "archivo.swift") y con
# renames ("R a -> b": correcto por accidente, pero frágil). Aquí: quita los 3
# chars de status, toma el destino del rename, y desquota nombres con espacios.
CHANGED="$(git status --porcelain 2>/dev/null \
  | sed -E 's/^...//; s/^.* -> //; s/^"(.*)"$/\1/' \
  | grep -vE '^\.agents/state/' || true)"

# ── Los archivos que DEFINEN los detectores se excluyen ─────────────
# Un archivo que declara "esto parece un secreto" contiene, por necesidad, algo
# que parece un secreto. Sin esta exclusión el gate se bloquea a sí mismo — pasó
# de verdad al implementar el PRD 0001, y es la misma clase de fallo que G1:
# **todo detector necesita tests de sus falsos positivos.**
# Fijado por `tools/tests/test_canon_enforce.sh`.
is_detector_definition() {
  case "$1" in
    scripts/agent-hooks/canon-enforce.sh|\
    .claude/security-patterns.yaml|\
    .claude/claude-security-guidance.md|\
    .gitleaks.toml|\
    tools/semgrep/rules/*|\
    tools/tests/*|\
    tools/check-drift.sh|\
    .agents/skills/security/SKILL.md) return 0 ;;
    *) return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
# CHECK 1 (universal) — capas: el dominio no depende de UI ni de infra
# ════════════════════════════════════════════════════════════════════
if [ -f tools/check-layers.sh ]; then
  if ! out="$(bash tools/check-layers.sh 2>&1)"; then
    while IFS= read -r line; do
      case "$line" in "❌"*) err "${line#❌ }" ;; esac
    done <<< "$out"
  fi
fi

# ════════════════════════════════════════════════════════════════════
# CHECK 2 (universal) — secretos: defensa redundante a gitleaks
# ════════════════════════════════════════════════════════════════════
# gitleaks (Anillo 1) mira lo staged. Esto mira lo que el agente acaba de
# escribir, ANTES de que llegue a staged. El coste de un secreto filtrado es
# asimétrico, así que se verifica dos veces: es defensa en capas, no duplicación.
if [ -n "$CHANGED" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in *.md|*.lock|*.example|*.sample) continue ;; esac
    is_detector_definition "$f" && continue
    if grep -qE "(service_role|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY)" "$f" 2>/dev/null; then
      err "Posible SECRETO hardcoded en $f (AGENTS.md §6). Muévelo a variable de entorno / secret manager."
    fi
  done <<< "$CHANGED"
fi

# ════════════════════════════════════════════════════════════════════
# CHECK 3 (universal) — datos sensibles en almacenamiento en claro
# ════════════════════════════════════════════════════════════════════
if [ -n "$CHANGED" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in *.md) continue ;; esac
    is_detector_definition "$f" && continue
    if grep -qE "(UserDefaults.*(token|password|secret|apiKey)|localStorage\.setItem\(.*(token|password|secret)|[Ss]haredPreferences.*(token|password))" "$f" 2>/dev/null; then
      err "Dato sensible en almacenamiento EN CLARO en $f (AGENTS.md §6). Usa Keychain/Keystore/cifrado."
    fi
  done <<< "$CHANGED"
fi

# ════════════════════════════════════════════════════════════════════
# CHECK 4 (universal) — el harness no puede quedar roto
# ════════════════════════════════════════════════════════════════════
# Si el turno tocó los gates, sus tests deben pasar. Un gate roto es peor que
# ausente: bloquea trabajo legítimo y deja pasar lo que debía parar.
#
# ⚠️  Esto corría `run-tests.sh` ENTERO —750 tests, 5:07 medidos— en CADA cierre
# de turno que tocara `tools/` o `scripts/`. En este repo el harness ES el
# producto, así que casi todo turno casaba: cinco minutos por turno, repetidos
# sobre un árbol que el turno siguiente volvía a cambiar (`f-e2a65344`).
#
# La suite completa NO desaparece — ya corría en otras dos capas y sigue ahí:
#   · `lefthook.yml` job `harness-suite` (pre-push, Anillo 1, instalado y activo)
#   · `ci/run-gates.sh` paso 1/8 (Anillo 3)
# Lo que se elimina aquí es la TERCERA ejecución: la de mayor frecuencia y menor
# rendimiento, sobre trabajo que aún no ha terminado. Es §14.1 aplicado a sí
# mismo — cázalo en la capa más barata, y "barata" incluye el reloj.
#
# Lo que un cierre de turno SÍ debe pagar (≈2s):
#   (a) `bash -n` sobre cada .sh tocado. La rotura catastrófica local es un hook
#       que NO PARSEA: se lee como DENY y deja al agente sin poder ejecutar nada
#       —ni el `git status` con el que diagnosticarlo—. Es la razón de ser de
#       `run-hook.sh`, y se caza en milisegundos.
#   (b) Los tests DIRIGIDOS del archivo tocado, con el filtro que `run-tests.sh`
#       ya acepta: 2s en vez de 307s.
#   (c) Un aviso NO bloqueante por lo que quedó sin test dirigido. Deferir en
#       silencio sería la "defensa anunciada que no existe" que este harness
#       persigue en todo lo demás.
# El alcance es el CÓDIGO y la CONFIGURACIÓN del harness: un `.conf` cambia el
# comportamiento de un gate igual que un `.sh` (`skill-matrix.conf` gobierna
# `skill-reminder`, `layers.conf` gobierna `check-layers`). Quedan fuera los
# DATOS y la doc bajo esas rutas —`findings/ledger.jsonl`, los `*-ratchet.json`,
# los `.md`—: cambian en casi todos los turnos y no alteran ninguna lógica, así
# que dispararían un aviso permanente. Un aviso que sale siempre no se lee.
HARNESS_CHANGED="$(printf '%s\n' "$CHANGED" | grep -E '^(scripts/agent-hooks/|tools/).*\.(sh|conf|ya?ml)$' || true)"
if [ -n "$HARNESS_CHANGED" ]; then

  # (a) Sintaxis — la rotura que deja al agente sin herramientas. Solo shell.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in *.sh) ;; *) continue ;; esac
    [ -f "$f" ] || continue
    if ! syn="$(bash -n "$f" 2>&1)"; then
      err "$f NO PARSEA — un hook que no parsea se lee como DENY:"$'\n'"$syn"
    fi
  done <<< "$HARNESS_CHANGED"

  # (b)+(c) Tests dirigidos. El token solo se usa si su archivo de test EXISTE:
  # un filtro que no casa nada sale 0 en el runner, así que derivar mal el nombre
  # sería un falso verde silencioso. Sin test que casar → aviso, no silencio.
  if [ -f tools/tests/run-tests.sh ]; then
    CE_TOKENS=""; CE_UNMAPPED=""
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      base="$(basename "$f")"; base="${base%.*}"; norm="${base//-/_}"; tok=""
      for cand in "$norm" "${norm#check_}"; do
        case "$cand" in test_*) [ -f "tools/tests/$cand.sh" ] && { tok="$cand"; break; } ;;
                        *)      [ -f "tools/tests/test_$cand.sh" ] && { tok="test_$cand"; break; } ;;
        esac
      done
      if [ -n "$tok" ]; then
        case " $CE_TOKENS " in *" $tok "*) ;; *) CE_TOKENS="$CE_TOKENS $tok" ;; esac
      else
        CE_UNMAPPED="$CE_UNMAPPED $f"
      fi
    done <<< "$HARNESS_CHANGED"

    for tok in $CE_TOKENS; do
      if ! out="$(bash tools/tests/run-tests.sh "$tok" 2>&1)"; then
        err "Tocaste el harness y los tests de \`$tok\` FALLAN:"$'\n'"$(printf '%s' "$out" | tail -12)"
      fi
    done

    [ -n "$CE_UNMAPPED" ] && warn "Sin test dirigido:$CE_UNMAPPED — la suite completa NO corrió aquí; corre en pre-push (lefthook \`harness-suite\`) y en CI."
  fi
fi

# ════════════════════════════════════════════════════════════════════
# CHECK 5 — tus reglas irrompibles
# ════════════════════════════════════════════════════════════════════
# <!-- FILL: añade aquí lo que en TU proyecto no puede pasar nunca.
#      Patrón: detecta el anti-patrón → err "..." (bloquea) o warn "..." (informa).
#      Candidatos habituales:
#        - print / console.log / NSLog en código de producción
#        - TODO/FIXME sin ticket asociado
#        - try! / force-unwrap / .unwrap() en paths de producción
#        - migraciones de DB sin política RLS
#        - endpoints nuevos sin check de authz
#      Ejemplo:
#   if [ -n "$CHANGED" ]; then
#     while IFS= read -r f; do
#       case "$f" in *.swift)
#         grep -qE 'try!|as!' "$f" 2>/dev/null && err "force-try/force-cast en $f" ;;
#       esac
#     done <<< "$CHANGED"
#   fi
#
#      Ejemplo REAL (del primer proyecto iOS): proteger DECISIONES DE BUILD
#      fijadas. El default de aislamiento (MainActor, Xcode 26) se intentó
#      revertir DOS veces pese a estar documentado en la skill — prosa que
#      nadie relee. La regla mecánica lo hizo imposible:
#   if printf '%s' "$CHANGED" | grep -q 'project\.pbxproj'; then
#     grep -q 'SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated' <TuApp>.xcodeproj/project.pbxproj 2>/dev/null \
#       && err "el default MainActor es decisión FIJADA (AGENTS.md §3): escapes puntuales con @concurrent, jamás a nivel de target"
#     grep -q 'SWIFT_TREAT_WARNINGS_AS_ERRORS = NO' <TuApp>.xcodeproj/project.pbxproj 2>/dev/null \
#       && err "warnings-as-errors es el nivel 0 (AGENTS.md §2): no se apaga"
#   fi
# -->

# ── Veredicto ───────────────────────────────────────────────────────
[ ${#VIOLATIONS[@]} -eq 0 ] && exit 0

# Telemetría (nivel 9): cada bloqueo de este gate es un dato de contención en
# fase `gate` — barata. Best-effort, jamás afecta al veredicto.
hook_log_detection "canon-enforce" "stop-check" "working-tree" "${#VIOLATIONS[@]}"

MSG=""
for v in "${VIOLATIONS[@]}"; do MSG+="$v"$'\n'; done

# ❌ bloquea el cierre de turno · ⚠️ solo informa.
if printf '%s' "$MSG" | grep -q "❌"; then
  hook_block "🛑 CANON ENFORCE — cierre de turno BLOQUEADO por reglas irrompibles:"$'\n\n'"$MSG"$'\n'"Arréglalo en este mismo turno. Estas reglas no admiten \"lo dejo para después\"."
fi
printf '%s' "$MSG" >&2
exit 0
