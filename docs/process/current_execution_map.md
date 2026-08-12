# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** el template está **en producción contra un adoptante real** (un proyecto iOS/Swift 6).
  Ese bucle —el adoptante sincroniza, usa el harness, reporta lo que falla, se arregla AQUÍ y
  vuelve a bajar— es el flujo de trabajo actual, no una fase de pruebas.
- **En curso:** nada. **PRD 0004 (reconciliación del workflow agéntico) está Shipped**: fases
  1a–10 mergeadas. Qué dejó, en una frase por bloque — el detalle vive en el PRD, no aquí:
  manifiesto de capacidades que gobierna los bloques documentales; probes funcionales que
  distinguen ausente / roto / operativo; scope mecánico del backlog antes de `in-review`;
  estados explícitos de las capacidades arquitectónicas; boundary portable `agent-runner` con
  backends intercambiables; eventos v2 y findings con lifecycle separado (detectar ≠ defecto);
  rotación de lecciones que dejó el contexto obligatorio en 236 líneas; caché de Semgrep staged
  solo para verde. **Fase 10 cerró el ciclo con la matriz E2E** (`tools/tests/test_e2e_matrix.sh`):
  un test por escenario golden, atado al PRD por un test que falla si la lista y su demostración
  divergen. Al construirla salieron tres huecos que ninguna fase anterior podía ver —el Anillo 3
  no tenía test propio, `claude.sh` declaraba `read_only` sin demostrarlo y la promesa de ≥30% de
  la caché no se medía— y los tres quedaron cubiertos (PRD 0004 §18).
- **Salud:** suite del harness verde en macOS (477 tests). El estado por gate NO se apunta aquí
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
4. `git add -A && bash tools/verify-run.sh && git commit` → `git push`. El adoptante sincroniza
   y **verifica en su repo**, que es la única verificación independiente que existe: quien
   escribe el arreglo no es quien lo aprueba (§14).

## Próximo paso

- **Siguiente entrega:** ninguna iniciativa abierta. El trabajo vuelve al bucle de arriba: el
  adoptante sincroniza, usa el harness y reporta con medición; el arreglo se hace aquí.
- **Handoff para el siguiente agente:** no hay fase pendiente que retomar. Antes de abrir una
  iniciativa nueva, mira `bash tools/metrics/escape-rate.sh` y el ledger: PRD 0004 §16 pide 2–4
  semanas de datos del adoptante antes de retirar o endurecer cualquier defensa, y endurecer sin
  ese dato es añadir ceremonia.
- **Base verificada de fase 10:** `bash tools/tests/run-tests.sh e2e_matrix` da 11/11 y la suite
  completa 477/477 en macOS. Cada test de la matriz se comprobó contra un mutante del script que
  dice cubrir (11 mutantes, cada uno rojo en su test y solo en el suyo). **Linux no se verificó
  en esa corrida**: lo dice el job `ubuntu-latest` de `harness-ci`, y hasta que ese job esté
  verde la mitad Linux de la promesa es una expectativa, no evidencia.
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
