#!/usr/bin/env bash
# El bucle lección → detector es lo que hace que la revisión humana DECREZCA.
# Si este gate produce falsos positivos, se desactiva, y el bucle se rompe.

_lessons_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_doc() { printf '%s\n' "$1" > docs/process/lessons_learned.md; }

# ── happy path ──────────────────────────────────────────────────────
_case_con_detector() {
  # El detector citado debe EXISTIR (el verificador ahora lo comprueba).
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '# Lecciones

### [2026-01-01] Secreto de prueba con formato real
- **Qué pasó:** un fixture tenía una API key con formato válido.
- **Regla:** usa formatos obviamente inválidos.
- **Detector:** tools/semgrep/rules/universal.yaml#secreto-hardcodeado
- **Área:** tests/fixtures'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    una lección CON detector fue rechazada"; return 1; }
}
test_leccion_con_detector_pasa() { _lessons_sandbox _case_con_detector; }

# ── ramas de error ──────────────────────────────────────────────────
_case_sin_detector() {
  _doc '# Lecciones

### [2026-01-01] Algo pasó
- **Qué pasó:** cosas.
- **Regla:** no hacerlo otra vez.
- **Área:** src/'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una lección SIN detector fue aceptada"; return 1; }
}
test_leccion_sin_detector_falla() { _lessons_sandbox _case_sin_detector; }

_case_detector_vacio() {
  _doc '# Lecciones

### [2026-01-01] Algo pasó
- **Detector:** manual'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    'Detector: manual' se aceptó como detector real"; return 1; }
}
test_detector_manual_a_secas_no_cuenta() { _lessons_sandbox _case_detector_vacio; }

_case_excepcion_justificada() {
  # Hay lecciones que de verdad no son mecanizables. La excepción es legítima
  # SI es explícita — forzar un detector sobre algo no mecanizable produce ruido.
  _doc '# Lecciones

### [2026-01-01] Elegimos mal el modelo de pricing
- **Detector:** n/a-manual — es una decisión de producto, no un patrón de código'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    la excepción n/a-manual justificada fue rechazada"; return 1; }
}
test_excepcion_na_manual_es_valida() { _lessons_sandbox _case_excepcion_justificada; }

# ── los bordes que matan a un detector por confianza ────────────────
_case_plantilla_en_code_fence() {
  # La plantilla de entrada del doc vive dentro de ``` y NO es una lección.
  # Contarla sería el falso positivo clásico que hace desactivar el gate.
  _doc '# Lecciones

## Plantilla

```
### [AAAA-MM-DD] <título corto>
- **Detector:** <check-drift / reviewer / test>
```
'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó la plantilla del code fence como lección"; return 1; }
}
test_plantilla_en_bloque_de_codigo_no_cuenta() { _lessons_sandbox _case_plantilla_en_code_fence; }

_case_ejemplo_en_comentario_html() {
  _doc '# Lecciones

<!--
### [AAAA-MM-DD] Ejemplo comentado
- Qué pasó: nada, es un ejemplo del template.
-->
'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó un ejemplo en comentario HTML"; return 1; }
}
test_ejemplo_en_comentario_html_no_cuenta() { _lessons_sandbox _case_ejemplo_en_comentario_html; }

_case_encabezado_de_prosa() {
  # El propio doc tiene encabezados `###` explicativos que NO son lecciones.
  # Contarlos fue un falso positivo real (PRD 0001 §18). Una entrada se
  # reconoce por el corchete con fecha: `### [AAAA-MM-DD] …`.
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '# Lecciones

### Cómo usar este doc
El campo Detector es obligatorio.

### [2026-01-01] Un error real
- **Detector:** tools/semgrep/rules/universal.yaml'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó un encabezado de prosa como lección"; return 1; }
}
test_encabezado_de_prosa_no_es_leccion() { _lessons_sandbox _case_encabezado_de_prosa; }

# ── el detector citado tiene que EXISTIR ────────────────────────────
# Validar solo que el campo esté relleno dejaba pasar detectores FANTASMA:
# una lección citó un grep de check-drift que ya había sido eliminado y el
# verificador daba ✅ igual. Prosa que cita un detector muerto es prosa.
_case_detector_fantasma_falla() {
  _doc '# Lecciones

### [2026-01-01] Error con detector que ya no existe
- **Detector:** tools/detector-que-borramos.sh'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un detector citado INEXISTENTE fue aceptado"; return 1; }
}
test_detector_citado_inexistente_falla() { _lessons_sandbox _case_detector_fantasma_falla; }

# FALSO POSITIVO guard: un detector descrito en prosa (sin ruta de archivo)
# sigue valiendo — no todo detector es un archivo (p. ej. "branch protection").
_case_detector_en_prosa_pasa() {
  _doc '# Lecciones

### [2026-01-01] Algo no mecanizable por archivo
- **Detector:** branch protection en GitHub exige el status check ci-gates'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un detector válido descrito en prosa fue rechazado"; return 1; }
}
test_detector_en_prosa_sin_ruta_pasa() { _lessons_sandbox _case_detector_en_prosa_pasa; }

_case_prosa_no_absorbe_la_siguiente() {
  # Un encabezado de prosa no debe "prestar" su detector a la entrada siguiente.
  _doc '# Lecciones

### Notas
- **Detector:** algo

### [2026-01-01] Error sin detector
- **Regla:** no repetirlo'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una entrada sin detector heredó el de un encabezado de prosa"; return 1; }
}
test_prosa_no_presta_su_detector() { _lessons_sandbox _case_prosa_no_absorbe_la_siguiente; }

_case_doc_ausente() {
  rm -f docs/process/lessons_learned.md
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    falló sin doc de lecciones (debe ser no-op)"; return 1; }
}
test_sin_doc_es_noop() { _lessons_sandbox _case_doc_ausente; }

# ════════════════════════════════════════════════════════════════════
# ROTACIÓN — una lección MECANIZADA ya no necesita leerse
# ════════════════════════════════════════════════════════════════════
# El corolario del propio bucle: si el detector es un test que corre en el
# Anillo 3, la regla está garantizada por una máquina y no por la memoria.
# El riesgo del mecanismo es archivar de MÁS (perder la lección de verdad),
# así que estos tests fijan sobre todo lo que NO debe archivarse.
_rot_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/tests" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lessons-rotate.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_rota_la_mecanizada_y_conserva_la_manual() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Con test en la suite
- **Regla:** algo mecánico.
- **Detector:** tools/tests/test_ejemplo.sh::test_x
- **Área:** x

### [2026-01-02] Juicio de producto
- **Regla:** algo opinable.
- **Detector:** n/a-manual — es criterio de diseño
- **Área:** proceso'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q 'Juicio de producto' docs/process/lessons_learned.md \
    || { echo "    la lección n/a-manual fue archivada: su prosa ES el mecanismo"; return 1; }
  grep -q '^### .*Con test en la suite' docs/process/lessons_learned.md \
    && { echo "    la lección mecanizada sigue entera en el doc vivo"; return 1; }
  grep -q 'Con test en la suite' docs/process/lessons_archive.md \
    || { echo "    la lección mecanizada no llegó al archivo"; return 1; }
  return 0
}
test_rotacion_archiva_mecanizadas_y_respeta_manuales() {
  _rot_sandbox _case_rota_la_mecanizada_y_conserva_la_manual
}

_case_deja_indice() {
  # Archivar SIN dejar rastro cambiaría un problema por otro: el agente
  # dejaría de saber que la regla existe y se enteraría al ver fallar un
  # test — una vuelta entera más cara que leer una línea.
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Regla mecanizada
- **Regla:** algo.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q 'Regla mecanizada' docs/process/lessons_learned.md \
    || { echo "    no quedó línea de índice: la señal de que la regla existe se perdió"; return 1; }
}
test_rotacion_deja_indice_de_una_linea() { _rot_sandbox _case_deja_indice; }

_case_keep_visible_manda() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] El owner quiere verla siempre
<!-- KEEP-VISIBLE: duele demasiado como para esconderla -->
- **Regla:** algo.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q '^### .*owner quiere verla' docs/process/lessons_learned.md \
    || { echo "    KEEP-VISIBLE no protegió la lección del archivado"; return 1; }
}
test_keep_visible_veta_el_archivado() { _rot_sandbox _case_keep_visible_manda; }

_case_detector_sin_test_no_se_archiva() {
  # Garantía PARCIAL: un detector que es un script sin test propio no
  # asegura nada por sí solo. Archivar eso sería archivar una promesa.
  printf '#!/usr/bin/env bash\n' > tools/otro.sh
  _doc '# Lecciones

### [2026-01-01] Detector sin test propio
- **Regla:** algo.
- **Detector:** tools/otro.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q '^### .*Detector sin test propio' docs/process/lessons_learned.md \
    || { echo "    se archivó una lección con garantía solo PARCIAL"; return 1; }
}
test_detector_sin_test_en_la_suite_no_se_archiva() {
  _rot_sandbox _case_detector_sin_test_no_se_archiva
}

_case_archivo_sigue_verificado() {
  # Sin esto, rotar sería la forma silenciosa de esquivar el gate de
  # lecciones: el archivo se volvería el sitio donde van a morir.
  mkdir -p docs/process
  printf '# Lecciones\n' > docs/process/lessons_learned.md
  printf '# Archivadas\n\n### [2026-01-01] Detector fantasma\n- **Detector:** tools/tests/test_borrado.sh\n- **Área:** x\n' \
    > docs/process/lessons_archive.md
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una lección ARCHIVADA con detector inexistente pasó el gate"; return 1; }
}
test_lecciones_archivadas_siguen_verificadas() { _rot_sandbox _case_archivo_sigue_verificado; }
