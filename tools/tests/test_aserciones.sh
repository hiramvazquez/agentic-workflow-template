#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Las ASERCIONES del propio runner, probadas directamente
# ════════════════════════════════════════════════════════════════════
# `assert_detector_limpio` distingue exit 3 ("no pude mirar", el fail-closed de
# AGENTS.md §14.3) de exit 1 (violación real). Esa distinción es el motivo
# entero por el que existe: confundirlas costó veinte minutos de diagnóstico el
# día que el Anillo 3 revivió y la suite corría sin semgrep — 10 tests gritaban
# "FALSO POSITIVO" sobre un exit 3.
#
# Y sin este archivo esa rama NO SE PROBABA. El reviewer lo demostró con un
# mutante: sustituir el cuerpo entero de la aserción por `return 0` dejaba los
# 26 tests de source-sets en VERDE, porque en un entorno con las herramientas
# instaladas `rc` siempre vale 0 y la rama de fallo nunca se ejercita. Los
# cuatro call-sites la usan; ninguno la probaba.
#
# Aquí se la invoca directamente con cada rc, que es la única forma de
# ejercitarla sin depender de qué haya instalado en la máquina.

_ad_captura() { # _ad_captura <rc> → imprime la salida, devuelve el rc de la aserción
  assert_detector_limpio "$1" "salida-del-detector" "el mensaje de falso positivo" 2>&1
}

# ── rc=0: limpio. Aprueba y NO dice nada ────────────────────────────
test_assert_detector_limpio_aprueba_solo_el_cero() {
  local out rc
  out="$(_ad_captura 0)"; rc=$?
  [ "$rc" = "0" ] || { echo "    rc=0 debería aprobar y devolvió $rc"; return 1; }
  [ -z "$out" ] || { echo "    rc=0 aprobó pero imprimió ruido: [$out]"; return 1; }
}

# ── rc=3: "no pude mirar". Falla, y dice la causa CORRECTA ──────────
test_assert_detector_limpio_llama_al_exit_3_por_su_nombre() {
  local out rc
  out="$(_ad_captura 3)"; rc=$?
  [ "$rc" = "1" ] || { echo "    rc=3 debería fallar el test y devolvió $rc"; return 1; }
  case "$out" in *"NO PUDO MIRAR"*) ;; *) echo "    rc=3 no se identificó como 'no pude mirar': [$out]"; return 1 ;; esac
  case "$out" in *"FALSO POSITIVO"*) echo "    rc=3 se etiquetó como FALSO POSITIVO — es justo la confusión que esta aserción existe para impedir"; return 1 ;; esac
}

# ── rc=1: violación real. Falla, y dice el mensaje del llamador ─────
test_assert_detector_limpio_llama_al_exit_1_falso_positivo() {
  local out rc
  out="$(_ad_captura 1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    rc=1 debería fallar el test y devolvió $rc"; return 1; }
  case "$out" in *"FALSO POSITIVO"*) ;; *) echo "    rc=1 no se etiquetó como falso positivo: [$out]"; return 1 ;; esac
  case "$out" in *"el mensaje de falso positivo"*) ;; *) echo "    el mensaje del llamador se perdió: [$out]"; return 1 ;; esac
  case "$out" in *"NO PUDO MIRAR"*) echo "    rc=1 se confundió con 'no pude mirar': [$out]"; return 1 ;; esac
}

# ── Y la salida del detector se propaga siempre que falla ───────────
# Sin esto, quien lee el rojo no ve QUÉ dijo el detector y tiene que
# reproducirlo a mano — que fue exactamente el coste del incidente original.
test_assert_detector_limpio_propaga_la_salida_del_detector() {
  local out
  out="$(_ad_captura 3)"
  case "$out" in *"salida-del-detector"*) ;; *) echo "    la salida del detector no llegó al informe: [$out]"; return 1 ;; esac
  out="$(_ad_captura 1)"
  case "$out" in *"salida-del-detector"*) ;; *) echo "    la salida del detector no llegó al informe: [$out]"; return 1 ;; esac
}
