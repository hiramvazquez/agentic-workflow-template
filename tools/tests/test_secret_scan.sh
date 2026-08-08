#!/usr/bin/env bash
# secret-scan: wrapper de gitleaks. Sus dos guards de FALSO POSITIVO son de
# infraestructura: gitleaks ausente no puede trabar el commit en LOCAL (el
# fail-closed vive en CI, ci/run-gates.sh), y un modo inválido debe fallar
# ruidosamente en vez de "pasar por limpio".
# Cierra parte de f-meta-fp-manifiesto.

_ss_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/bin"
  cp "$PROJECT_ROOT/tools/secret-scan.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── FALSO POSITIVO guard: gitleaks ausente → avisa, NO bloquea local ─
_case_sin_gitleaks_no_traba() {
  PATH="/usr/bin:/bin" bash tools/secret-scan.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    sin gitleaks instalado, el commit local quedó trabado"; return 1; }
}
test_gitleaks_ausente_no_traba_en_local() { _ss_sandbox _case_sin_gitleaks_no_traba; }

# ── un modo inválido NO pasa por limpio ─────────────────────────────
_case_modo_invalido_falla() {
  # gitleaks falso para que el guard de instalación no dispare primero:
  printf '#!/usr/bin/env bash\nexit 0\n' > bin/gitleaks; chmod +x bin/gitleaks
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/secret-scan.sh --modo-inventado >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    un modo inválido no falló (¿pasó por limpio?)"; return 1; }
}
test_modo_invalido_falla_ruidoso() { _ss_sandbox _case_modo_invalido_falla; }

# ── la detección propaga: gitleaks encuentra → exit != 0 ────────────
_case_hallazgo_propaga() {
  printf '#!/usr/bin/env bash\necho "leak encontrado" >&2\nexit 1\n' > bin/gitleaks; chmod +x bin/gitleaks
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/secret-scan.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un hallazgo de gitleaks no propagó el fallo"; return 1; }
}
test_hallazgo_de_gitleaks_propaga() { _ss_sandbox _case_hallazgo_propaga; }
