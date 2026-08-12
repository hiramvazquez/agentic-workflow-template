# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** el template está **en producción contra un adoptante real** (un proyecto iOS/Swift 6).
  Ese bucle —el adoptante sincroniza, usa el harness, reporta lo que falla, se arregla AQUÍ y
  vuelve a bajar— es el flujo de trabajo actual, no una fase de pruebas.
- **En curso:** PRD 0004, reconciliación del workflow agéntico. Fases 1a–9 implementadas:
  manifiesto estructurado, bloques documentales generados y upgrade que funde esos fragmentos
  sin pisar la prosa del adoptante; el informe calcula tests/FILLs contra el commit actual en
  vez de copiar conteos manuales; probe funcional con commit/plataforma/fecha y consumo desde
  arranque/validate; contratos separados `run`/`review`, watchdog con timeout/cancelación
  y transporte completo de sus adapters/prompts en upgrades; backlog y AI review ya consumen
  el boundary portable con preflight de capacidades y review final observable; la telemetría
  ya emite eventos v2 con identidad/fase/commit/triage desconocido, los lectores normalizan
  streams mixtos v1/v2 sin reescribirlos y el ledger puede promover detecciones mediante
  `source_event_ids[]`; `escape-rate` ya cuenta findings únicos en una ventana explícita y
  `gate-value` separa eventos únicos, actividad, promoción y cobertura de latencia sin llamar
  “false-positive” a lo que sigue sin triar; la rotación dejó 11 lecciones vivas y movió 52
  racionales mecanizados al archivo, con un índice único regenerable. El contexto obligatorio
  termina antes del índice y ocupa 236 líneas; el histórico solo se consulta bajo demanda;
  Semgrep staged reutiliza exclusivamente resultados 0/0 mediante una key de diff+HEAD+targets+
  reglas+scanner+binario+versión+plataforma y TTL, revalidada antes de consumir y publicar;
  targets con cambios no stageados fuerzan scan real. Fase 10 pendiente.
- **Salud:** las suites herméticas de capabilities, upgrade y clasificación están verdes. La
  capacidad runtime de Semgrep en esta máquina está **broken**: su binario revienta al inicializar
  X509. La fase 2 ya separa ambos hechos; un clasificador verde no convierte el entorno en verde.
  El backlog ya deriva su allowlist solo de `scope: |` y valida rango, índice, worktree,
  untracked, deletes y ambos lados de renames antes de permitir `in-review`.
  `check-layers` ya se declara por lo que realmente hace: dirección de imports directos,
  sin atribuirse grafo, transitividad ni detección de ciclos.
  Ciclos y complejidad ahora se clasifican como `operational|unsupported|missing|broken`
  mediante adapters opt-in; ausencia ya no se presenta como arquitectura limpia.
  Seguridad ya distingue decisiones sensibles fail-closed de fallos de observabilidad
  fail-loud; se eliminó la autorización genérica y peligrosa de “fail-open OK”.
  TDD/DbC conserva red-first, mutación e invariantes, pero la matriz nace del riesgo y del
  comportamiento observable; se eliminaron cuotas universales de casos/aserciones decorativas.
  Existe un boundary portable `agent-runner` con contratos separados `run`/`review`, backend
  fake hermético, adapter Claude y limpieza del grupo completo ante timeout/cancelación.
  Backlog exige `run+review+read_only+subagents+hooks`, conserva scope/worktrees y no llega a
  `in-review` sin review final parseable; CI exige `review+read_only` sin acoplarse al proveedor.
  Eventos y findings ya tienen lifecycle separado: detectar no implica true-positive; solo
  `findings.sh add/import --source-event` crea el vínculo durable y nunca modifica el evento.

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

- **Siguiente entrega:** fase 10 — matriz E2E y cutover documental final, sin comportamiento nuevo.
- **Handoff para el siguiente agente:** empezar en PRD 0004 §5b/§9/§10. Construir la matriz E2E
  que demuestre los criterios 1–10, incluyendo `fake.sh` y `claude.sh` conectado a un stub
  hermético; el smoke con Claude real queda opcional. No añadir capacidades ni cambiar contratos:
  fase 10 integra, verifica macOS/Linux y hace el cutover final de documentación.
- **Base verificada de fase 9:** `bash tools/tests/run-tests.sh gate_cache` da 15/15. Cubre hit,
  TTL, atomicidad, corrupción/payload manipulado, invalidación por diff/HEAD/targets/reglas/
  scanner/binario/versión/plataforma, TOCTOU, worktree distinto, exits 1/3, warnings y `--all`.
- El informe del adoptante sigue siendo una verificación posterior, no bloquea esta iniciativa.
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
