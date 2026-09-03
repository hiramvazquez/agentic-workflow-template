# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** el template está **en producción contra un adoptante real** (un proyecto iOS/Swift 6).
  Ese bucle —el adoptante sincroniza, usa el harness, reporta lo que falla, se arregla AQUÍ y
  vuelve a bajar— es el flujo de trabajo actual, no una fase de pruebas.
- **En curso:** **PRD 0005 (estabilización del harness)**, Approved. Entregadas 0a, 0b, 0c, 1a, 1b,
  1c, 2b y **2a parcial (2026-08-25)**: las cuatro divisiones que estaban rescatadas en worktrees
  (test_backlog, test_e2e_matrix, test_lessons y validate-harness → orquestador + libs en
  `tools/lib/`) se integraron a main por orden del owner, con la suite completa verde, cero tests
  perdidos (los nombres `test_*` de cada monolito y de su división coinciden exactamente) y las
  citas `Detector:` del archivo de lecciones re-apuntadas + índice regenerado con el rotador.
  La **fase 3 corrió parcialmente el 2026-08-24** —informe en
  `docs/process/reviews/2026-08-24-valor-por-gate-fase3.md`— y le falta una segunda pasada: lo
  primero que encontró fue que los gates **no registraban cuando bloquean**, así que no hay base
  para decidir sobre los mecánicos hasta que la telemetría (ya arreglada) acumule ventana. De la
  **2a queda su mitad de más riesgo**: `upgrade.sh` (restricción de bootstrap, PRD 0005 §6) y el
  resto de archivos sobre el límite; `f-wf04-archivos-sobre-el-limite` los lista y trae el comando
  que los recalcula — no los cuentes desde aquí.
- **El diff de la fase 3 llegó a commiteable el 2026-08-24, en la cuarta ronda.** Venía de **tres
  rondas en RED**, todas por la misma causa: afirmar cobertura que no se verificó (`f-20ed9b44`,
  abierto — es owner-decision, la pregunta es qué cambio de proceso evita la cuarta). Cerrados
  `f-2bd11525` (las tres primitivas de bloqueo de `lib/io.sh` instrumentadas en un punto común, con
  el git-guard cubierto de punta a punta) y `f-658e2533` (contradicción del gate KMP + tasa vieja
  del reviewer). Lo que cambió respecto de las tres rondas anteriores no es el parche: es que **la
  afirmación de cobertura pasó a ser un test** que relee `io.sh` y deriva las primitivas en vez de
  listarlas. Lección rotada al archivo con su detector.
- **El `process-judge` YA CORRIÓ (2026-08-25):** su cola se procesó y de ahí salieron los dos
  commits de esa mañana — el contexto del juez dejó de fingir que miraba la trayectoria
  (`2196f43`) y el nivel 1 dejó de ser ciego a lo que se escribe por Bash (`0072188`, motivado
  por el dato del juez: casi todo el trabajo de una sesión medida entró por Bash y
  `post-edit-verify` no corrió ni una vez). Abrió además `f-6d4e01b8` y `f-a5f3e17c`.
- **ORDEN vigente:** ~~cola del `process-judge`~~ (hecha) → **segunda pasada de la fase 3**
  (espera a que la telemetría de bloqueos acumule ventana; no es trabajo de máquina sino de
  medición) → **resto de la fase 2a** (`upgrade.sh` y demás — la parte con restricción de
  bootstrap). La integración parcial de 2a del 2026-08-25 fue orden explícita del owner sobre
  trabajo ya escrito y verificado, no un adelanto de la fase congelada: no añade gates y el
  freeze de gates nuevos sigue vigente.
- **UN gate sigue abierto, y conviene separar sus dos mitades porque se confunden.** El gate de 0a
  pedía **30 corridas macOS seguidas sin rerun**. En CI no llegó a correr: los dos runs despachados
  (2026-08-19) murieron en 5s por presupuesto de Actions (`gh run list --workflow=gate-0a-macos.yml`).
  Pero el **plan B sí corrió** —el bucle en el Mac del owner, que PRD 0005 §5b acepta explícitamente
  como vía válida— el **2026-08-24**, con resultado **29 verdes y 1 rojo** (corrida 9,
  `test_review_timeout_tambien_mata_descendientes`). De ahí las dos mitades: el **gate literal NO se
  cumple** (29 ≠ 30) y por eso sigue abierto; pero la **hipótesis de la fase 0a queda REFUTADA** —se
  atribuía el flaky a presión de spawn en runners de pocos núcleos y una máquina en reposo lo
  reprodujo igual—. Fuente de los dos hechos: `f-wf01-ci-macos-intermitente` en el ledger y el
  mensaje del commit `206bc16`; no los cuentes desde aquí.
  **Este párrafo llegó a afirmar que ese 29/30 era una cifra fabricada** que "no existe en ningún
  commit, PRD, ledger ni artefacto de CI". Era falso y estaba a un `grep` de distancia: la búsqueda
  se hizo por la grafía `29/30` y la fuente dice `29 verdes`. Una búsqueda encuentra lo que hay con
  la grafía que buscas — **nunca demuestra que algo no exista** (`f-6c1a0f6a`). El FP contra corpus
  KMP ajeno de 1c **está CERRADO desde el 2026-08-22** (PRD 0005 §5b). El detalle por fase vive en
  el PRD, no aquí.
- **Antes:** **PRD 0004 (reconciliación del workflow agéntico) está Shipped**: fases
  1a–10 mergeadas. Qué dejó, en una frase por bloque — el detalle vive en el PRD, no aquí:
  manifiesto de capacidades que gobierna los bloques documentales; probes funcionales que
  distinguen ausente / roto / operativo; scope mecánico del backlog antes de `in-review`;
  estados explícitos de las capacidades arquitectónicas; boundary portable `agent-runner` con
  backends intercambiables; eventos v2 y findings con lifecycle separado (detectar ≠ defecto);
  rotación de lecciones que dejó el contexto obligatorio dentro del límite que fija y mide
  `test_contexto_vivo_obligatorio_cabe_en_250_lineas` (`tools/tests/test_lessons_presupuesto_contexto.sh`) — la
  cifra real la imprime ese test, no este doc; caché de Semgrep staged solo para verde.
  **Fase 10 cerró el ciclo con la matriz E2E** (hoy dividida en los `tools/tests/test_e2e_*.sh`):
  un test por escenario golden, atado al PRD por un test que falla si la lista y su demostración
  divergen. Al construirla salieron tres huecos que ninguna fase anterior podía ver —el Anillo 3
  no tenía test propio, `claude.sh` declaraba `read_only` sin demostrarlo y la promesa de ≥30% de
  la caché no se medía— y los tres quedaron cubiertos (PRD 0004 §18).
- **Salud:** el total de la suite lo imprime `bash tools/tests/run-tests.sh` en cada corrida;
  no se copia aquí porque un conteo literal caduca solo y este doc se inyecta con autoridad en
  cada arranque (`f-wf02-mapa-cifras-podridas`). El estado por gate NO se apunta aquí
  a propósito —caduca y se lee como garantía permanente—: lo dice `session-start` en cada
  arranque y `bash tools/validate-harness.sh --selftest` cuando lo preguntes. El único hecho de
  entorno que conviene recordar porque confunde: **la capacidad runtime de Semgrep en esta
  máquina está `broken`** (su binario revienta al inicializar X509), y eso NO es un fallo del
  clasificador — la fase 2 separa ambos hechos justamente para que un clasificador verde no se
  lea como entorno verde.

## Cómo se trabaja aquí (el bucle, no la historia)

1. El adoptante corre `bash tools/upgrade.sh`, usa el harness y manda un informe de lo que
   falló, con la medición.
2. El arreglo se hace **en el template**, con su test **verificado fallando contra la versión
   anterior** — no basta con que el test pase.
3. Lección en `lessons_learned.md` (con `Detector:`) + entrada en el ledger, en el mismo cambio.
4. **Antes de invocar al `reviewer`, mira la naturaleza del lote:**
   `bash tools/check-diff-nature.sh` — **sin flags**, que es el modo `--staged`. NO uses
   `--range`: compara `BASE...HEAD` y por construcción no ve lo que está staged sin commitear,
   o sea justo lo que vas a mandar a revisar. Esta línea nació diciendo `--range` y su
   "verificación" salió limpia por eso mismo: un falso verde producido por el flag equivocado,
   dentro del paso escrito para evitar falsos verdes. Si avisa, **parte el lote
   antes de la primera review, no después de la tercera**. No es ceremonia: el lote de la fase 3
   disparó ese aviso, no se partió, y el coste está medido en `f-15089319` — no lo copies aquí, que
   es justo la clase de cifra que se pudre (`f-wf02-mapa-cifras-podridas`). La cabecera del propio
   script trae su propio dato y su racional: partido por naturaleza, GREEN a la primera.
5. **Stagea por paths**, nunca `-A` a ciegas: `git add <los archivos del cambio>` →
   `bash tools/verify-run.sh` → `git commit` (comandos separados: el marker liga
   `sha256(diff staged)` y encadenarlos lo evade) → `git push`. `git add -A` solo tiene
   sentido cuando `git status --short` ya salió limpio de todo lo demás, y entonces no
   ahorra nada. Este doc recomendaba `-A` mientras AGENTS.md §7 lo prohíbe con cambios
   fuera de scope (`f-wf08-git-add-A-canonico`): el mapa contradecía la regla canónica desde la puerta de
   entrada de cada sesión.
6. El adoptante sincroniza y **verifica en su repo**, que es la única verificación
   independiente que existe: quien escribe el arreglo no es quien lo aprueba (§14).

## Próximo paso

> **2026-09-03 — auditoría de dos días y PRD 0008 en curso.** El harness entregó: selftest de
> rutas (los detectores demuestran que ven aunque el harness cambie de sitio), registro de
> ejecución en los 7 detectores, suite en paralelo (medido: 379 s → ~150 s, commit `09c7638`),
> recorte de `AGENTS.md` moviendo el racional a `docs/process/agents-rationale.md` (commit
> `587164b`; el tamaño lo mide `wc -l AGENTS.md`, no se copia aquí), instalador que no destruye
> el proyecto adoptante (`1f958b5`), y el arreglo de portabilidad del `stat` que tenía CI en
> rojo (`1d021cc`). **CI verde.**
>
> **PRD 0008 — "El harness no borra código".** Nació al partir un PRD mayor tras dos
> design-reviews RED (§13: la tercera no se revisa, se parte). Su gemelo,
> `0009-el-harness-se-cuenta.md`, agrupa lo que sigue con decisiones de diseño abiertas y
> declara que no puede tener DoD todavía.
>
> **Fase 3a ENTREGADA:** `permissions.deny` deniega invocar `bootstrap.sh` — el comando con el
> que un sub-agente borró ficheros de este repo el 2026-09-03. Verificado EN VIVO, no solo por
> test. Límite declarado: el matching de Bash es por prefijo, así que no cubre
> `cd scripts && bash bootstrap.sh`; esa mitad la cierra la fase 2.
>
> **Fase 2 ENTREGADA:** `bootstrap.sh` ya no borra — propone el comando y deja la decisión al
> adoptante (OQ-5). Precondición que aborta si no hay remote `template` (OQ-8). Reemplazo de
> placeholders acotado a `git ls-files` (OQ-11). Cierra `f-970c3590`. Y al reescribir ese
> bloque salió un bug preexistente peor: `grep -lZ` alimentando un `read -d ''` no itera en
> BSD, así que bootstrap **nunca reemplazó los placeholders en macOS** anunciando que sí —
> registrado, arreglado, y con detector nuevo para la clase.
>
> **Siguiente:** fase 1 (lector del denominador).


- **DECISIÓN DEL OWNER 2026-08-24 — el freeze de gates nuevos (PRD 0005 §3) sigue VIGENTE y se
  cumple.** El motivo está medido, no intuido: desde el 19 de agosto el ledger abre 2–3× más
  hallazgos de los que cierra mientras los commits/día caían de 13–17 a 2–3. El proyecto pasó de
  construir a auditar. **No se añaden gates.** PRD 0006 (inversión a fail-closed de la superficie
  de enforcement) queda On hold pese a cerrar un agujero vivo, y sus vías 8 y 9 quedan como
  findings documentados.
- **PRD 0007 — Approved COMPLETO (owner, 2026-08-25).** La ronda 1 del design-review dio RED (15
  hallazgos) y acotó el Approved a las fases 0–1; la ronda 2 sobre la v2 dio AMBER, verificó los
  tres bloqueantes cerrados y recomendó aprobar 2–3; la v2.1 aplicó su re-cosido (incluido N1: el
  gate de fase 2 se cumplía solo) y el owner extendió el Approved el mismo día. Todas las Open
  Questions resueltas — Q4 (retroactivo) se resuelve en la fase 0 de cada proyecto, Q6 (techo de
  fuego) = tres. El arranque real de un proyecto: decisiones de arquitectura escritas (como
  ADRs ampliados), un módulo de referencia que las instancia (fase 1 partida en contrato→lógica→
  vertical, con `security-reviewer` en el gate), el harness cableado, y un criterio falsable de
  autonomía (dos verticales autónomas consecutivas con `ARCH_DEVIATIONS: 0`; cierre MANUAL
  declarado hasta que el consumidor de esa línea exista — §9 del PRD). **v2.2 el mismo día:** una
  auditoría externa (informe en `docs/process/reviews/2026-08-25-auditoria-prd-0007-workflow.md`)
  confirmó que dos fixes de las rondas introdujeron problemas nuevos (la evidencia TDD imposible
  de 1b y el waiver `pending` sin tipar) más tres contradicciones residuales; los ocho hallazgos
  están en el ledger y la v2.2 cerró los seis del PRD. La ronda 3 verificó la v2.2 contra el
  criterio de cierre de la auditoría (cinco de siete condiciones) y la **v2.3** remató las dos
  restantes con cuatro decisiones más del owner — Q8/§12 re-cosidos y la evidencia de fase 3
  promovida a `docs/process/reviews/` fechado; el detalle, en el change log del PRD. Las dos rondas de design-review tienen
  copia durable en `docs/process/reviews/2026-08-25-design-review-prd-0007.md` (los reportes del
  hook son gitignored — `f-35ef4b81`).
  **Corrección de este mapa (F3):** la frase que decía "no es un gate, no choca con el freeze" era
  mecánicamente falsa — `check-decision-coverage.sh` SÍ es un gate (el glob `tools/check-*.sh` lo
  clasifica) y queda **condicionado al levantamiento del freeze**; las fases 0–1 no lo necesitan.
  Absorbe `/adoptar` (queda como stub; `docs/ADOPTION.md` §4 sigue mandando el orden de relleno).
- **FASE 3 EJECUTADA (parcial) 2026-08-24** — informe en
  `docs/process/reviews/2026-08-24-valor-por-gate-fase3.md`. Lo primero que encontró fue un agujero
  en su propio instrumento: los gates que BLOQUEAN no registraban nada, así que casi todos figuraban
  con cero eventos. Arreglado. Lo que sí quedó medido, sobre los 127 hallazgos del ledger:
  el `design-reviewer` rinde entre **4.0 y 9.0** hallazgos por invocación (4 llegaron al ledger, 9
  autorreportó), los jueces adversariales 3.3 y el `reviewer` **0.84 por invocación y 1.5 por diff
  revisado** (dos tasas porque un mismo diff se revisó hasta 17 veces; la cifra por invocación está
  deprimida por ese artefacto del flujo, no por el agente) — y el `design-reviewer` se había
  invocado **UNA vez en toda la vida del proyecto**. No falta maquinaria: falta usar antes la que ya
  existe. **Sobre los gates mecánicos no se decide nada** hasta que haya ventana real con la
  telemetría arreglada. El informe declara su método de atribución y el error que cometió: la
  primera versión daba 5.0 al `design-reviewer` porque un clasificador por subcadenas se tragó una
  entrada de otra fecha y de otra fuente.
- **HECHO 2026-08-25 — la cola del `process-judge` se procesó** (el contador vivo es
  `wc -l < .agents/state/judge-queue.txt`; hoy imprime cero). Sus hallazgos ya son commits
  (`2196f43`, `0072188`) y entradas del ledger. Con esto el juez deja de ser la defensa sin datos;
  su rendimiento entra en la segunda pasada de la fase 3.
- **Siguiente entrega: segunda pasada de la fase 3**, ya con la telemetría de bloqueos acumulando
  (arreglada el 2026-08-24 — la ventana corre desde entonces). Es lo que cierra
  `f-wf09-ventana-de-valor`, y lo que falta para eso no es más maquinaria: es la medición.
  PRD 0004 §16 pide 2–4 semanas de datos antes de retirar o endurecer nada.
- **Después: el RESTO de la fase 2a.** Las cuatro divisiones rescatadas de los worktrees ya están
  en main (2026-08-25, orden del owner — ver «Estado actual»). Lo que queda es la mitad con más
  riesgo: `upgrade.sh` y los demás archivos sobre el límite — cuáles son y cuántos, en
  `f-wf04-archivos-sobre-el-limite`, que trae el comando que lo recalcula: ese finding ya congeló
  el conteo mal tres veces. Su restricción de diseño está escrita en el PRD §6: la
  auto-actualización copia HOY solo `upgrade.sh` a un temporal y hace `exec`, así que un
  orquestador que sourcee libs inexistentes en el árbol del adoptante **rompe a todos los
  adoptantes en el salto de versión**. Léela antes de tocar una línea.
- **Handoff para el siguiente agente:** lee el PRD 0005 §5b, que dice fase por fase qué se
  entregó y qué gate sigue abierto. Queda UNO y no lo cierra quien implementó, a propósito: el
  30/30 de macOS de la fase 0a, que dio **29/30** en el bucle del Mac del owner — el gate literal no
  se cumple, aunque su hipótesis quedó refutada (detalle en «Estado actual»). El de corpus KMP de 1c
  cerró el 2026-08-22. Antes de abrir una iniciativa
  NUEVA —distinta de terminar 0005— mira `bash tools/metrics/escape-rate.sh` y el ledger:
  PRD 0004 §16 pide 2–4 semanas de datos del adoptante antes de retirar o endurecer cualquier
  defensa, y endurecer sin ese dato es añadir ceremonia.
- **Base verificada de fase 10:** sobre `61e3d06` (2026-08-12) la matriz E2E y la suite completa
  salieron verdes en macOS — las cifras exactas las imprimen `bash tools/tests/run-tests.sh
  golden` (la matriz vive dividida en los `test_e2e_*.sh` y sus demostraciones se llaman
  `test_golden_*`) y la suite completa; no se copian aquí porque caducan. Cada test de la matriz se
  comprobó contra un mutante del script que dice cubrir (11 mutantes, cada uno rojo en su test y
  solo en el suyo). **Linux quedó verificado DESPUÉS de esa corrida:** el push de fase 10 dejó
  `ubuntu-latest` en rojo (`f-stat-f-orden-invertido`, arreglado en `4a6a775` el 2026-08-12) y la
  suite Ubuntu está verde en descendientes — run 32217407840 de `harness-ci` sobre `cab2f4c`,
  consultado read-only el 2026-08-18
  (`docs/process/reviews/2026-08-18-workflow-improvement-assessment.md` §2).
- El informe del adoptante sigue siendo la verificación independiente: quien escribe el arreglo
  no es quien lo aprueba.
- Pendientes del lado del adoptante, no bloqueantes: las macros de Swift en semgrep (vive en
  SU ledger, no en este — los ids de un adoptante no resuelven aquí, y `check-finding-refs.sh`
  caza la cita si alguien la pega).
- `f-mutation-score-nunca-medido` sigue abierto **a propósito**: el bloqueo es que el runner de
  mutación del adoptante no localiza su bundle de tests. Es issue upstream de esa herramienta,
  no trabajo del template. No lo cierres sin que él lo confirme.

## Lo que ya NO es el próximo paso (estaba aquí y confundía)

Este bloque decía "cablear el stack" y listaba seis FILLs. Cuatro ya están hechos —
`tools/verify.conf`, el paso 6 de CI, `mutation-score.sh` y las reglas de semgrep— y quien
leyera esto en frío se ponía a rehacerlos. Se deja anotado porque **un mapa desactualizado es
peor que no tener mapa**: no dice "no sé", dice algo falso con tono de instrucción.
Los FILLs que de verdad falten los declara `session-start.sh` en cada arranque, con el estado
real medido; esa es la fuente, no esta lista.

## Lo que NO hacemos todavía (explícito)

Diferido a propósito (ver PRD 0001 §8 y §16). No lo construyas "de paso":

- **Fuzzing** coverage-guided · **simulación determinista** · **fault injection**.
- **Métodos formales** (TLA+, Dafny, model checking) — se documenta cuándo valen, no se integran.
- **`sandbox` activado por defecto** — cambia el flujo de permisos del usuario; es decisión suya.
- **CI de un proveedor concreto** — `ci/run-gates.sh` es el único punto de entrada; los
  `ci/examples/` siguen siendo stubs.
- **Agent teams como flujo por defecto** — documentado para diffs de alto riesgo, nada más.
- **SBOM / SLSA / OpenTelemetry.**

## Punteros

- Reglas: `AGENTS.md` · **Bucle de verificación:** `.agents/skills/process/references/verification-loop.md`
- Lecciones: `docs/process/lessons_learned.md` (toda entrada exige `Detector:`)
- PRDs: `docs/process/prds/` · Findings: `docs/process/findings-ledger.md`
- Salud del harness: `bash tools/tests/run-tests.sh` · `bash ci/run-gates.sh`
- Métrica de confianza: `bash tools/metrics/escape-rate.sh`
