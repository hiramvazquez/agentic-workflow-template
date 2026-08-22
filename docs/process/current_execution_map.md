# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** el template está **en producción contra un adoptante real** (un proyecto iOS/Swift 6).
  Ese bucle —el adoptante sincroniza, usa el harness, reporta lo que falla, se arregla AQUÍ y
  vuelve a bajar— es el flujo de trabajo actual, no una fase de pruebas.
- **En curso:** **PRD 0005 (estabilización del harness)**, Approved. Entregadas 0a, 0b, 0c,
  1a, 1b, 1c y 2b; quedan **2a** (bajar del hard limit los archivos que
  lo exceden — `f-wf04-archivos-sobre-el-limite` los lista y trae el comando que los
  recalcula; no los cuentes desde aquí — con la restricción de bootstrap) y **3** (reporte keep/tune/retire, cuya ventana
  de medición EMPIEZA al cerrar la ola 2). Dos gates siguen abiertos a propósito y no los
  cierra quien implementó: el 30/30 de macOS de 0a y el FP contra corpus KMP ajeno de 1c.
  El detalle por fase vive en el PRD, no aquí.
- **Antes:** **PRD 0004 (reconciliación del workflow agéntico) está Shipped**: fases
  1a–10 mergeadas. Qué dejó, en una frase por bloque — el detalle vive en el PRD, no aquí:
  manifiesto de capacidades que gobierna los bloques documentales; probes funcionales que
  distinguen ausente / roto / operativo; scope mecánico del backlog antes de `in-review`;
  estados explícitos de las capacidades arquitectónicas; boundary portable `agent-runner` con
  backends intercambiables; eventos v2 y findings con lifecycle separado (detectar ≠ defecto);
  rotación de lecciones que dejó el contexto obligatorio dentro del límite que fija y mide
  `test_contexto_vivo_obligatorio_cabe_en_250_lineas` (`tools/tests/test_lessons.sh`) — la
  cifra real la imprime ese test, no este doc; caché de Semgrep staged solo para verde.
  **Fase 10 cerró el ciclo con la matriz E2E** (`tools/tests/test_e2e_matrix.sh`):
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
4. **Stagea por paths**, nunca `-A` a ciegas: `git add <los archivos del cambio>` →
   `bash tools/verify-run.sh` → `git commit` (comandos separados: el marker liga
   `sha256(diff staged)` y encadenarlos lo evade) → `git push`. `git add -A` solo tiene
   sentido cuando `git status --short` ya salió limpio de todo lo demás, y entonces no
   ahorra nada. Este doc recomendaba `-A` mientras AGENTS.md §7 lo prohíbe con cambios
   fuera de scope (`f-wf08-git-add-A-canonico`): el mapa contradecía la regla canónica desde la puerta de
   entrada de cada sesión.
5. El adoptante sincroniza y **verifica en su repo**, que es la única verificación
   independiente que existe: quien escribe el arreglo no es quien lo aprueba (§14).

## Próximo paso

- **Siguiente entrega: PRD 0005 fase 2a** — bajar del hard limit los archivos del harness que
  lo exceden, sin debilitar nada. Cuáles son y cuántos, en `f-wf04-archivos-sobre-el-limite`,
  que trae el comando que lo recalcula: ese finding ya congeló el conteo mal dos veces. Es la fase con más riesgo del programa y su
  restricción de diseño está escrita en el PRD §6: la auto-actualización copia HOY solo
  `upgrade.sh` a un temporal y hace `exec`, así que un orquestador que sourcee libs inexistentes
  en el árbol del adoptante **rompe a todos los adoptantes en el salto de versión**. Léela antes
  de tocar una línea. Después queda la fase 3 (keep/tune/retire).
- **Handoff para el siguiente agente:** lee el PRD 0005 §5b, que dice fase por fase qué se
  entregó y qué gate sigue abierto. Dos gates NO los cierra quien implementó, a propósito: el
  30/30 de macOS de la fase 0a (bloqueado por presupuesto de Actions; plan B es el bucle en el
  Mac del owner) y el FP contra corpus KMP ajeno de la fase 1c. Antes de abrir una iniciativa
  NUEVA —distinta de terminar 0005— mira `bash tools/metrics/escape-rate.sh` y el ledger:
  PRD 0004 §16 pide 2–4 semanas de datos del adoptante antes de retirar o endurecer cualquier
  defensa, y endurecer sin ese dato es añadir ceremonia.
- **Base verificada de fase 10:** sobre `61e3d06` (2026-08-12) la matriz E2E y la suite completa
  salieron verdes en macOS — las cifras exactas las imprimen `bash tools/tests/run-tests.sh
  e2e_matrix` y la suite completa; no se copian aquí porque caducan. Cada test de la matriz se
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
