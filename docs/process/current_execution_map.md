# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Es la
> respuesta a **"¿en qué estamos y qué sigue?"**: una pantalla, un estado, un próximo paso.
>
> **La historia NO vive aquí.** Vive en los PRDs, en los mensajes de commit, en el ledger y en
> `docs/process/reviews/`. Este fichero llegó a cruzar el hard limit de §4 con narrativa
> acumulada y dejó de ser legible justo en el sitio donde se lee con más autoridad
> (`wc -l` lo dice; el número no se escribe aquí, por lo mismo que el resto).
> Si vas a añadir un párrafo que empieza contando lo que pasó, va en otro sitio.
>
> **Ni las cifras.** Un conteo literal caduca solo y aquí se lee como garantía permanente
> (`f-wf02-mapa-cifras-podridas`). Lo que un comando puede calcular, se cita como comando.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** el template está **en producción contra un adoptante real** (un proyecto iOS/Swift 6).
  El bucle —sincroniza, usa el harness, reporta lo que falla, se arregla AQUÍ, vuelve a bajar—
  es el flujo de trabajo actual, no una fase de pruebas.
- **PRD 0011 (carriles por peso del cambio): COMPLETO** el 2026-09-04, sus cinco fases. El
  coste de verificar es ya proporcional a lo que un cambio puede romper: un PRD o cualquier
  prosa cuesta **0 s y 0 reviews**; un detector, **39 s y una review enfocada**; la maquinaria
  que decide qué se verifica, **150 s y una review profunda**. La review de una unidad normal
  pasó de 1208 s a 95 s. Lo que NO se hizo, y por qué, está en su §5b y en `f-wf09`.
- **PRD abierto:** **0005 (estabilización del harness)**, Approved y parcial. Lo que queda es la
  mitad de más riesgo de su fase 2a (`upgrade.sh`, restricción de bootstrap) y la segunda pasada
  de su fase 3, que **espera medición, no código**: la telemetría de bloqueos tiene que acumular
  ventana antes de decidir keep/tune/retire (`f-wf09-ventana-de-valor`). El detalle por fase vive
  en el PRD.
- **PRDs cerrados en esta línea de trabajo:** **0008** (el harness no borra código) completo, y
  **0009** (el harness se cuenta) con sus fases ejecutables entregadas. Qué quedó fuera y por
  qué, en su §5b y su DoD — no se resume aquí.
- **Un gate sigue abierto:** el de 0a pedía 30 corridas macOS seguidas sin rerun y el plan B dio
  29 verdes y 1 rojo, así que **el gate literal no se cumple**. Pero su hipótesis quedó
  REFUTADA: se atribuía el flaky a presión de spawn en runners pequeños y una máquina en reposo
  lo reprodujo igual. Los dos hechos, con su fuente: `f-wf01-ci-macos-intermitente`.
- **Un hecho de entorno que confunde si no se sabe:** la capacidad runtime de Semgrep **en esta
  máquina** está `broken` (su binario revienta al inicializar X509). No es un fallo del
  clasificador — el harness separa los dos hechos a propósito para que un clasificador verde no
  se lea como entorno verde.
- **Salud:** no se apunta aquí. La imprime `session-start` en cada arranque, y a demanda
  `bash tools/validate-harness.sh --selftest`, `bash tools/tests/run-tests.sh` y
  `bash tools/metrics/dora.sh --sin-serie`.

## Cómo se trabaja aquí (el bucle, no la historia)

1. El adoptante corre `bash tools/upgrade.sh`, usa el harness y manda un informe de lo que
   falló, **con la medición**.
2. El arreglo se hace **en el template**, con su test **verificado fallando contra la versión
   anterior** — no basta con que el test pase.
3. Lección en `lessons_learned.md` (con `Detector:`) + entrada en el ledger, en el mismo cambio.
4. **Antes de invocar al `reviewer`, mira la naturaleza del lote:**
   `bash tools/check-diff-nature.sh` — **sin flags**, que es el modo `--staged`. NO uses
   `--range`: compara `BASE...HEAD` y por construcción no ve lo staged sin commitear, o sea justo
   lo que vas a mandar a revisar. Esta línea nació diciendo `--range` y su "verificación" salió
   limpia por eso mismo. Si avisa, **parte el lote antes de la primera review, no después de la
   tercera** — el coste de no hacerlo está medido en `f-15089319`.
5. **Stagea por paths**, nunca `-A` a ciegas: `git add <los archivos del cambio>` →
   `bash tools/verify-run.sh` → `git commit` (comandos separados: el marker liga
   `sha256(diff staged)` y encadenarlos lo evade) → `git push`.
6. El adoptante sincroniza y **verifica en su repo**, que es la única verificación independiente
   que existe: quien escribe el arreglo no es quien lo aprueba (§14).

## Próximo paso

**Arreglar el flaky de `f-wf01`, que por fin tiene repro.** Es lo que queda con coste
medido y camino claro (lo abierto, al día: `bash tools/findings/findings.sh list --status open`).
Cuesta **72 s en cada pre-push, el 49% del reloj**, y desde el
2026-09-04 se reproduce a demanda en 81 s con

    TESTS_SERIAL_FILES=__ninguno__ TESTS_JOBS=32 bash tools/tests/run-tests.sh

3 de 3 corridas en rojo bajo presión de procesos; 4 de 4 en verde sin ella. El disparador
NO es macOS —eso era el título viejo— es la presión: en local iba verde porque sobraban
núcleos. La causa raíz está en la cabecera de `test_agent_runner.sh`: el fixture compite
contra su propio timeout. Subirlo otra vez solo mueve el umbral; el arreglo es que el
fixture espere a su descendiente con un sondeo acotado ANTES de arrancar el reloj.

Mientras eso no se haga, `TESTS_SERIAL_FILES` **no se vacía**: se intentó el 2026-09-04 y
el rojo volvió. Esa lista no es deuda, es la única defensa viva contra una causa que sigue ahí.

**El PRD 0011 está completo, y su fase 5 terminó en "no se retira nada", con el dato.** De
los 7 gates de la ventana: 3 no tienen sustrato en un repo `harness` (`check-source-sets`
corrió 0 veces con objetivos reales, `check-layers` 1 de 249, `check-drift` 1 de 242); 3 son
KEEP sin discusión (0.04-0.13 s cada uno y fallo catastrófico); y `semgrep` es el único
candidato real, pero mide sin sustrato porque sus reglas son de Swift y aquí no hay Swift.
`f-wf09` sigue abierto a propósito: **se cierra cuando la ventana se recoja en un proyecto
adoptante**, no antes.

Después, por coste: `f-8b74d177` —`check-skill-matrix-doc.sh` compara el CONJUNTO global de
referencias entre el conf y su vista humana, no los pares `path → referencias`, así que la
frase "exactamente el conf" de §11 promete una garantía que el detector no da—; las columnas
del rollup, que mezclan ventanas de tiempo distintas en la misma fila (`f-cb4f7155`); y
`f-ec811739`, que hace inalcanzable el ahorro que §6b promete (el marker de `verify-run` no
llega al worktree aislado, así que la review enfocada nunca puede leerlo y siempre re-corre).

**Aviso para quien siga: cinco afirmaciones de este repo se cayeron al medirlas el
2026-09-04.** `f-wf04` acusaba a dos ficheros sanos y callaba al peor con diferencia; `f-wf01`
culpaba a macOS; el "coste de semgrep" era 44% una corrida colgada de 936 s; el juez y las
métricas nunca estuvieron en el camino crítico; y la ventana de valor mide el repo
equivocado. Ninguna era mentira deliberada: eran agregados que nadie volvió a abrir. Antes
de actuar sobre una cifra de este mapa o del ledger, mira su distribución.

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
- Métricas de entrega: `bash tools/metrics/dora.sh --sin-serie` · contención: `escape-rate.sh`
