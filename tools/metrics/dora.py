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

_GIT = runpy.run_path(str(Path(__file__).with_name("dora_git.py")))
_git, _tronco, _desfase_local = _GIT["git"], _GIT["tronco"], _GIT["desfase_local"]

SERIE = Path(".agents/state/metrics/series.jsonl")
ROLLUP = Path("docs/process/metrics-weekly.md")
REVIEWS = Path(".agents/state/review-history.jsonl")
VENTANA = 90

# `gh run list` es red, y desde que `/status` lo invoca de rutina está en el
# camino crítico de un comando que se documenta a ~13 s: 60 s de espera lo
# convertían en un minuto de pantalla en blanco (`f-7a219330`). 20 s son de
# sobra para una llamada sana, y si no responde en ese tiempo la respuesta
# honesta ya es `n/a`. Ajustable por entorno porque una CI lenta es un caso
# real — y porque es lo que hace TESTEABLE la rama del timeout sin dormir 20 s.
try:
    TIMEOUT_GH = max(1, int(os.environ.get("DORA_GH_TIMEOUT", "20")))
except ValueError:
    TIMEOUT_GH = 20


class Metrica:
    """Un valor medido, o un hueco CON su razón. Nunca las dos cosas."""

    def __init__(self, nombre, valor=None, texto=None, razon=None, clave=None):
        self.nombre, self.valor, self.texto = nombre, valor, texto
        self.razon, self.clave = razon, clave or nombre

    def linea(self) -> str:
        derecha = self.texto if self.razon is None else f"n/a — {self.razon}"
        return f"  {self.nombre:<26}{derecha}"


def _desde(dias: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=dias)).strftime("%Y-%m-%d")


# ── 1. Frecuencia de entrega ────────────────────────────────────────
def frecuencia(dias: int) -> Metrica:
    """En un repo-plantilla, `main` ES el artefacto: el adoptante clona y
    actualiza desde ahí. No hay despliegue aparte que medir, y esperarlo
    dejaría muda una métrica que aquí sí tiene evento."""
    tronco = _tronco()
    if not tronco:
        return Metrica("frecuencia de entrega", razon="no pude determinar la rama del tronco: ninguna de origin/HEAD, main, master, trunk ni la rama actual resuelve (¿repo sin commits?)")
    log = _git("log", "--first-parent", tronco, f"--since={_desde(dias)}", "--format=%H")
    n = len([x for x in log.splitlines() if x.strip()])
    if not n:
        return Metrica("frecuencia de entrega",
                       razon=f"0 commits en `{tronco}` en {dias} días")
    por_semana = n / (dias / 7.0)
    # La rama se NOMBRA. Sin eso el lector no puede saber si se midió lo que cree.
    return Metrica("frecuencia de entrega", por_semana,
                   f"{por_semana:.1f} /semana  ({n} commits en `{tronco}`, {dias} días)")


# ── 2. Lead time ────────────────────────────────────────────────────
def lead_time(dias: int) -> Metrica:
    """Ventana entre el primer commit de un cambio y su llegada a main. Con
    trabajo directo sobre main esa ventana es CERO POR CONSTRUCCIÓN, y un
    '0.0 h' se leería como entrega instantánea en vez de como ausencia de
    medición. Por eso el hueco se declara en vez de calcularse."""
    tronco = _tronco()
    if not tronco:
        return Metrica("lead time", razon="no pude determinar la rama del tronco: ninguna de origin/HEAD, main, master, trunk ni la rama actual resuelve (¿repo sin commits?)")
    merges = [m for m in _git("log", tronco, f"--since={_desde(dias)}",
                              "--merges", "--format=%H").splitlines() if m.strip()]
    if not merges:
        total = len([x for x in _git("log", tronco, "--format=%H").splitlines() if x.strip()])
        return Metrica("lead time", razon=(
            f"0 merges en {total} commits: el trabajo va directo a `{tronco}`, "
            "así que no hay ventana entre el commit y su llegada"))
    horas, sin_datar = [], 0
    for m in merges:
        fin = _git("show", "-s", "--format=%ct", m)
        rama = [c for c in _git("log", "--format=%ct", f"{m}^1..{m}^2").splitlines() if c.strip()]
        if fin and rama:
            horas.append((int(fin) - int(rama[-1])) / 3600.0)
        else:
            sin_datar += 1
    if not horas:
        return Metrica("lead time",
                       razon=f"hay {len(merges)} merges y no pude datar la rama de ninguno")
    med = statistics.median(horas)
    cola = f"; {sin_datar} sin datar" if sin_datar else ""
    return Metrica("lead time", med, f"{med:.1f} h (mediana de {len(horas)} merges{cola})")


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
                           capture_output=True, text=True, timeout=TIMEOUT_GH)
    except FileNotFoundError:
        return Metrica("tiempo de recuperación", razon="`gh` no está instalado")
    except subprocess.TimeoutExpired:
        # ANTES de la rama genérica: `TimeoutExpired` ES un `SubprocessError`,
        # así que caía ahí y salía como "falló al invocarse" — cierto en vago y
        # falso en concreto. `gh` arrancó bien; lo que pasó es que tardó.
        return Metrica("tiempo de recuperación",
                       razon=f"`gh` no respondió en {TIMEOUT_GH} s (¿red lenta?)")
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
    vistos = descartadas = 0
    for c in corridas:
        cuando = _ts(c.get("updatedAt"))
        if cuando is None:
            # Se CUENTA. Antes se hacía `continue` a secas: la corrida salía del
            # denominador sin que nadie lo dijera, que es el patrón de la
            # lección [2026-09-03] cometido en el commit que la añadió.
            descartadas += 1
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
    cola = f"; {descartadas} descartada(s) por fecha ilegible" if descartadas else ""
    if not horas:
        return Metrica("tiempo de recuperación", razon=(
            f"ninguna corrida roja recuperada en las últimas {vistos}{cola}"))
    med = statistics.median(horas)
    return Metrica("tiempo de recuperación", med,
                   f"{med:.1f} h (mediana de {len(horas)}{cola})")


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
    sin_sha = sin_veredicto = 0
    try:
        for ev in api["read"](REVIEWS):
            sha = str(ev.get("staged_sha") or "").strip()
            veredicto = str(ev.get("verdict") or "").strip().upper()
            if veredicto and not sha:
                # No es una unidad de trabajo y NO debe contar. Pero que no
                # cuente y que nadie lo diga son cosas distintas: una review que
                # ocurrió y no se pudo atribuir a un diff es un dato.
                sin_sha += 1
            elif not veredicto:
                # Ni veredicto ni forma de atribuirlo. Hoy es latente —el único
                # escritor real nunca deja el veredicto vacío— pero dejar un
                # descarte mudo en el cambio cuyo propósito es que no los haya
                # es la contradicción que este harness castiga en todo lo demás.
                sin_veredicto += 1
            elif sha not in primero:
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
    partes = []
    if sin_sha:
        partes.append(f"{sin_sha} sin diff que firmar")
    if sin_veredicto:
        partes.append(f"{sin_veredicto} sin veredicto")
    cola = "; " + ", ".join(partes) if partes else ""
    return Metrica("tasa de aceptación", pct,
                   f"{pct:.0f}% ({verdes}/{len(primero)} unidades verdes a la primera{cola}){aviso}")


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


def _apuntar_serie(metricas: list[Metrica], dias: int) -> None:
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


def informar(dias: int, serie: bool = True) -> int:
    """El informe. `serie=False` (`--sin-serie`) lo imprime SIN apuntar nada.

    `/status` se declara de solo lectura, y una fila escrita "de mirar" no es
    inocua: la serie alimenta el rollup VERSIONADO, así que falsearía la media
    semanal de un fichero que se commitea. Observar no puede modificar — la
    misma trampa por la que `session-start` necesitó su `--report`
    (`f-session-start-fx`). Lo que NO cambia es lo que se imprime: un modo de
    lectura que además recorta el informe no sirve para lo que se pidió.
    """
    metricas = _recoger(dias)
    print(f"━━━ entrega · ventana {dias} días ━━━")
    for m in metricas:
        print(m.linea())

    aviso = _desfase_local(_tronco())
    if aviso:
        print("")
        print(aviso)

    huecos = [m for m in metricas if m.razon is not None]
    if huecos:
        print("")
        # Una sola línea, y autocontenida: el filtro de `/status` recoge las
        # líneas con dos espacios de sangría, así que una nota partida en dos
        # llegaba a pantalla cortada a mitad de frase.
        print(f"  ℹ️  {len(huecos)} de 6 sin evento que medir aquí — un hueco declarado "
              "es una lectura correcta; un 0 en su lugar, no.")

    if serie:
        _apuntar_serie(metricas, dias)
    return 0


def main(argv: list[str]) -> int:
    if "--rollup" in argv:
        api = runpy.run_path(str(Path(__file__).with_name("dora_rollup.py")))
        return api["rollup"](SERIE, ROLLUP)
    dias = VENTANA
    if "--days" in argv:
        try:
            dias = max(1, int(argv[argv.index("--days") + 1]))
        except (IndexError, ValueError):
            print("⚠️  --days necesita un entero positivo.", file=sys.stderr)
            return 3
    return informar(dias, serie="--sin-serie" not in argv)


if __name__ == "__main__":
    os.environ.setdefault("GIT_OPTIONAL_LOCKS", "0")
    raise SystemExit(main(sys.argv[1:]))
