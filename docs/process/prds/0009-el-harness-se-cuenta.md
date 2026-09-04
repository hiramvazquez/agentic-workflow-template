# PRD — El harness se cuenta

> **Tipo:** Forward · **Status:** Draft → listo para `Approved` en las fases 4 y 5; la 6 APARCADA, la 3b degradada a regla, la 7 sigue bloqueada por OQ-1
> **Autor:** sesión de auditoría (Claude Opus 5) · **Fecha:** 2026-09-03
> **Design-review:** hereda dos rondas RED del PRD 0008 original. **Este documento agrupa justo lo que hizo que aquellas volvieran rojas**, para que se decida antes de escribir código y no durante.

---

> **Qué es este PRD y por qué no está listo.** El PRD 0008 original juntaba ocho fases. Dos
> rondas de design-review lo dejaron RED por las mismas tres: cada una prometía una fuente de
> datos que el código desmiente. §13 prohíbe una tercera ronda, así que se partió: lo que tenía
> el diseño cerrado se fue a `0008-el-harness-no-borra-codigo.md` y **aquí queda lo que hay que
> decidir**.
>
> **Todas las OQ resueltas el 2026-09-03.** Tres se cerraron investigando el código (OQ-9,
> OQ-10 y OQ-12; la de OQ-10 **cambió la fase 3b**, que ya no puede ser una configuración),
> dos las decidió el owner (OQ-2 y OQ-11b, que **aparca la fase 6**) y una queda APLAZADA con
> su razón escrita (OQ-4). Un `Approved` hoy
> mandaría al implementador a una configuración sin domicilio y a tres métricas sin fuente.

## 1. Contexto

En la auditoría del 2 y 3 de septiembre de 2026 se estudió la práctica de la industria
(`docs/process/reviews/2026-09-03-paridad-industria.md`). La conclusión: en rigor de evidencia
el harness va por delante de lo habitual; en observabilidad va por detrás, y siempre por lo
mismo — **lo nuestro es *pull* (te enteras si ejecutas un comando) y lo suyo es *push***.

Este PRD es el intento de cerrar esa distancia. El `0008` entrega el denominador (qué mira cada
detector); esto entrega la serie, el aislamiento y el juez automático.

## 2. Problema

**(a) Todo lo que damos es una foto.** Nadie puede responder "¿esto va mejor que hace dos
semanas?" sin releer commits. Las seis métricas de referencia de 2026 —las cuatro DORA más
aceptación y retrabajo— no existen aquí.

**(b) El mapa de ejecución lleva días atrás y su detector no lo dice.**
`check-execution-map.sh:179-182` **ya compara** el último commit de producto contra el del
mapa. Sale `stale=0` porque `PROD_DIRS="${EXECUTION_MAP_PROD_DIRS:-}"` (línea 69) está vacío y
nadie lo configura. No falta la dimensión: falta configurarla.

**(c) Las evals de trayectoria no corren solas.** `process-judge` lee la trayectoria, no solo el
diff — que es la práctica de 2026 — pero no está en ningún workflow. La cola de sesiones sin
juzgar ha llegado a once.

**(d) No hay aislamiento de sub-agentes.** El 2026-09-03 uno borró ficheros del repo. El `0008`
entrega la capa barata (deny en Anillo 0); esta es la cara.

## 3. Objetivo

Las seis métricas como serie, el mapa vigilándose a sí mismo, el juez corriendo solo, y los
sub-agentes con capacidad destructiva acotada.

## 4. Filosofía / principios

**P1 — Una métrica sin evento definido en ESTE repo es una métrica inventada.** El design-review
lo demostró: tres de las seis nombraban `git log` como fuente en un repo con **0 merges de 149
commits**. Definir el evento va antes que escribir el lector.

**P2 — Un gate que no corrió no puede parecer un gate que pasó (§14.3).** Vale también para el
juez nocturno: si no encuentra backend, sale 0 y el badge queda verde para siempre.

## 5. Estructura de archivos a crear / tocar

```
tools/project.conf                      ← domicilio candidato de EXECUTION_MAP_PROD_DIRS
                                           (fase 4). Propiedad del adoptante, fuera del sync,
                                           commiteado — y ci/run-gates.sh:134 ya lo lee así
tools/check-execution-map.sh            ← leer el conf con precedencia env > conf > vacío.
                                           SÍ toca el detector: la versión anterior decía que
                                           no, y era falso
lefthook.yml                            ← aviso LOCAL del mapa (fase 4). Sin esto el gate solo
                                           existe en CI y el rojo es pegajoso
tools/metrics/dora.sh                   ← [SLICE-FUTURO] fase 5. Wrapper delgado
tools/metrics/dora.py                   ← [SLICE-FUTURO] fase 5. Las 6 métricas, con serie
.github/workflows/nightly-judge.yml     ← [SLICE-FUTURO] fase 6. REUSA ci/ai-review.sh, que ya
                                           implementa el contrato de fail-open
.claude/settings.json                   ← aislamiento de sub-agentes (fase 3b), si OQ-10 dice
                                           que la opción existe
tools/tests/test_dora.sh                ← [SLICE-FUTURO] fase 5
```

### NO-TOUCH

```
tools/metrics/metrics-report.py         ← 368 líneas, hard limit 400. Los subcomandos NUEVOS
                                           van a su propio módulo; NO se refactoriza a
                                           dispatcher (mover escape_rate/gate_value tocaría
                                           métricas que ci/run-gates.sh:253 ya consume)
tools/metrics/escape-rate.sh            ← la tasa de fallo del cambio se DERIVA de aquí, no se
                                           recalcula: son primas y calculadas por separado se
                                           contradicen
.gitignore:3 (.agents/state/)           ← es la CAUSA de que la serie sea local y de que la
                                           cola del juez no viaje. No se "arregla de paso": es
                                           OQ-2, y decidirlo cambia las fases 5 y 6
tools/drift-ratchet.json · tools/mutation-ratchet.json
                                        ← trinquetes: solo los escribe su propio script (§9)
```

## 5b. Fases entregables — **ninguna arranca sin su OQ**

| Fase | Entrega | Bloqueada por |
|---|---|---|
| **4** | **El harness se vigila a sí mismo.** Configurar `EXECUTION_MAP_PROD_DIRS` + aviso local + mapa al día en el mismo commit. | OQ-9 |
| **5** | **Las seis métricas como serie.** | OQ-2, OQ-12 |
| **3b** | **Aislamiento por worktree** para sub-agentes con capacidad destructiva. | OQ-10 |
| **6** | **Juez nocturno.** | OQ-2, OQ-11b |
| **7** | **Segunda pasada de `AGENTS.md`.** Entregada: el criterio se aplicó hasta agotarlo. El objetivo de ~120 era inalcanzable sin violarlo — ver DoD. | OQ-1 (cerrada) |

## 6. Modelo de datos — lo que hay que definir

### Las seis métricas: por qué la tabla anterior no servía

El design-review verificó el `git log` real: **0 merges de 149 commits, 3 autores, cero
despliegues** — es un template, no un servicio. Con eso, tres de las seis definiciones de la
versión anterior eran inaplicables:

| Métrica | Lo que decía | Por qué no vale aquí |
|---|---|---|
| Frecuencia de entrega | `git log` → despliegues/semana | No hay despliegue |
| Lead time | primer commit → **merge** | 0 merges en el camino que usa este repo |
| Tiempo de recuperación | `git log`: commit rojo → arreglo | `git log` **no contiene el estado de CI**; eso vive en `gh run list` |
| Tasa de retrabajo | findings sobre área ya tocada | El campo `area` del ledger es texto libre (`"tools/check-layers.sh:22 + tools/…"`): no hay join sin normalizar |

Si el implementador cuenta `git log --merges` verá 0 y publicará "frecuencia de entrega:
0/semana" en un repo que entrega varias veces al día. **Es el cero ambiguo que todo esto existe
para matar, reintroducido en la fase que lo mide.** Por eso OQ-12.

Las dos que sí tienen fuente: **tasa de fallo del cambio** (se deriva de `escape-rate`) y
**tasa de aceptación** (`.agents/state/review-history.jsonl`, campo `verdict`; hoy 27%, 29 de
107, medido a mano una vez).

## 7. Anti-features

- **No se añade ningún gate bloqueante nuevo, con una excepción que hay que declarar.** La fase
  4 **no crea un gate: amplía uno que ya bloquea** en el Anillo 3 (`ci/run-gates.sh:244`). A
  partir de ella, todo commit que toque los prod dirs paga el peaje del mapa. Es una segunda
  excepción a `f-wf09-ventana-de-valor` y tiene coste real.
- **No se implementan dashboards web.** La serie se guarda y se lee por terminal.
- **No se resuelve `f-wf01-ci-macos-intermitente`.**

## 8. Escenarios golden

Se escribirán **al cerrar las OQ**: un golden sobre una métrica cuyo evento no está definido
sería una afirmación disfrazada. Los dos que ya se pueden fijar, del aislamiento:

1. **Mecanismo.** Un script que hace `rm -rf android` con ruta **relativa**, cwd = worktree → el
   `android/` del padre sigue existiendo y el del worktree no.
2. **Límite DECLARADO.** El mismo borrado por ruta **absoluta al padre, o con `../`** → el
   worktree **no** protege. *El worktree se crea en `.agents/worktrees/…`, dentro del repo
   padre, así que `../../android` sale igual y es más corto de escribir que la ruta absoluta.*
   Esta es la razón por la que la fase 3a del `0008` no es opcional.

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| **El gate del mapa solo bloquea en CI y el rojo es pegajoso.** No está en `lefthook.yml`. Un commit que no toque el mapa sale verde en local y rojo en CI — y **sigue rojo en cada corrida** hasta que alguien commitee el mapa, porque el rojo lo produce la comparación de timestamps, no el commit. | La fase 4 entrega **también** el aviso local, con el patrón exit-3-avisa que ya usan `semgrep-staged` y `check-source-sets`. Si no, baja al final del orden. |
| **`EXECUTION_MAP_PROD_DIRS` en el propio script viaja a todo adoptante** vía `SYNC_GLOBS="tools/*.sh"`, y rompe la promesa escrita en sus líneas 61-68 ("dejarlo vacío NO deja el día 1 en rojo"). | OQ-9: el domicilio candidato es `tools/project.conf`, que es del adoptante y está fuera del sync. |
| **El juez nocturno queda verde para siempre.** No hay credencial de IA en ningún workflow (0 coincidencias de `secrets.`/`ANTHROPIC`/`API_KEY` en los tres), y `ci/ai-review.sh` está escrito para fallar ABIERTO. | OQ-11b. Y reusar `ci/ai-review.sh`, que ya implementa el contrato, en vez de reimplementarlo en YAML. |
| **`backlog/run.sh` no resuelve la fase 3b.** Crea el worktree para el runner **headless** de backlog, un camino por historia; el incidente fue un sub-agente en sesión **interactiva**, que ese camino no toca. Y `scope-check.sh` corre **después**, sobre el rango git del worktree: un `rm -rf` en el padre no aparece ahí. | OQ-10 decide qué se entrega: worktree por sub-agente interactivo (si la opción existe) o la política de enrutar el trabajo destructivo por `backlog/run.sh` — que es una regla, no código. |

## 10. Open Questions

**Seis cerradas · una (OQ-4) APLAZADA con su razón.** Eran todas bloqueantes al abrirse; la
que queda dejó de serlo cuando el lector de la fase 1 adoptó el default seguro.

> **OQ-1 — CERRADA por el owner el 2026-09-03.** La pregunta era qué contexto es
> irrenunciable en cada turno. La respuesta elegida: **aplicar el criterio del propio fichero**
> —regla con detector en una línea que lo nombra, regla sin detector entera— y sacar a
> referencias la pirámide de §14 y las tablas de §9 y §11.
>
> **Y la aplicación corrigió el objetivo.** El "~120" que acompañaba a esta OQ era una
> estimación mía hecha antes de medir, y es errónea: **87 líneas son reglas sin detector
> mecánico** que el criterio protege, y el resto ya está en su mínima expresión. El total lo
> dice `wc -l`; no se escribe aquí.
>
> Lo que la OQ sí desbloqueó, y vale más que el recorte: **para adelgazar `AGENTS.md` no se
> edita `AGENTS.md`, se mecanizan sus reglas.** Cada detector nuevo convierte párrafos en una
> línea que lo nombra. El mutation score dormido es el ejemplo más caro (§5 es la sección más
> grande y hoy solo se cumple leyéndola). Los espejos (`.cursor/rules/*.mdc`, `.codex/`,
> `CLAUDE.md`) no quedaron afirmando de más: `CLAUDE.md` importa este fichero, no lo copia.

> **OQ-2 — CERRADA por el owner el 2026-09-03: crudo local, resumen semanal commiteado.**
> El JSONL sigue en `.agents/state/` (cada corrida escribe sin ensuciar el árbol) y un rollup
> semanal agregado SÍ se commitea. Da histórico compartido y visible en CI sin conflictos de
> merge constantes en un fichero al que todos hacen append — que es como estos ficheros acaban
> ignorados o borrados. Coste asumido: hay que escribir el agregador y decidir cuándo corre.
> **OQ-4 — APLAZADA con su razón, no cerrada.** El lector de la fase 1 ya la trata con
> honestidad: cuenta las filas y, si son 0, imprime `n/a` **con el conteo**, así que el informe
> dejará de decirlo solo el día que un detector emita su primera detección. Unificar los
> vocabularios —que los detectores escriban en `detections.jsonl`— es un cambio de contrato
> compartido (§9) que no cabe en un PRD de solo-lectura, y una tabla de alias sería deuda
> permanente. Con la fase 6 aparcada, además, baja la urgencia: nadie va a leer esa columna en
> un informe automático. Se decide cuando alguien la necesite.
> **OQ-9 — CERRADA el 2026-09-03: no hace falta una clave nueva.** `tools/lib/scope.sh:111`
> ya declara *"Repo del harness: producto = lo que EJECUTA (tools/, scripts/, ci/, lefthook)"*,
> y `project_kind` ya distingue harness de application. Así que `check-execution-map` **deriva**
> los prod dirs de la declaración que ya existe, en vez de pedir una segunda. Es el mismo
> patrón que cerró la retirada de detectores (commit `2282078`): una declaración, dos
> consumidores, cero drift. Precedencia: `EXECUTION_MAP_PROD_DIRS` del entorno si está (para
> que un adoptante pueda afinar), y si no, lo que diga `scope.sh`.
> **OQ-10 — CERRADA el 2026-09-03, y la respuesta CAMBIA la fase 3b.** Verificado:
> `.claude/settings.json` solo admite `permissions`, `enabledPlugins` y `hooks` — **no hay
> aislamiento de sub-agentes por configuración**. El aislamiento existe como parámetro *por
> invocación* de la tool `Agent` (`isolation: "worktree"`), es decir lo elige quien llama, no
> el proyecto.
>
> Consecuencia: la fase 3b **no puede ser una config**. Lo que se puede entregar es (a) una
> REGLA en las definiciones de los sub-agentes y en `AGENTS.md` —el trabajo destructivo se
> enruta por un worktree aislado—, y (b) el camino que ya existe y funciona,
> `tools/backlog/run.sh`, que corre al agente dentro de un worktree. Una regla no es un
> mecanismo (§P2 del `0008`), así que la fase se degrada de "aislamiento" a "enrutado
> declarado", y su valor real baja: el deny del Anillo 0 de la fase 3a sigue siendo la única
> capa que impide algo.
> **OQ-11b — CERRADA por el owner el 2026-09-03: la fase 6 se APARCA.** No se cablea el juez
> nocturno. Verificado que no hay ninguna credencial de IA en los tres workflows y que
> `ci/ai-review.sh` está escrito para fallar ABIERTO, así que cablearlo sin credencial daría un
> badge verde permanente — un gate que no corrió con aspecto de gate que pasó (§14.3).
>
> Queda escrito lo que se pierde: la eval de trayectoria (`process-judge`) existe y lee lo
> correcto, pero se invoca a mano, y la práctica de 2026 la considera no opcional. La cola de
> sesiones sin juzgar sigue creciendo. Reabrir esto exige decidir credencial y presupuesto
> recurrente.
> **OQ-12 — CERRADA el 2026-09-03 con las fuentes verificadas una a una:**
>
> | Métrica | Evento en ESTE repo | Fuente verificada |
> |---|---|---|
> | Frecuencia de entrega | commit que llega a `main` (no hay despliegue: es un template) | `git log main` |
> | Lead time | primer commit del cambio → su llegada a `main` (**no hay merges**: 0 de 149) | `git log` |
> | Tasa de fallo del cambio | se DERIVA de `escape-rate`, no se recalcula | ledger |
> | Tiempo de recuperación | corrida roja → primera verde posterior | **`gh run list --json headSha,conclusion,createdAt`** — verificado que da los tres campos |
> | Tasa de aceptación | primer veredicto por unidad de trabajo (`staged_sha`) | `.agents/state/review-history.jsonl` — 173 filas, campos `verdict` y `staged_sha` |
> | Tasa de retrabajo | **`n/a` con su razón** | el campo `area` del ledger es texto libre; normalizarlo es otro trabajo |
>
> **Dato ya calculado con la fuente real: 25% de aceptación** (35 verdes a la primera de 138
> unidades). El rango sano de la industria es 25–45%, así que estamos **en el borde inferior**:
> por debajo, el harness estorba más de lo que ayuda. Es la primera cifra de este PRD que ya
> se puede leer, y sale de datos que llevaban meses acumulándose sin que nadie los mirara.

## 11. Definition of Done

Ya se puede escribir. De las **siete** OQ, seis están cerradas y **OQ-4 sigue APLAZADA**
con su razón (no cerrada): el lector de la fase 1 ya la trata con el default seguro, así que no
bloquea nada entregado. Cada condición es un comando, no una
afirmación.

| # | Condición | Cómo se verifica | Estado |
|---|---|---|---|
| 1 | El mapa se vigila solo: tocar producto sin tocar el mapa se delata | `bash tools/check-execution-map.sh` con `tools/` sucio y el mapa viejo → exit 1 | ✅ fase 4 |
| 2 | El aviso del mapa existe en LOCAL y nunca bloquea | job `execution-map` en `lefthook.yml`, `exit 0` incondicional | ✅ fase 4 |
| 3 | Las seis métricas se leen de una vez | `bash tools/metrics/dora.sh` → exit 0 con las seis líneas | ✅ fase 5 |
| 4 | **Ninguna métrica sin evento imprime un 0** | `test_lo_que_no_se_puede_medir_sale_na_con_razon` | ✅ fase 5 |
| 5 | La serie es serie, no foto | `test_la_serie_es_append_only` | ✅ fase 5 |
| 6 | El resumen semanal se versiona y no ensucia el diff | `docs/process/metrics-weekly.md` + `test_el_rollup_semanal_es_idempotente` | ✅ fase 5 |
| 7 | Lo medido llega al fichero commiteado | `test_todo_lo_medido_llega_al_rollup` | ✅ fase 5 |
| 8 | Sin `gh`, las otras cinco siguen saliendo | `test_sin_gh_declara_y_sigue` | ✅ fase 5 |

**Fuera de la DoD, y por qué.** Las tres fases restantes no se cierran con un comando porque su
OQ decidió que no se hacen así:

- **3b** — OQ-10 demostró que no existe aislamiento de sub-agentes por configuración; solo un
  parámetro por invocación. Baja de mecanismo a **regla**, y una regla no tiene DoD verificable.
- **6** — OQ-11b (owner): **aparcada**. Sin credencial de IA en ningún workflow, `ci/ai-review.sh`
  falla abierto y el juez nocturno daría un badge verde permanente — que es P2 violado por la
  fase que lo predica.
- **7** — **entregada, y con el objetivo corregido.** El owner eligió aplicar el criterio del
  propio fichero (regla con detector → una línea; sin detector → entera) hasta donde llegara.
  No llega a ~120, y la aritmética dice por qué: **87 líneas son reglas sin detector** que el
  criterio protege, y el resto ya está en su mínima expresión. (El total exacto no se escribe
  aquí: `wc -l AGENTS.md`. Una cifra derivable en un doc vivo caduca sola — y esta ya lo hizo
  en la misma sesión, porque restaurar la regla que la ronda 1 encontró perdida la movió.) La estimación de ~120 se hizo antes de medir qué
  fracción del fichero carece de detector, y era mía: la corrijo aquí.

  **Lo que sí desbloquea el camino:** para adelgazar `AGENTS.md` no se edita `AGENTS.md`, se
  **mecanizan sus reglas**. Cada detector nuevo convierte párrafos en una línea que lo nombra.
  El mutation score dormido es el ejemplo más caro — §5 es la sección más grande del fichero y
  hoy solo se cumple leyéndola.

## 12. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-03 | Ronda 1 de la fase 5: RED. `recuperacion()` pareaba rojo→verde sobre la lista mezclada de workflows y publicaba recuperaciones que nunca ocurrieron; el número ya estaba en el fichero versionado. Se parea por workflow y se regeneró. Dos notas no bloqueantes al ledger. | reviewer |
| 2026-09-03 | Fases 4 y 5 entregadas; DoD escrita con seis de las siete OQ cerradas (OQ-4 aplazada). La fase 5 encontró dos huecos silenciosos propios: el rollup repetía a mano los nombres de las métricas (renombrar una la escondía), y guardaba la tasa de fallo como texto, así que la métrica MEDIDA se caía de la tabla commiteada igual que una no medida. | sesión de auditoría |
| 2026-09-03 | Nace al partir el PRD 0008 original por el remedio de §13, tras dos design-reviews RED. Recoge sus fases con diseño ABIERTO y convierte en OQ bloqueante cada premisa que el código desmintió. | sesión de auditoría |
