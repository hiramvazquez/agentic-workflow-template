# PRD — El harness se cuenta

> **Tipo:** Forward · **Status:** Draft — **con tres decisiones de diseño abiertas**
> **Autor:** sesión de auditoría (Claude Opus 5) · **Fecha:** 2026-09-03
> **Design-review:** hereda dos rondas RED del PRD 0008 original. **Este documento agrupa justo lo que hizo que aquellas volvieran rojas**, para que se decida antes de escribir código y no durante.

---

> **Qué es este PRD y por qué no está listo.** El PRD 0008 original juntaba ocho fases. Dos
> rondas de design-review lo dejaron RED por las mismas tres: cada una prometía una fuente de
> datos que el código desmiente. §13 prohíbe una tercera ronda, así que se partió: lo que tenía
> el diseño cerrado se fue a `0008-el-harness-no-borra-codigo.md` y **aquí queda lo que hay que
> decidir**.
>
> **No pasa a `Approved` sin responder OQ-2, OQ-4, OQ-9, OQ-10 y OQ-12.** Un `Approved` hoy
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
| **7** | **Segunda pasada de `AGENTS.md`** (262 → ~120). | OQ-1 |

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

## 10. Open Questions — **todas bloqueantes**

- [ ] **OQ-1 (fase 7).** ¿Qué es irrenunciable en el contexto de cada turno? La guía de la
      industria dice 30 líneas; estamos en 262. Bajar a ~120 exige mover reglas *con detector* a
      la skill del área, y un agente que no cargue esa skill no las verá. **Y arrastra los
      espejos**: `.cursor/rules/*.mdc`, `.codex/config.toml` y `CLAUDE.md` quedarían afirmando
      reglas movidas de sitio, más los tres ficheros donde `test_security_contract` exige la
      misma frase de §6.
- [ ] **OQ-2 (fases 5 y 6, por vías distintas).** ¿La serie y la cola del juez siguen en
      `.agents/state/` (gitignored, local por máquina) o pasan a un sitio versionado? La 5 lo
      necesita para tener histórico compartido; la 6, para que un runner de CI pueda ver la cola.
- [ ] **OQ-4 (la columna de disparos).** ¿De dónde sale la cifra por detector, si los
      vocabularios de `source` son disjuntos? Emitir detecciones desde los detectores es cambio
      de contrato compartido (§9); una tabla de alias es deuda permanente.
- [ ] **OQ-9 (fase 4).** ¿Dónde vive `EXECUTION_MAP_PROD_DIRS` y con qué valor, en un repo cuyo
      producto **es** el harness? Candidato: `tools/project.conf`, con precedencia
      `env > conf > vacío`.
- [ ] **OQ-10 (fase 3b).** ¿Existe la opción de worktree por sub-agente en la versión de Claude
      Code que usamos? Hasta verificarlo, la fase es una apuesta.
- [ ] **OQ-11b (fase 6).** ¿Qué backend, con qué credencial en Actions, y quién paga el diff
      completo cada noche?
- [ ] **OQ-12 (fase 5).** ¿Cuál es el **evento** de cada métrica en ESTE repo? Entrega = ¿commit
      a `main`, o tag? Recuperación = `gh run list`, no `git log`. Retrabajo = regla de
      normalización del campo `area`, o `n/a` con su razón — el mismo tratamiento honesto que se
      le dio a "disparos".

## 11. Definition of Done

Se escribirá al cerrar las OQ. Hoy no se puede: una DoD sobre fases cuyo diseño está abierto
sería un checklist que no verifica nada.

## 12. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-03 | Nace al partir el PRD 0008 original por el remedio de §13, tras dos design-reviews RED. Recoge sus fases con diseño ABIERTO y convierte en OQ bloqueante cada premisa que el código desmintió. | sesión de auditoría |
