#!/usr/bin/env python3
"""detector_runs.py — el DENOMINADOR: qué miró cada detector, y qué no.

PRD 0008 fase 1. Los siete detectores escriben `.agents/state/metrics/runs.jsonl`
desde el 2026-09-02 con `targets` y `exit` por ejecución, y hasta ahora no lo
leía nadie — "detectar no basta, CERRAR" (§1.1) incumplido por el propio harness.

Sin denominador, "cero detecciones" significa tres cosas que ningún dato separa:

  · DISUASIÓN      corrió, miró objetivos reales, no halló nada. Es un éxito.
  · SIN OBJETIVOS  corrió sin nada que mirar. Su `errors=0` alimenta un trinquete
                   que SOLO BAJA, así que una medición falsa fija el suelo en
                   cero de forma permanente (f-6b761f06).
  · NO CORRIÓ      nadie lo invocó.

Este informe separa las tres. Lo que NO hace, y está declarado en el PRD: la
columna de "disparos" no sale de un JOIN con `detections.jsonl`, porque hoy los
vocabularios de `source` son disjuntos — ese log solo lo escriben los hooks
(`reviewer`, `reviewer-gate`, `run-tests`…), nunca un detector. La línea se
DERIVA contando, y enseña el conteo: si un día un detector emite su primera
detección, el informe deja de decir n/a por sí solo. Escribir "n/a" a mano lo
dejaría mintiendo para siempre.

Contrato de exit (§14.3):  0 leí · 3 NO PUDE MIRAR (log ausente o corrupto).
Nunca 0 con la tabla en ceros: eso sería un gate mudo con disfraz de verde.
"""
from __future__ import annotations

import runpy
import sys
from pathlib import Path

RUNS_POR_DEFECTO = Path(".agents/state/metrics/runs.jsonl")
DETECCIONES = Path(".agents/state/metrics/detections.jsonl")


def _lector():
    """El parser de JSONL se REUSA, no se reescribe.

    `read-events.py` ya normaliza líneas y —lo que aquí importa— **lanza**
    ante una línea inválida en vez de saltársela. Eso es justo lo que convierte
    un log corrupto en exit 3 y no en una tabla de ceros.
    """
    api = runpy.run_path(str(Path(__file__).with_name("read-events.py")))
    return api["read"]


def _entero(valor):
    return valor if isinstance(valor, int) and not isinstance(valor, bool) else None


def _p95(valores: list[int]) -> int:
    if not valores:
        return 0
    ordenados = sorted(valores)
    idx = max(0, round(0.95 * len(ordenados)) - 1)
    return ordenados[min(idx, len(ordenados) - 1)]


def main(argv: list[str]) -> int:
    runs = Path(argv[0]) if argv else RUNS_POR_DEFECTO

    if not runs.exists():
        print(f"⚠️  detector-runs: NO PUDE MIRAR — {runs} no existe.", file=sys.stderr)
        print("   Ningún detector ha registrado una ejecución todavía, o el log", file=sys.stderr)
        print("   se borró. Un informe con la tabla en ceros aquí diría 'los gates", file=sys.stderr)
        print("   están limpios', que es lo contrario de lo que pasa (§14.3).", file=sys.stderr)
        return 3

    leer = _lector()
    por_detector: dict[str, dict] = {}
    try:
        for evento in leer(runs):
            if evento.get("kind") != "run":
                continue
            nombre = str(evento.get("source") or "?")
            d = por_detector.setdefault(
                nombre, {"corridas": 0, "objetivos": None, "sin_declarar": 0, "fallos": 0, "dur": []}
            )
            d["corridas"] += 1
            objetivos = _entero(evento.get("targets"))
            if objetivos is None:
                # `null` es "no lo declaró", que NO es "declaró que miró cero".
                # Colapsarlos reintroduce la ambigüedad que el campo elimina.
                d["sin_declarar"] += 1
            else:
                # MAX, no el ÚLTIMO ni la suma. La pregunta que este informe
                # responde es "¿tuvo alguna vez algo que mirar?", que es la que
                # decide keep/tune/retire: un detector que miró 145 una vez no
                # es candidato a retirarse aunque las otras 79 corridas fueran
                # sobre un árbol vacío. Y no es teórico — semgrep-scan declara
                # [10, 5, 5, 2, 5, 10, 7] en el log real de este repo, así que
                # MAX y "último" dan 10 y 7: números distintos.
                d["objetivos"] = objetivos if d["objetivos"] is None else max(d["objetivos"], objetivos)
            if _entero(evento.get("exit")) not in (0, None):
                d["fallos"] += 1
            dur = _entero(evento.get("duration_s"))
            if dur is not None:
                d["dur"].append(dur)
    except (ValueError, OSError) as error:
        # OSError además de ValueError: un log sin permisos de lectura NO cae en
        # la rama de "ausente" (`exists()` es True) y PermissionError es OSError,
        # no ValueError — así que la versión anterior escupía un traceback y
        # salía 1, incumpliendo el contrato de exit 3 que este mismo docstring
        # promete. Lo reprodujo el review con `chmod 000`.
        print(f"⚠️  detector-runs: NO PUDE MIRAR — {error}", file=sys.stderr)
        print("   El log está corrupto o no se puede leer. Se sale 3 en vez de", file=sys.stderr)
        print("   informar sobre las líneas que sí se pudieron leer: un informe", file=sys.stderr)
        print("   parcial que no dice que es parcial es peor que ninguno.", file=sys.stderr)
        return 3

    if not por_detector:
        print("⚠️  detector-runs: el log existe pero no tiene ni una ejecución.", file=sys.stderr)
        return 3

    print("━━━ detectores · registro de ejecución ━━━")
    print(f"  {'detector':<26}{'corridas':>9}{'objetivos':>11}{'exit≠0':>8}{'p95':>6}")
    mudos = []
    for nombre in sorted(por_detector):
        d = por_detector[nombre]
        if d["objetivos"] is None:
            # Nunca lo declaró: se enseña como raya, no como cero.
            objetivos = "—"
        else:
            objetivos = str(d["objetivos"])
            if d["objetivos"] == 0:
                mudos.append(nombre)
        print(
            f"  {nombre:<26}{d['corridas']:>9}{objetivos:>11}{d['fallos']:>8}{_p95(d['dur']):>5}s"
        )

    # ── La línea de disparos se DERIVA ──────────────────────────────
    universo = set(por_detector)
    disparos = 0
    if DETECCIONES.exists():
        try:
            for evento in leer(DETECCIONES):
                if str(evento.get("source") or "") in universo:
                    disparos += 1
        except ValueError:
            disparos = -1

    if disparos < 0:
        print("  disparos: no pude contarlos — detections.jsonl está corrupto")
    elif disparos == 0:
        print(
            f"  disparos: n/a (0 filas de detections.jsonl con source de detector; "
            f"universo: {len(universo)})"
        )
    else:
        print(f"  disparos: {disparos} filas de detections.jsonl con source de detector")

    if mudos:
        print("")
        print(f"  ⚠️  CERO OBJETIVOS declarados: {', '.join(mudos)}")
        print("      Corrieron y no tenían nada que mirar. Su `errors=0` NO es")
        print("      'está limpio' — y alimenta un trinquete que solo baja (f-6b761f06).")
        print("      Decide keep/tune/retire con este dato, que es lo que pedía")
        print("      f-wf09-ventana-de-valor.")

    sin_declarar = [n for n, d in por_detector.items() if d["sin_declarar"]]
    if sin_declarar:
        print("")
        print(f"  ℹ️  Sin declarar objetivos (—): {', '.join(sorted(sin_declarar))}")
        print("      No es cero: es que el detector no dijo contra cuántos miró.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
