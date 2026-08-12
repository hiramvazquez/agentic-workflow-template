# PRD — Reconciliar y simplificar el workflow agéntico

> **Tipo:** Forward · **Status:** In progress
> **Autor:** Codex + owner · **Fecha:** 2026-08-11 · **Tracking:** commits de las fases 1a–10
> **Design-review:** OK (2026-08-11) — AMBER final atendido antes de aprobación

---

## 1. Contexto

En el snapshot auditado el 2026-08-11, el harness tenía tres anillos operativos, evidencia ligada
al diff y 347 pruebas de regresión,
ledger de findings, backlog headless y validación en un adoptante real. Una auditoría conjunta de
documentación y código encontró que el núcleo mecánico es fuerte, pero varias afirmaciones
operativas ya divergieron de lo que el repositorio realmente hace.

La auditoría ejecutó los scripts reales. En el snapshot local del 2026-08-11 la suite terminó con
345 pruebas verdes y 2 fallos porque el binario de Semgrep existe pero revienta al inicializar su almacén X509. El
health-check superficial lo clasificaba como “instalado”; el selftest sí descubrió que estaba
mudo. También se encontraron promesas más amplias que su implementación, scope del backlog solo
advisory, automatización acoplada a `claude -p`, métricas que suman fuentes no deduplicadas y un
coste de contexto excesivo por leer, en ese snapshot, 1.271 líneas de lecciones en cada tarea.

## 2. Problema

El harness combate la falsa confianza, pero hoy contiene ejemplos de ella:

- documentación que llama opcional al Anillo 3 aunque `full` lo exige;
- conteos y estados de salud hardcodeados que caducan;
- “instalado” confundido con “operativo”;
- un check de imports directos descrito como grafo con ciclos y complejidad;
- `scope`/`NO-TOUCH` del backlog sin veredicto mecánico;
- caminos autónomos y review de CI dependientes de Claude;
- una tasa de escape que puede contar dos veces el mismo defecto;
- reglas universales de seguridad/tests demasiado ambiguas o prescriptivas;
- lectura obligatoria de contexto histórico que ya está mecanizado.

Si no se corrige, los adoptantes pagan ceremonia y tokens por garantías que en algunos clientes
no existen o no significan exactamente lo anunciado. Eso erosiona la confianza y termina en la
desactivación de los gates correctos junto con los defectuosos.

## 3. Objetivo

Dejar un workflow cuya documentación, health-checks, automatización y métricas describan y
demuestren exactamente sus garantías; con scope mecánico para runs autónomos, backends de agente
intercambiables y un coste de contexto proporcional al área tocada.

Resultado medible:

1. cero divergencias en las afirmaciones operativas enumeradas en el manifiesto de capacidades;
2. health-check capaz de distinguir ausente, instalado-roto y operativo;
3. ningún run de backlog llega a `in-review` con paths fuera de scope;
4. cada capacidad arquitectónica declara `operational|missing|broken|unsupported` por stack;
5. backlog y AI review funcionan contra un runner fake sin tener `claude` instalado;
6. métricas cuentan defectos únicos dentro de una ventana explícita;
7. el arranque normal carga únicamente `lessons_learned.md` después de ejecutar la rotación
   existente y no carga el archivo histórico por defecto;
8. suite hermética y selftest verdes en macOS y Linux; el smoke del entorno real puede resultar
   `missing|broken`, pero debe clasificarlo honestamente y nunca producir un falso verde.

## 4. Filosofía / principios

1. **Capacidad demostrada > promesa uniforme.** Un adaptador puede declarar `unsupported`; nunca
   se convierte en verde por no existir.
2. **Compatibilidad por entrypoint.** Los scripts públicos existentes se conservan; la nueva
   implementación vive detrás de contratos pequeños y testeables.
3. **Menos contexto, mismas garantías.** Lo mecanizado lo recuerda el detector; el agente carga
   solo el documento vivo después de aplicar la rotación existente.

## 5. Estructura de archivos a crear / tocar

```text
AGENTS.md                                           ← reglas de seguridad, tests, contexto y claims
README.md                                           ← alcance real, anillos y conteos dinámicos
docs/ADOPTION.md                                    ← CI full obligatorio y runner configurable
docs/ONBOARDING-IA.md                               ← salud funcional y estado real
docs/PLAYBOOK.md                                    ← flujo diario actualizado
docs/process/current_execution_map.md               ← estado de esta iniciativa
docs/process/lessons_learned.md                     ← nuevas lecciones con detector
docs/process/prds/0004-reconciliar-workflow-agentico.md
.agents/skills/process/SKILL.md                     ← ruta correcta del backlog
.agents/skills/process/references/*.md              ← garantías y criterios corregidos
.claude/agents/*.md                                 ← CLI del ledger y contrato portable
.codex/* · .cursor/*                                ← claims de capacidades reales
ci/README.md · ci/run-gates.sh · ci/ai-review.sh   ← semántica CI y runner desacoplado
scripts/agent-hooks/session-start.sh                ← contexto vivo reducido y salud funcional
tools/capabilities.json                             ← NUEVO: fuente estructurada de capacidades
tools/render-capabilities.sh                       ← NUEVO: genera/verifica fragmentos operativos
tools/validate-harness.sh                           ← probes funcionales
tools/harness-report.sh                             ← evidencia con entorno/commit/fecha
tools/backlog/scope-check.sh                        ← NUEVO: scope/NO-TOUCH mecánico
tools/backlog/run.sh                                ← exige scope antes de in-review
tools/architecture-check.sh                         ← NUEVO: contrato de capacidades por stack
tools/architecture.conf.example                     ← NUEVO: contrato de adaptadores opt-in
tools/check-layers.sh                               ← baseline honesto de imports directos
tools/agent-runner.sh                               ← NUEVO: interfaz de ejecución/review
tools/agent-backends/claude.sh                      ← backend existente aislado
tools/agent-backends/fake.sh                        ← backend hermético para pruebas
tools/agent-prompts/backlog.md                      ← prompt portable y transportable del run
tools/agent-prompts/review.md                       ← contrato portable de review read-only
tools/metrics/escape-rate.sh                        ← defectos únicos + ventana
tools/metrics/gate-value.sh                         ← coste, FP y denominadores honestos
tools/lessons-rotate.sh                             ← aplicar la rotación viva/archivo existente
tools/gate-cache.sh                                 ← NUEVO: caché ligada a staged SHA
tools/findings/findings.sh                          ← promoción explícita detección→finding
tools/findings/README.md                            ← lifecycle de métricas/findings
tools/upgrade.sh                                    ← transporte de archivos nuevos
scripts/agent-hooks/lib/io.sh                       ← eventos v2 sin fingir triage
tools/tests/test_*.sh                               ← regresiones y falsos positivos de cada fase
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```text
ios/**                                             ← código/plataforma de referencia fuera de scope
backlog/000*.md                                    ← historias de ejemplo
tools/drift-ratchet.json                           ← solo su script puede actualizarlo
tools/mutation-ratchet.json                        ← solo su script puede actualizarlo
.gitleaks-baseline.json · .gitleaks.toml           ← sin cambio de política de secretos
.git/**                                            ← salvo commits normales por fase
docs/process/prds/0001-*.md .. 0003-*.md           ← histórico inmutable
```

## 5b. Fases entregables

| Fase | Entrega mergeable | Depende de | Historia backlog |
|---|---|---|---|
| 1a | Manifiesto de capacidades + renderer/check de fragmentos exactos | — | n/a |
| 1b | Migrar README/ADOPTION/CI al manifiesto; rutas y CLIs obsoletos | 1a | n/a |
| 1c | Eliminar conteos manuales y generar evidencia de suite/FILLs | 1a | n/a |
| 2a | Probe funcional común + huella de entorno/commit/fecha | 1a | n/a |
| 2b | Clasificación Semgrep `missing|broken|operational` y diagnóstico X509 | 2a | n/a |
| 3a | Contrato y parser de scope desde frontmatter únicamente | — | n/a |
| 3b | Integración de `scope-check` antes de `in-review` | 3a | n/a |
| 4a | Renombrar/documentar el baseline real de imports directos | 1b | n/a |
| 4b | Contrato de adaptadores y estados explícitos para ciclos/complejidad | 4a, 2a | n/a |
| 5a | Semántica fail-closed/fail-loud de seguridad | 1b | n/a |
| 5b | DbC/tests/criterio PRD guiados por riesgo e invariantes | 5a | n/a |
| 6a | Contratos separados `run`/`review` + backend fake | 2a | n/a |
| 6b | Backend Claude y migración de backlog/CI | 6a | n/a |
| 7a | Lifecycle y esquema de eventos v2 con lectura mixta v1/v2 | 2a | n/a |
| 7b | Escape-rate desde findings únicos; gate-value desde eventos | 7a | n/a |
| 8 | Ejecutar/fijar rotación existente y reducir obligación de lectura | 1b | n/a |
| 9 | Caché verde solo para Semgrep staged, con key y escritura atómicas | 2b | n/a |
| 10 | Matriz E2E y cutover documental, sin comportamiento nuevo | 1a–9 | n/a |

Cada fila es un commit coherente. Si una fase crece, se divide; no se mezclan naturalezas para
“terminar antes”.

## 6. Modelo de datos / contratos

### Manifiesto y resultado de capacidad

```json
{"schema":1,"capabilities":{"ring3":{"required_in_full":true},"architecture_cycles":{"provider":"external","required":false}}}
```

Los probes emiten JSONL seguro y parseable:

```json
{"capability":"semgrep","status":"operational","detail":"2.1.0"}
```

- `missing`: falta una dependencia/configuración que sí debería existir.
- `broken`: existe pero su probe funcional falla.
- `unsupported`: el backend/stack declara honestamente que no ofrece la capacidad.
- solo `operational` cuenta como defensa activa.
- `unsupported` es informativo únicamente si el manifiesto declara `required:false`; si es
  obligatorio en el preset activo, equivale a fallo de configuración.
- contrato de exit codes: `0` = todas las capacidades requeridas operativas; `1` = capacidad
  requerida ausente/rota/no soportada; `3` = el clasificador no pudo evaluar.
- README, ADOPTION y CI contienen bloques delimitados generados por `render-capabilities.sh`;
  el check compara esos bloques exactos, no intenta entender prosa libre.

### Runner de agente

```text
tools/agent-runner.sh run --prompt-file <path> --cwd <path>
tools/agent-runner.sh review --prompt-file <path> --base <ref> --head <ref> --cwd <path>
```

`run` y `review` son contratos distintos:

- `run`: stdout opaco del agente, stderr diagnóstico, y propaga el exit code del backend. No
  exige ni interpreta `VERDICT`.
- `review`: stdout es el texto que termina en `VERDICT/FINDINGS/SCOPE`; ausencia o valor inválido
  devuelve 1. Diagnósticos van a stderr.
- ambos validan que `cwd`, prompt y refs estén dentro del repo; esperan el proceso, propagan
  timeout/cancelación y nunca usan `eval` ni dejan hijos en background.
- el backend declara `run`, `review`, `read_only`, `subagents` y `hooks`. El backlog autónomo exige
  las cinco: `hooks+subagents` preservan la review previa a **cada** commit que exige `AGENTS.md
  §13`; al finalizar, el orquestador ejecuta además `review+read_only` sobre el rango completo,
  valida la salida y guarda evidencia observable antes de `in-review`. Un backend sin esas
  capacidades se rechaza como `unsupported`, no se degrada silenciosamente. Review CI requiere
  `review+read_only`.
- selección única: `--backend <nombre>`; si se omite, el default es `claude`. No hay config ni
  variables de entorno implícitas para cambiar de proveedor. El nombre se valida contra un
  allowlist de adapters bajo `tools/agent-backends/`, nunca se interpreta como path libre.
- `--prompt-file` recibe maquinaria común transportable: `tools/agent-prompts/backlog.md` para
  `run` y `tools/agent-prompts/review.md` para `review`. Los adapters no dependen de prompts
  compartidos `report-only` bajo directorios específicos de un cliente.
- backlog concatena literalmente el prompt común y la historia en un archivo temporal validado y
  lo entrega a `run`; CI concatena literalmente `review.md` y las refs ya validadas y lo entrega a
  `review`. No existe evaluación de templates, sustitución de shell ni `eval`.
- la prueba E2E instrumenta el fake y el hook: para cada commit de producto registra primero el
  SHA del diff staged que aceptó `check-review-marker.sh`, y rechaza cualquier commit sin una
  evidencia previa para ese mismo SHA. Una review final jamás valida commits retroactivamente.
- el boundary de confianza se declara: prompt/diff pueden salir al proveedor; secretos y
  credenciales nunca se incluyen en logs, y los reportes pasan por la redacción existente.

### Evento métrico v2

```json
{"schema":2,"event_id":"...","ts":"...","phase":"gate","source":"semgrep","duration_ms":123,"commit":"...","triage":"unknown"}
```

Un gate solo conoce una detección, no un defecto durable ni si fue true-positive. El lifecycle es:

```text
detección(event_id, triage=unknown) → triage humano/agente → finding durable(source_event_ids[])
```

`findings.sh add/import` puede recibir `--source-event`; ese vínculo promociona la detección sin
reescribir el evento. `escape-rate` cuenta IDs del ledger dentro de una ventana explícita y usa
eventos solo para actividad/latencia. Lectores aceptan JSONL v1 y v2; v1 queda como `triage=unknown`.

### Scope del backlog

Fuente única: `scope: |` del frontmatter. “Fuera de scope” sigue siendo explicación humana y no
se parsea. Contrato:

```text
scope-check.sh --story <path> --base <ref> --head <ref> --worktree <path>
```

- inspecciona `base...head`, índice, modificaciones y untracked del worktree;
- en renames valida origen y destino; incluye deletes;
- allowlist cerrada: solo el propio archivo de historia es automático. Tests, implementación,
  ledger JSONL y su vista generada deben estar enumerados en `scope`; no se afirma procedencia
  del CLI cuando Git solo permite demostrar qué bytes cambiaron;
- globs se evalúan sobre paths relativos normalizados, sin escapar del repo;
- antes del run, checker e historia deben estar limpios y commiteados; el orquestador fija sus
  blobs en memoria y reduce la base a OID, por lo que la rama evaluada no puede reescribir al juez,
  ampliar su propia allowlist ni mover la referencia base para ocultar el rango. También fija las
  rutas absolutas de Bash, Python y Git para que un ejecutable añadido luego a `PATH` no suplante
  al gate;
- `0` limpio, `1` path fuera de scope, `3` no pudo resolver story/base/head/worktree.

### Upgrade: propiedad y estrategia

| Familia | Propietario | Sync sin ancestro | Merge con ancestro |
|---|---|---|---|
| scripts/tools y prompts de maquinaria nuevos | template | reemplaza salvo marcador FILL | merge normal |
| `tools/capabilities.json` y defaults `.example` | template | reemplaza | merge normal |
| config local sin `.example`, ratchets, AGENTS, skills | adoptante | report-only | merge normal |
| README/docs/agentes por cliente | compartida | bloque generado se funde; resto report-only exacto | merge normal |
| settings JSON | compartida | merge estructural solo-añade existente | merge normal |

`test_upgrade.sh` crea un template con cada familia y demuestra que el adoptante recibe toda la
maquinaria necesaria, conserva su contenido y obtiene un informe exacto de lo report-only.

## 7. Flujo de la solución

### User stories

- Como owner quiero que cada defensa declarada tenga una prueba funcional para saber qué existe.
- Como agente quiero cargar el documento vivo ya rotado, no todo el archivo histórico.
- Como operador de backlog quiero que un path fuera de scope bloquee antes de `in-review`.
- Como equipo no-Claude quiero reutilizar el harness sin reescribir su automatización.
- Como responsable de calidad quiero métricas basadas en defectos únicos, no en volumen de eventos.

### Edge cases

- binario presente que revienta antes de emitir salida parseable;
- stack que no soporta ciclos/complejidad y lo declara explícitamente;
- scope con globs, archivos borrados/renombrados y archivos obligatorios del harness;
- runner ausente, salida sin contrato, timeout y backend que termina con trabajo pendiente;
- mismo defecto detectado varias veces o en varias máquinas;
- caché Semgrep con misma diff pero reglas/binario/HEAD/plataforma distintos;
- proyecto nuevo sin historial de métricas ni lecciones vivas después de la rotación.

## 8. Anti-features

- No implementar analizadores AST completos para todos los lenguajes dentro de Bash.
- No introducir un proveedor obligatorio de CI o de modelos.
- No prometer protección contra un agente adversarial con acceso al mismo filesystem.
- No habilitar sandbox, fuzzing, métodos formales, SBOM, SLSA u OpenTelemetry.
- No cambiar la arquitectura de producto iOS ni sus reglas específicas.
- No eliminar `full`/`lite` ni relajar gates mecánicos existentes.

## 9. Escenarios golden

1. Dado un bloque operativo generado que diverge del manifiesto, `renderer --check` falla sin
   intentar interpretar la prosa libre que lo rodea.
2. Dado un ejecutable Semgrep presente pero roto, el health-check informa `broken`, nunca verde.
3. Dada una historia cuyo diff toca un path fuera de `scope`, el runner no marca `in-review`.
4. Dado un stack sin detector de ciclos, arquitectura informa `unsupported`, no “sin ciclos”.
5. Dado el backend `fake.sh`, backlog demuestra evidencia de review anterior a cada commit de
   producto, ejecuta una review read-only final y solo entonces llega a `in-review`; AI review
   completa el mismo contrato sin instalar Claude.
6. Dado el mismo defecto en ledger y telemetría, escape-rate lo cuenta una sola vez.
7. Después de aplicar la rotación existente, el arranque carga solo `lessons_learned.md` reducido
   y no carga `lessons_archive.md` por defecto.
8. Dado el mismo staged diff y los mismos HEAD/reglas/binario/plataforma, Semgrep reutiliza un
   resultado verde; cualquier cambio invalida, y exits 1/3 nunca se cachean.
9. Dado preset `full`, la iniciativa no reduce reviewer, seguridad, TDD, mutación, DbC, secretos,
   ratchets, capas, build ni CI; no se añade autoclasificación de riesgo.
10. En macOS y Linux, las pruebas herméticas del clasificador pasan; los smoke tests reales pueden
   declarar una dependencia `missing|broken` sin confundirla con un bug del clasificador.

## 10. Métricas de éxito

- cero divergencias entre manifiesto y bloques operativos generados;
- 100% de dependencias críticas con probe funcional;
- 100% de runs `in-review` con scope verificado;
- cero capacidades arquitectónicas inferidas desde ausencia de configuración;
- tests E2E contra `fake.sh` y `claude.sh` conectado a un stub hermético del CLI; el smoke contra
  Claude real es opcional y se reporta por separado;
- tasa de duplicados de defectos en métricas = 0;
- contexto obligatorio de arranque ≤250 líneas fuera de la skill del área;
- tiempo de gates repetidos sobre el mismo diff reducido ≥30% sin perder detección;
- cero regresiones en todos los tests preexistentes, comparados por nombre y resultado.

## 11. Rollout

1. Entrypoints y formatos actuales se mantienen durante todas las fases.
2. Nuevos contratos se introducen con fallback explícito y aviso de deprecación cuando aplique.
3. `tools/upgrade.sh` transporta maquinaria/defaults y reporta contenido compartido según la
   matriz anterior; su test se actualiza en cada fase con archivos nuevos.
4. Primero se valida en este template, después en el adoptante iOS supervisado.
5. Rollback por commit de fase; no hay migración irreversible.

## 12. Riesgos

- **Más tooling para reducir tooling.** Mitigación: cada archivo nuevo sustituye duplicación medible
  y tiene criterio de retiro; no se añade una abstracción sin dos consumidores reales.
- **Scope gate ruidoso.** Mitigación: corpus bueno/malo y escape explícito auditado para archivos
  obligatorios, nunca glob abierto.
- **Métrica v2 sin datos históricos completos.** Mitigación: reporte `unknown`, no imputación.
- **Caché acepta evidencia stale.** Mitigación: solo Semgrep staged, solo verde; key incluye diff,
  HEAD, reglas transitivas, hash del ejecutable, versión, plataforma y TTL; escritura atómica con
  rename. Nunca cachea exit 1/3, review, CI, red/historial/tiempo ni sustituye markers.
- **Portabilidad al mínimo común denominador.** Mitigación: contrato común pequeño y capacidades
  opcionales, sin ocultar las ventajas específicas de cada cliente.

## 13. Open Questions

- [x] ¿Se autoriza tocar tooling/meta-doc compartido? Sí — el owner indicó “adelante” sobre el
  plan completo el 2026-08-11.
- [x] ¿Se implementarán analizadores reales para todos los stacks? No — se implementa el contrato
  de capacidades y adaptadores; cada stack trae el suyo.
- [x] ¿Se preservan `full` y `lite`? Sí; este PRD no introduce perfiles de riesgo ni cambia la
  semántica de los presets existentes.
- [x] ¿Se introduce algún perfil de riesgo? No. Cualquier propuesta futura que cambie ceremonia
  o reglas canónicas requerirá una decisión explícita del owner fuera de este PRD.
- [x] ¿Cómo obtiene identidad durable un evento temprano? No la inventa: el ledger enlaza uno o
  varios `event_id` durante el triage y es la única fuente para escape-rate.
- [x] ¿Qué cachea la primera versión? Únicamente resultados verdes de Semgrep staged.
- [x] ¿Qué necesita un backend compatible? Backlog=
  `run+review+read_only+subagents+hooks`; CI review=`review+read_only`; cwd/prompt validados,
  espera síncrona, timeout y stdout/stderr/exit según contrato. Solo existe `--backend`; el
  default explícito es `claude`.

No quedan preguntas bloqueantes para `Approved` si el design-review valida el approach.

## 14. Mockups / referencias

```text
manifest ──► renderer --check ──► fragmentos operativos + probes funcionales
                                           │
historia ──► agent-runner ──► diff ──► scope-check ──► gates ──► in-review
                                           │
                                           └── eventos v2 ──► métricas deduplicadas
```

## 15. Definition of Done

- [ ] Escenarios golden 1–10 pasan.
- [ ] Cada fase tuvo regresión roja antes de implementación y guards de falso positivo.
- [ ] Pruebas herméticas verdes en macOS/Linux; smoke real reporta capacidades sin falsos verdes.
- [ ] `bash tools/check-drift.sh` sin errores nuevos.
- [ ] Design-review y reviews de cada fase atendidos.
- [ ] Tooling transportado y docs/skills/config compartida transportados o reportados exactamente
  según la matriz de propiedad de upgrade.
- [ ] Sin secretos; gitleaks limpio.
- [ ] Findings descubiertos cerrados o aceptados con razón en el ledger.

## 16. Próximos pasos

Tras 2–4 semanas en el adoptante, medir reducción de contexto, tiempo de gates, falsos positivos
y defectos escapados antes de retirar o endurecer cualquier defensa.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-11 | Draft inicial a partir de auditoría documental + ejecución real | Codex |
| 2026-08-11 | Corrige 9 bloqueantes del design-review: contratos, upgrade, scope y fases | Codex |
| 2026-08-11 | Elimina contradicciones de claims, review portable, rotación y perfiles | Codex |
| 2026-08-11 | Exige evidencia pre-commit portable y cierra selección/prompts del runner | Codex |
| 2026-08-11 | Atiende AMBER final: flujo literal y único de prompts run/review | Codex |

## 18. Gaps detectados

Se llenará durante la implementación. Todo gap accionable irá al ledger y toda lección nueva
citará su detector o una excepción manual explícita.
