#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-finding-refs.sh — un id de finding citado tiene que EXISTIR
# ════════════════════════════════════════════════════════════════════
# El ledger es el inventario único de hallazgos (§10) y la doc lo cita por id:
# "cerrado en `f-marker-spoof`", "ver `f-range-failopen`". Esa cita es el único
# puente entre la prosa y el estado terminal — y hasta hoy nadie la comprobaba.
#
# Un id fantasma es peor que una cita ausente, y por un motivo concreto: LEE
# COMO CERRADO. Quien encuentra "decidido en `f-xxxxxxx`" no vuelve a abrir el
# tema; da por hecho que hay una entrada con su tier, su razón y su fecha. Si esa
# entrada no existe, el hallazgo se evaporó **con el aspecto de haberse cerrado**,
# que es exactamente el modo de fallo que el ledger existe para impedir. Y se
# produce solo: basta un typo, un id inventado de memoria tras una compactación,
# o renombrar una entrada sin repasar quién la citaba.
#
#   bash tools/check-finding-refs.sh
#
# Contrato de salida:  FINDING_REFS citas=<N> fantasma=<M>
# Exit: 0 todas las citas resuelven · 1 hay ids fantasma · 3 no pude mirar
#
# ── Qué cuenta como CITA (y por qué tan estrecho) ──────────────────
# Solo un span de código en línea: `f-algo`. NO el texto suelto, y NO lo que
# viva dentro de un bloque ``` (ahí están los ejemplos de uso del CLI, con sus
# `f-xxxx` de mentira).
#
# La primera versión de este check buscaba `f-[a-z0-9-]+` en el texto crudo, y
# su primer falso positivo salió —cómo no— contra este mismo repo: casó
# `f-nature` dentro de `check-diff-nature`. La subcadena de un nombre que
# HABLA de otra cosa. Es la cuarta vez que este harness tropieza con la misma
# ley y ya está escrita en `lessons_learned.md`:
#
#   **si un detector puede dispararse con el texto que HABLA de la cosa, no
#     está mirando la cosa.**
#
# Los acentos graves son la marca que el autor pone deliberadamente para decir
# "esto es un identificador". Exigirlos convierte una heurística en una lectura.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  check-finding-refs: python3 ausente — NO he podido mirar." >&2
  echo "FINDING_REFS citas=0 fantasma=0"
  exit 3
fi

if [ ! -f "$LEDGER" ]; then
  # Sin ledger no hay contra qué resolver. Es un 3 (no pude mirar), no un 0:
  # un repo recién adoptado sin ledger no debe leerse como "todas las citas
  # resuelven" — leería como verde justo el caso en que no hay nada que mirar.
  echo "⚠️  check-finding-refs: no existe $LEDGER — nada contra qué resolver." >&2
  echo "FINDING_REFS citas=0 fantasma=0"
  exit 3
fi

CFR_LEDGER="$LEDGER" python3 - <<'PY'
import json, os, re, sys

ledger = os.environ["CFR_LEDGER"]

ids = set()
prosa = []          # (id_del_finding, campo, texto)
malas = 0
with open(ledger, encoding="utf-8") as f:
    for n, linea in enumerate(f, 1):
        linea = linea.strip()
        if not linea:
            continue
        try:
            d = json.loads(linea)
        except json.JSONDecodeError:
            malas += 1
            continue
        if isinstance(d, dict) and d.get("id"):
            ids.add(str(d["id"]))
            # Los campos de texto LIBRE del ledger: es donde los agentes
            # escriben prosa citando otros findings, y hasta hoy no los leia
            # nadie (el render no los vuelca al .md, que es lo unico que se
            # recorria mas abajo).
            # SOLO `source`, y la restriccion es el resultado de medirlo.
            # Ver el bloque largo mas abajo antes de ampliarlo.
            for campo in ("source",):
                v = d.get(campo)
                if isinstance(v, str) and v:
                    prosa.append((str(d["id"]), campo, v))

if malas:
    # Un ledger con líneas rotas haría este check MENTIR hacia el rojo (ids
    # reales que parecen fantasma). Se para y se dice, en vez de acusar.
    print(f"⚠️  check-finding-refs: {malas} línea(s) del ledger no son JSON — arréglalas primero.",
          file=sys.stderr)
    print("FINDING_REFS citas=0 fantasma=0")
    sys.exit(3)

# Un span de código en línea cuyo contenido ENTERO es un id.
CITA = re.compile(r'`(f-[0-9a-z][0-9a-z-]*)`')
# Un placeholder no es un id: `f-xxxx` en un ejemplo de uso no cita nada.
PLACEHOLDER = re.compile(r'^f-[xn?]+$')

def sin_bloques(texto):
    """Quita los bloques ``` — dentro viven los ejemplos del CLI."""
    fuera, dentro = [], False
    for l in texto.splitlines():
        if l.lstrip().startswith("```"):
            dentro = not dentro
            continue
        if not dentro:
            fuera.append(l)
    return "\n".join(fuera)

archivos = []
for raiz, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".build")]
    for fn in files:
        if fn.endswith(".md"):
            archivos.append(os.path.join(raiz, fn).lstrip("./"))
archivos.sort()

total, fantasma = 0, []
for ruta in archivos:
    try:
        with open(ruta, encoding="utf-8") as f:
            cuerpo = sin_bloques(f.read())
    except (OSError, UnicodeDecodeError):
        continue
    for n, linea in enumerate(cuerpo.splitlines(), 1):
        for fid in CITA.findall(linea):
            if PLACEHOLDER.match(fid):
                continue
            total += 1
            if fid not in ids:
                fantasma.append((ruta, fid))

# ── `source` del ledger: SOLO los ids que NO resuelven ──────────────
#
# POR QUE SOLO `source` Y NO TAMBIEN `detail`/`resolution`. Se probo con los
# tres y se midio sobre este ledger (319 citas):
#     detail+source+resolution → 3 reportes, 0 defectos, 100% FP
#     detail+source            → 2 reportes, 0 defectos, 100% FP
#     source                   → 0 reportes, 0 FP
# Los tres falsos positivos eran findings que DOCUMENTAN un incidente de id
# fantasma y por tanto tienen que nombrar el id invalido ("f346baf cita
# 'f-9f39759f', un id que nunca existio"). No es una categoria rara: cada vez
# que este harness convierte una leccion en finding, crea otro. Escanear los
# campos narrativos es reintroducir la ley de la cabecera —«si un detector
# puede dispararse con el texto que HABLA de la cosa, no esta mirando la
# cosa»— en el sitio donde mas prosa sobre findings se escribe.
#
# `source` es distinto por su FUNCION, no por conveniencia: registra la
# PROCEDENCIA ("reviewer del sync 2026-08-27", "auditoria de navegacion"). No
# es donde se discuten otros findings; es donde se dice de donde salio este. Un
# id que no resuelve ahi significa "este hallazgo dice venir del analisis de
# algo que no existe", y eso es un defecto siempre.
#
# LIMITE DECLARADO, no oculto: un id fantasma que viva SOLO en `detail` no se
# caza. Se acepta a sabiendas — la alternativa medida era 100% de FP, y un
# detector ruidoso no se tolera: se desactiva entero, y con el se pierde
# tambien esta deteccion. El incidente que motivo todo esto SI se habria
# cazado: tenia el id inventado en el `source` de f-a3b6dafc.
#
# ── Los ids que NO resuelven ────────────────────────────────────────
# Aqui NO se exigen acentos graves, y la excepcion esta acotada a proposito.
# El backtick existe para distinguir CITAR de HABLAR DE, y esa distincion solo
# importa para ids REALES: mencionar `f-abc123` en prosa es legitimo y
# frecuente. Pero un `f-` que no resuelve contra NADA es un defecto lo
# escribas como cita o como mencion — no hay motivo legitimo para nombrar algo
# que no existe. Por eso reportar solo los fantasma mantiene los falsos
# positivos en ~0 sin tocar la exencion.
#
# La frontera por delante no es opcional: sin ella, `f-nature` casa dentro de
# `check-diff-nature.sh` y el detector vuelve a dispararse con el texto que
# HABLA de un archivo — el fallo que ya mato a check-version-claims.sh.
CITA_PROSA = re.compile(r"(?<![0-9A-Za-z_-])(f-[0-9a-z][0-9a-z-]*)")

# Una ABREVIATURA de un id real no es un fantasma. Los ids con slug
# (`f-wf04-archivos-sobre-el-limite`) se escriben en prosa por su prefijo
# (`f-wf04`), y eso es legitimo y frecuentisimo: medido sobre este ledger, 5 de
# los 9 primeros reportes eran justo eso. Contarlos habria puesto el detector
# al 78% de falsos positivos — el mismo numero con el que murio
# check-version-claims.sh. Se resuelve por prefijo antes de acusar.
def resuelve(fid):
    if fid in ids:
        return True
    return any(real.startswith(fid + "-") for real in ids)

for fid_origen, campo, texto in prosa:
    for fid in sorted(set(CITA_PROSA.findall(texto))):
        if PLACEHOLDER.match(fid):
            continue
        # Se cuenta ANTES de decidir: `citas` es "cuantas referencias mire",
        # no "cuantas estaban bien". Sin esto el resumen podia decir
        # `citas=0 fantasma=1`, que se contradice a si mismo — el contrato de
        # stdout de la cabecera sugiere `fantasma` como subconjunto de `citas`.
        total += 1
        if resuelve(fid):
            continue
        fantasma.append((f"{ledger} ({fid_origen}.{campo})", fid))

print(f"FINDING_REFS citas={total} fantasma={len(fantasma)}")

if fantasma:
    print("")
    print(f"❌ {len(fantasma)} cita(s) a findings que NO existen en {ledger}:")
    for ruta, fid in fantasma:
        print(f"  - {ruta}: `{fid}`")
    print("")
    print("Un id fantasma LEE COMO CERRADO: quien lo encuentra da por hecho que hay")
    print("una entrada con su tier y su razón, y no vuelve a abrir el tema. El")
    print("hallazgo se evaporó con el aspecto de haberse cerrado — justo lo que el")
    print("ledger existe para impedir (AGENTS.md §10).")
    print("")
    print("Arréglalo en el MISMO cambio, de una de las dos formas:")
    print("  · el hallazgo es real  → créalo:")
    print("      bash tools/findings/findings.sh add --title \"...\" --area \"...\" \\")
    print("           --severity high|medium|low --tier auto-fix|owner-decision")
    print("  · la cita está mal     → corrige el id (o quita los acentos graves si")
    print("    de verdad no estabas citando un finding).")
    sys.exit(1)

print(f"✅ check-finding-refs: las {total} citas a findings resuelven contra el ledger.")
PY
