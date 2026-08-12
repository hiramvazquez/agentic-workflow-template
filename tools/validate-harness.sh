#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-harness.sh — ¿los gates EXISTEN de verdad, o solo lo parecen?
# ════════════════════════════════════════════════════════════════════
# La lección más cara de este harness: sus peores fallos no fueron gates que
# bloquearon mal, sino gates que NUNCA DISPARARON — hooks sobre eventos
# inexistentes, patrones de permisos que no matchean, wrappers con el esquema
# equivocado. Todos fallan hacia el SILENCIO: un gate mudo y uno sano se ven
# igual desde fuera... hasta que corres esto.
#
# Regla operativa: NINGÚN gate cuenta como existente hasta que lo has visto
# bloquear algo una vez. Este script hace (A) todo lo verificable en estático,
# y (B) imprime el checklist EN VIVO de lo que solo una sesión real prueba.
#
#   bash tools/validate-harness.sh            # checks estáticos + checklist
#   bash tools/validate-harness.sh --selftest # además: cada detector DEMUESTRA
#                                             # que ve, contra un fixture mínimo
#   bash tools/validate-harness.sh --full     # estático + selftest + suite entera
#
# Salida: exit 1 si algún check falla. Correr tras CADA update de
# Claude Code / Cursor / Codex: sus contratos de hooks versionan rápido.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

echo "━━━ validate-harness: checks estáticos ━━━"

# ── 1. Los tres configs de hooks son JSON válido ────────────────────
echo ""
echo "── 1. Sintaxis de configuración ──"
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || { warn "$f ausente"; continue; }
  if python3 -c "import json;json.load(open('$f'))" 2>/dev/null; then
    ok "$f: JSON válido"
  else
    bad "$f: JSON INVÁLIDO — ese cliente ignorará TODOS sus hooks"
  fi
done

# ── 2. Solo eventos que EXISTEN en cada cliente ─────────────────────
# (la lista se comparte con tools/tests/test_hook_events.sh)
echo ""
echo "── 2. Nombres de evento por cliente ──"
python3 - <<'PY' || FAIL=1
import json, sys
SPECS = {
    ".claude/settings.json": ({"SessionStart","UserPromptSubmit","PreToolUse","PostToolUse",
                               "Notification","Stop","SubagentStop","SessionEnd","PreCompact"}, "hooks"),
    ".cursor/hooks.json":    ({"beforeSubmitPrompt","beforeShellExecution","beforeMCPExecution",
                               "beforeReadFile","afterFileEdit","stop"}, "hooks"),
    ".codex/hooks.json":     ({"PreToolUse","PostToolUse"}, "hooks"),
}
rc = 0
for path,(valid,key) in SPECS.items():
    try:
        cfg = json.load(open(path))
    except FileNotFoundError:
        continue
    events = [k for k in cfg.get(key,{}) if not k.startswith("_")]
    ghosts = [e for e in events if e not in valid]
    if ghosts:
        print(f"  ❌ {path}: eventos INEXISTENTES {ghosts} — esos hooks JAMÁS dispararán (gate mudo)")
        rc = 1
    else:
        print(f"  ✅ {path}: {len(events)} eventos, todos válidos")
sys.exit(rc)
PY

# ── 3. Cada comando de hook apunta a un script que existe y parsea ──
echo ""
echo "── 3. Scripts referenciados por los hooks ──"
MISSING=0
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || continue
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -f "$s" ]; then bad "$f referencia $s — NO EXISTE"; MISSING=1
    elif ! bash -n "$s" 2>/dev/null; then bad "$s no parsea (bash -n)"; MISSING=1; fi
  done < <(grep -oE 'scripts/agent-hooks/[A-Za-z0-9_./-]+\.sh' "$f" | sort -u)
done
[ "$MISSING" = "0" ] && ok "todos los scripts de hooks existen y parsean"

# ── 4. Symlinks del contrato multi-cliente ──────────────────────────
echo ""
echo "── 4. Symlinks ──"
for l in .claude/skills .cursor/agents; do
  if [ -L "$l" ] && [ -e "$l" ]; then ok "$l → $(readlink "$l")"
  elif [ -e "$l" ]; then warn "$l existe pero no es symlink"
  else warn "$l ausente (¿clone en un FS sin symlinks?) — skills/agents no cargarán ahí"; fi
done

# ── 5. La matriz de skills: refs existen y cubre tu código ──────────
echo ""
echo "── 5. skill-matrix.conf ──"
if [ -f tools/skill-matrix.conf ]; then
  BADREF=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _oldIFS="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { bad "skill-matrix: ref inexistente '$r' (glob '$glob')"; BADREF=1; }
    done
    IFS="$_oldIFS"
  done < tools/skill-matrix.conf
  [ "$BADREF" = "0" ] && ok "todas las refs de la matriz existen"
else
  bad "tools/skill-matrix.conf AUSENTE — skill-reminder degrada a globs de fábrica"
fi

# ── 6. Dependencias externas de los gates ───────────────────────────
echo ""
echo "── 6. Dependencias ──"
for dep in jq python3 git; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || bad "$dep AUSENTE — varios hooks degradan o fallan"
done
for dep in gitleaks lefthook; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || warn "$dep ausente — el nivel que lo usa está MUDO (session-start ya lo reporta)"
done
if [ -x tools/probe-capability.sh ]; then
  _probe="$(PROBE_TIMEOUT_SECS="${PROBE_TIMEOUT_SECS:-15}" bash tools/probe-capability.sh semgrep 2>/dev/null)"; _probe_rc=$?
  _probe_status="$(printf '%s' "$_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null || echo unknown)"
  _probe_detail="$(printf '%s' "$_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("detail","sin diagnóstico"))' 2>/dev/null || echo 'salida no parseable')"
  case "$_probe_status:$_probe_rc" in
    operational:0) ok "semgrep operational — $_probe_detail" ;;
    missing:1) bad "semgrep missing — $_probe_detail" ;;
    broken:1) bad "semgrep broken — $_probe_detail" ;;
    *) bad "semgrep unknown (exit $_probe_rc) — $_probe_detail" ;;
  esac
else
  bad "probe de semgrep ausente — presencia no demuestra operación"
fi
if [ -d .git ] && [ -f lefthook.yml ]; then
  grep -q lefthook .git/hooks/pre-commit 2>/dev/null \
    && ok "Anillo 1 instalado (.git/hooks/pre-commit)" \
    || bad "ANILLO 1 DORMIDO: corre \`lefthook install\`"
fi

# ── 7. La suite del harness existe (y opcionalmente pasa) ───────────
echo ""
echo "── 7. Suite del harness ──"
NT="$(find tools/tests -name 'test_*.sh' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NT:-0}" = "0" ]; then
  bad "0 archivos test_*.sh — canon-enforce CHECK 4 y CI paso 1 aprueban en vacuo"
else
  ok "$NT archivos de test presentes"
  if [ "${1:-}" = "--full" ]; then
    bash tools/tests/run-tests.sh || FAIL=1
  fi
fi

# ── 8. ¿El COMPILADOR está en algún gate? ───────────────────────────
# El fallo más caro del primer proyecto real: nueve niveles en verde y el
# build de Xcode roto — la comprobación más barata y definitiva (¿compila?)
# era la única sin cablear, mientras semgrep, capas y trinquetes venían
# listos de fábrica. Esto no puede ser un FILL silencioso más.
echo ""
echo "── 8. Compilador en los gates ──"
if ! bash tools/verify-run.sh --cmd-only >/dev/null 2>&1; then
  warn "tools/verify.conf sigue sin cablear: NINGÚN gate compila ni corre tus tests."
  warn "Los 9 niveles pueden estar en verde con el build ROTO. Cablea build+tests ANTES que nada."
else
  ok "tools/verify.conf cableado (build+tests en el gate local Y en el Anillo 3)"
fi

# ── 8b. ¿EXISTE el Anillo 3? ────────────────────────────────────────
# El fail-open local de §14.3 está justificado POR el backstop. Si el
# backstop no existe, el razonamiento entero se cae — y hasta hoy nada lo
# comprobaba: se declaraban niveles mudos, nunca el anillo mudo.
# Severidad por preset: en `full` es un FALLO; en `lite` (uso personal) se
# DECLARA con todas las letras, que es el mínimo innegociable.
echo ""
echo "── 8b. Anillo 3 (CI) ──"
if [ -f tools/check-ring3.sh ]; then
  if _r3="$(bash tools/check-ring3.sh 2>&1)"; then
    ok "$(printf '%s' "$_r3" | grep -v RING3_SUMMARY | head -1)"
  else
    _preset="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null || echo full)"
    if [ "${_preset:-full}" = "lite" ]; then
      warn "Anillo 3 AUSENTE (preset lite: se declara, no bloquea)."
      warn "Cada exit 3 de un detector es fail-open DEFINITIVO mientras siga así."
    else
      bad "Anillo 3 AUSENTE en preset full — el backstop de §14.3 no existe."
      printf '%s\n' "$_r3" | grep -E '^\s+(·|Remedio|CONSECUENCIA)' | sed 's/^/     /'
    fi
  fi
else
  warn "tools/check-ring3.sh ausente — no puedo verificar el Anillo 3."
fi

# ── 9. Bits de ejecución ────────────────────────────────────────────
# 15 scripts sin +x el mismo día no es ruido: es el síntoma de archivos que
# llegaron por FUERA de git (un puente/cp no preserva permisos). Funciona
# igual porque todo se invoca con `bash script.sh`, pero ensucia cada diff.
echo ""
echo "── 9. Bits de ejecución ──"
if [ -f tools/check-exec-bits.sh ]; then
  if _eb="$(bash tools/check-exec-bits.sh --all 2>&1)"; then
    ok "todos los .sh ejecutables tienen bit +x (las libs sourceadas están exentas)"
  else
    bad "hay scripts .sh sin bit +x YA en el repo — se pierden en todo camino que no sea git."
    printf '%s\n' "$_eb" | grep -E '^\s+·' | head -8 | sed 's/^/     /'
    warn "Remedio rápido:  git ls-files '*.sh' | grep -v '/lib/' | xargs chmod +x && git add -u"
  fi
else
  warn "tools/check-exec-bits.sh ausente — no puedo verificar los bits de ejecución."
fi

# ════════════════════════════════════════════════════════════════════
# SELFTEST — cada detector DEMUESTRA una vez que ve (--selftest / --full)
# ════════════════════════════════════════════════════════════════════
# Nacido de la retrospectiva del primer proyecto real: sus tres fallos más
# caros (build sin cablear, semgrep autodeclarado muerto, nivel 4 fantasma)
# tenían la misma forma — un gate que PARECÍA sano y nunca había producido
# una detección. Los checks estáticos miran configuración; esto exige
# EVIDENCIA: cada detector corre contra un fixture mínimo, con los binarios
# y confs de ESTE repo, y debe emitir su contrato (§14.3) — un exit code
# correcto y su marca (SUMMARY / score). Un detector que no pasa su selftest
# no está "pendiente": está MUDO y anunciándose como sano.
selftest() {
  echo ""
  echo "━━━ selftest: cada detector demuestra que VE ━━━"
  local SB out rc
  SB="$(mktemp -d)"
  mkdir -p "$SB/r"
  cp -R tools "$SB/r/tools" 2>/dev/null
  cp -R scripts "$SB/r/scripts" 2>/dev/null   # los hooks bloqueantes también se selftestean
  rm -rf "$SB/r/tools/tests"   # la suite no es un detector
  (
    cd "$SB/r" || exit 1
    git init -q . 2>/dev/null; git config user.email s@s.s; git config user.name s
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    echo full > tools/preset
  ) || { warn "selftest: no pude montar el sandbox"; rm -rf "$SB"; return 0; }

  # 1. conflict-markers: un conflicto staged DEBE bloquear (exit 1).
  ( cd "$SB/r" && printf '%s HEAD\na\n%s\nb\n%s rama\n' '<<<<<<<' '=======' '>>>>>>>' > c.txt \
    && git add c.txt ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-conflict-markers.sh 2>&1)"; rc=$?
  if [ "$rc" = "1" ]; then ok "conflict-markers: VE (bloqueó un conflicto staged)"
  else bad "conflict-markers: NO vio un conflicto staged (exit $rc)"; fi
  ( cd "$SB/r" && git rm -q --cached c.txt 2>/dev/null; rm -f c.txt )

  # 2. review-marker: código de producto staged sin marker DEBE bloquear.
  ( cd "$SB/r" && mkdir -p app && echo 'let x = 1' > app/main.swift && git add app/main.swift ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-review-marker.sh --staged 2>&1)"; rc=$?
  if [ "$rc" = "1" ]; then ok "review-marker: VE (exigió review a producto staged sin marker)"
  else bad "review-marker: dejó pasar producto sin marker (exit $rc) — el gate nº1 está mudo"; fi
  ( cd "$SB/r" && git rm -q --cached app/main.swift 2>/dev/null; rm -rf app )

  # 3. secret-scan: un secreto con formato real staged DEBE bloquear.
  #    (La clave se ENSAMBLA para no dejar un patrón contiguo en este script.)
  #
  #    ⚠️ La clave del fixture NO puede ser la CANÓNICA de la documentación de
  #    AWS — el prefijo AKIA seguido de IOSFODNN7 y EXAMPLE. gitleaks la ignora
  #    A PROPÓSITO (aparece en todos los tutoriales del mundo), así que con ella
  #    el selftest daba ❌ sobre un gate perfectamente sano. Verificado en vivo:
  #    esa misma clave en cualquier archivo → exit 0; cualquier otra AKIA en el
  #    mismo archivo → exit 1. Un selftest con falsos positivos se ignora
  #    entero, y entonces deja de proteger de los gates mudos, que es justo para
  #    lo que existe (§14, ley del 10%). Usa un formato válido pero NO canónico,
  #    como hace docs/ADOPTION.md §7.
  #
  #    ⚠️⚠️ Y POR ESO EL NOMBRE DE LA CLAVE VA PARTIDO ARRIBA, en trozos que no
  #    forman el literal. NO lo "arregles" juntándolo para que se lea mejor:
  #    `canon-enforce.sh` (CHECK 2) escanea los archivos recién escritos y una
  #    clave AWS contigua en ESTE archivo bloquea el cierre de turno — incluido
  #    el turno que la escribió. Le pasó a un agente en un proyecto real: vio el
  #    nombre partido, lo unió por prolijidad, y se dejó el turno trabado.
  #    La alternativa mala sería añadir este archivo a `is_detector_definition()`
  #    del secret-scan: eso lo dejaría CIEGO a secretos de verdad para siempre.
  #    Partir el literal cuesta una línea fea; cegar el detector cuesta el gate.
  if command -v gitleaks >/dev/null 2>&1; then
    ( cd "$SB/r" && printf 'aws_secret_access_key = "%s%s"\n' 'AKIA' '1234567890ABCDEF' > s.env.py \
      && git add s.env.py ) 2>/dev/null
    out="$(cd "$SB/r" && bash tools/secret-scan.sh --staged 2>&1)"; rc=$?
    if [ "$rc" = "1" ]; then ok "secret-scan: VE (cazó una clave AWS staged)"
    else bad "secret-scan: NO cazó una clave AWS staged (exit $rc) — gitleaks está pero no mira"; fi
    ( cd "$SB/r" && git rm -q --cached s.env.py 2>/dev/null; rm -f s.env.py )
  else
    warn "secret-scan: gitleaks no instalado — selftest saltado (el nivel ya se reporta MUDO)"
  fi

  # 4. semgrep: un patrón prohibido staged debe dar exit 1 + SEMGREP_SUMMARY;
  #    sin semgrep instalado, el contrato correcto es exit 3 (no pudo mirar).
  # `*-malo.*` EXPLÍCITO, no "el primero del directorio". La versión anterior
  # cogía `ls … | head -1` dando por hecho que todo lo de ahí dispara alguna
  # regla; en cuanto el directorio tuvo un README y un fixture BUENO (el que
  # debe dar cero por definición), el selftest empezó a coger uno de esos y a
  # declarar el nivel 2 MUDO estando perfectamente sano. Un selftest con falsos
  # positivos se ignora entero — y entonces deja de proteger de los gates
  # mudos, que es justo para lo que existe.
  local FIXT=""
  if ls tools/semgrep/fixtures/*-malo.* >/dev/null 2>&1; then
    FIXT="$(ls tools/semgrep/fixtures/*-malo.* | head -1)"
    cp "$FIXT" "$SB/r/fixture_selftest.${FIXT##*.}" 2>/dev/null
  elif [ -f tools/semgrep/rules/swift.yaml ]; then
    printf 'import Foundation\nlet d = try! JSONDecoder().decode(Int.self, from: Data())\n' \
      > "$SB/r/fixture_selftest.swift"
  fi
  if [ -n "$(ls "$SB"/r/fixture_selftest.* 2>/dev/null)" ]; then
    ( cd "$SB/r" && git add fixture_selftest.* ) 2>/dev/null
    out="$(cd "$SB/r" && bash tools/semgrep-scan.sh --staged 2>&1)"; rc=$?
    if command -v semgrep >/dev/null 2>&1; then
      if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q 'SEMGREP_SUMMARY'; then
        ok "semgrep: VE (cazó el fixture y emitió SEMGREP_SUMMARY)"
      else
        bad "semgrep: instalado pero NO cazó el fixture (exit $rc) — reglas rotas o scan mudo"
      fi
    else
      if [ "$rc" = "3" ]; then ok "semgrep: ausente y lo DECLARA (exit 3, contrato §14.3)"
      else bad "semgrep ausente pero exit $rc (esperaba 3) — un scanner que no corrió parece uno que pasó"; fi
    fi
  else
    warn "semgrep: sin fixture generable para tus reglas — añade uno en tools/semgrep/fixtures/"
  fi

  # 5. mutation-score: el CABLEADO del score, con override (muter real es
  #    lento y va aparte). Fija que el número entra, viaja y sale.
  out="$(cd "$SB/r" && MUTATION_SCORE_OVERRIDE=57 bash tools/mutation-score.sh --report 2>&1)"; rc=$?
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'score=57'; then
    ok "mutation-score: el cableado del score funciona (override 57 → score=57)"
  else
    bad "mutation-score: el score NO viaja (exit $rc: $out) — nivel 4 fantasma"
  fi
  if command -v muter >/dev/null 2>&1 && { [ -f muter.conf.yml ] || [ -f muter.conf.json ]; }; then
    warn "mutation-score: runner real presente; el selftest NO lo corre (lento). Evidencia real: bash tools/mutation-score.sh --report"
  fi

  # 6. drift-ratchet: corre y emite su resumen (sin crashear en ESTE repo).
  out="$(cd "$SB/r" && bash tools/drift-ratchet.sh --check 2>&1)"; rc=$?
  case "$rc" in
    0|1) ok "drift-ratchet: corre y responde (exit $rc)" ;;
    *)   bad "drift-ratchet: crasheó en el selftest (exit $rc): $(printf '%s' "$out" | head -2)" ;;
  esac

  # ── Los tres que BLOQUEAN trabajo ─────────────────────────────────
  # Donde un fallo mudo o un falso positivo cuestan más: si uno de estos
  # tres calla, el flujo entero pierde su garantía — y si grita de más,
  # el equipo lo desactiva. Pedido explícitamente por la retro del primer
  # proyecto real ("los que paran el trabajo son donde más duele").

  # 7. git-guard (reviewer-gate §0): un --no-verify DEBE denegarse (exit 2).
  #    El bloqueo ocurre ANTES de los detectores, así que no requiere stubs.
  out="$(cd "$SB/r" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' \
        | bash scripts/agent-hooks/reviewer-gate.sh 2>&1)"; rc=$?
  if [ "$rc" = "2" ]; then ok "git-guard: VE (denegó git commit --no-verify)"
  else bad "git-guard: NO denegó --no-verify (exit $rc) — la prohibición nº1 de §7 está muda"; fi

  # 8. skill-reminder: editar un path de la matriz sin haber leído las refs
  #    DEBE bloquear (exit 2, preset full). El path se SINTETIZA desde tu
  #    propio skill-matrix.conf y se verifica contra el mismo glob que usa
  #    el hook — así el selftest sigue valiendo cuando cambies la matriz.
  local CAND="" g c
  while IFS='|' read -r g _; do
    case "$g" in ''|'#'*) continue ;; esac
    g="$(printf '%s' "$g" | sed -E 's/[[:space:]]+$//')"
    c="$g"; c="${c//\*\*\//app/}"; c="${c//\*\*/app}"; c="${c//\*/X}"
    # candidatos que caen en las EXCLUSIONES del hook (doc/tooling) no sirven
    case "$c" in .agents/*|.claude/*|.cursor/*|docs/*|tools/*|scripts/*|ci/*|enterprise/*|*.md) continue ;; esac
    # shellcheck disable=SC2254  # el glob DEBE expandirse como patrón
    case "$c" in $g) CAND="$c"; break ;; esac
  done < tools/skill-matrix.conf
  if [ -n "$CAND" ]; then
    out="$(cd "$SB/r" && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$CAND" \
          | bash scripts/agent-hooks/skill-reminder.sh 2>&1)"; rc=$?
    if [ "$rc" = "2" ]; then ok "skill-reminder: VE (bloqueó editar $CAND sin leer sus refs)"
    else bad "skill-reminder: dejó editar $CAND sin lecturas (exit $rc) — la matriz §11 está muda"; fi
  else
    warn "skill-reminder: no pude sintetizar un path desde tu skill-matrix.conf — verifica el gate a mano"
  fi

  # 9. canon-enforce: un secreto RECIÉN ESCRITO en el árbol debe bloquear el
  #    cierre de turno. (Clave ensamblada; formato válido no canónico.)
  ( cd "$SB/r" && printf 'let apiKey = "%s%s"\n' 'AKIA' 'X7Q4ZR9PL2MN8V3B' > Leak.swift )
  out="$(cd "$SB/r" && bash scripts/agent-hooks/canon-enforce.sh </dev/null 2>&1)"; rc=$?
  if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q 'SECRETO'; then
    ok "canon-enforce: VE (bloqueó el cierre de turno con un secreto recién escrito)"
  else
    bad "canon-enforce: NO bloqueó un secreto recién escrito (exit $rc) — el Stop-gate está mudo"
  fi
  ( cd "$SB/r" && rm -f Leak.swift )

  rm -rf "$SB"
}
case "${1:-}" in --selftest|--full) selftest ;; esac

# ── Veredicto estático + checklist en vivo ──────────────────────────
echo ""
echo "━━━ checklist EN VIVO (esto NO se puede verificar en estático) ━━━"
cat <<'LIVE'
En una sesión REAL de Claude Code sobre este repo, verifica una vez por
versión del cliente (y anota la fecha en docs/process/lessons_learned.md):

  □ SessionStart: al abrir la sesión se imprime el health-check.
  □ git-guard: pide `git commit --no-verify -m x` → debe DENEGARSE por el
    reviewer-gate. (Las prohibiciones de FLAGS viven en el guard a propósito:
    permissions no soporta comodines intermedios — lección f-3c027a85.)
  □ skill-reminder: intenta editar un archivo que case la matriz sin haber
    leído las refs → debe bloquear (preset full).
  □ reviewer-gate: `git commit` sin marker → bloqueado (full) / aviso (lite).
  □ SubagentStop: invoca al sub-agente reviewer; al terminar debe existir
    .agents/state/markers/reviewer_run.txt con `source: hook`.
  □ Compactación: fuerza `/compact`; el turno siguiente debe traer el digest
    reinyectado (SessionStart matcher compact → post-compact.sh) y NO debe
    haberse borrado .agents/state/skills-read/.
  □ Telemetría: .agents/state/metrics/detections.jsonl crece cuando un gate
    detecta algo.

En Codex CLI (si lo usas):
  □ hooks habilitados ([features] codex_hooks) y `git commit --no-verify`
    denegado por el adapter. Si tu versión no soporta hooks de proyecto,
    muévelos a ~/.codex/hooks.json.

En Cursor (si lo usas):
  □ beforeShellExecution deniega `git commit` sin marker (respuesta JSON del
    gate-adapter). Recuerda: sin SubagentStop, el marker se genera con
    scripts/mark-reviewer-run.sh (auditado) o preset lite.
LIVE

echo ""
if [ "$FAIL" = "0" ]; then
  echo "✅ validate-harness: checks estáticos OK. Lo de arriba ↑ solo lo prueba una sesión real."
  exit 0
fi
echo "❌ validate-harness: hay checks estáticos FALLANDO — gates mudos o rotos. Arréglalos antes de confiar."
exit 1
