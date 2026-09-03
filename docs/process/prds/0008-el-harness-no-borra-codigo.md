# PRD — El harness no borra código, y sus detectores dicen qué miran

> **Tipo:** Forward · **Status:** Draft
> **Autor:** sesión de auditoría (Claude Opus 5) · **Fecha:** 2026-09-03
> **Design-review:** dos rondas sobre el PRD 0008 original, las dos **RED** (11 y 18 hallazgos). El remedio de §13 —"la tercera no se revisa: se parte"— produjo este documento y el `0009`.

---

> **Por qué este PRD existe y qué NO contiene.** El PRD 0008 original juntaba ocho fases:
> tres con el diseño cerrado y cinco con decisiones abiertas. Las dos rondas de design-review
> volvieron RED por las segundas, no por las primeras. §13 prohíbe una tercera ronda sobre la
> misma unidad, así que se partió **por naturaleza**:
>
> - **Este PRD (0008)** — lo que tiene incidente ocurrido y diseño cerrado: que ninguna
>   herramienta del harness borre código, y que los detectores digan contra qué miran.
> - **`0009-el-harness-se-cuenta.md`** — las métricas, el mapa vigilándose y el juez nocturno.
>   Cada una con una decisión de diseño que el código desmintió y que sigue abierta.

## 1. Contexto

El 2026-09-03, durante una auditoría del harness, **un sub-agente `reviewer` ejecutó
`scripts/bootstrap.sh` contra el repo real** y borró `android/AGENTS.md`, `web/AGENTS.md` y
reescribió `tools/preset`. Los restauró y lo declaró. Nada mecánico se lo impidió.

En la misma sesión se instrumentaron los siete detectores para que registren qué miran
(`runs.jsonl`) — y nadie lee ese registro.

## 2. Problema

**(a) `bootstrap.sh` puede borrar código ajeno.** Su bucle hace `rm -rf` de las plataformas
que el usuario no liste, sobre `ios android web backend`. Como `install-harness.sh` clasifica
`ios android web` como rutas que **nunca** copia, en una adopción Caso B cualquiera de esos
directorios que bootstrap encuentre **es del adoptante**. Son los cuatro elementos del bucle,
no solo `backend` (`f-970c3590`, `high`, reproducido dos veces).

Hay una segunda mutación: `bootstrap.sh:26-30` hace `sed -i` en sitio sobre los ficheros que
contienen los placeholders `<PROJECT>`. *Precisión que el design-review corrigió: no reescribe
"todo fichero de texto" — solo los que llevan el placeholder. El radio real es menor que el que
decía la versión anterior de este PRD, y la decisión debe partir del radio real.*

**(b) Nada barato impide invocar lo destructivo.** El Anillo 0 (`permissions.deny`) evalúa
antes de que la tool corra y cuesta 0 ms. No tiene ninguna regla para esto.

**(c) Se grabó una medición que nadie lee.** Los siete detectores escriben `runs.jsonl` con
`targets` y `exit`. Ningún informe lo consume, así que "cero detecciones" sigue significando
tres cosas distintas: disuasión, sin objetivos, no corrió.

## 3. Objetivo

1. Ninguna herramienta del harness borra ficheros del proyecto por respuesta a un prompt.
2. Invocar lo destructivo conocido está denegado en la capa más barata.
3. Un programador sabe **si cada detector corrió y contra cuántos objetivos**.

## 4. Filosofía / principios

**P1 — Un aviso que llega después del comando es prosa.** Aprendido dos veces en la sesión que
originó esto: "revisa el diff antes de commitear" no evitó que el `cp -R` pisara ficheros, y un
aviso puesto *debajo* de un bloque copiable llega tarde por construcción.

**P2 — Primero la capa barata (§14.1).** El incidente lo habría parado una línea en
`permissions.deny`, no una configuración de aislamiento que primero hay que verificar que
existe.

**P3 — No ejecutes destrucción por respuesta a un prompt.** Decisión del owner del 2026-09-03
(OQ-5, resuelta). `bootstrap.sh` **propone** el borrado y no lo ejecuta. Esto elimina de raíz
la heurística "¿este `ios/` es del template o del adoptante?", sus falsos positivos y dos
escenarios golden. Es nivel 0 (imposibilitar) en vez de nivel 2 (detectar).

**P4 — El denominador antes que el numerador.** Lo que falta no es más detección: es saber
cuántas veces corrió cada detector y contra qué.

## 5. Estructura de archivos a crear / tocar

```
.claude/settings.json                   ← permissions.deny de prefijo (fase 3a)
scripts/bootstrap.sh                    ← propone el borrado en vez de ejecutarlo (P3) +
                                           precondición "¿apunto al template?" (OQ-8)
docs/ADOPTION.md                        ← §1 Caso B dice hoy que f-970c3590 está "no arreglado
                                           todavía": cerrado el finding, esa frase es FALSA y
                                           nada la detecta. Se actualiza en el MISMO commit
tools/metrics/detector-runs.sh          ← [SLICE-FUTURO] fase 1. Wrapper delgado: guarda de
                                           python3, exit 3, exec. NO parsea nada
tools/metrics/detector_runs.py          ← [SLICE-FUTURO] fase 1. Lector de runs.jsonl. Reusa
                                           tools/metrics/read-events.py, que ya normaliza JSONL
tools/tests/test_bootstrap_no_borra_ajeno.sh ← [SLICE-FUTURO] fase 2
tools/tests/test_detector_runs_report.sh     ← [SLICE-FUTURO] fase 1
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
tools/metrics/metrics-report.py         ← 368 líneas, hard limit 400. Los subcomandos NUEVOS
                                           van a su propio módulo: NO se refactoriza a
                                           dispatcher. Mover escape_rate/gate_value tocaría
                                           dos métricas que ci/run-gates.sh:253 ya consume
tools/drift-ratchet.json                ← trinquete: solo lo escribe su propio script (§9)
tools/mutation-ratchet.json             ← ídem, y está DORMIDO a propósito
.agents/state/metrics/detections.jsonl  ← metrics-report.py hace `gate["detections"] += n`
                                           por FILA. Los registros de ejecución van a
                                           runs.jsonl, aparte
tools/upgrade.sh:224 (SYNC_PATHS)       ← install-harness.sh la lee con
                                           `grep -m1 ^SYNC_PATHS= | cut -d'"' -f2`.
                                           Reformatearla rompe el instalador EN SILENCIO
tools/tests/test_detector_runs.sh       ← su lista de 7 detectores ES el universo del
                                           denominador de la fase 1
tools/lib/scope.sh:109,116              ← eximen enterprise/ y (ios|android|web|backend)/AGENTS.md
                                           en las DOS clasificaciones. Mover esas rutas
                                           re-clasificaría ficheros como PRODUCTO y cambiaría
                                           qué edición exige marker de review
```

## 5b. Fases entregables

| Fase | Entrega (mergeable) | Depende de | Golden que la cierra |
|---|---|---|---|
| **3a** | **Deny de prefijo.** `permissions.deny` con la forma garantizada para invocar lo destructivo conocido. Anillo 0, 0 ms. **Con su límite declarado** (ver golden 2). | — | 1, 2 |
| **2** | **`bootstrap.sh` propone, no ejecuta** (P3) + precondición del remote `template` (OQ-8, cerrada) + `sed` acotado con `git ls-files` (OQ-11, cerrada) + `ADOPTION.md` al día en el mismo commit. Cierra `f-970c3590`. | — | 3, 4 |
| **1** | **Lector del denominador.** Por detector: corridas, objetivos, exit, p95. La línea de disparos se **deriva**, no se escribe a mano (ver §6). | — | 5, 6 |

## 6. Modelo de datos

### `runs.jsonl` (ya existe, NO cambia)

```json
{"schema":1,"kind":"run","ts":"…","source":"check-layers","targets":0,"exit":0,"duration_s":0,"commit":"…"}
```

`targets: null` es **"no lo declaró"**, distinto de `0` ("declaró que miró cero").

### La línea de disparos se DERIVA, no se escribe

Hoy los vocabularios de `source` son **disjuntos**: `runs.jsonl` usa nombres de detector,
`detections.jsonl` solo lo escriben los hooks. Intersección vacía, verificado con grep.

Pero eso es un hecho de HOY, no una imposibilidad — `metrics-report.py:19` ya declara
`check-drift`, `check-layers` y `semgrep` como fuentes válidas de la fase `gate`. Así que el
informe **cuenta** las filas de `detections.jsonl` cuyo `source` esté en el universo de
`runs.jsonl` y, **si el conteo es 0**, imprime `n/a` con ese conteo. Escribir "n/a" a mano
dejaría el informe mintiendo el día que un detector empiece a emitir. Es la misma regla de
"cifras derivables, no copiadas" que el harness ya le impone al mapa de ejecución.

Unificar los vocabularios es cambio de contrato compartido (§9) y vive en el `0009` como OQ.

## 7. Flujo de la solución

### User stories
- Como adoptante quiero que **ninguna herramienta del harness borre mi código**, aunque me
  equivoque respondiendo a un prompt.
- Como owner quiero saber **qué detector no ha mirado nunca nada**, para retirarlo con datos.

### Edge cases
- Detector que corre sin declarar objetivos (`targets: null`) → se cuenta aparte, no como cero.
- `runs.jsonl` ausente o corrupto → exit 3 ("no pude mirar"), nunca 0 con la tabla en ceros.
- `bootstrap.sh` en un entorno no interactivo → como ya no ejecuta el borrado, no hay default
  peligroso que decidir.

## 8. Anti-features (qué NO entra)

- **No se añade ningún gate bloqueante nuevo, con una excepción declarada.** La fase 3a es
  excepción explícita a `f-wf09-ventana-de-valor`: ese finding congela gates que consumen
  presupuesto y necesitan ventana de valor; un `permissions.deny` cuesta 0 ms y no tiene falsos
  positivos medibles. *Sin esta frase escrita, un implementador lee el anti-feature y no pone
  el deny.*
- **No se toca `metrics-report.py`.** Está en NO-TOUCH por una razón concreta: refactorizarlo a
  dispatcher movería métricas que un gate del Anillo 3 ya consume.
- **No entra el aislamiento por worktree.** Es la capa cara; va al `0009` y depende de
  verificar que la opción existe.
- **No se mueven `enterprise/` ni `ios/ android/ web/` a `examples/`.** *Corrección: la versión
  anterior de este PRD alegaba que tocaría `SYNC_PATHS` y las rutas de `install-harness.sh`.
  Los dos costes eran falsos —`SYNC_PATHS` no los menciona y la variable `NUNCA` es inerte
  (`SC2034`)—. El coste real, mayor, es que `tools/lib/scope.sh:109,116` los exime en las dos
  clasificaciones: moverlos re-clasificaría ficheros como producto y cambiaría qué edición
  exige marker de review.* Queda en §16 con el argumento correcto.

## 9. Escenarios golden (deben pasar al terminar)

1. **Dado** un agente que intenta invocar `bootstrap.sh` en la forma exacta del incidente del
   2026-09-03, **cuando** el hook evalúa el permiso, **entonces** se deniega en el Anillo 0.
2. **Límite DECLARADO del deny.** `.claude/settings.json` documenta que las reglas Bash matchean
   **solo por prefijo**. **Dado** el mismo intento escrito como
   `cd scripts && bash bootstrap.sh`, **entonces** el deny **no** lo cubre — y por eso la fase 2
   no es opcional. *Corrección del review: la versión anterior de este golden daba también
   `./scripts/bootstrap.sh` y `sh scripts/…` como no cubiertos, y el review demostró EN VIVO que
   sí lo están. El PRD contradecía a su propio código en el mismo diff — inofensivo para la
   seguridad (subestimaba la cobertura) pero mina la fiabilidad del documento justo en la
   sección que existe para declarar límites con honestidad.* *Este golden no verifica una protección: verifica que el
   límite está escrito, con la misma honestidad que el resto del harness.*
3. **Dado** un proyecto con `backend/src/server.js` y un `ios/` reales, **cuando** se corre
   `bootstrap.sh` y se responde "web", **entonces** no se borra nada: imprime el comando que
   borraría y termina.
4. **Dado** `bootstrap.sh` invocado desde el propio repo del template, **cuando** arranca,
   **entonces** aborta con la precondición — el incidente del 2026-09-03, hecho test.
5. **Dado** un repo donde `check-layers` corrió 5 veces sin objetivos y `check-exec-bits` 3
   veces con 140, **cuando** se ejecuta el lector, **entonces** distingue los dos casos y
   ninguno aparece como "limpio".
6. **Dado** `runs.jsonl` ausente o corrupto, **cuando** se ejecuta el lector, **entonces** sale
   3 y lo declara.

## 10. Métricas de éxito

- **Ningún detector con `targets=0` sostenido sin decisión keep/tune/retire registrada.** Es
  literalmente lo que pide `f-6b761f06`, y la fase 1 lo hace formulable. *La decisión inversa
  —`targets>0` y cero disparos— necesita unificar vocabularios y vive en el `0009`.*
- **Cero borrados de ficheros por una herramienta del harness.** Se declara `n/a-manual — no
  hay detector que cuente el evento; el contador leería findings, no borrados` (§10 permite la
  excepción explícita). Contar findings daría 1 para siempre por `f-970c3590`.

## 11. Rollout

Sin flag. Cada fase es aditiva y mergeable sola.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **El deny de 3a viaja al adoptante y le deniega el paso que `ADOPTION.md` le ordena.** `.claude/settings.json` es SEMILLA en `install-harness.sh`: se copia si no existe. | La fase 3a declara el alcance del deny; si viaja, `ADOPTION.md` gana la nota en el mismo commit. |
| **3a estorba el 🔴 del TDD de la fase 2**: el deny cubre la forma con la que un implementador reproduciría el incidente a mano, y el riesgo es que lo quite para trabajar. | La fase 3a declara que el repro vive **dentro del test** desde el minuto uno: un test no pasa por el permiso de la tool. |
| El lector escribe un segundo parser de JSONL. | `read-events.py` ya normaliza; está en §5 como reúso obligatorio. |

## 13. Open Questions — **ninguna abierta**

> **Las dos OQ de este PRD quedaron cerradas el 2026-09-03 con evidencia del repo.**

**OQ-8 — cerrada. El discriminador es el remote `template`.**
El repo del template tiene **solo `origin`**. Y las dos rutas de adopción crean un remote
llamado `template` **antes** de bootstrap: Caso A lo hace renombrando (`ADOPTION.md:66`,
`git remote rename origin template`) y Caso B añadiéndolo (`ADOPTION.md:90`). Por tanto:

- **existe un remote `template`** → estás en un clon o en un proyecto adoptante → sigue.
- **no existe** → estás en el template, o te saltaste el paso documentado → **aborta**, y el
  mensaje señala la línea exacta de la guía.

Falla seguro en el único caso ambiguo: quien se saltó el rename recibe un abort con la
instrucción, no un borrado. *Descartada la vía que decía la versión anterior —"precondición
copiada de `install-harness.sh:47`"—: esa línea compara DOS rutas (origen y destino) y
`bootstrap.sh` solo tiene una, así que la comparación análoga sería siempre verdadera y
abortaría también en el Caso A, su único uso legítimo.*

**OQ-11 — cerrada. El alcance del `sed` se lo pregunta a git, no a una lista.**
Hoy `bootstrap.sh:26` usa `grep -rlZ --exclude-dir=.git … .`, que recorre el árbol entero:
`node_modules/`, `.venv/`, `vendor/` incluidos. La respuesta NO es una lista de exclusiones
—habría que mantenerla y quedaría desfasada— sino
`git ls-files -z --cached --others --exclude-standard`:

- **`--cached`**: lo que git ya rastrea, o sea lo que el proyecto considera suyo.
- **`--others --exclude-standard`**: lo recién copiado y aún sin commitear, respetando el
  `.gitignore` del adoptante. Esto es imprescindible: en el Caso B, bootstrap corre justo
  después de `install-harness.sh` y los ficheros del harness todavía no están commiteados —
  con `--cached` a secas, el reemplazo de placeholders no los tocaría y bootstrap dejaría de
  hacer su trabajo.

Límite conocido y declarado: un adoptante que **no** ignore `node_modules/` en su `.gitignore`
sigue expuesto, porque entonces esos ficheros son parte de su repo por decisión suya. El
criterio pasa a ser "tocamos lo que TU git considera del proyecto", que es defendible y no
exige mantener ninguna lista.

> **OQ-5 resuelta** el 2026-09-03 por el owner: bootstrap **propone, no ejecuta** (P3).
> **OQ-3 y OQ-6** del PRD original: la 3 la respondió el propio repo (`backlog/run.sh` corre al
> agente dentro del worktree); la 6 se retira porque su contenido pasó al `0009`. Se dejan
> nombradas para que la numeración no tenga huecos sin explicar.

## 14. Mockups / referencias

Estudio de la práctica de 2026: `docs/process/reviews/2026-09-03-paridad-industria.md`.

```
━━━ detectores · últimos 30 días ━━━
  detector                corridas  objetivos  exit≠0    p95
  check-layers                  42          0       0     0s
  check-drift                   42          0       0     3s
  check-exec-bits               42        140       2     0s
  semgrep-scan                  38          —       1     2s   (— = no declarado)
  disparos: n/a (0 filas de detections.jsonl con source de detector)
  ⚠️  check-layers y check-drift: 42 corridas, CERO objetivos.
      Su "errors=0" alimenta un trinquete que solo baja (f-6b761f06).
```

## 15. Definition of Done

**Por fase**, no un checklist único — cada una es mergeable sola:

- **3a**: goldens 1 y 2 · alcance del deny declarado · `ADOPTION.md` si viaja
- **2**: goldens 3 y 4 · `f-970c3590` cerrado · `ADOPTION.md` actualizado en el mismo commit
- **1**: goldens 5 y 6 · decisión registrada sobre los detectores con `targets=0`

Y en las tres: TDD con el test escrito primero · `reviewer` atendido · `check-drift` sin
errores nuevos · `current_execution_map.md` en el mismo commit · ningún fichero por encima del
hard limit de §4 · gitleaks limpio.

## 16. Próximos pasos

- **`0009-el-harness-se-cuenta.md`** — las tres fases con diseño abierto.
- **Sacar `enterprise/` e `ios/ android/ web/` a `examples/`.** Con OQ-5 resuelta el bucle
  destructivo ya no borra, así que el valor bajó — pero sigue siendo nivel 0: si esos
  directorios no están en la raíz del adoptante, el bucle no tiene nada ajeno que proponer
  borrar. Coste real: `tools/lib/scope.sh:109,116` los exime en las dos clasificaciones.
- Ya en el ledger: `f-wf01-ci-macos-intermitente` (77 de los 150 s de la suite), `f-wf04-archivos-sobre-el-limite`, `f-cb48c808`, y la
  variable inerte `NUNCA` de `install-harness.sh`.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-03 | Nace al partir el PRD 0008 original por el remedio de §13, tras dos design-reviews RED. Recoge sus tres fases con diseño cerrado (3a, 2, 1) con los hallazgos aplicados. OQ-5 resuelta por el owner: bootstrap propone, no ejecuta — lo que elimina la heurística de discriminación y dos goldens. | sesión de auditoría |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._
