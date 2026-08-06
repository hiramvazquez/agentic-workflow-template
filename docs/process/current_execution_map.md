# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

> ⚠️ Este bloque describe el estado del **template en sí**. Cuando lo clones para un proyecto
> real, sustitúyelo por el estado de TU proyecto.

- **Fase:** template — pirámide de verificación + bucle de aprendizaje cerrados; pendiente de
  cablear a un stack real.
- **En curso:** nada — PRD 0001 y PRD 0002 shipped.
- **Último ship:** PRD 0002 · ledger operable sin Deno/Node (findings.sh), gates que registran
  detecciones (escape-rate con datos), cola del process-judge, meta-detector de tests de FP,
  DbC con mecanismo declarado, patrón N-jueces.

## Próximo paso

**Cablear el stack.** El harness está montado pero varios niveles están MUDOS hasta que se
rellenen sus `<!-- FILL -->`. El `session-start.sh` te dice cuáles en cada sesión. En orden
de impacto:

1. `AGENTS.md §2` — stack, build, tests, lint. Sin esto nada más se puede cablear.
2. `scripts/agent-hooks/post-edit-verify.sh` §FILL — **el gate de mayor ROI**. Sin él el
   agente no recibe señal in-loop y descubre sus errores 40 turnos tarde.
3. `brew install semgrep` + reglas en `tools/semgrep/rules/` — nivel 2 de la pirámide.
4. `tools/mutation-score.sh` §FILL — runner de mutación. Es lo único que distingue un test
   real de uno decorativo; hasta entonces el piso está en 0 y el gate no dice nada.
5. `tools/layers.conf` — ajusta los globs de capa a tus rutas reales.
6. `ci/run-gates.sh` paso 6 — build+tests de tu stack.

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
