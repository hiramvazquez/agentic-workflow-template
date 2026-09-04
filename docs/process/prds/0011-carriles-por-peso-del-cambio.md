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
| **4** | Profundidad de review por carril (§6b) + los tests lentos fuera de pre-push | Lo único que queda del coste |
| **5** | Retirada de gates: los que no cazaron nada, fuera, con su dato | Cerrar `f-wf09-ventana-de-valor` |

## 6. Modelo de datos — los tres carriles

El carril se deriva del conjunto de rutas del diff staged. **La más severa gana**: si
un solo fichero es estructural, el cambio entero es estructural.

| Carril | Qué lo activa | Qué corre |
|---|---|---|
| **ligero** | Nada que se ejecute: `docs/**`, prosa en `*.md` | Gates rápidos (secretos, marcadores de conflicto, exec-bits) · **ni tests ni review** |
| **normal** | Código que se ejecuta y no es maquinaria de gates | Gates rápidos + los tests del área tocada + **una review ENFOCADA** (§6b) |
| **estructural** | La maquinaria que decide qué se verifica: `lefthook.yml`, `.claude/settings.json`, `scripts/agent-hooks/**`, `ci/**`, `AGENTS.md`, `tools/verify.conf`, `tools/carril.*` | Todo lo anterior + suite completa + **una review PROFUNDA** (§6b) |

**Por qué esa frontera y no otra.** Un cambio en un detector puede dar un resultado
equivocado; un cambio en la maquinaria puede hacer que **ningún** detector corra. El
segundo caso no lo caza ningún test del propio detector, así que es el único que
justifica pagar la suite entera.

## 6b. La profundidad de la review, también por carril

La review es el 70% del coste por unidad, así que es donde queda el tiempo. La palanca
**no** es diferirla: es pedirle menos cuando hay menos que romper.

**Lo que la review cobra no es el diff, es el encargo.** Medido el 2026-09-04, con
diffs de tamaño comparable:

| Review | Qué se le pidió | Duró |
|---|---|---:|
| Unidad del saneo de `verify-run` | una pregunta, 4 ficheros | 577 s |
| Fase 3, ronda 1 | 5 frentes + verificar mutantes ajenos + medir coste | 1208 s |

El doble de tiempo salió del prompt, no del código. Por eso la profundidad se declara
aquí y no se improvisa en cada invocación:

- **`normal` → review ENFOCADA.** El diff, sus tests, y un intento de encontrar un
  mutante que sobreviva. NO re-corre la suite (`verify-run` ya la corrió y su marker lo
  demuestra), NO audita lo adyacente, NO mide costes. Objetivo: 250-400 s.
- **`estructural` → review PROFUNDA.** La de hoy. Aquí sí valen 20 minutos: es el único
  carril donde un fallo puede hacer que *ningún* detector corra, y es la que cazó el
  bypass de lectura-desde-disco de la fase 3.

**Y la review NO se difiere a un lote de commits.** La evidencia va atada a
`sha256(diff staged)`: aplazar significa meter commits sin evidencia y revisarlos
después en bloque. Si ese lote sale RED, el código malo ya está en la historia y su
arreglo va enredado con todo lo que se commiteó encima — §14.1 al revés. La ronda 1 de
la fase 3 encontró un bypass completo mirando 4 ficheros; sobre 12 y tres commits, es
razonable dudar que lo hubiera visto.

**Dos correcciones a esta tabla, hechas en la fase 3 y reproducidas antes de tocarlas.**
Los **fixtures** salieron de `ligero`: `ligero` significa "nada que se ejecute", y un
fixture es la entrada que un test interpreta — con `ligero` no corría ninguno, así que
cambiar el dato con el que se afirma algo quedaba sin verificar. Caen en `normal`, donde
la derivación por referencia encuentra los tests que los nombran. Y `.claude/agents/*`
pasó a **estructural**: el glob `ligero|*.md` casaba `.claude/agents/reviewer.md`, es
decir, clasificaba como prosa el prompt del propio revisor.

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

- [x] **OQ-1 — RESUELTA (fase 3).** No coinciden, y no deben fundirse. "¿es producto?"
      es una pregunta de RUTAS (qué pertenece al adoptante); "¿cuánto puede romper?"
      es el carril. Se solapan mucho pero cada una exime cosas que la otra no: el
      criterio de rutas exime `backlog/` y `.agents/`, que el carril llama `normal`;
      el carril exime prosa dentro del árbol de producto, que el criterio de rutas
      llama producto. Por eso el carril se añade como exención EXTRA sobre el criterio
      existente y nunca como sustituto: sustituirlo endurecería el gate en media
      docena de sitios a la vez, y un gate con falsos positivos se acaba apagando
      (§14.2). Y la exención por carril nunca alcanza las llaves del reino
      (`scope_siempre_producto`): la superficie que gobierna un gate no se exime.

- [x] **OQ-2 — RESUELTA (owner, 2026-09-04): una review por unidad, y la PROFUNDIDAD
      por carril (§6b).** Diferirla a un lote se descartó por dos razones medidas, no
      por principio. Primera: ya es por unidad — las tres unidades de la sesión fueron
      un commit cada una, así que diferir no habría ahorrado nada; solo ahorraría cuando
      una unidad son varios commits, que es justo cuando romper el binding al
      `sha256(diff staged)` sale más caro. Segunda: el tiempo no lo pone el *cuándo*
      sino el *cuánto se le pide* (la tabla de §6b: 577 s frente a 1208 s con diffs
      parecidos). La palanca correcta es la profundidad, no el aplazamiento.

      Queda para la fase 4 hacerlo real: `.claude/agents/reviewer.md` tiene que saber
      leer el carril y ajustar su alcance. Mientras eso no exista, esto es una decisión
      escrita, no un mecanismo — y este PRD no cuenta como entregado lo que solo está
      declarado.

## 15. Definition of Done

Los seis escenarios golden pasando, y la tabla de métricas de éxito con sus tiempos
medidos antes y después.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-04 | Nace de la auditoría de lentitud: el coste por cambio era plano y la mitad del trabajo lo generaba el propio trabajo | sesión de estabilización |
| 2026-09-04 | Fases 1-3 entregadas. La fase 3 destapó dos misclasificaciones de la fase 1: `ligero\|*.md` se tragaba `.claude/agents/*` (el prompt del propio revisor) y los fixtures estaban en `ligero` pese a que un test los ejecuta. Corregidas: la primera a `estructural`, los segundos a `normal` | sesión de estabilización |
| 2026-09-04 | OQ-2 resuelta por el owner: review por unidad con profundidad por carril (§6b); diferir a un lote descartado con datos. Y la fase 4 se redefine: al medirla, el juez de trayectoria y las métricas NO estaban en el camino crítico (solo se nombran en el banner de sesión y en `/status`), y la suite ya salió a pre-push en la fase 2. Lo que queda del coste es la review y los tests lentos | sesión de estabilización |
