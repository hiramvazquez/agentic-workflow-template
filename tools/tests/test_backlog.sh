#!/usr/bin/env bash
# Backlog runner (PRD 0003). El selector decide QUÉ historia trabaja un agente
# sin supervisión — sus falsos positivos son caros en las dos direcciones:
# elegir una historia que no tocaba (deps sin mergear, ejemplos del template)
# o saltarse una legítima.

_bl_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/backlog" "$d/backlog"
  cp "$PROJECT_ROOT/tools/backlog/next.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/run.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/criteria-link.sh" "$d/tools/backlog/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_story() { # _story <archivo> <id> <status> <deps>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia $2
status: $3
depends_on: [$4]
base: develop
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.

## Verificación de criterios
1. n/a-manual — historia de juguete del harness, sin código que verificar
EOF
}

# ── selección básica ────────────────────────────────────────────────
_case_elige_primera_ready() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready ""
  _story 0003-c.md 0003 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    eligió '$out' (esperaba 0002-b.md, la primera ready)"; return 1
}
test_elige_la_primera_ready() { _bl_sandbox _case_elige_primera_ready; }

# ── FALSO POSITIVO guard: ejemplos y terminadas NO se eligen ────────
_case_ignora_ejemplos_y_terminadas() {
  _story 0001-ej.md 0001 ejemplo ""
  _story 0002-done.md 0002 done ""
  _story 0003-rev.md 0003 in-review ""
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    FALSO POSITIVO: eligió '$out' sin haber historias ready"; return 1; }
}
test_ignora_ejemplos_y_no_ready() { _bl_sandbox _case_ignora_ejemplos_y_terminadas; }

# ── dependencias: solo desbloquea el DONE (= mergeado a base) ───────
_case_dep_pendiente_bloquea() {
  _story 0001-a.md 0001 in-review ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    eligió '$out' con su dependencia 0001 aún sin mergear (in-review)"; return 1; }
}
test_dependencia_sin_done_bloquea() { _bl_sandbox _case_dep_pendiente_bloquea; }

_case_dep_done_desbloquea() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    con la dep en done, no eligió 0002 (out='$out')"; return 1
}
test_dependencia_done_desbloquea() { _bl_sandbox _case_dep_done_desbloquea; }

_case_salta_bloqueada_y_toma_siguiente() {
  _story 0001-a.md 0001 ready "0009"     # dep inexistente → no elegible
  _story 0002-b.md 0002 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    no saltó a la siguiente elegible (out='$out')"; return 1
}
test_salta_la_bloqueada_y_toma_la_siguiente() { _bl_sandbox _case_salta_bloqueada_y_toma_siguiente; }

_case_sin_backlog_silencio() {
  rm -rf backlog
  bash tools/backlog/next.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    sin backlog/ devolvió error (debe ser no-op apto para cron)"; return 1; }
}
test_sin_backlog_es_noop() { _bl_sandbox _case_sin_backlog_silencio; }

# ── guards del runner (contrato WORKTREE: el checkout del humano es intocable) ─
_fake_claude() { # instala un claude falso que registra invocaciones en $CLAUDE_LOG
  mkdir -p bin
  printf '#!/usr/bin/env bash\n[ -n "${CLAUDE_LOG:-}" ] && echo run >> "$CLAUDE_LOG"\nexit 0\n' > bin/claude
  chmod +x bin/claude
}

_case_arbol_sucio_ya_no_bloquea() {
  # ANTES: guard duro (exit 1). AHORA el worktree aísla: el run procede y los
  # cambios sucios del humano quedan EXACTAMENTE como estaban.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  echo dirty > seed.txt
  _fake_claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "0" ] || { echo "    con worktrees, el árbol sucio no debería bloquear (rc=$rc)"; return 1; }
  [ "$(cat seed.txt)" = "dirty" ] || { echo "    el run TOCÓ los cambios sin commitear del humano"; return 1; }
}
test_arbol_sucio_ya_no_bloquea() { _bl_sandbox _case_arbol_sucio_ya_no_bloquea; }

_case_checkout_humano_intacto() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  _fake_claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    || { echo "    el run CAMBIÓ la rama del checkout del humano ($(git rev-parse --abbrev-ref HEAD))"; return 1; }
  grep -q "status: ready" backlog/0001-a.md \
    || { echo "    el estado cambió en la BASE antes del merge (debe cambiar solo en la rama)"; return 1; }
  git rev-parse --verify story/0001-a >/dev/null 2>&1 \
    || { echo "    no existe la rama de la historia"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md | grep '^status:')"
  case "$st" in *in-review*) : ;; *) echo "    en la rama la historia no quedó in-review ($st)"; return 1 ;; esac
}
test_checkout_del_humano_queda_intacto() { _bl_sandbox _case_checkout_humano_intacto; }

_case_in_review_no_se_retrabaja() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  _fake_claude
  export CLAUDE_LOG="$PWD/runs.log"
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1   # 1º: trabaja → in-review
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1   # 2º: debe SALTARLA
  local n; n="$(wc -l < runs.log | tr -d ' ')"
  unset CLAUDE_LOG
  [ "$n" = "1" ] || { echo "    una historia in-review fue RE-trabajada ($n invocaciones de claude, esperaba 1)"; return 1; }
}
test_historia_in_review_no_se_retrabaja() { _bl_sandbox _case_in_review_no_se_retrabaja; }

_case_sin_claude_exit3() {
  _story 0001-a.md 0001 ready ""
  PATH="/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "3" ] || { echo "    sin binario claude no dio exit 3 (rc=$rc)"; return 1; }
  grep -q "status: ready" backlog/0001-a.md || { echo "    la historia cambió de estado sin haberse trabajado"; return 1; }
  git rev-parse --verify story/0001 >/dev/null 2>&1 && { echo "    creó la rama pese a no poder trabajar"; return 1; }
  return 0
}
test_sin_claude_exit3_e_historia_intacta() { _bl_sandbox _case_sin_claude_exit3; }

# ── historia sin criterios de aceptación → blocked, no improvisación ─
_case_sin_criterios_se_bloquea() {
  cat > backlog/0001-vacia.md <<'EOF'
---
id: 0001
titulo: Historia sin criterios
status: ready
depends_on: []
base: develop
---
Hacer algo, ya tal.
EOF
  _fake_claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  grep -q "status: blocked" backlog/0001-vacia.md \
    || { echo "    una historia SIN criterios de aceptación no quedó blocked (§1.4: no se improvisa)"; return 1; }
}
test_historia_sin_criterios_queda_blocked() { _bl_sandbox _case_sin_criterios_se_bloquea; }

# ════════════════════════════════════════════════════════════════════
# f-runner-retrabaja — el estado real no está solo en la rama base
# ════════════════════════════════════════════════════════════════════
# El `in-review` lo commitea el runner DENTRO de story/NNNN, así que desde
# develop una historia terminada sigue diciendo `ready` y el selector la
# devolvía otra vez. Con el humano tardando en mergear —el escenario para el
# que existe un runner desatendido— eso es rehacer trabajo ya verificado, y
# mientras tanto no avanzar a la siguiente.
_rama_con_estado() { # _rama_con_estado <rama> <archivo> <estado>
  local actual; actual="$(git rev-parse --abbrev-ref HEAD)"
  git checkout -q -b "$1" 2>/dev/null || git checkout -q "$1"
  sed -i.bak "s/^status: .*/status: $3/" "$2" && rm -f "$2.bak"
  git add -A >/dev/null 2>&1; git commit -qm "estado $3 en $1" >/dev/null 2>&1
  git checkout -q "$actual"
}

_case_terminada_en_su_rama_no_se_reofrece() {
  _story 0005-e.md 0005 ready ""
  _story 0006-f.md 0006 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  _rama_con_estado story/0005-e backlog/0005-e.md in-review
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0005-e.md)
    echo "    re-ofreció una historia TERMINADA que espera merge (~rehacerla desde cero)"; return 1 ;;
  esac
  case "$out" in *0006-f.md) return 0 ;; esac
  echo "    saltó la 0005 pero tampoco avanzó a la 0006 (el backlog se para): '$out'"
  return 1
}
test_historia_terminada_en_rama_no_se_reofrece_y_avanza() {
  _bl_sandbox _case_terminada_en_su_rama_no_se_reofrece
}

_case_trabajo_a_medias_si_se_retoma() {
  # La otra cara, y la que hace peligroso el arreglo ingenuo ("saltar si existe
  # la rama"): un run que se cortó deja la rama en `in-progress`. Si el selector
  # la saltara, esa historia quedaría huérfana PARA SIEMPRE — nadie la volvería
  # a ofrecer nunca. Se devuelve: run.sh sabe retomar el worktree.
  _story 0005-e.md 0005 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  _rama_con_estado story/0005-e backlog/0005-e.md in-progress
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0005-e.md) return 0 ;; esac
  echo "    una historia a MEDIAS quedó huérfana: nadie la volverá a ofrecer ('$out')"
  return 1
}
test_historia_a_medias_se_sigue_ofreciendo_para_retomarla() {
  _bl_sandbox _case_trabajo_a_medias_si_se_retoma
}

_case_mergeada_sin_marcar_avisa() {
  # Si el humano mergea y olvida poner `done` en la base, las dependientes no
  # se desbloquean nunca y el backlog se para sin que nadie vea por qué.
  _story 0005-e.md 0005 in-review ""
  _story 0006-f.md 0006 ready "0005"
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  local err; err="$(bash tools/backlog/next.sh 2>&1 >/dev/null)"
  case "$err" in *"MERGEADA"*|*"status: done"*) return 0 ;; esac
  echo "    no avisó de la historia mergeada sin marcar (el backlog se para en silencio)"
  return 1
}
test_mergeada_sin_marcar_done_se_avisa() { _bl_sandbox _case_mergeada_sin_marcar_avisa; }

_case_sin_ramas_todo_igual() {
  # FALSO POSITIVO guard: sin ninguna rama story/*, el selector se comporta
  # exactamente como antes. El arreglo no puede cambiar el caso normal.
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    sin ramas, el selector cambió de comportamiento: '$out'"; return 1
}
test_sin_ramas_el_selector_no_cambia() { _bl_sandbox _case_sin_ramas_todo_igual; }

# ════════════════════════════════════════════════════════════════════
# f-run-a-medias-exit0 · f-criterio6-sin-test — cerrar no es "salir con 0"
# ════════════════════════════════════════════════════════════════════
_hist_con_verificacion() { # <archivo> <id> <n-criterios> <lineas-verificacion>
  cat > "backlog/$1" <<EOF
---
id: $2
status: ready
depends_on: []
base: develop
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.
2. Dado A cuando B entonces C.

## Verificación de criterios
$4
EOF
}

_case_criterios_sin_test_bloquean() {
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/FooTests.swift::testUno"
  mkdir -p Tests; printf 'test\n' > Tests/FooTests.swift
  bash tools/backlog/criteria-link.sh backlog/0009-i.md >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un criterio SIN test pasó el gate"; return 1; }
}
test_criterio_sin_test_no_pasa() { _bl_sandbox _case_criterios_sin_test_bloquean; }

_case_criterios_con_test_pasan() {
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/FooTests.swift::testUno
2. n/a-manual — es un criterio visual, verificado en captura"
  mkdir -p Tests; printf 'test\n' > Tests/FooTests.swift
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"total=2 sin_test=0"*) return 0 ;; esac
  echo "    una historia bien verificada fue rechazada: $out"; return 1
}
test_criterios_con_test_o_excepcion_pasan() { _bl_sandbox _case_criterios_con_test_pasan; }

_case_test_fantasma_no_cuenta() {
  # Mismo fallo que los detectores citados que ya no existían, un nivel arriba:
  # validar solo que el campo esté relleno deja pasar tests que no existen.
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/NoExiste.swift::testUno
2. n/a-manual — visual"
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"NO existe"*) return 0 ;; esac
  echo "    un test FANTASMA se dio por válido: $out"; return 1
}
test_test_citado_inexistente_no_cuenta() { _bl_sandbox _case_test_fantasma_no_cuenta; }

_case_historia_sin_criterios_es_noop() {
  # FALSO POSITIVO guard: sin criterios no hay nada que exigir. (El guard de
  # "historia sin criterios" es otro y vive en run.sh.)
  printf -- '---\nid: 0009\nstatus: ready\n---\n# vacía\n' > backlog/0009-i.md
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    una historia sin criterios fue rechazada (exit $rc)"; return 1; }
  case "$out" in *"total=0"*) return 0 ;; esac
  echo "    contó criterios donde no los hay: $out"; return 1
}
test_historia_sin_criterios_no_exige_verificacion() {
  _bl_sandbox _case_historia_sin_criterios_es_noop
}

_case_lista_posterior_no_infla_el_total() {
  # FALSO POSITIVO real esperando a pasar: cualquier lista numerada MÁS ABAJO
  # en la historia (notas técnicas, bloqueos) inflaría el total y el gate
  # pediría cobertura de criterios que no existen.
  cat > backlog/0009-i.md <<'EOF'
---
id: 0009
status: ready
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.

## Verificación de criterios
1. n/a-manual — visual

## Notas técnicas
1. Mira el adapter de red.
2. Ojo con el timeout.
EOF
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"total=1 sin_test=0"*) return 0 ;; esac
  echo "    una lista de otra sección infló el conteo: $out"; return 1
}
test_listas_de_otras_secciones_no_cuentan_como_criterios() {
  _bl_sandbox _case_lista_posterior_no_infla_el_total
}

_case_run_con_trabajo_sin_commitear_no_es_in_review() {
  # Cazado en vivo: el agente lanzó la suite en background, dijo "me notificará
  # al terminar" y acabó su turno. `claude -p` salió con 0 → la historia quedaba
  # in-review y el runner exit 0, con 691 líneas sin commitear que ni siquiera
  # salían en `git diff base...rama`. El exit code de un sub-proceso dice que el
  # proceso terminó, no que el trabajo esté hecho.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  printf '#!/usr/bin/env bash\nprintf "adapter a medias\\n" > Adapter.swift\nexit 0\n' > bin/claude
  chmod +x bin/claude
  local rc; PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    un run que dejó trabajo sin commitear salió con 0 (parece terminado)"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md 2>/dev/null | grep '^status:')"
  case "$st" in *in-review*) echo "    quedó marcada in-review con trabajo sin commitear ($st)"; return 1 ;; esac
  case "$st" in *in-progress*) : ;; *) echo "    no volvió a in-progress ($st)"; return 1 ;; esac
  [ -f ".agents/worktrees/story-0001-a/Adapter.swift" ] \
    || { echo "    el trabajo pendiente desapareció del worktree"; return 1; }
  ls .agents/state/backlog/0001-pendiente-*/Adapter.swift >/dev/null 2>&1 \
    || { echo "    no se respaldó el trabajo pendiente (se pierde si alguien poda el worktree)"; return 1; }
}
test_run_que_deja_trabajo_sin_commitear_no_cierra() {
  _bl_sandbox _case_run_con_trabajo_sin_commitear_no_es_in_review
}

_case_run_limpio_si_cierra() {
  # FALSO POSITIVO guard: el caso normal —el agente commitea lo suyo— tiene que
  # seguir cerrando en in-review. Un gate que bloquea también al que hace las
  # cosas bien se desactiva en una semana.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  printf '#!/usr/bin/env bash\nprintf "hecho\\n" > Adapter.swift\ngit add -A >/dev/null 2>&1\ngit -c user.email=a@a -c user.name=a commit -qm "feat: adapter" >/dev/null 2>&1\nexit 0\n' > bin/claude
  chmod +x bin/claude
  local rc; PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    un run LIMPIO fue rechazado (rc=$rc)"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md 2>/dev/null | grep '^status:')"
  case "$st" in *in-review*) return 0 ;; esac
  echo "    un run limpio no cerró en in-review ($st)"; return 1
}
test_run_limpio_si_cierra_en_in_review() { _bl_sandbox _case_run_limpio_si_cierra; }
