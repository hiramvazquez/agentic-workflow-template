#!/usr/bin/env python3
"""dora_rollup.py — la serie agregada por semana, que es lo que se commitea.

Se separó de `dora.py` cuando ese fichero cruzó el hard limit de 400 líneas
(§4). La división no es por tamaño sino por responsabilidad, y hasta hace poco
no era segura: mientras el rollup repetía a mano los nombres de las métricas,
separarlo de quien las produce habría hecho ese drift invisible. Desde que las
columnas se DERIVAN de los datos, el agregador no necesita saber qué métricas
existen — solo leer lo que la serie traiga.

Las rutas llegan por parámetro a propósito: definirlas aquí otra vez sería el
mismo drift que se acaba de quitar de las columnas.
"""
from __future__ import annotations

import runpy
import statistics
import sys
from datetime import datetime
from pathlib import Path


def rollup(SERIE: Path, ROLLUP: Path) -> int:
    """La decisión del owner (OQ-2): el crudo se queda local y volátil, el
    resumen semanal se commitea. Y por eso es IDEMPOTENTE y no lleva fecha de
    generación: un fichero versionado que cambia en cada corrida llena el diff
    de ruido, y un diff ruidoso se deja de leer."""
    if not SERIE.exists():
        print(f"⚠️  dora --rollup: no hay serie que resumir ({SERIE}).", file=sys.stderr)
        return 3
    api = runpy.run_path(str(Path(__file__).with_name("read-events.py")))
    semanas: dict[str, dict[str, list[float]]] = {}
    sin_datar = 0
    try:
        for ev in api["read"](SERIE):
            if ev.get("kind") != "dora":
                continue
            try:
                cuando = datetime.fromisoformat(str(ev.get("ts", "")).replace("Z", "+00:00"))
            except ValueError:
                # Aquí el descarte llegaba al fichero VERSIONADO: la fila se
                # caía de la agregación y el commiteado no lo decía.
                sin_datar += 1
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
              "> salida de `dora.sh`. No es lo mismo que 0.", ""]
    if sin_datar:
        lineas += [f"> ⚠️  {sin_datar} fila(s) de la serie **sin datar** y fuera de esta tabla:",
                   "> su `ts` no se pudo interpretar. Un descarte que no se declara no es un",
                   "> filtro, es una pérdida.", ""]
    lineas += [
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
    aviso = f" ({sin_datar} fila(s) sin datar, declaradas en el fichero)" if sin_datar else ""
    print(f"✅ rollup: {len(semanas)} semana(s) en {ROLLUP}{aviso}")
    return 0
