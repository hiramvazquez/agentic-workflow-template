#!/usr/bin/env python3
"""dora_git.py — todo lo que este informe le pregunta a git.

Separado de `dora.py` cuando ese fichero volvió a cruzar el hard limit de 400
líneas (§4). La junta la señaló el review antes de que hiciera falta: resolver
CONTRA QUÉ se mide es una responsabilidad distinta de medir, y es la que más ha
costado — dos rondas en rojo, primero por codificar `main` a mano y luego por
devolver un nombre sin comprobar que apuntara a algo.

Las funciones públicas no llevan guion bajo: `dora.py` las consume por nombre.
"""
from __future__ import annotations

import os
import subprocess

# Las llamadas a git son LOCALES y de milisegundos; 30 s era una espera pensada
# para nada. Y esta librería está en el camino de `/status`, que declara su
# presupuesto. Mismo criterio que el owner fijó para `gh` (`f-7a219330`).
try:
    TIMEOUT_GIT = max(1, int(os.environ.get("DORA_GIT_TIMEOUT", "10")))
except ValueError:
    TIMEOUT_GIT = 10


class GitLento(Exception):
    """git no respondió a tiempo.

    Existe porque `git()` devuelve cadena vacía en dos situaciones que NO son la
    misma: git **dijo que no** (un `rev-parse` sobre una ref inexistente sale 1,
    y eso es una respuesta legítima que hay que tratar como tal) y git **no
    respondió**. Colapsarlas hacía que un git colgado saliera aguas abajo como
    "no pude determinar la rama del tronco (¿repo sin commits?)" — una razón
    falsa sobre un repo lleno de commits, que es justo lo que la lección
    [2026-09-03] dice que es peor que no decir nada.
    """


def git(*args) -> str:
    try:
        r = subprocess.run(("git",) + args, capture_output=True, text=True,
                           timeout=TIMEOUT_GIT)
    except subprocess.TimeoutExpired as e:
        # ANTES de la genérica: `TimeoutExpired` ES un `SubprocessError`.
        raise GitLento(f"`git {args[0] if args else ''}` no respondió en "
                       f"{TIMEOUT_GIT} s") from e
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def resuelve(ref: str) -> bool:
    """¿Este nombre apunta a algo? La pregunta que faltaba."""
    return bool(ref) and bool(git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"))


def tronco() -> str:
    """La rama que hace de tronco, DERIVADA y VERIFICADA. Cadena vacía si
    ninguna candidata resuelve.

    Estaba escrita a mano como `main`, y en un repo con `master` o `trunk` eso
    producía "0 commits en main en 90 días": un `n/a` cuya razón declarada es
    falsa —no es que no hubiera commits, es que se miró un sitio que no
    existe—. Esta es una plantilla que se distribuye, así que le pasaba a
    cualquier adoptante que no usara `main`.

    Y la primera versión de este arreglo cortaba el prefijo de `origin/HEAD`
    para devolver el nombre pelado, que **solo resuelve si existe la rama
    LOCAL**. Borrarla es rutina, y entonces reaparecía exactamente el mismo
    bug por otra puerta. Lo cazó el review con el repro completo. De ahí que
    aquí no se devuelva ningún nombre sin comprobar antes que apunta a algo:
    la lección es que un `n/a` es una AFIRMACIÓN, y una afirmación se verifica.
    """
    remoto = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if remoto.startswith("origin/"):
        corto = remoto[len("origin/"):]
        # La REMOTA primero. El orden anterior probaba el nombre pelado "porque
        # es lo que el usuario reconoce", y con una rama local por detrás medía
        # la local sin decirlo: el review lo reprodujo dando 2 commits donde
        # había 3 entregados. Y preferirla es lo correcto por definición —
        # "entrega" es lo que llegó al tronco compartido, no lo que hay en tu
        # clon; lo que aún no has empujado, precisamente, no se ha entregado.
        for cand in (remoto, corto):
            if resuelve(cand):
                return cand
    for nombre in ("main", "master", "trunk"):
        if resuelve(nombre):
            return nombre
    actual = git("rev-parse", "--abbrev-ref", "HEAD")
    return actual if resuelve(actual) else ""


def desfase_local(tronco: str) -> str:
    """Aviso si se midió contra la referencia remota y la rama local del mismo
    nombre va por detrás. El número es correcto —es el tronco compartido— pero
    el lector necesita saber que su copia no contiene lo que se le está
    contando.

    El caso simétrico (la local por DELANTE) no es un aviso: son commits sin
    empujar, y no empujado es no entregado. Esa asimetría es justamente la
    razón de preferir la remota."""
    if not tronco.startswith("origin/"):
        return ""
    local = tronco[len("origin/"):]
    if not resuelve(f"refs/heads/{local}"):
        return ""
    detras = git("rev-list", "--count", f"refs/heads/{local}..{tronco}")
    if not detras.isdigit() or detras == "0":
        return ""
    return (f"  ⚠️  tu rama local `{local}` va {detras} commit(s) por detrás de "
            f"`{tronco}`.\n      Se midió contra la remota: esto es lo entregado, "
            "no lo que tienes delante.")
