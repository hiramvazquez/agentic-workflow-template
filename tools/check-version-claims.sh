#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-version-claims.sh — el gestor de paquetes NO es la fuente
# ════════════════════════════════════════════════════════════════════
# Caso real, y caro: el nivel 4 (mutation score) llevaba semanas declarado
# "no disponible" porque `muter 16` —la versión que sirve Homebrew— no parsea
# los typed throws de Swift 6. La conclusión escrita en el ledger fue "no hay
# upgrade posible". Al mirar el repositorio, `main` tenía el arreglo desde
# 2026-07: el proyecto llevaba meses desarrollando **sin publicar un release**.
# El gate no estaba bloqueado por una limitación de la herramienta; estaba
# bloqueado por una limitación del canal por el que se preguntó.
#
#   **`brew`/`apt`/`npm` responden "cuál es el último RELEASE", no "qué
#     soporta el proyecto". Son preguntas distintas y la respuesta diverge
#     durante meses. Antes de declarar un gate no disponible por versión,
#     mira el repositorio.**
#
# Y el daño de equivocarse aquí es asimétrico: una capa entera de la pirámide
# se declara imposible, se documenta como tal, y nadie vuelve a intentarlo —
# la conclusión negativa se auto-preserva porque desalienta justo la
# comprobación que la refutaría. Es la clase de error que no se cae solo.
#
#   bash tools/check-version-claims.sh
#
# Contrato de salida:  VERSION_CLAIMS afirmaciones=<N> sin_repo=<M>
# Exit: 0 limpio · 1 hay una afirmación sin procedencia · 3 no pude mirar
#
# ── Alcance: SOLO el ledger, y esto no es pereza ───────────────────
# Este check NO mira `lessons_learned.md`. La lección que explica esta regla
# contiene, necesariamente, las palabras "brew", "no hay versión" y "muter 16":
# un detector que la escaneara se dispararía contra el texto que HABLA de la
# cosa en vez de contra la cosa — el falso positivo que este harness ya ha
# pisado cuatro veces y que tiene su propia entrada en las lecciones.
# En el ledger, en cambio, una afirmación de versión no es prosa: es la
# EVIDENCIA con la que se cerró (o se dejó abierto) un hallazgo. Ahí sí se
# exige que la evidencia diga de dónde salió.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  check-version-claims: python3 ausente — NO he podido mirar." >&2
  echo "VERSION_CLAIMS afirmaciones=0 sin_repo=0"
  exit 3
fi
if [ ! -f "$LEDGER" ]; then
  echo "⚠️  check-version-claims: no existe $LEDGER — nada que mirar." >&2
  echo "VERSION_CLAIMS afirmaciones=0 sin_repo=0"
  exit 3
fi

CVC_LEDGER="$LEDGER" python3 - <<'PY'
import json, os, re, sys

ledger = os.environ["CVC_LEDGER"]

# ── Qué DISPARA ────────────────────────────────────────────────────
# Una afirmación de NO-EXISTENCIA sobre la versión de una herramienta. El
# matiz es el que hace este detector usable:
#
#   · "jq 1.6 se comporta así"            → observación. Se verifica CORRIENDO
#                                            jq. No dispara, y no debe.
#   · "muter 16 no parsea typed throws"   → afirmación de no-existencia. NO se
#                                            puede verificar con la copia que
#                                            tienes: exige mirar la fuente.
#
# Sin esa distinción el check saltaría con cada número de versión del ledger
# (medido: 2 de 38 entradas disparan; con la regla ingenua, muchas más) y
# moriría por la ley del 10% en su primera semana.
_TOOL_VER = r'[A-Za-z][A-Za-z0-9_.+@/-]{1,24}[ ]+v?\d+(?:\.\d+)*'
_NO_PUEDE = (r'no[ ]+(?:lo[ ]+)?(?:soporta|parsea|entiende|admite|implementa|'
             r'trae|tiene|cubre)|no[ ]+est[aá][ ]+disponible|'
             r'no[ ]+(?:es|resulta)[ ]+compatible')
DISPARA = [
    # <herramienta> <versión> … <no puede X>   (la afirmación y su sujeto, en
    # la misma oración: el corte en [.;|] impide cruzar de frase y atribuir
    # una negación a un número que estaba tres frases más arriba)
    re.compile(rf'{_TOOL_VER}[^.;|]{{0,90}}?(?:{_NO_PUEDE})', re.I),
    # "no hay / no existe versión|release|upgrade que…"  (aquí ni siquiera hay
    # número: es la conclusión negativa en su forma más pura)
    re.compile(r'no[ ]+(?:hay|existe|queda)[ ]+(?:ning[uú]n[ao]?[ ]+)?'
               r'(?:versi[oó]n|release|upgrade|actualizaci[oó]n)', re.I),
]

# ── Qué SATISFACE ──────────────────────────────────────────────────
# La procedencia: el repositorio, no el escaparate del gestor de paquetes.
REPO = re.compile(r'github\.com|gitlab\.com|codeberg\.org|bitbucket\.org|'
                  r'\bsr\.ht|git[ ]+ls-remote|git[ ]+log[ ]+upstream', re.I)
# Excepción explícita, con la misma forma que la de las lecciones (`n/a-manual`):
# hay herramientas sin repositorio público, y forzar una URL inventada sería
# peor que no pedir nada. Se DECLARA, para que no se confunda con un olvido.
EXCEPCION = re.compile(r'n/a-repo\b', re.I)

# El gestor de paquetes se nombra solo para poder decir, en el mensaje, qué
# fue lo que se consultó. Nunca satisface por sí mismo: ese es el punto.
GESTOR = re.compile(r'\b(brew|homebrew|apt|apt-get|apt-cache|npm|pnpm|yarn|'
                    r'pip3?|gem|port|choco|winget|mise|asdf|nix|dnf|yum|'
                    r'pacman|scoop)\b', re.I)

CAMPOS = ("title", "detail", "source", "resolution")

afirmaciones, sin_repo, malas = 0, [], 0
with open(ledger, encoding="utf-8") as f:
    for linea in f:
        linea = linea.strip()
        if not linea:
            continue
        try:
            d = json.loads(linea)
        except json.JSONDecodeError:
            malas += 1
            continue
        if not isinstance(d, dict):
            continue
        texto = " | ".join(str(d.get(k) or "") for k in CAMPOS)
        disparo = next((r.search(texto) for r in DISPARA if r.search(texto)), None)
        if not disparo:
            continue
        afirmaciones += 1
        if REPO.search(texto) or EXCEPCION.search(texto):
            continue
        sin_repo.append((d.get("id", "?"), disparo.group(0).strip(),
                         bool(GESTOR.search(texto))))

if malas:
    print(f"⚠️  check-version-claims: {malas} línea(s) del ledger no son JSON.",
          file=sys.stderr)
    print("VERSION_CLAIMS afirmaciones=0 sin_repo=0")
    sys.exit(3)

print(f"VERSION_CLAIMS afirmaciones={afirmaciones} sin_repo={len(sin_repo)}")

if sin_repo:
    print("")
    print(f"❌ {len(sin_repo)} hallazgo(s) declaran una herramienta incapaz por versión")
    print("   SIN citar de dónde salió esa versión:")
    for fid, frase, hay_gestor in sin_repo:
        print(f"  - {fid}: \"{frase}\"")
        if hay_gestor:
            print("      (el hallazgo cita un gestor de paquetes — y eso es")
            print("       exactamente lo que no basta: ver abajo)")
    print("")
    print("`brew`/`apt`/`npm` contestan \"cuál es el último RELEASE\". Tú preguntaste")
    print("\"qué soporta el proyecto\". Son preguntas distintas, y la respuesta puede")
    print("llevar MESES divergiendo: un proyecto vivo puede pasar un año sin publicar.")
    print("Pasó aquí — el nivel 4 se dio por imposible con el arreglo ya en `main`.")
    print("")
    print("Antes de cerrar el hallazgo, mira la fuente y cítala:")
    print("  git ls-remote --tags https://github.com/<org>/<repo>")
    print("  ...o el issue/commit concreto que confirma (o refuta) la limitación.")
    print("")
    print("Si la herramienta no tiene repositorio público, decláralo — igual que")
    print("`n/a-manual` en las lecciones, para que no parezca un olvido:")
    print("  --resolution \"... n/a-repo — <por qué no hay fuente que mirar>\"")
    sys.exit(1)

print(f"✅ check-version-claims: las {afirmaciones} afirmaciones de versión citan su fuente.")
PY
