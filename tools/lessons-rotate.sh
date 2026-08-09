#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# lessons-rotate.sh — una lección MECANIZADA ya no necesita leerse
# ════════════════════════════════════════════════════════════════════
# EL COROLARIO QUE FALTABA. El harness afirma: "error cometido → lección →
# detector → error mecánicamente imposible". Si eso es cierto, entonces una
# lección cuyo detector está VERIFICADO EN CI ya no depende de que nadie la
# recuerde: su cumplimiento está garantizado por una máquina. Seguir
# obligando a leerla es cobrar dos veces por el mismo seguro.
#
# El problema que resuelve es real y crece solo: `lessons_learned.md` no
# tiene mecanismo de caducidad, así que crece monótonamente y CADA proyecto
# nacido del template hereda el archivo entero. Cada sesión de cada agente
# paga ese peaje de contexto — y el propio AGENTS.md advierte contra el
# monolito mientras este archivo camina hacia serlo.
#
# CRITERIO DE ARCHIVO (deliberadamente conservador — archivar de más sería
# perder la lección de verdad):
#   ARCHIVABLE  · su `Detector:` cita al menos un `tools/tests/test_*.sh`
#                 que EXISTE. Esa suite corre entera en el Anillo 3, así que
#                 la regla está mecánicamente garantizada, no recordada.
#   SE QUEDA    · `n/a-manual` (juicio no mecanizable: la prosa ES el
#                 mecanismo) · detector que solo cita docs o un script sin
#                 test propio (garantía parcial) · lección marcada a mano
#                 con `<!-- KEEP-VISIBLE: razón -->` (veto del owner).
#
# Nada se borra JAMÁS: se mueve a `docs/process/lessons_archive.md`, que
# sigue versionado, sigue siendo grep-able y sigue verificado por
# `lesson-detector-link.sh`. Lo que cambia es qué se lee por defecto.
#
#   bash tools/lessons-rotate.sh            # informe: qué archivarías y por qué
#   bash tools/lessons-rotate.sh --apply    # mueve las ARCHIVABLE al archivo
#
# Contrato de stdout:  ROTATE_SUMMARY vivas=<N> archivables=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

DOC="${LESSONS_DOC:-docs/process/lessons_learned.md}"
ARCHIVE="${LESSONS_ARCHIVE:-docs/process/lessons_archive.md}"
MODE="${1:---report}"
[ -f "$DOC" ] || { echo "ROTATE_SUMMARY vivas=0 archivables=0"; exit 0; }

python3 - "$DOC" "$ARCHIVE" "$MODE" <<'PY'
import os, re, sys

doc, archive, mode = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(doc, encoding="utf-8").read()

# El cuerpo del doc empieza donde empieza la primera entrada real; todo lo de
# antes (cómo usar, plantilla) es cabecera y NO se toca nunca.
entries, head = [], raw
m = re.search(r"^### \[\d{4}-\d{2}-\d{2}\]", raw, re.M)
if m:
    head, body = raw[:m.start()], raw[m.start():]
    # Separador `---` entre entradas: se parte por el encabezado y se
    # reconstruye, para no depender de que el separador exista siempre.
    parts = re.split(r"(?m)^(?=### \[\d{4}-\d{2}-\d{2}\])", body)
    entries = [p for p in parts if p.strip()]

def classify(text):
    title = text.splitlines()[0].strip().lstrip("# ").strip()
    if "KEEP-VISIBLE" in text:
        return "viva", title, "veto explícito del owner (KEEP-VISIBLE)"
    det = ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("- **Detector:**"):
            det = s
        elif det and s.startswith(("- **", "###", "---")):
            break
        elif det:
            det += " " + s
    if not det:
        return "viva", title, "sin línea Detector (lesson-detector-link ya lo bloquea)"
    if "n/a-manual" in det:
        return "viva", title, "n/a-manual: la prosa ES el mecanismo"
    tests = [t for t in re.findall(r"tools/tests/test_[A-Za-z0-9_]+\.sh", det)
             if os.path.isfile(t)]
    if tests:
        return "archivable", title, f"garantizada por {tests[0]} (corre en el Anillo 3)"
    return "viva", title, "detector sin test propio en la suite: garantía PARCIAL"

vivas, archivables = [], []
for e in entries:
    kind, title, why = classify(e)
    (archivables if kind == "archivable" else vivas).append((title, why, e))

print(f"ROTATE_SUMMARY vivas={len(vivas)} archivables={len(archivables)}")

if mode != "--apply":
    print()
    print(f"━━━ Rotación de lecciones ({len(entries)} entradas) ━━━")
    print()
    print(f"ARCHIVABLES ({len(archivables)}) — su detector es un test que corre en CI:")
    for t, w, _ in archivables:
        print(f"  · {t}\n      {w}")
    if not archivables:
        print("  (ninguna todavía)")
    print()
    print(f"SE QUEDAN VIVAS ({len(vivas)}) — su cumplimiento aún depende de leerlas:")
    for t, w, _ in vivas:
        print(f"  · {t}\n      {w}")
    print()
    print("Aplica con:  bash tools/lessons-rotate.sh --apply")
    print("Nada se borra: se mueve a", archive, "(versionado y verificado igual).")
    sys.exit(0)

if not archivables:
    print("Nada que archivar todavía.")
    sys.exit(0)

AHEAD = """# Lecciones archivadas — mecanizadas, ya no hace falta leerlas

> **Por qué existe este archivo.** Cada lección de aquí tiene un detector que es un
> test de `tools/tests/` y que corre en el Anillo 3. Su cumplimiento NO depende de que
> nadie la recuerde: está garantizado por una máquina. Mantenerlas en el documento vivo
> cobraba dos veces el mismo seguro — en contexto del agente, en cada sesión.
>
> Siguen versionadas, siguen siendo grep-ables y `lesson-detector-link.sh` las sigue
> verificando. Si alguna vez borras su detector, **devuélvela al documento vivo**: sin
> el test, la regla vuelve a depender de la memoria.
>
> Generado/actualizado por `tools/lessons-rotate.sh --apply`.

"""

prev = ""
if os.path.isfile(archive):
    prev = open(archive, encoding="utf-8").read()
    if prev.startswith("# Lecciones archivadas"):
        i = prev.find("\n### [")
        prev = prev[i + 1:] if i != -1 else ""

with open(archive, "w", encoding="utf-8") as f:
    f.write(AHEAD)
    if prev.strip():
        f.write(prev if prev.endswith("\n") else prev + "\n")
    for t, w, e in archivables:
        f.write(e if e.endswith("\n") else e + "\n")

# El doc vivo NO pierde la señal, solo el volumen: cada lección archivada deja
# una línea de índice. Archivarlas del todo cambiaría un problema por otro —
# el agente dejaría de saber siquiera que la regla EXISTE, y se enteraría solo
# al ver fallar un test (una vuelta entera más cara que leer una línea).
# ~10 líneas de prosa por lección pasan a 1: el 90% del ahorro, con el 100%
# de la discoverability.
INDEX_HEAD = """
---

## Lecciones mecanizadas (índice)

> Estas ya NO dependen de tu memoria: cada una tiene un test en `tools/tests/` que corre en el
> Anillo 3, así que violarlas hace fallar la suite. Se listan para que sepas que existen; el
> relato completo (síntoma, causa raíz, racional) vive en `docs/process/lessons_archive.md`.
> Si necesitas el detalle de una, búscala ahí — no la reescribas.

"""

def index_line(title, why):
    det = why.replace("garantizada por ", "").replace(" (corre en el Anillo 3)", "")
    return f"- {title} — `{det}`\n"

with open(doc, "w", encoding="utf-8") as f:
    f.write(head)
    for t, w, e in vivas:
        f.write(e if e.endswith("\n") else e + "\n")
    f.write(INDEX_HEAD)
    for t, w, _ in archivables:
        f.write(index_line(t, w))

print(f"✅ {len(archivables)} lección(es) movidas a {archive}. Quedan {len(vivas)} vivas.")
for t, _, _ in archivables:
    print(f"   · {t}")
print("   Commitea AMBOS archivos en el mismo cambio.")
PY
