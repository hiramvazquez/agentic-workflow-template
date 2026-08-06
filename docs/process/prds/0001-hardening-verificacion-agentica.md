# PRD — Hardening de la pirámide de verificación agéntica

> **Tipo:** Forward · **Status:** Approved
> **Autor:** Hiram (owner) · **Fecha:** 2026-08-05 · **Tracking:** PRD 0001 · commits `feat(gates)`, `feat(hooks)`, `feat(tools)`
> **Design-review:** OK (2026-08-05) — la solución se validó contra la doc oficial de Claude Code
> (hooks reference, skills, permissions, `/goal`, security-guidance) y contra literatura de
> ingeniería de calidad pre-IA (Tricorder/Google, Infer/Meta, Power of Ten/JPL, correctness
> practices/AWS, fitness functions, mutation & property-based testing, DORA).

---

## 1. Contexto

El template ya tiene la **topología correcta**: 3 anillos de enforcement, `AGENTS.md` canónico,
drift-ratchet, findings-ledger, sub-agentes de review y captura de trayectoria. El
`reviewer-gate` incluso liga el marker de review al `sha256` del diff staged, algo más riguroso
que lo habitual.

Pero la implementación está **muy por debajo de las primitivas disponibles**:

- Se usan **6 de ~30 eventos de hook** de Claude Code.
- **Cero** uso de `permissions` (deny/ask) — la primitiva de bloqueo nativa más fuerte.
- Los detectores son `grep`, no AST → falsos positivos altos y evasión trivial.
- `canon-enforce.sh` está **enteramente comentado**: es un no-op que el `SessionStart`
  anuncia como gate activo.
- El marker de review lo escribe **el propio modelo** (`mark-reviewer-run.sh`), no el sistema.

## 2. Problema

**El objetivo del proyecto es que cada día se necesite menos revisión humana del código escrito
por IA.** Hoy eso no se sostiene por tres razones concretas:

1. **Integridad rota.** El agente firma su propia revisión. `reviewer-gate` bloquea el commit
   hasta que exista un marker, pero el marker lo produce un script que el modelo invoca. Un
   agente que quiere commitear solo tiene que ejecutarlo. El gate de review es decorativo.
2. **Sin verificación in-loop.** El agente no recibe señal mecánica hasta el `Stop` o el commit.
   Un error de tipos introducido en el turno 3 se descubre en el turno 40, con el contexto ya
   contaminado por 37 turnos construidos sobre él.
3. **Sin medida de la calidad de los tests.** La función objetivo de un agente es "que los tests
   pasen", y la forma más barata de lograrlo es escribir tests que no comprueban nada. No hay
   ningún gate que distinga un test real de uno decorativo.

Si no se construye: el techo de autonomía queda donde está — cada entrega de un agente necesita
lectura humana completa, porque ninguna señal automática es confiable ni infalsificable.

## 3. Objetivo

Cuando esté hecho:

- **Ningún veredicto de calidad lo emite el mismo agente que escribió el código.** Todos los
  markers los produce el sistema (hooks), no el modelo.
- **El agente recibe señal determinista en el mismo turno** en que introduce el error
  (lint/typecheck del archivo tocado vía `PostToolUse`).
- **Existe un número medible de "cuán reales son los tests"** (mutation score) con ratchet.
- **Toda lección aprendida se convierte en un detector mecánico**, o se marca explícitamente
  como no mecanizable. La necesidad de review humano decrece en vez de mantenerse plana.

Medible: `escape rate` por área (defectos que pasaron el gate N y se cazaron en N+1) con
tendencia a la baja; `mutation-ratchet` que solo sube; `drift-ratchet` que solo baja.

## 4. Filosofía / principios

1. **El que escribe nunca es el que aprueba, y "aprobar" es presentar evidencia.**
   Un veredicto es la salida de un comando, un exit code o un score — nunca una afirmación del
   modelo. Todo marker lo escribe un hook a partir de output real.
2. **Cázalo en la capa más barata.** Tipos > lint > patrón AST > test > mutation > review IA >
   humano. Cada nivel que sube el coste de detección × 10. Un error detectable por el
   compilador que llega a un juez IA es un fallo de diseño del harness.
3. **Un detector con >10% de falsos positivos es peor que no tenerlo** (ley de Tricorder,
   Google). Los devs — y los agentes — descartan sistemáticamente lo ruidoso, y el agente
   además aprende a evadirlo. Preferimos 5 reglas AST exactas a 50 greps.
4. **Fail-open en la mecánica del hook, fail-closed en la política.** Un bug del hook nunca
   traba al dev (backstop = Anillo 3). Pero una violación detectada sí bloquea.

## 5. Estructura de archivos a crear / tocar

```
── P0: integridad y bucle in-loop ──────────────────────────────────────────
scripts/agent-hooks/capture-review-verdict.sh   ← NUEVO. SubagentStop: escribe el marker
                                                   parseando el veredicto REAL del sub-agente
scripts/agent-hooks/post-edit-verify.sh         ← NUEVO. PostToolUse Edit|Write: lint/typecheck
                                                   del archivo tocado → additionalContext
scripts/agent-hooks/lib/io.sh                   ← + hook_json_out(), hook_context(), hook_agent_*()
scripts/mark-reviewer-run.sh                    ← degradado a fallback manual AUDITADO
scripts/agent-hooks/canon-enforce.sh            ← activar checks universales reales
tools/check-review-marker.sh                    ← NUEVO. Verificación del marker reusable
                                                   por Anillo 1 (lefthook) y 3 (CI)
.claude/settings.json                           ← permissions{deny,ask} + 6 hooks nuevos
                                                   + enabledPlugins(security-guidance)
.claude/claude-security-guidance.md             ← NUEVO. Threat model para el revisor del plugin
.claude/security-patterns.yaml                  ← NUEVO. Reglas per-edit deterministas
.claude/agents/reviewer.md                      ← + contrato de salida VERDICT parseable
.claude/agents/security-reviewer.md             ← + contrato de salida VERDICT parseable
.cursor/hooks.json                              ← paridad de los hooks nuevos que Cursor soporta
lefthook.yml                                    ← + check-review-marker (Anillo 1)
ci/run-gates.sh                                 ← + marker, semgrep, capas, mutación, IA

── P1: detectores AST, arquitectura y calidad de test ──────────────────────
tools/semgrep/rules/*.yaml                      ← NUEVO. Reglas AST (reemplazan greps)
tools/semgrep-scan.sh                           ← NUEVO. Runner + degradación si falta semgrep
tools/check-layers.sh                           ← NUEVO. Fitness function por grafo de imports
tools/mutation-score.sh                         ← NUEVO. Runner de mutación por stack
tools/mutation-ratchet.json                     ← NUEVO. Piso de mutation score (SOLO SUBE)
tools/check-drift.sh                            ← delega a semgrep + capas; quita greps frágiles
scripts/agent-hooks/post-compact.sh             ← NUEVO. PostCompact: reinyecta reglas + findings
ci/ai-review.sh                                 ← NUEVO. Anillo 3 con IA (claude -p headless)

── P2: autonomía, métricas y bucle de aprendizaje ──────────────────────────
.agents/skills/*/SKILL.md                       ← + frontmatter moderno (paths, allowed-tools…)
.agents/skills/process/references/tdd-workflow.md      ← + property-based + DbC + conformidad
.agents/skills/process/references/verification-loop.md ← NUEVO. La pirámide de 9 niveles
.agents/skills/domain/SKILL.md                  ← + suite de conformidad puerto↔fake
tools/metrics/escape-rate.sh                    ← NUEVO. Métrica DORA-like de contención
tools/lesson-detector-link.sh                   ← NUEVO. Toda lección cita un detector
docs/process/lessons_learned.md                 ← + columna Detector
AGENTS.md                                       ← §5 (DbC) · §6 · §9 (ratchets) · §11 · §15 nuevo
README.md                                       ← actualizar mapa y anillos
CODEOWNERS · .editorconfig                      ← NUEVO
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
docs/process/prds/_template.md      ← meta-doc; cambiarlo invalida PRDs existentes
tools/drift-ratchet.json            ← lo actualiza SOLO `drift-ratchet.sh --update`
tools/findings/ledger.jsonl         ← se anexa vía findings.ts, nunca a mano
.claude-plugin/marketplace.json     ← distribución; fuera del scope de este PRD
enterprise/managed-settings.example.json ← se ajusta al final, tras estabilizar settings.json
```

## 6. Modelo de datos

### Contrato de veredicto de sub-agente (NUEVO — es el corazón del PRD)

Todo sub-agente de review termina su mensaje final con una línea machine-parseable:

```
VERDICT: GREEN|AMBER|RED
FINDINGS: <n>
SCOPE: <descripción corta>
```

`capture-review-verdict.sh` (hook `SubagentStop`, matcher `reviewer|security-reviewer`) lee
`last_assistant_message` del payload, parsea la línea, y **solo entonces** escribe el marker.
Sin línea `VERDICT:` → no hay marker. `RED` → no hay marker y el hook devuelve `decision: block`.

### Formato del marker (extendido)

```
ts: <ISO8601>
agent: reviewer|security-reviewer
verdict: GREEN|AMBER
scope: <texto>
head: <sha corto>
staged_sha: <sha256 del diff staged>
source: hook|manual-override
```

`source: manual-override` solo lo escribe `mark-reviewer-run.sh` y queda auditado en
`.agents/state/markers/override_log.txt`.

### Ratchets (invariante: dirección fija, nunca editable a mano)

| Archivo | Métrica | Dirección permitida |
|---|---|---|
| `tools/drift-ratchet.json` | `errors`, `warns` | **solo baja** |
| `tools/mutation-ratchet.json` | `min_score` (0-100) | **solo sube** |

## 7. Flujo de la solución

### User stories

- Como **owner**, quiero que un veredicto de review sea imposible de falsificar por el agente,
  para poder confiar en el gate sin releer el diff.
- Como **agente**, quiero recibir el error de lint/tipos en el mismo turno en que lo introduzco,
  para corregirlo antes de construir 30 turnos encima.
- Como **owner**, quiero un número que me diga si los tests que escribió la IA comprueban algo,
  para no tener que leerlos uno a uno.
- Como **equipo**, quiero que cada error cometido una vez sea mecánicamente imposible la segunda.

### Flujo end-to-end tras este PRD

```
Edit/Write ──► PostToolUse: lint+typecheck del archivo  ──► additionalContext al agente
                                                              (corrige en el mismo turno)
       │
       ├─ per-edit: security-patterns.yaml (0 tokens)
       │
Stop ──► canon-enforce (checks duros) + drift-stop (delta) ──► bloquea si hay error nuevo
       │
PostCompact ──► reinyecta digest de AGENTS.md + findings abiertos del área
       │
Agent(reviewer) ──► SubagentStop ──► parsea VERDICT ──► escribe marker (o BLOQUEA en RED)
       │
git commit ──► Anillo 2 reviewer-gate  (marker + ratchet)
           ──► Anillo 1 lefthook       (marker + secretos + ratchet)   ← NUEVO en Anillo 1
           ──► Anillo 3 run-gates.sh   (todo lo anterior + mutación + capas + IA headless)
```

### Edge cases

- **`semgrep` / mutación / `claude` no instalados** → el gate AVISA con instrucción de
  instalación y no bloquea en local; en CI **sí** bloquea (`ci/run-gates.sh` es fail-closed).
- **Preset `lite`** → `post-edit-verify` y el marker avisan; ratchets, capas y `canon-enforce`
  siguen duros. Idéntico criterio al existente.
- **Sub-agente muere sin emitir `VERDICT:`** → no hay marker, el commit se bloquea. Correcto:
  ausencia de evidencia ≠ evidencia de ausencia.
- **Repo sin git** (uso del template fuera de repo) → todos los hooks fail-open, `exit 0`.
- **Archivo tocado sin linter configurado** (`<!-- FILL -->` sin rellenar) → no-op silencioso,
  pero el `health-check` del `SessionStart` lo reporta como configuración incompleta.
- **Cursor no soporta `SubagentStop`** → su paridad se limita a los eventos que sí soporta; el
  backstop para Cursor y Codex es Anillo 1 + 3.

## 8. Anti-features (qué NO entra)

- **No** se implementa CI de ningún proveedor concreto. `ci/run-gates.sh` sigue siendo el único
  punto de entrada; los `ci/examples/` siguen siendo stubs.
- **No** se elige stack. Todo detector nuevo es agnóstico con `<!-- FILL -->` por plataforma.
- **No** se implementan métodos formales (TLA+, Dafny, model checking). Se documenta cuándo
  valen la pena y se deja fuera del harness por defecto.
- **No** se implementa fuzzing ni simulación determinista. Se documentan como escalón siguiente.
- **No** se activa `sandbox` por defecto: se documenta y se deja opt-in (cambia el flujo de
  permisos del usuario, decisión suya).
- **No** se toca `_template.md` de PRD ni el formato del ledger.
- **No** se migra a agent-teams como flujo por defecto — se documenta para diffs de alto riesgo.

## 9. Escenarios golden (deben pasar al terminar)

1. **Falsificación imposible.** Dado un repo con cambios staged en código de producto, cuando
   el agente ejecuta `bash scripts/mark-reviewer-run.sh "x"` sin haber corrido el sub-agente,
   entonces el marker queda con `source: manual-override`, se registra en `override_log.txt`,
   y `reviewer-gate` lo rechaza salvo `REVIEWER_OVERRIDE=1` explícito.
2. **Veredicto real produce marker.** Dado un `SubagentStop` con `agent_type: reviewer` cuyo
   `last_assistant_message` contiene `VERDICT: GREEN`, entonces se escribe el marker con
   `source: hook` y `git commit` pasa el gate.
3. **RED bloquea.** Mismo caso con `VERDICT: RED` → no se escribe marker y el hook devuelve
   `decision: block` con la razón.
4. **Señal in-loop.** Dado un archivo con error de sintaxis introducido por `Edit`, cuando
   termina el `PostToolUse`, entonces la salida del linter llega al agente vía
   `additionalContext` en el mismo turno.
5. **Ratchet de mutación.** Dado `min_score: 60`, cuando una corrida arroja 55, entonces
   `ci/run-gates.sh` falla; con 65, pasa y `--update` sube el piso a 65 (nunca lo baja).
6. **Capas.** Dado un archivo en `Domain/` que importa algo de `UI/`, entonces
   `tools/check-layers.sh` reporta error y `canon-enforce` bloquea el `Stop`.
7. **Permisos duros.** `git commit --no-verify` y `git push --force` son rechazados por
   `permissions.deny` sin llegar a ejecutarse.
8. **Lección → detector.** Una entrada nueva en `lessons_learned.md` sin columna `Detector`
   rellenada (ni marcada `n/a-manual`) hace fallar `tools/lesson-detector-link.sh`.
9. **Degradación limpia.** En una máquina sin `semgrep`, `git commit` sigue funcionando y el
   gate imprime la instrucción de instalación exacta.

## 10. Métricas de éxito

| Métrica | Baseline | Objetivo 4 semanas |
|---|---|---|
| Eventos de hook usados | 6 | ≥ 12 |
| Markers falsificables por el modelo | 100% | 0% |
| Detectores AST vs. grep | 0 / 7 | ≥ 5 AST |
| Mutation score con gate | no existe | ratchet activo |
| Escape rate (defecto cazado en fase N+1) | no medido | medido y con tendencia |
| Lecciones con detector asociado | 0% | 100% (o `n/a-manual` justificado) |

## 11. Rollout

Por fases, cada una commiteable y reversible de forma independiente:

- **Fase P0** (integridad + in-loop) — sin ella el resto no tiene sentido, porque los veredictos
  no son confiables. Rollback: revertir `settings.json` y borrar los scripts nuevos.
- **Fase P1** (AST + arquitectura + mutación) — entra con ratchets en su valor más permisivo
  (`min_score: 0`) para no romper repos existentes; se aprieta después.
- **Fase P2** (autonomía + métricas) — documental y de métricas; sin riesgo de bloqueo.

Preset: todo lo bloqueante nuevo respeta `tools/preset`. `lite` avisa, `full` bloquea, salvo
ratchets y capas que son duros en ambos (consistente con el diseño existente).

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **Sobre-bloqueo** — tantos gates que el trabajo se traba | Todo gate nuevo respeta preset; los ratchets entran en valor permisivo; `post-edit-verify` nunca bloquea (solo informa) |
| **Falsos positivos** matan la confianza (ley Tricorder) | Reglas AST en vez de grep; presupuesto explícito <10% FP; los greps frágiles actuales se **eliminan**, no se acumulan |
| **Latencia del hook** degrada la sesión | `post-edit-verify` con `timeout: 10` y solo sobre el archivo tocado, nunca el repo |
| **Dependencias externas** (semgrep, mutación) no instaladas | Degradación explícita: avisa en local, bloquea en CI |
| **El contrato `VERDICT:` no se cumple** por el sub-agente | Es parte del prompt del agente + el hook falla ruidosamente (sin marker) en vez de asumir GREEN |
| **Coste de tokens** del review IA en CI | Solo sobre el diff, solo en PR, con `--allowedTools` restringido |

## 13. Open Questions

- [x] ¿El marker debe escribirlo el hook o el modelo? → **El hook.** Es el núcleo del PRD.
- [x] ¿Reemplazar `check-drift.sh` o complementarlo? → **Complementar**: `check-drift.sh` sigue
      siendo el agregador y el contrato `DRIFT_SUMMARY`; delega la detección a semgrep/capas.
- [x] ¿`sandbox` on por defecto? → **No.** Cambia el flujo de permisos del usuario; opt-in documentado.
- [ ] ¿Qué runner de mutación por stack? Depende del stack real del adoptante → queda `<!-- FILL -->`
      con recomendaciones por plataforma (muter/Stryker/PIT/mutmut). **No bloquea `Approved`.**
- [ ] ¿`security-guidance` como dependencia dura o recomendación? → entra como `enabledPlugins`
      en el `settings.json` del template, desactivable. **No bloquea.**

## 14. Mockups / referencias

Pirámide objetivo (detalle completo en `.agents/skills/process/references/verification-loop.md`):

```
 coste ↑     9  Métricas + lección→detector          escape rate, ratchets
   de        8  Gate por evidencia                   /goal, Stop hook, marker↔diff
detección    7  Review adversarial IA                contexto fresco, N jueces, refutar
   ↑         6  Arquitectura                         grafo de imports, ciclos, tamaños
   │         5  Contratos                            fake ≡ real, Pact
   │         4  Calidad del test                     MUTATION SCORE, property-based
   │         3  Spec ejecutable                      TDD red-first, aserciones/DbC
   │         2  Patrón semántico                     Semgrep AST
   │         1  Determinista in-loop                 formatter, lint, typecheck
 barato      0  Imposibilitar                        tipos, -Werror, exhaustividad
```

Fuentes: Tricorder (Google) · Infer (Meta) · Power of Ten (NASA/JPL) · Systems Correctness
Practices at AWS (ACM Queue) · Building Evolutionary Architectures (fitness functions) ·
DORA · Claude Code docs (hooks, skills, permissions, `/goal`, security-guidance).

## 15. Definition of Done

- [ ] Los 9 escenarios golden pasan
- [ ] **TDD**: cada script nuevo con lógica de decisión tiene test de shell (happy + ≥2 bordes) escrito primero
- [ ] `bash tools/check-drift.sh` sin errores nuevos · `bash ci/run-gates.sh` verde
- [ ] `reviewer` GREEN/AMBER atendido · `security-reviewer` (toca permisos y secretos)
- [ ] `AGENTS.md`, `README.md` y skills actualizados en el mismo PR
- [ ] Sin secretos (gitleaks limpio)
- [ ] Finding `f-8145599c` del ledger cerrado (test del invariante ratchet-antes-de-bypass-lite)

## 16. Próximos pasos

Fuera de este PRD, en orden de valor:

1. **Fuzzing** coverage-guided para parsers y fronteras de input no confiable.
2. **Simulación determinista** con semilla para lógica concurrente/distribuida.
3. **Métodos formales dosificados** — TLA+/P para protocolos, Dafny para authz/cripto.
4. **Readability gate** como aprobación separada de la de corrección (modelo Google).
5. **SBOM + SCA con reachability** y provenance SLSA.
6. **OpenTelemetry** para observabilidad de sesiones agénticas.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-05 | Draft inicial tras investigación de doc oficial + literatura pre-IA | Claude |
| 2026-08-05 | Approved por el owner; arranca implementación P0 | Hiram |
| 2026-08-05 | P0 + P1 + P2 implementados. 43 tests de harness verdes. Status → In progress | Claude |

## 18. Gaps detectados (durante la implementación)

Lo que se aprendió construyéndolo. Cada uno va a `lessons_learned.md` con su detector.

### G1 — El propio harness produjo un falso positivo mientras se construía

Al editar `.agents/skills/domain/SKILL.md`, el hook `skill-reminder` bloqueó la edición: el
path casa con el glob `*/domain/*` de la matriz §11, así que exigía **leer la skill de dominio
para poder editar la skill de dominio**.

Es exactamente el fallo contra el que advierte la ley del 10%, y llegó desde dentro. Un gate
con falsos positivos se acaba desactivando entero — y con agentes es peor, porque además
aprenden a evadirlo.

- **Fix:** `skill-reminder` excluye `docs/`, `tools/`, `scripts/`, `.agents/`, `.claude/`,
  `.cursor/`, `enterprise/` y `*.md`, con excepción para los PRDs numerados.
- **Detector:** `tools/tests/test_skill_reminder.sh` — 4 de sus 7 tests son casos de falso
  positivo, no de detección.
- **Lección transferible:** **todo gate necesita tests de sus falsos positivos, no solo de sus
  detecciones.** Es la mitad del contrato que casi nadie escribe.

### G2 — La ausencia de una herramienta se contaba como deuda

`semgrep-scan.sh` emitía *"⚠️ semgrep no está instalado"* por stdout, y `check-drift.sh` agrega
stdout contando líneas `❌`/`⚠️`. Resultado: no tener semgrep instalado **subía el trinquete**,
que bloqueaba el commit por un motivo falso.

- **Fix:** los avisos de infraestructura van a stderr; solo los hallazgos reales a stdout.
- **Detector:** `test_drift_aggregation.sh::test_infraestructura_ausente_no_infla_el_conteo`.
- **Lección transferible:** cuando un script alimenta un contador, **separa el canal de datos
  del canal de diagnóstico**. Mezclarlos convierte un problema de entorno en deuda de código.

### G3 — El override de emergencia relajaba de más

`REVIEWER_OVERRIDE=1` se evaluaba **antes** que el drift-ratchet, así que saltarse el marker de
review también saltaba el trinquete. La doc siempre dijo que el trinquete es duro en todos los
presets; el código no lo cumplía.

- **Fix:** los detectores mecánicos se evalúan antes que el override y que el preset.
- **Detector:** `test_override_no_relaja_el_ratchet` + `test_ratchet_duro_incluso_en_preset_lite`.
- **Lección transferible:** un escape hatch necesita un **alcance declarado y testeado**. "Es
  para emergencias" no define qué relaja. Aquí: relaja **juicio humano** (el marker), nunca un
  **número objetivo** (el trinquete).

### G4 — El check de "lógica sin test" era trivial de gamear

Hacía `grep "$base" --include='*Tests.swift'`. Mencionar el nombre en un comentario lo
satisfacía. Un agente optimizando para pasar el gate lo encuentra enseguida.

- **Fix:** ahora exige que **exista el archivo** de test esperado, no una mención.
- **Detector:** `test_mencion_en_comentario_no_cuenta_como_test`.
- **Lección transferible:** todo detector heurístico debe pasar la prueba *"¿cómo lo gamearía
  yo?"*. Si la respuesta es fácil, mide adherencia, no calidad. Por eso la existencia del test
  es solo una señal y el veredicto real lo da el **mutation score**.

### G5 — Un gate anunciado y no implementado es peor que uno ausente

`canon-enforce.sh` estaba enteramente comentado mientras el `SessionStart` lo anunciaba como
guardrail activo. Nadie lo habría notado: un gate que nunca dispara y uno que no existe se ven
exactamente igual desde fuera.

- **Fix:** checks universales activos + `session-start.sh` ahora declara explícitamente qué
  niveles de la pirámide están **MUDOS** en esta configuración.
- **Lección transferible:** el health-check debe reportar lo que **no** cubre, no solo lo que
  sí. La falsa confianza es un modo de fallo, no un estado neutro.

### G7 — El detector de secretos se bloqueó a sí mismo (lo cazó el propio gate, en vivo)

Al cerrar el turno de implementación, `canon-enforce.sh` bloqueó el cierre señalando como
secretos a `canon-enforce.sh` y a `.claude/security-patterns.yaml`: los dos archivos que
**definen** qué es un secreto.

Es el tercer falso positivo generado por el propio harness durante su construcción (G1, G2, G7),
y el más ilustrativo: **el primer falso positivo de un detector casi siempre aparece en el repo
del propio detector.**

- **Fix:** `is_detector_definition()` excluye la implementación del gate, sus reglas
  (`security-patterns.yaml`, `semgrep/rules/`, `.gitleaks.toml`) y sus tests.
- **Detector:** `tools/tests/test_canon_enforce.sh` — 5 de sus 8 tests son casos de falso
  positivo, incluido `test_el_detector_no_se_detecta_a_si_mismo`.
- **Lección transferible:** un detector debe excluir los archivos que lo **configuran**. Y el
  patrón general que confirman G1+G2+G7: **escribe los tests de falso positivo el mismo día que
  el detector**, no cuando alguien se queje.

**Nota de proceso:** que el gate cazara este fallo *después* de que yo diera el trabajo por
terminado es exactamente el comportamiento que el PRD buscaba. La evidencia mecánica contradijo
mi propia afirmación de "hecho" — que es el principio §4.2 funcionando en vivo.

### G6 — `session-start.sh` tiene efectos secundarios y se puede invocar a mano

Ejecutarlo para *verificar* su salida borró los markers de skills leídas a mitad de sesión, y
el siguiente Edit quedó bloqueado. El script mezcla "informar" con "resetear estado".

- **Fix propuesto (no aplicado, requiere decisión del owner):** separar `--report` (puro) de
  `--reset` (efectos), y que el hook invoque `--reset --report`.
- **Estado:** registrado aquí; no entra en este PRD por §8 (scope).
- **Lección transferible:** un script que un humano va a ejecutar para inspeccionar debe tener
  un modo **sin efectos secundarios**. Si no lo tiene, observarlo lo modifica.

### Pendiente para el owner

- **Cerrar `f-8145599c`** en el ledger — ya está cubierto por
  `test_ratchet_duro_incluso_en_preset_lite`, pero `findings.ts` necesita Deno o Node y no
  había runner en el entorno. El ledger es NO-TOUCH manual (§5), así que se deja al owner:
  ```
  deno run -A tools/findings/findings.ts close f-8145599c \
    --resolution "PRD 0001: cubierto por tools/tests/test_ratchets.sh"
  ```
- **Registrar G1-G6 en `lessons_learned.md`** con su detector (el gate `lesson-detector-link.sh`
  lo exigirá cuando se añadan).
- **Subir el piso de mutación** en cuanto exista la primera medición real. Arranca en 0 para no
  romper repos existentes, y en 0 el gate no dice nada.
