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
  _doc '# Lecciones

### Cómo usar este doc
El campo Detector es obligatorio.

### [2026-01-01] Un error real
- **Detector:** tools/semgrep/rules/universal.yaml'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó un encabezado de prosa como lección"; return 1; }
}
test_encabezado_de_prosa_no_es_leccion() { _lessons_sandbox _case_encabezado_de_prosa; }

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
