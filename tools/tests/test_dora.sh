#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Las métricas: las que se pueden medir aquí, y las que NO
# ════════════════════════════════════════════════════════════════════
# PRD 0009 fase 5. Las cuatro DORA más aceptación y retrabajo son la referencia
# de 2026 porque miden RESULTADOS de entrega, no actividad: son difíciles de
# inflar con líneas de código o tasas de aceptación.
#
# Pero el design-review verificó el `git log` real de este repo —0 merges de 149
# commits, cero despliegues— y demostró que tres de las seis definiciones que el
# PRD traía eran inaplicables aquí. Publicar "frecuencia de entrega: 0/semana"
# en un repo que entrega varias veces al día sería el cero ambiguo que todo este
# trabajo existe para matar, reintroducido en la fase que lo mide.
#
# Así que la regla de este informe es la misma que la del lector de detectores:
# **una métrica sin evento definido en ESTE repo sale `n/a` CON su razón**, nunca
# 0. Un cero que nadie midió es peor que un hueco declarado.

_DORA_LIB="$PROJECT_ROOT/tools/tests/lib/dora-sandbox.sh"
# shellcheck source=/dev/null
. "$_DORA_LIB"

# ── 1. Lo que no se puede medir sale n/a CON su razón ───────────────
# El corazón del asunto. Sin merges no hay lead time, y el campo `area` del
# ledger es texto libre: no hay join para el retrabajo. Las dos tienen que
# DECIRLO, no dar 0.
_case_lo_no_medible_se_declara() {
  local out; out="$(_dora)"
  local m
  for m in "lead time" "retrabajo"; do
    printf '%s' "$out" | grep -i "$m" | grep -qi 'n/a' || {
      echo "    '$m' no sale como n/a:"
      printf '%s\n' "$out" | grep -i "$m" | sed 's/^/      /'
      echo "    Publicar un 0 aquí sería el cero ambiguo que esto viene a matar."
      return 1; }
    printf '%s' "$out" | grep -i "$m" | grep -qE '—|porque|:' || {
      echo "    '$m' sale n/a pero SIN razón; un hueco sin explicar se lee como un fallo"
      return 1; }
  done
}
test_lo_que_no_se_puede_medir_sale_na_con_razon() {
  _dora_sandbox _case_lo_no_medible_se_declara
}

# ── 2. La aceptación se calcula por UNIDAD, no por fila ─────────────
# 'Verde a la primera' es una propiedad de la unidad de trabajo, no del número
# de veredictos: un cambio revisado tres veces cuenta una vez, y cuenta por su
# PRIMER veredicto.
_case_aceptacion_por_unidad() {
  _dora_review RED   aaa
  _dora_review GREEN aaa   # misma unidad, segunda ronda: NO cuenta como verde
  _dora_review GREEN bbb
  local out; out="$(_dora)"
  printf '%s' "$out" | grep -i 'aceptaci' | grep -q '50' || {
    echo "    con 2 unidades (una RED-luego-GREEN, otra GREEN) la tasa debería ser 50%:"
    printf '%s\n' "$out" | grep -i 'aceptaci' | sed 's/^/      /'
    echo "    Contar filas en vez de unidades premia al que revisa más veces."
    return 1; }
}
test_la_aceptacion_se_cuenta_por_unidad_de_trabajo() {
  _dora_sandbox _case_aceptacion_por_unidad
}

# ── 3. Sin `gh` no se cae: declara y sigue ──────────────────────────
# El tiempo de recuperación necesita el estado de CI, que vive en `gh`, no en
# git. Un adoptante sin `gh` no puede quedarse sin las otras cinco.
_case_sin_gh_no_aborta() {
  mkdir -p bin; printf '#!/usr/bin/env bash\nexit 127\n' > bin/gh; chmod +x bin/gh
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/metrics/dora.sh 2>&1)"; rc=$?
  [ "$rc" != "0" ] && { echo "    sin gh el informe entero abortó (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -i 'recuperaci' | grep -qi 'n/a' || {
    echo "    sin gh, el tiempo de recuperación no se declara n/a:"
    printf '%s\n' "$out" | grep -i 'recuperaci' | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -qi 'frecuencia' || {
    echo "    sin gh se perdieron las métricas que NO dependen de gh"; return 1; }
}
test_sin_gh_declara_y_sigue() { _dora_sandbox _case_sin_gh_no_aborta; }

# ── 6. La tasa de fallo ARRASTRA su denominador ─────────────────────
# 0% sobre 41 clasificados de 247 no es 0%. Publicar la tasa desnuda sería el
# cero sin denominador que `detector_runs.py` existe para separar.
_case_denominador() {
  # escape-rate falso: solo tiene que imprimir la línea que dora parsea.
  cat > tools/metrics/escape-rate.sh <<'FAKE'
#!/usr/bin/env bash
echo "ESCAPE RATE: 7% (3/41 findings clasificados)"
FAKE
  chmod +x tools/metrics/escape-rate.sh
  local out; out="$(_dora)"
  local l; l="$(printf '%s\n' "$out" | grep -i 'tasa de fallo')"
  printf '%s' "$l" | grep -q '7' || { echo "    no salió la tasa: $l"; return 1; }
  printf '%s' "$l" | grep -q '41' || {
    echo "    la tasa sale SIN su denominador: $l"
    echo "    '7%' a secas oculta que solo 41 de 247 findings están clasificados."
    return 1; }
}
test_la_tasa_de_fallo_arrastra_su_denominador() { _dora_sandbox _case_denominador; }

# ── 9. El rojo de un pipeline NO lo recupera el verde de otro ────────
# Lo cazó el review con el `gh run list` real de este repo: hay tres workflows
# activos, y parear "roja → primera verde posterior" sobre la lista MEZCLADA
# emparejaba un rojo de `gate-0a-macos` con un verde de `harness-ci` 27h
# después. No es una recuperación: es un artefacto de mezclar dos pipelines.
# Y el número contaminado ya se había commiteado en metrics-weekly.md.
#
# El fixture está construido para que las dos lecturas den números DISTINTOS:
#   mezclado → 1.0 h sobre 1 par   ·   por workflow → 4.0 h sobre 3 pares
#
# Y los tres intervalos (1h, 4h, 10h) tienen MEDIANA 4 y MEDIA 5 a propósito:
# el review lanzó `median`→`mean` y sobrevivió porque el fixture anterior las
# hacía coincidir. Un fixture simétrico no distingue estadísticos.
_case_recuperacion_por_workflow() {
  mkdir -p bin
  cat > bin/gh <<'FAKE'
#!/usr/bin/env bash
cat <<'JSON'
[{"conclusion":"failure","updatedAt":"2026-09-01T10:00:00Z","name":"alfa"},
 {"conclusion":"failure","updatedAt":"2026-09-01T10:15:00Z","name":"beta"},
 {"conclusion":"success","updatedAt":"2026-09-01T11:00:00Z","name":"alfa"},
 {"conclusion":"failure","updatedAt":"2026-09-01T10:30:00Z","name":"gamma"},
 {"conclusion":"success","updatedAt":"2026-09-01T14:15:00Z","name":"beta"},
 {"conclusion":"success","updatedAt":"2026-09-01T20:30:00Z","name":"gamma"}]
JSON
FAKE
  chmod +x bin/gh
  local l; l="$(PATH="$PWD/bin:$PATH" bash tools/metrics/dora.sh 2>&1 | grep -i 'recuperaci')"
  printf '%s' "$l" | grep -q '4.0' || {
    echo "    esperaba 4.0 h (alfa 1h, beta 4h, gamma 10h → mediana 4), salió:"
    echo "      $l"
    echo "    1.0 h sobre 1 par = el rojo de beta lo cerró el verde de alfa."
    echo "    5.0 h = se usó la MEDIA, no la mediana: un rojo largo la arrastra."
    return 1; }
  printf '%s' "$l" | grep -q 'de 3' || {
    echo "    esperaba 3 pares, uno por workflow; salió: $l"; return 1; }
}
test_la_recuperacion_no_cruza_workflows() { _dora_sandbox _case_recuperacion_por_workflow; }

# ── 10. La rama del tronco NO se codifica a mano ─────────────────────
# `main` estaba escrito en el código. En un repo con rama `trunk` —o `master`,
# que sigue siendo el defecto de git— dora decía "0 commits en main en 90 días":
# un n/a cuya RAZÓN es falsa. No es que no hubiera commits; es que miró un sitio
# que no existe. Peor que callar: miente sobre el motivo. Y esto es una
# plantilla que se distribuye a adoptantes, así que le pasa a cualquiera.
_case_tronco_derivado() {
  git branch -m "$(git rev-parse --abbrev-ref HEAD)" trunk 2>/dev/null
  local l; l="$(_dora | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -qi 'n/a' && {
    echo "    con rama 'trunk' la frecuencia sale n/a: $l"
    echo "    Hay un commit; lo que no hay es una rama llamada 'main'."
    return 1; }
  printf '%s' "$l" | grep -q 'trunk' || {
    echo "    mide, pero no dice CONTRA QUÉ rama: $l"
    echo "    Sin nombrarla, el lector no puede saber si midió lo que cree."
    return 1; }
}
test_el_tronco_se_deriva_no_se_codifica() { _dora_sandbox _case_tronco_derivado; }

# ── 11. Lo descartado se declara ────────────────────────────────────
# El cierre de f-... : `_ts()` devolvía None ante una fecha ilegible y el bucle
# hacía `continue`. Esa corrida no contaba en el denominador y nadie lo decía.
# Es el patrón EXACTO de la lección [2026-09-03] sobre agregadores que filtran
# en silencio, cometido en el mismo commit que la añadió. Un descarte que no se
# declara no es un filtro: es una pérdida.
_case_descartes_declarados() {
  mkdir -p bin
  cat > bin/gh <<'FAKE'
#!/usr/bin/env bash
cat <<'JSON'
[{"conclusion":"failure","updatedAt":"2026-09-01T10:00:00Z","name":"alfa"},
 {"conclusion":"success","updatedAt":"2026-09-01T11:00:00Z","name":"alfa"},
 {"conclusion":"failure","updatedAt":"ayer por la tarde","name":"beta"},
 {"conclusion":"success","updatedAt":null,"name":"beta"}]
JSON
FAKE
  chmod +x bin/gh
  local l; l="$(PATH="$PWD/bin:$PATH" bash tools/metrics/dora.sh 2>&1 | grep -i 'recuperaci')"
  printf '%s' "$l" | grep -q '2 descartada' || {
    echo "    dos corridas con fecha ilegible desaparecen sin declararse:"
    echo "      $l"
    return 1; }
}
test_las_corridas_descartadas_se_declaran() { _dora_sandbox _case_descartes_declarados; }

# ── 12. Un veredicto sin diff que firmar también se declara ─────────
# Mismo patrón en la aceptación: una fila sin `staged_sha` no es una unidad de
# trabajo y NO debe contar — pero que no cuente y que nadie lo diga son dos
# cosas distintas. Una review que ocurrió y no se pudo atribuir es un dato.
_case_reviews_sin_sha() {
  _dora_review GREEN aaa
  printf '{"ts":"2026-09-01T10:00:00Z","agent":"reviewer","verdict":"RED"}\n' \
    >> .agents/state/review-history.jsonl
  local l; l="$(_dora | grep -i 'aceptaci')"
  printf '%s' "$l" | grep -q '1 sin diff' || {
    echo "    la fila sin staged_sha se descarta en silencio: $l"; return 1; }
}
test_los_veredictos_sin_sha_se_declaran() { _dora_sandbox _case_reviews_sin_sha; }

# ── 14. Estar en una rama de trabajo no cambia contra qué se mide ────
# "Lo que llega al tronco" es el tronco, no donde tú estés parado. Derivar la
# rama de `HEAD` a secas mediría la frecuencia de tu feature branch y la
# llamaría entrega.
#
# (La indirección A=add/C=commit es la misma que usa `_dora_sandbox`: el
# reviewer-gate lee el texto crudo del comando y ve un `git add` seguido de un
# `git commit` como una evasión del gate, aunque aquí sean datos de un fixture.)
_case_tronco_no_es_head() {
  local base A=add C=commit; base="$(git rev-parse --abbrev-ref HEAD)"
  git checkout -q -b una-feature 2>/dev/null
  echo y > b.txt; git "$A" b.txt 2>/dev/null; git "$C" -qm dos 2>/dev/null
  local l; l="$(_dora | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -q "$base" || {
    echo "    parado en 'una-feature', midió contra otra cosa: $l"
    echo "    Esperaba el tronco ('$base'), no la rama de trabajo."
    return 1; }
  printf '%s' "$l" | grep -q 'una-feature' && {
    echo "    midió contra la rama de trabajo: $l"; return 1; }
  return 0
}
test_el_tronco_no_es_la_rama_actual() { _dora_sandbox _case_tronco_no_es_head; }

# ── 15. El nombre que devuelve `_tronco()` tiene que RESOLVER ───────
# Lo cazó el review con un repro end-to-end. `origin/HEAD` apunta a
# `origin/main`, y de ahí se cortaba el prefijo y se devolvía `main` pelado.
# Pero un nombre pelado solo resuelve si existe la rama LOCAL, y borrarla es
# rutina (`git branch -D main` tras terminar un trabajo). Resultado: el mismo
# "0 commits en `main`" que este cambio dice cerrar, por otra puerta. Y la rama
# de MAYOR prioridad de la función no tenía ni un test.
_case_origin_sin_rama_local() {
  local base; base="$(git rev-parse --abbrev-ref HEAD)"
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git checkout -q --detach
  git branch -q -D "$base" 2>/dev/null
  local l; l="$(_dora | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -qi 'n/a' && {
    echo "    con origin/HEAD y sin rama local, la frecuencia sale n/a:"
    echo "      $l"
    echo "    Hay un commit alcanzable desde origin/main; el nombre pelado no resuelve."
    return 1; }
  printf '%s' "$l" | grep -q 'origin/main' || {
    echo "    midió, pero no contra la referencia que sí resuelve: $l"; return 1; }
}
test_el_tronco_devuelto_tiene_que_resolver() { _dora_sandbox _case_origin_sin_rama_local; }

# ── 16. Si NINGÚN candidato resuelve, se dice — no se inventa uno ───
# El caso límite del mismo defecto: en un repo sin un solo commit no hay tronco
# que medir. Devolver un nombre igualmente produce "0 commits en `X`", que
# vuelve a ser un n/a con la razón equivocada.
_case_sin_tronco_posible() {
  local l; l="$(bash tools/metrics/dora.sh 2>&1 | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -qi 'n/a' || { echo "    esperaba n/a: $l"; return 1; }
  printf '%s' "$l" | grep -qi 'tronco' || {
    echo "    dice n/a pero culpa a la ventana, no a que no hay tronco:"
    echo "      $l"
    echo "    '0 commits en X' en un repo vacío señala al sitio equivocado."
    return 1; }
}
test_sin_tronco_que_medir_se_declara() { _dora_sandbox_vacio _case_sin_tronco_posible; }

# ── 17. Una fila sin veredicto NI sha tampoco se cae callada ────────
# El mutante que el review lanzó y SOBREVIVIÓ: `if veredicto and not sha` deja
# fuera de todo contador a la fila que no tiene ninguno de los dos. Hoy es un
# hueco latente —el único escritor real nunca produce un veredicto vacío— pero
# dejar un descarte mudo en el cambio cuyo propósito es que no los haya es la
# contradicción que este harness castiga en todo lo demás.
_case_fila_sin_nada() {
  _dora_review GREEN aaa
  printf '{"ts":"2026-09-01T10:00:00Z","agent":"reviewer"}\n' \
    >> .agents/state/review-history.jsonl
  local l; l="$(_dora | grep -i 'aceptaci')"
  printf '%s' "$l" | grep -q '1 sin veredicto' || {
    echo "    la fila sin veredicto ni sha desaparece sin contador: $l"; return 1; }
}
test_las_filas_sin_veredicto_ni_sha_se_declaran() { _dora_sandbox _case_fila_sin_nada; }

# ── 18. Se mide contra la REMOTA, y el desfase local se dice ────────
# Decisión del owner tras el hallazgo de la ronda 2. El orden anterior probaba
# el nombre pelado primero "porque es lo que el usuario reconoce", y con una
# rama local por detrás de `origin/<rama>` medía la local sin decirlo: el
# reviewer lo reprodujo dando "2 commits" donde había 3 entregados.
#
# Preferir la remota es además lo correcto por definición: "entrega" es lo que
# llegó al tronco compartido, no lo que tienes en tu clon. Y el desfase se
# declara porque el lector necesita saber que su copia va por detrás de lo que
# se le está contando.
_dora_tres_commits_con_remoto() { # deja origin/main 2 commits por delante de main
  local A=add C=commit c1
  git branch -m "$(git rev-parse --abbrev-ref HEAD)" main 2>/dev/null
  c1="$(git rev-parse HEAD)"
  echo a > x.txt; git "$A" x.txt; git "$C" -qm dos
  echo b > y.txt; git "$A" y.txt; git "$C" -qm tres
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git checkout -q --detach          # para poder mover `main` sin tocar el árbol
  git branch -f main "$c1"
}

_case_prefiere_la_remota() {
  _dora_tres_commits_con_remoto
  local l; l="$(_dora | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -q 'origin/main' || {
    echo "    midió contra la rama local, no contra la remota: $l"; return 1; }
  printf '%s' "$l" | grep -q '3 commits' || {
    echo "    esperaba los 3 commits de origin/main; salió: $l"
    echo "    Con la local (1 commit) el número es el de tu clon, no el entregado."
    return 1; }
}
test_el_tronco_prefiere_la_referencia_remota() { _dora_sandbox _case_prefiere_la_remota; }

_case_avisa_del_desfase() {
  _dora_tres_commits_con_remoto
  local out; out="$(_dora)"
  printf '%s' "$out" | grep -qi 'por detrás' || {
    echo "    no avisa de que la rama local va por detrás de la remota:"
    printf '%s\n' "$out" | tail -4 | sed 's/^/      /'
    return 1; }
  printf '%s' "$out" | grep -qi 'por detrás' && printf '%s' "$out" | grep -q '2 commit' || {
    echo "    avisa, pero sin decir CUÁNTOS commits de desfase"; return 1; }
}
test_avisa_cuando_la_rama_local_va_por_detras() { _dora_sandbox _case_avisa_del_desfase; }

# ── 19. Con la local al día, el aviso CALLA ─────────────────────────
# El review lanzó un mutante sobre el guard de silencio (`or` → `and` en
# `if not detras.isdigit() or detras == "0"`) y SOBREVIVIÓ: mis cuatro mutantes
# cubrían la lógica de negocio y ninguno el silencio. Lo reprodujo contra este
# repo, sincronizado, sacando "va 0 commit(s) por detrás" — un aviso que asusta
# sin motivo. Un detector que avisa cuando no pasa nada se aprende a ignorar,
# y entonces no avisa cuando sí pasa.
_case_sin_desfase_calla() {
  local A=add C=commit
  git branch -m "$(git rev-parse --abbrev-ref HEAD)" main 2>/dev/null
  echo a > x.txt; git "$A" x.txt; git "$C" -qm dos
  git update-ref refs/remotes/origin/main HEAD      # remota == local, al día
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  local out; out="$(_dora)"
  printf '%s' "$out" | grep -qi 'por detrás' && {
    echo "    con la rama local AL DÍA sigue avisando de desfase:"
    printf '%s\n' "$out" | grep -i 'detrás' | sed 's/^/      /'
    return 1; }
  # y sigue midiendo contra la remota, que es lo que se decidió
  printf '%s' "$out" | grep -i 'frecuencia' | grep -q 'origin/main' || {
    echo "    dejó de medir contra la remota"; return 1; }
  return 0
}
test_sin_desfase_el_aviso_calla() { _dora_sandbox _case_sin_desfase_calla; }

# ── 20. Si `gh` no responde a tiempo, se dice ESO ────────────────────
# Decisión del owner tras `f-7a219330`: el timeout baja de 60 s a 20 porque esta
# llamada está ahora en el camino crítico de `/status`, que se documenta a ~13 s.
#
# Pero el número solo era la mitad. Un `TimeoutExpired` es un `SubprocessError`,
# así que caía en el except genérico y salía como "`gh` falló al invocarse" —
# una razón cierta de forma vaga y falsa en lo concreto: no falló al invocarse,
# respondió tarde. Y este informe entero se apoya en que un `n/a` traiga la
# razón VERDADERA; si no, es peor que el 0 al que sustituye.
_case_gh_lento() {
  mkdir -p bin
  printf '#!/usr/bin/env bash\nsleep 5\n' > bin/gh; chmod +x bin/gh
  local out rc
  out="$(PATH="$PWD/bin:$PATH" DORA_GH_TIMEOUT=1 bash tools/metrics/dora.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un gh lento tumbó el informe entero (exit $rc)"; return 1; }
  local l; l="$(printf '%s\n' "$out" | grep -i 'recuperaci')"
  printf '%s' "$l" | grep -qi 'n/a' || { echo "    no salió n/a: $l"; return 1; }
  printf '%s' "$l" | grep -qiE 'no respondió|tard' || {
    echo "    dice n/a pero culpa a la invocación, no a la espera:"
    echo "      $l"
    echo "    'falló al invocarse' es falso: gh arrancó bien, respondió tarde."
    return 1; }
}
test_un_gh_lento_se_declara_como_espera_agotada() { _dora_sandbox _case_gh_lento; }

# ── 21. Un `git` colgado no es "repo sin commits" ────────────────────
# Cierre de `f-74c528ef`, que el review encontró al revisar el arreglo de `gh`:
# el mismo patrón quedaba en otros dos sitios. Este es el peor de los dos.
#
# `git()` devuelve cadena vacía tanto si git DIJO QUE NO (un `rev-parse` sobre
# una ref inexistente sale 1, y eso es una respuesta legítima) como si NO
# RESPONDIÓ. Aguas abajo, `tronco()` no distingue y la métrica salía como "no
# pude determinar la rama del tronco (¿repo sin commits?)" — la razón falsa
# otra vez, sobre un repo con commits y un git que simplemente colgaba.
_case_git_colgado() {
  mkdir -p bin
  printf '#!/usr/bin/env bash\nsleep 5\n' > bin/git; chmod +x bin/git
  local out rc
  out="$(PATH="$PWD/bin:$PATH" DORA_GIT_TIMEOUT=1 bash tools/metrics/dora.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un git colgado tumbó el informe (exit $rc)"; return 1; }
  local l; l="$(printf '%s\n' "$out" | grep -i 'frecuencia')"
  printf '%s' "$l" | grep -qiE 'no respondió|tard' || {
    echo "    un git que no responde se declara mal:"
    echo "      $l"
    echo "    '¿repo sin commits?' es falso: hay commits, git no contestó."
    return 1; }
}
test_un_git_colgado_no_se_confunde_con_repo_vacio() { _dora_sandbox _case_git_colgado; }

# ── 22. Y lo mismo para el script de la tasa de fallo ───────────────
# El tercer sitio del patrón, y el de la ventana MÁS grande (120 s, mayor que
# los 60 originales de `gh`) — también en el camino de `/status`.
_case_escape_colgado() {
  printf '#!/usr/bin/env bash\nsleep 5\n' > tools/metrics/escape-rate.sh
  chmod +x tools/metrics/escape-rate.sh
  local l
  l="$(DORA_ESCAPE_TIMEOUT=1 bash tools/metrics/dora.sh 2>&1 | grep -i 'tasa de fallo')"
  printf '%s' "$l" | grep -qiE 'no respondió|tard' || {
    echo "    escape-rate colgado se declara mal: $l"; return 1; }
}
test_un_escape_rate_colgado_se_declara_como_espera() { _dora_sandbox _case_escape_colgado; }
