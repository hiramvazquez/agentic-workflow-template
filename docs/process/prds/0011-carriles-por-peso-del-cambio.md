# PRD 0011 — Carriles: que un cambio pequeño cueste como un cambio pequeño

**Estado:** Approved (owner, 2026-09-04) · **Owner:** hiram · **Tipo:** arquitectura de proceso

---

## 1. Contexto

El PRD 0010 fijó la frontera de V1: *un cambio pequeño llega a commit con pruebas
verdes, una revisión, y sin corregir el workflow por el camino*. Se cumplió a medias:
la suite pasó de rojo determinista a verde y tres unidades entraron limpias. Pero el
coste por unidad siguió siendo el mismo para todo, y ese es el problema que queda.

## 2. Problema

**El workflow no sabe cuánto pesa un cambio.** Añadir un string y reescribir el motor
pagan idéntico: la suite completa, una revisión, y los doce gates de pre-commit.

Medido en la sesión del 2026-09-04, con los comandos que lo reproducen:

| Qué | Coste | Cómo se midió |
|---|---:|---|
| Gates de pre-commit | ~4 s | `lefthook run pre-commit` |
| Suite completa (`verify.conf`) | ~140 s | `bash tools/tests/run-tests.sh` |
| Una ronda de review | 254–788 s | duración de los sub-agentes de la sesión |

Y tres consecuencias que el mismo día dejó medidas:

1. **La mitad del trabajo lo generó el propio trabajo.** De los commits de esa sesión,
   ocho existen porque un commit anterior creó trabajo. Hay una cadena de seis
   commits que sale de una sola feature.
2. **Un gate añadido ese mismo día causó tres de esos ocho** — el de frescura del mapa.
   Nadie midió su coste de arrastre antes de ponerlo.
3. **Había una regla que lo prohibía y no se respetó**: `f-wf09-ventana-de-valor` pide
   congelar gates nuevos hasta cerrar su ventana de observación.

**La causa no es el lenguaje.** De los findings abiertos, el 47% son errores de diseño
que ninguna reescritura evita; el 37% son de clase Bash y el 16% de semántica de git.
La lentitud viene de la política, no de shell.

## 3. Objetivo

**Que el coste de verificar un cambio sea proporcional a lo que ese cambio puede
romper.** Un cambio que no ejecuta nada no paga una suite de dos minutos.

## 4. Filosofía / principios

- **P1 — El carril lo decide lo que TOCAS, no lo que dices.** Se deriva del diff
  staged, mecánicamente. Nadie declara su propio carril.
- **P2 — Cada gate paga peaje a todos los cambios futuros.** Un gate entra solo si
  retira una comprobación manual Y trae medido lo que caza frente a lo que cobra.
  Mientras este PRD corre: **cero gates nuevos**.
- **P3 — Lo pesado no desaparece: se mueve.** Métricas, evals de trayectoria,
  auditorías históricas y comprobaciones documentales globales siguen existiendo bajo
  demanda, en pre-push o en release. Fuera del camino de cada commit.
- **P4 — La revisión tiene suelo.** Solo reporta lo que rompe corrección, seguridad o
  un requisito explícito del encargo. Es la regla que §13 ya declara y que no se
  aplicaba.

## 5. Estructura de archivos a crear / tocar

```
tools/carril.sh                     ← [SLICE-FUTURO] fase 1. Deriva el carril del diff staged
tools/carril.conf                   ← [SLICE-FUTURO] fase 1. Los patrones de cada carril, fuente única
tools/tests/test_carril.sh          ← [SLICE-FUTURO] fase 1. Su suite
tools/verify-run.sh                 ← consulta el carril y elige qué ejecutar
tools/check-review-marker.sh        ← el carril ligero no exige marker de review
lefthook.yml                        ← la suite completa sale de pre-commit
docs/process/current_execution_map.md ← un estado, un próximo paso
```

### NO-TOUCH

```
tools/mutation-ratchet.json · tools/drift-ratchet.json   ← trinquetes (§9)
tools/tests/run-tests.sh    ← el runner ya expresa selección por filtro; no se duplica
.github/workflows/**        ← se cablea con autorización explícita
```

## 5b. Fases entregables

| Fase | Entrega | Qué desbloquea |
|---|---|---|
| **1** | `carril.sh` + su conf + tests. Solo DERIVA y lo imprime; no cambia nada todavía | Poder medir antes de decidir |
| **2** | `verify-run` elige por carril; la suite completa sale de pre-commit a pre-push | El grueso del tiempo devuelto |
| **3** | El carril ligero no exige review; el normal exige una | El "string en una view" |
| **4** | Lo pesado se mueve: juez de trayectoria, métricas y tests lentos a demanda/release | Camino crítico limpio |
| **5** | Retirada de gates: los que no cazaron nada, fuera, con su dato | Cerrar `f-wf09-ventana-de-valor` |

## 6. Modelo de datos — los tres carriles

El carril se deriva del conjunto de rutas del diff staged. **La más severa gana**: si
un solo fichero es estructural, el cambio entero es estructural.

| Carril | Qué lo activa | Qué corre |
|---|---|---|
| **ligero** | Nada que se ejecute: `docs/**`, `*.md`, fixtures de test | Gates rápidos (secretos, marcadores de conflicto, exec-bits) |
| **normal** | Código que se ejecuta y no es maquinaria de gates | Gates rápidos + los tests del área tocada + **una** review |
| **estructural** | La maquinaria que decide qué se verifica: `lefthook.yml`, `.claude/settings.json`, `scripts/agent-hooks/**`, `ci/**`, `AGENTS.md`, `tools/verify.conf`, `tools/carril.*` | Todo lo anterior + suite completa + review |

**Por qué esa frontera y no otra.** Un cambio en un detector puede dar un resultado
equivocado; un cambio en la maquinaria puede hacer que **ningún** detector corra. El
segundo caso no lo caza ningún test del propio detector, así que es el único que
justifica pagar la suite entera.

## 7. Flujo de la solución

```
git add <paths>  →  tools/carril.sh  →  ligero | normal | estructural
                         │
      ┌──────────────────┼───────────────────────┐
   ligero              normal                estructural
   gates (~4 s)     gates + tests del área    todo + suite completa
   sin review       + UNA review              + review
```

## 8. Anti-features (qué NO entra)

- Un runner nuevo. `run-tests.sh` ya selecciona por filtro; el carril elige el filtro.
- Que el autor declare su carril. Se deriva o no vale.
- Gates nuevos, de cualquier clase, mientras este PRD corra.
- Borrar comprobaciones. Lo pesado se MUEVE, no se tira.
- Un carril que se salte el escaneo de secretos. Ese corre siempre, en los tres.

## 9. Escenarios golden (deben pasar al terminar)

1. Un cambio solo en `docs/**` sale `ligero`, y su verificación tarda segundos.
2. Un cambio en `tools/check-drift.sh` sale `normal` y corre los tests de drift, no los 74.
3. Un cambio en `lefthook.yml` sale `estructural` y corre la suite completa.
4. Un diff que mezcla `docs/` y `lefthook.yml` sale **estructural**: la más severa gana.
5. El escaneo de secretos corre en los tres carriles.
6. Un cambio de un string en un fichero de producto llega a commit **sin review**
   solo si es carril ligero; si ejecuta algo, paga su review.

## 10. Métricas de éxito

Antes y después, con el mismo comando: tiempo de verificación de un cambio de una
línea en `docs/`, de uno en un detector, y de uno en `lefthook.yml`. Si el primero no
baja de dos minutos a segundos, esto no sirvió.

## 12. Riesgos

- **Un carril mal derivado es peor que no tener carriles**: un cambio estructural
  clasificado como ligero se salta la suite. Por eso la regla es "la más severa gana"
  y por eso `carril.conf` es fuente única con su test.
- **La fase 1 no cambia nada a propósito.** Deriva e imprime. Sin ese paso, la decisión
  de qué carril aplica a qué se tomaría sin datos.

## 13. Open Questions

- [ ] **OQ-1.** ¿El carril ligero necesita marker de tests? Hoy `check-verify-marker`
      ya exime los cambios que no tocan producto; hay que comprobar si esa exención
      coincide con el carril ligero o si son dos criterios que van a divergir.

## 15. Definition of Done

Los seis escenarios golden pasando, y la tabla de métricas de éxito con sus tiempos
medidos antes y después.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-04 | Nace de la auditoría de lentitud: el coste por cambio era plano y la mitad del trabajo lo generaba el propio trabajo | sesión de estabilización |
