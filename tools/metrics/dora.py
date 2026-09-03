#!/usr/bin/env python3
"""dora.py — las seis métricas de entrega, y las que aquí NO se pueden medir.

PRD 0009 fase 5. Las cuatro DORA más aceptación y retrabajo son la referencia de
2026 porque miden RESULTADOS de entrega y no actividad: son difíciles de inflar
con líneas de código. El estudio de paridad las marcó `3` — "no podemos ni
mirar" — porque no teníamos ninguna, ni serie temporal.

La regla que gobierna este informe la impuso el design-review al verificar el
`git log` real: **0 merges en 149 commits**. Tres de las seis definiciones que
el PRD traía eran inaplicables aquí, y publicar un 0 por ellas habría metido el
cero ambiguo —el que este harness existe para matar— en la fase que lo mide.

  Un 0 dice "medí y salió cero".  `n/a` dice "no hay evento que medir, y este es
  el motivo". No son el mismo dato y no se colapsan.

Contrato de exit (§14.3): 0 informé (aunque haya n/a: un hueco declarado es una
lectura correcta) · 3 no pude ni leer el repo.
"""
from __future__ import annotations

import json
import os
import runpy
import statistics
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

SERIE = Path(".agents/state/metrics/series.jsonl")
ROLLUP = Path("docs/process/metrics-weekly.md")
REVIEWS = Path(".agents/state/review-history.jsonl")
VENTANA = 90


class Metrica:
    """Un valor medido, o un hueco CON su razón. Nunca las dos cosas."""

    def __init__(self, nombre, valor=None, texto=None, razon=None, clave=None):
        self.nombre, self.valor, self.texto = nombre, valor, texto
        self.razon, self.clave = razon, clave or nombre

    def linea(self) -> str:
        derecha = self.texto if self.razon is None else f"n/a — {self.razon}"
        return f"  {self.nombre:<26}{derecha}"


def _git(*args) -> str:
    try:
        r = subprocess.run(("git",) + args, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def _desde(dias: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=dias)).strftime("%Y-%m-%d")


# ── 1. Frecuencia de entrega ────────────────────────────────────────
def frecuencia(dias: int) -> Metrica:
    """En un repo-plantilla, `main` ES el artefacto: el adoptante clona y
    actualiza desde ahí. No hay despliegue aparte que medir, y esperarlo
    dejaría muda una métrica que aquí sí tiene evento."""
    log = _git("log", "--first-parent", "main", f"--since={_desde(dias)}", "--format=%H")
    n = len([x for x in log.splitlines() if x.strip()])
    if not n:
        return Metrica("frecuencia de entrega", razon=f"0 commits en main en {dias} días")
    por_semana = n / (dias / 7.0)
    return Metrica("frecuencia de entrega", por_semana,
                   f"{por_semana:.1f} /semana  ({n} commits en {dias} días)")


# ── 2. Lead time ────────────────────────────────────────────────────
def lead_time(dias: int) -> Metrica:
    """Ventana entre el primer commit de un cambio y su llegada a main. Con
    trabajo directo sobre main esa ventana es CERO POR CONSTRUCCIÓN, y un
    '0.0 h' se leería como entrega instantánea en vez de como ausencia de
    medición. Por eso el hueco se declara en vez de calcularse."""
    merges = [m for m in _git("log", "main", f"--since={_desde(dias)}",
                              "--merges", "--format=%H").splitlines() if m.strip()]
    if not merges:
        total = len([x for x in _git("log", "main", "--format=%H").splitlines() if x.strip()])
        return Metrica("lead time", razon=(
            f"0 merges en {total} commits: el trabajo va directo a main, "
            "así que no hay ventana entre el commit y su llegada"))
    horas = []
    for m in merges:
        fin = _git("show", "-s", "--format=%ct", m)
        rama = [c for c in _git("log", "--format=%ct", f"{m}^1..{m}^2").splitlines() if c.strip()]
        if fin and rama:
            horas.append((int(fin) - int(rama[-1])) / 3600.0)
    if not horas:
        return Metrica("lead time", razon="hay merges pero no pude datar sus ramas")
    med = statistics.median(horas)
    return Metrica("lead time", med, f"{med:.1f} h (mediana de {len(horas)} merges)")


# ── 3. Tasa de fallo del cambio ─────────────────────────────────────
def tasa_fallo() -> Metrica:
    """Se DERIVA de escape-rate, no se recalcula: dos definiciones del mismo
    fenómeno acaban contradiciéndose y nadie sabe cuál mirar.

    Y arrastra su denominador. El escape rate de este repo es 0%, pero sobre
    41 findings clasificados de 247: publicar '0%' a secas sería exactamente el
    cero sin denominador que `detector_runs.py` existe para separar."""
    try:
        r = subprocess.run(["bash", "tools/metrics/escape-rate.sh", "--days", str(VENTANA)],
                           capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return Metrica("tasa de fallo", razon="no pude ejecutar escape-rate.sh")
    if r.returncode != 0:
        return Metrica("tasa de fallo", razon=f"escape-rate.sh salió {r.returncode}")
    pct = clasif = None
    for linea in r.stdout.splitlines():
        if "ESCAPE RATE:" in linea:
            resto = linea.split("ESCAPE RATE:", 1)[1].strip()
            pct = resto.split("%", 1)[0].strip()
            if "/" in resto:
                clasif = resto.split("/", 1)[1].split()[0]
    if pct is None:
        return Metrica("tasa de fallo", razon="escape-rate no imprimió una tasa")
    cola = f" (derivada de escape-rate; denominador: {clasif} findings clasificados)" if clasif else ""
    try:
        # NUMÉRICO, no la cadena parseada. El rollup solo agrega números, así
        # que una métrica MEDIDA pero guardada como texto se cae de la tabla
        # commiteada — y se cae igual que una que no se pudo medir. Guardar el
        # texto dejaba "tasa de fallo" fuera del fichero versionado en silencio.
        valor = float(pct)
    except ValueError:
        return Metrica("tasa de fallo", razon=f"escape-rate imprimió una tasa no numérica ({pct!r})")
    return Metrica("tasa de fallo", valor, f"{pct}%{cola}")


# ── 4. Tiempo de recuperación ───────────────────────────────────────
def recuperacion() -> Metrica:
    """Vive en el estado de CI, que git no conoce: hace falta `gh`. Sin él las
    otras cinco se calculan igual — un adoptante sin `gh` no puede quedarse sin
    informe entero por una métrica."""
    try:
        r = subprocess.run(["gh", "run", "list", "--limit", "100",
                            "--json", "conclusion,updatedAt,name"],
                           capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return Metrica("tiempo de recuperación", razon="`gh` no está instalado")
    except (OSError, subprocess.SubprocessError):
        return Metrica("tiempo de recuperación", razon="`gh` falló al invocarse")
    if r.returncode != 0:
        return Metrica("tiempo de recuperación",
                       razon=f"`gh run list` salió {r.returncode} (¿sin auth o sin remoto?)")
    try:
        corridas = json.loads(r.stdout or "[]")
    except ValueError:
        return Metrica("tiempo de recuperación", razon="`gh` devolvió algo que no es JSON")

    def _ts(v):
        try:
            return datetime.fromisoformat(str(v).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None

    # El pareo es POR WORKFLOW. Sobre la lista mezclada, el verde de un pipeline
    # cerraba el rojo de otro y publicaba ese intervalo como una recuperación
    # que nunca ocurrió: con el `gh run list` real de este repo salía un rojo de
    # `gate-0a-macos` "recuperado" por un verde de `harness-ci` casi 27 h
    # después. Lo cazó el review, y el número contaminado ya estaba commiteado.
    por_wf: dict[str, list] = {}
    vistos = 0
    for c in corridas:
        cuando = _ts(c.get("updatedAt"))
        if cuando is None:
            continue
        vistos += 1
        por_wf.setdefault(str(c.get("name") or "?"), []).append((cuando, c.get("conclusion")))

    horas = []
    for corridas_wf in por_wf.values():
        roto = None
        for cuando, resultado in sorted(corridas_wf, key=lambda par: par[0]):
            # `conclusion` nulo (en curso) y `cancelled` no son ninguna de las
            # dos cosas: ni rompen ni recuperan. Dejarlos cerrar un rojo
            # inventaría una recuperación; dejarlos abrirlo, una rotura.
            if resultado == "failure" and roto is None:
                roto = cuando
            elif resultado == "success" and roto is not None:
                horas.append((cuando - roto).total_seconds() / 3600.0)
                roto = None
    if not horas:
        return Metrica("tiempo de recuperación",
                       razon=f"ninguna corrida roja recuperada en las últimas {vistos}")
    med = statistics.median(horas)
    return Metrica("tiempo de recuperación", med, f"{med:.1f} h (mediana de {len(horas)})")


# ── 5. Tasa de aceptación ───────────────────────────────────────────
def aceptacion() -> Metrica:
    """'Verde a la primera' es propiedad de la UNIDAD de trabajo, no del número
    de veredictos: contar filas premiaría al que revisa más veces. Se agrupa por
    `staged_sha` y cuenta el PRIMER veredicto de cada unidad.

    Umbral contraintuitivo de la industria: sano es 25-45%, y por ENCIMA de 45%
    se lee como aceptación acrítica, no como calidad."""
    if not REVIEWS.exists():
        return Metrica("tasa de aceptación", razon="aún no hay review-history.jsonl")
    api = runpy.run_path(str(Path(__file__).with_name("read-events.py")))
    primero: dict[str, str] = {}
    try:
        for ev in api["read"](REVIEWS):
            sha = str(ev.get("staged_sha") or "").strip()
            veredicto = str(ev.get("verdict") or "").strip().upper()
            if sha and veredicto and sha not in primero:
                primero[sha] = veredicto
    except (ValueError, OSError) as e:
        return Metrica("tasa de aceptación", razon=f"review-history ilegible ({e})")
    if not primero:
        return Metrica("tasa de aceptación", razon="review-history no tiene veredictos con staged_sha")
    verdes = sum(1 for v in primero.values() if v == "GREEN")
    pct = 100.0 * verdes / len(primero)
    aviso = ""
    if pct > 45:
        aviso = "  ⚠️ >45%: la industria lo lee como aceptación acrítica"
    elif pct < 25:
        aviso = "  ⚠️ <25%: por debajo del rango sano"
    return Metrica("tasa de aceptación", pct,
                   f"{pct:.0f}% ({verdes}/{len(primero)} unidades verdes a la primera){aviso}")


# ── 6. Tasa de retrabajo ────────────────────────────────────────────
def retrabajo() -> Metrica:
    """Captura lo que la tasa de fallo no ve: los defectos pequeños que SÍ
    pasaron la revisión. Necesita ligar un finding con el cambio que lo
    introdujo, y el campo `area` del ledger es texto libre —'tools/upgrade.sh +
    8 tests', 'gobierno del harness'—: no hay join posible sin inventarlo."""
    return Metrica("tasa de retrabajo", razon=(
        "el campo `area` del ledger es texto libre; no hay forma de ligar un "
        "finding con el commit que lo introdujo sin inventar el vínculo"))


def _recoger(dias: int) -> list[Metrica]:
    return [frecuencia(dias), lead_time(dias), tasa_fallo(),
            recuperacion(), aceptacion(), retrabajo()]


def informar(dias: int) -> int:
    metricas = _recoger(dias)
    print(f"━━━ entrega · ventana {dias} días ━━━")
    for m in metricas:
        print(m.linea())

    fila = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "kind": "dora", "dias": dias,
            # Sin sort_keys: el ORDEN de esta dict es el orden de las columnas
            # del rollup, que las deriva de aquí en vez de repetirlas a mano.
            "metricas": {m.clave: (m.valor if m.razon is None else None) for m in metricas},
            "sin_medir": [m.clave for m in metricas if m.razon is not None]}
    try:
        SERIE.parent.mkdir(parents=True, exist_ok=True)
        with SERIE.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(fila, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"⚠️  no pude apendar a {SERIE}: {e}", file=sys.stderr)

    huecos = [m for m in metricas if m.razon is not None]
    if huecos:
        print("")
        print(f"  ℹ️  {len(huecos)} de 6 sin evento que medir en este repo. Un hueco")
        print("      declarado es una lectura correcta; un 0 en su lugar, no.")
    return 0


# ── El rollup semanal, que es lo que se commitea ────────────────────
def rollup() -> int:
    """La decisión del owner (OQ-2): el crudo se queda local y volátil, el
    resumen semanal se commitea. Y por eso es IDEMPOTENTE y no lleva fecha de
    generación: un fichero versionado que cambia en cada corrida llena el diff
    de ruido, y un diff ruidoso se deja de leer."""
    if not SERIE.exists():
        print(f"⚠️  dora --rollup: no hay serie que resumir ({SERIE}).", file=sys.stderr)
        return 3
    api = runpy.run_path(str(Path(__file__).with_name("read-events.py")))
    semanas: dict[str, dict[str, list[float]]] = {}
    try:
        for ev in api["read"](SERIE):
            if ev.get("kind") != "dora":
                continue
            try:
                cuando = datetime.fromisoformat(str(ev.get("ts", "")).replace("Z", "+00:00"))
            except ValueError:
                continue
            iso = cuando.isocalendar()
            sem = semanas.setdefault(f"{iso[0]}-W{iso[1]:02d}", {})
            for k, v in (ev.get("metricas") or {}).items():
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    sem.setdefault(k, []).append(float(v))
    except (ValueError, OSError) as e:
        print(f"⚠️  dora --rollup: serie ilegible — {e}", file=sys.stderr)
        return 3
    if not semanas:
        print("⚠️  dora --rollup: la serie no tiene ni una fila legible.", file=sys.stderr)
        return 3

    # Las columnas SALEN DE LOS DATOS, en orden de primera aparición. Escribir
    # aquí la lista de nombres a mano creaba un drift silencioso de los caros:
    # renombrar una métrica no rompía nada, solo dejaba su columna en `n/a`
    # para siempre — un hueco que parece un hueco legítimo.
    columnas: list[str] = []
    for sem in sorted(semanas):
        for c in semanas[sem]:
            if c not in columnas:
                columnas.append(c)
    if not columnas:
        print("⚠️  dora --rollup: la serie no trae ni una métrica con valor.", file=sys.stderr)
        return 3
    lineas = ["# Métricas de entrega — resumen semanal", "",
              "> Lo genera `bash tools/metrics/dora.sh --rollup` a partir de",
              "> `.agents/state/metrics/series.jsonl`. **No se edita a mano.**",
              "> El crudo es local y volátil; esto es lo que se versiona, así que",
              "> es idempotente a propósito: sin fecha de generación, para que el",
              "> diff solo cambie cuando cambian los datos.", "",
              "> `n/a` = no hay evento que medir en este repo, y la razón está en la",
              "> salida de `dora.sh`. No es lo mismo que 0.", "",
              "| semana | " + " | ".join(columnas) + " |",
              "|---|" + "---|" * len(columnas)]
    for sem in sorted(semanas):
        celdas = []
        for c in columnas:
            vals = semanas[sem].get(c)
            celdas.append(f"{statistics.mean(vals):.1f}" if vals else "n/a")
        lineas.append(f"| {sem} | " + " | ".join(celdas) + " |")

    try:
        ROLLUP.parent.mkdir(parents=True, exist_ok=True)
        ROLLUP.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    except OSError as e:
        print(f"⚠️  dora --rollup: no pude escribir {ROLLUP} — {e}", file=sys.stderr)
        return 3
    print(f"✅ rollup: {len(semanas)} semana(s) en {ROLLUP}")
    return 0


def main(argv: list[str]) -> int:
    if "--rollup" in argv:
        return rollup()
    dias = VENTANA
    if "--days" in argv:
        try:
            dias = max(1, int(argv[argv.index("--days") + 1]))
        except (IndexError, ValueError):
            print("⚠️  --days necesita un entero positivo.", file=sys.stderr)
            return 3
    return informar(dias)


if __name__ == "__main__":
    os.environ.setdefault("GIT_OPTIONAL_LOCKS", "0")
    raise SystemExit(main(sys.argv[1:]))
