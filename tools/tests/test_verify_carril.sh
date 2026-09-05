#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El carril decide QUÉ se ejecuta — y nunca puede decidir ejecutar menos
# ════════════════════════════════════════════════════════════════════
# Hermano de `test_verify_marker.sh`: aquél fija que la evidencia esté LIGADA
# al diff, éste fija cuánta evidencia hay que producir. Se separaron cuando el
# fichero cruzó el hard limit de §4, por esa junta.
#
# El riesgo de todo lo de aquí tiene una sola forma: firmar en verde habiendo
# ejecutado menos de lo que tocaba. Por eso cada caso afirma QUÉ se corrió
# (leyendo el marker), no solo que el exit code fuera 0.
_VS_LIB="$PROJECT_ROOT/tools/tests/lib/verify-sandbox.sh"
# shellcheck source=/dev/null
. "$_VS_LIB"

# ── El carril decide QUÉ se verifica ────────────────────────────────
# PRD 0011 fase 2. Antes todo cambio pagaba la suite entera: ~140 s para añadir
# un string igual que para reescribir el motor. Ahora `verify-run` pregunta el
# carril y ejecuta en proporción.
#
# Lo que NO cambia es el invariante: si lo que se ejecuta falla, no se firma.
_case_ligero_no_corre_la_suite() {
  local A=add
  mkdir -p docs
  printf 'texto\n' > docs/nota.md
  git "$A" docs/nota.md
  # El comando que SIEMPRE falla se inyecta por ENTORNO, no editando
  # `tools/verify.conf`: ese fichero está en el carril estructural, así que
  # stagearlo convertiría el cambio en estructural y el fixture probaría lo
  # contrario de lo que dice. El clasificador tenía razón y el fixture no.
  # Este caso decía "ligero no ejecuta NADA", y eso resultó ser demasiado: hay
  # tests que validan la documentación real contra el ledger, y un cambio de
  # solo-prosa SÍ los ejecuta. Se demostró rompiéndolo — un commit de docs con
  # tres ids de finding mal citados salió ligero, corrió cero tests y puso la
  # suite en rojo. Lo que se sigue protegiendo, que es lo que importa: que la
  # prosa no pague la SUITE ENTERA, y que el marker declare qué corrió.
  VERIFY_CMD=true bash tools/verify-run.sh >/dev/null 2>&1
  local m=.agents/state/markers/verify_run.txt
  [ -f "$m" ] || { echo "    no firmó nada con un comando que pasa"; return 1; }
  grep -q 'carril: ligero' "$m" 2>/dev/null || {
    echo "    el marker no DECLARA el carril:"
    sed 's/^/      /' "$m" 2>/dev/null
    return 1; }
  grep -q 'tests: todos' "$m" 2>/dev/null && {
    echo "    un cambio de prosa pagó la SUITE ENTERA:"
    grep '^tests:' "$m" | sed 's/^/      /'
    return 1; }
  grep -qE '^tests: .*test_' "$m" 2>/dev/null || {
    echo "    el marker no declara QUÉ tests corrió — un gate que no lo dice es mudo (§14.3):"
    grep '^tests:' "$m" 2>/dev/null | sed 's/^/      /'
    return 1; }
}
test_el_carril_ligero_no_paga_la_suite_entera() { _vm_sandbox _case_ligero_no_corre_la_suite; }

# Y el reverso, que es lo que impide que esto sea un agujero: si el carril NO es
# ligero, el comando se ejecuta y un fallo sigue sin firmarse.
_case_no_ligero_si_ejecuta() {
  _stage_producto 1
  local rc; VERIFY_CMD=false bash tools/verify-run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    con carril no-ligero y comando rojo, verify-run dio $rc (esperaba 1)"
    return 1; }
  [ -f .agents/state/markers/verify_run.txt ] && {
    echo "    FIRMÓ pese a que el comando falló"; return 1; }
  return 0
}
test_fuera_del_carril_ligero_el_comando_si_corre() { _vm_sandbox _case_no_ligero_si_ejecuta; }

# ── Sin clasificador, se corre TODO ─────────────────────────────────
# El default tiene que ser el SEGURO, y este es el mutante más peligroso de los
# cuatro: si al faltar `carril.sh` se asumiera "no hay nada que correr", todo
# cambio se firmaría sin verificar nada — un gate mudo con disfraz de verde,
# que es exactamente lo que §14.3 prohíbe. Un `verify-run` que no sabe qué
# ejecutar no puede decidir ejecutar menos.
_case_sin_clasificador_corre_todo() {
  _stage_producto 1
  local rc; VERIFY_CMD=false bash tools/verify-run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    sin clasificador, verify-run dio $rc (esperaba 1: ejecutó y falló)"
    echo "    Si no ejecuta, firma sin verificar."
    return 1; }
  [ -f .agents/state/markers/verify_run.txt ] && {
    echo "    FIRMÓ sin clasificador y con el comando rojo"; return 1; }
  return 0
}
test_sin_clasificador_se_corre_todo() {
  _VM_SIN_CARRIL=1 _vm_sandbox _case_sin_clasificador_corre_todo
}

# ── Un clasificador que falla NO puede hacer que se corra menos ─────
# Defensa en profundidad del hallazgo del review. `carril.sh` ya no imprime su
# resumen en modo `--tests`, pero el consumidor tampoco puede fiarse: hacía
# `$(carril.sh --tests || echo TODOS)`, y dentro de una sustitución ese `||`
# CONCATENA la salida del fallo con "TODOS" en vez de reemplazarla. El resultado
# caía en la rama de tests dirigidos, filtraba por basura, no casaba nada — y
# `run-tests` sale 0 cuando un filtro no casa. Se firmaba con CERO tests.
_case_clasificador_roto_corre_todo() {
  # El clasificador roto vive FUERA del repo: escribirlo dentro ensuciaría el
  # árbol y `verify-run` lo rechazaría antes de llegar al carril. Se inyecta por
  # `CARRIL_SH`, la misma costura de entorno que usan otros detectores.
  local roto; roto="$(mktemp -d)/carril-roto.sh"
  printf '#!/usr/bin/env bash\necho "BASURA carril=lo-que-sea"\nexit 3\n' > "$roto"
  chmod +x "$roto"
  _stage_producto 1
  # El comando PASA a propósito: con uno que falla, cualquier rama daría exit 1
  # y el test no distinguiría "corrió lo correcto" de "corrió basura". Lo que se
  # afirma es QUÉ se ejecutó, que es lo único que importa aquí.
  CARRIL_SH="$roto" VERIFY_CMD=true bash tools/verify-run.sh >/dev/null 2>&1
  rm -rf "$(dirname "$roto")"
  local m=.agents/state/markers/verify_run.txt
  [ -f "$m" ] || { echo "    no firmó nada con un comando que pasa"; return 1; }
  grep -q 'tests: todos' "$m" || {
    echo "    con el clasificador roto NO se corrió todo:"
    grep -E '^(carril|tests):' "$m" | sed 's/^/      /'
    echo "    No saber qué correr nunca puede traducirse en correr menos."
    return 1; }
  return 0
}
test_un_clasificador_roto_no_reduce_lo_que_se_corre() {
  _vm_sandbox _case_clasificador_roto_corre_todo
}

# ── Y un clasificador que MIENTE en verde tampoco ───────────────────
# El de arriba falla y se nota. Este sale 0 y su salida pasa por nombres de
# test: filtra por algo que no existe, y `run-tests` sale 0 cuando un filtro no
# casa. El saneo de `verify-run` solo lo tapa si exige el prefijo `test_`.
_case_clasificador_mentiroso_corre_todo() {
  local m; m="$(mktemp -d)/carril-mentiroso.sh"
  printf '#!/usr/bin/env bash\necho "basura"\nexit 0\n' > "$m"; chmod +x "$m"
  _stage_producto 1
  CARRIL_SH="$m" VERIFY_CMD=true bash tools/verify-run.sh >/dev/null 2>&1
  rm -rf "$(dirname "$m")"
  local mk=.agents/state/markers/verify_run.txt
  [ -f "$mk" ] || { echo "    no firmó nada con un comando que pasa"; return 1; }
  grep -q 'tests: todos' "$mk" || {
    echo "    se aceptó como lista de tests algo que no lo es:"
    grep -E '^tests:' "$mk" | sed 's/^/      /'; return 1; }
}
test_un_clasificador_que_miente_en_verde_no_reduce_lo_que_se_corre() {
  _vm_sandbox _case_clasificador_mentiroso_corre_todo
}
