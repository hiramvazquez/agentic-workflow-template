#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-selftest.sh — cada detector DEMUESTRA una vez que ve
# ════════════════════════════════════════════════════════════════════
# El bloque `--selftest` / `--full` de tools/validate-harness.sh. Los checks
# estáticos miran CONFIGURACIÓN; esto exige EVIDENCIA: cada detector corre
# contra un fixture mínimo en un sandbox, con los binarios y confs de ESTE
# repo, y debe emitir su contrato (§14.3) — el exit code correcto y su marca
# (SUMMARY / score).
#
# Se SOURCEA desde tools/validate-harness.sh: usa sus helpers ok/bad/warn y su
# variable FAIL. No se ejecuta suelta (tools/lib/ → sin bit +x, exento de
# check-exec-bits.sh).

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
  # ── De dónde se copia: de donde ESTÁ el harness, no del cwd ────────
  # Esto era `cp -R tools …`, una ruta relativa al directorio de trabajo. Solo
  # funciona mientras el harness viva EN la raíz del repo. Medido el 2026-09-02
  # sobre un clon con `tools/ scripts/ ci/` movidos a `.workflow/`: el `cp`
  # fallaba, el sandbox no se montaba y NINGUNO de los casos corría — incluidos
  # los cuatro escritos ese mismo día para cubrir exactamente ese escenario.
  # `$VH_LIB` sí se resuelve desde la ubicación del script (`dirname
  # "${BASH_SOURCE[0]}"`), así que el harness siempre sabe dónde está.
  local _ST_TOOLS _ST_HOME
  _ST_TOOLS="$(cd "${VH_LIB:-tools/lib}/.." 2>/dev/null && pwd)" || _ST_TOOLS=""
  _ST_HOME="$(cd "${VH_LIB:-tools/lib}/../.." 2>/dev/null && pwd)" || _ST_HOME=""
  [ -n "$_ST_TOOLS" ] && cp -R "$_ST_TOOLS" "$SB/r/tools" 2>/dev/null
  [ -n "$_ST_HOME" ] && cp -R "$_ST_HOME/scripts" "$SB/r/scripts" 2>/dev/null   # los hooks bloqueantes también se selftestean
  rm -rf "$SB/r/tools/tests"   # la suite no es un detector
  (
    cd "$SB/r" || exit 1
    [ -d tools ] && [ -d scripts ] || exit 1
    git init -q . 2>/dev/null; git config user.email s@s.s; git config user.name s
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    echo full > tools/preset
  ) || {
    # `bad`, no `warn`: warn NO toca FAIL, así que un selftest que se rendía
    # salía como sano y los 13 casos se saltaban en silencio. Un selftest que
    # no puede montarse es EXACTAMENTE "un gate que no corrió pareciendo un
    # gate que pasó" (§14.3), el único pecado que este harness no comete.
    bad "selftest: NO pude montar el sandbox — ningún detector demostró que ve (¿el harness no está donde cree?)"
    rm -rf "$SB"; return 0
  }

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
  # Las rutas salen de la copia YA MONTADA en el sandbox, no del cwd: leerlas
  # con `ls tools/…` hacía que desde un harness movido no se encontrara el
  # fixture y el caso degradara a ⚠️ — y `warn` no marca FAIL, así que el
  # nivel 2 se quedaba sin demostrar y el selftest salía verde igual.
  local FIXT=""
  if ls "$SB"/r/tools/semgrep/fixtures/*-malo.* >/dev/null 2>&1; then
    FIXT="$(ls "$SB"/r/tools/semgrep/fixtures/*-malo.* | head -1)"
    cp "$FIXT" "$SB/r/fixture_selftest.${FIXT##*.}" 2>/dev/null
  elif [ -f "$SB/r/tools/semgrep/rules/swift.yaml" ]; then
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
  # Limpieza — NO es cosmética. Este fixture es un archivo lleno de violaciones
  # a propósito; si se queda en el sandbox, los casos que miden AGREGADOS lo
  # cuentan. Medido: el caso 13 aprobaba con `errors=2` que eran de ESTE archivo,
  # no del suyo. Todos los demás casos limpian; este era el único que no.
  ( cd "$SB/r" && git rm -q --cached fixture_selftest.* 2>/dev/null; rm -f fixture_selftest.* )

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
  done < "$SB/r/tools/skill-matrix.conf"   # la copia montada, no el cwd (ver caso 4)
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

  # ── Los que resuelven RUTAS y pueden quedar mudos EN VERDE ────────
  # Esta tanda existe por un fallo reproducido, no por completitud. Los
  # detectores de abajo resuelven QUÉ mirar con rutas relativas al cwd: su CONF
  # (`tools/layers.conf`) y los directorios del proyecto (`ios android web src
  # app lib Sources`, `commonMain/`). Si falta cualquiera de los dos, salen
  # **0 con su SUMMARY en cero**. En la reproducción real la rama que dispara
  # primero es la del CONF ausente (`check-layers.sh:22`), porque `layers.conf`
  # viaja con `tools/`; la de SRC_DIRS (líneas 24-26) es la segunda. Las dos
  # llevan al mismo sitio — no el 3 de "no pude mirar" que
  # §14.3 define, sino el 0 de "miré y está limpio".
  #
  # Medido el 2026-09-02 sobre un clon con `tools/ scripts/ ci/` movidos a
  # `.workflow/`: la MISMA violación (`web/domain/repo.ts` importando axios)
  # daba `exit=1 · errors=1` desde la raíz y `exit=0 · errors=0` desde
  # `.workflow/`. Agravante: ese `errors=0` alimenta el trinquete de drift,
  # que SOLO BAJA — una medición falsa fija el suelo en cero de forma
  # permanente, en un fichero que está en `permissions.deny`.
  #
  # Por eso el caso no comprueba "el detector arrancó": comprueba que **ve
  # una violación real**. Un detector sin objetivos no puede pasarlo.

  # 10. check-layers: una violación de capas real DEBE bloquear (exit 1).
  #     El fixture usa la regla `*/domain/*` + `axios` de layers.conf, que es
  #     la que menos supuestos hace sobre el stack del adoptante.
  ( cd "$SB/r" && mkdir -p web/domain \
    && printf 'import axios from "axios"\nexport const r = 1\n' > web/domain/repo.ts ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-layers.sh 2>&1)"; rc=$?
  if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q 'axios'; then
    ok "check-layers: VE (cazó el import de infraestructura en el dominio)"
  else
    bad "check-layers: NO vio una violación real (exit $rc) — si su SUMMARY dice errors=0, está mirando una raíz sin fuentes"
  fi
  ( cd "$SB/r" && rm -rf web )

  # 11. check-source-sets: un import de plataforma en commonMain DEBE bloquear.
  #     Con semgrep operativo sale 1 por el motor primario; sin semgrep, el
  #     fallback textual también lo caza porque el import está a inicio de
  #     línea. Un exit 3 aquí sería "no pude mirar" y también es un fallo del
  #     selftest: el detector no puede demostrar que ve.
  ( cd "$SB/r" && mkdir -p shared/src/commonMain/kotlin \
    && printf 'package d\nimport android.net.Uri\nclass R\n' > shared/src/commonMain/kotlin/R.kt ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-source-sets.sh 2>&1)"; rc=$?
  if [ "$rc" = "1" ]; then
    ok "check-source-sets: VE (cazó un import de plataforma en commonMain)"
  else
    bad "check-source-sets: NO vio un import de plataforma en commonMain (exit $rc) — el segundo eje de capas está mudo"
  fi
  ( cd "$SB/r" && rm -rf shared )

  # 12. check-exec-bits: un .sh sin bit de ejecución DEBE detectarse.
  #     Recorre el árbol del repo; desde una raíz equivocada no ve ninguno y
  #     aprueba. Se invoca SIN --fix para que reporte en vez de reparar.
  ( cd "$SB/r" && printf '#!/usr/bin/env bash\necho x\n' > sinbit.sh && chmod 644 sinbit.sh \
    && git add sinbit.sh ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-exec-bits.sh 2>&1)"; rc=$?
  # `&&` con exit 1 exacto, no `||`: el contrato de check-exec-bits es 0 =
  # limpio · 1 = hay .sh sin +x, sin tercera vía. Con `||` bastaba con que el
  # MENSAJE se imprimiera, así que quitarle el `exit 1` al detector —su modo de
  # fallo real— pasaba este caso en verde.
  if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q 'sinbit.sh'; then
    ok "check-exec-bits: VE (detectó un .sh staged sin bit de ejecución)"
  else
    bad "check-exec-bits: NO vio un .sh sin bit de ejecución (exit $rc) — puede estar recorriendo un árbol vacío"
  fi
  ( cd "$SB/r" && git rm -q --cached sinbit.sh 2>/dev/null; rm -f sinbit.sh )

  # 13. check-drift: agrega métricas sobre las MISMAS fuentes del proyecto,
  #     así que comparte el modo de fallo. Un archivo muy por encima del hard
  #     limit de §4 tiene que aparecer en su resumen.
  # Se mide el DELTA que ESTE archivo provoca, no un absoluto. Dos razones, las
  # dos medidas el 2026-09-02 contra mutantes reales:
  #  · Un `errors=[1-9]` absoluto lo satisface CUALQUIER error del sandbox. Fue
  #    literalmente lo que pasó: el fixture de semgrep del caso 4 se quedaba en
  #    el árbol y aportaba `errors=2`, así que el caso aprobaba sin haber contado
  #    nada suyo. (Eso también está arreglado arriba, pero el assert no debe
  #    depender de que nadie ensucie.)
  #  · Exigir solo que el nombre se IMPRIMA deja vivo el mutante que reporta sin
  #    incrementar el contador — y el contador es lo ÚNICO que lee
  #    `drift-ratchet.sh`, el trinquete que solo baja. Un `errors=0` falso fija
  #    el suelo en cero de forma permanente.
  _cd_errores() { printf '%s\n' "$1" | sed -n 's/.*DRIFT_SUMMARY errors=\([0-9][0-9]*\).*/\1/p' | tail -1; }
  local base con
  base="$(_cd_errores "$(cd "$SB/r" && bash tools/check-drift.sh 2>&1)")"
  ( cd "$SB/r" && mkdir -p app && { printf '// l\n'; for _i in $(seq 1 450); do printf 'let x%s = 1\n' "$_i"; done; } > app/Enorme.swift ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-drift.sh 2>&1)"; rc=$?
  con="$(_cd_errores "$out")"
  if printf '%s' "$out" | grep -q 'Enorme' && [ "${con:-0}" -gt "${base:-0}" ]; then
    ok "check-drift: VE (contó un archivo sobre el hard limit)"
  else
    bad "check-drift: NO contó un archivo de 451 líneas sobre el límite (errors ${base:-?}→${con:-?}) — o mide un árbol vacío, o reporta sin sumar al contador que lee el trinquete"
  fi
  ( cd "$SB/r" && rm -rf app )

  rm -rf "$SB"
}
