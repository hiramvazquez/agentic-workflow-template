# PRD — Estabilización del harness: señal determinista, verdad única, menos complejidad

- **Status:** Draft (pendiente de Approved del owner + design-review del CÓMO)
- **Origen:** evaluación externa del workflow sobre `cab2f4c`, re-verificada por el
  adoptante (11 de 12 cifras reproducidas) y re-verificada de nuevo al redactar este
  PRD (518+ funciones `test_*` contra 477 declaradas; contexto vivo en 250/250;
  los cinco tamaños de archivo, exactos).
- **Owner:** Hiram · **Implementadores:** agentes del template, una ola por sesión

## 1. Contexto

El harness cruzó un umbral: detecta bien, y empieza a pagar caro mantener, explicar y
ejecutar sus defensas. La evaluación (WF-01…WF-09) no encontró gates ausentes sino
señal intermitente, cifras canónicas podridas y complejidad interna. Tres de los
hallazgos caen sobre código con menos de dos días (`scope.sh`, `check-source-sets.sh`,
los añadidos a `test_verdict.sh`): eso es la revisión funcionando, no deuda vieja.

## 2. Problema

1. **La señal no es determinista.** CI macOS roja dos runs recientes por
   `test_review_tambien_respeta_timeout`; HEAD pasó después. Rerun-hasta-verde degrada
   la confianza en el gate entero.
2. **El estado canónico miente.** El mapa —que todos los agentes reciben con autoridad
   en cada arranque— declara 477 tests (hay ≥518) y 236 líneas de contexto (hay 250,
   el límite exacto). El PRD 0004 figura Shipped con pendientes en su DoD. Ya hay una
   lección sobre conteos hardcodeados (README los retiró); el mapa la violó.
3. **La complejidad supera los límites que el propio harness impone** (§4): cinco
   archivos sobre o rozando el hard limit de 400 líneas.

## 3. Objetivo

Un harness **igual de estricto, más estable y más pequeño**, cuyas afirmaciones
operativas coincidan con la evidencia. Nada de gates nuevos (WF-09: ventana de
observación del PRD 0004 §16 en curso).

## 4. Filosofía / principios

- La prioridad ya NO es añadir defensas: es que las existentes sean deterministas,
  verdaderas y mantenibles.
- Cifra derivable en doc vivo = mentira futura garantizada. Se sustituye por comando,
  artefacto generado, o evidencia con commit+fecha.
- Simplificar sin retirar garantías: contratos públicos y nombres de escenarios
  intactos; mutantes antes/después demuestran que dividir no debilitó.
- Timeout que sube "para estabilizar" = bug escondido. Causa raíz primero.

## 5. Estructura de archivos a tocar

| Ola | Archivos |
|---|---|
| 0 | `tools/tests/test_agent_runner.sh` (+ runner si la causa está ahí) · `docs/process/current_execution_map.md` · `tools/check-execution-map.sh` (test anti-claims-derivables) · `docs/process/prds/0004-*.md` (solo status/checklist) · `tools/lessons-rotate.sh` |
| 1 | `scripts/agent-hooks/capture-review-verdict.sh` + emisor JSON común en `scripts/agent-hooks/lib/` · `tools/lib/scope.sh` · `tools/check-source-sets.sh` (+ regla semgrep kotlin) |
| 2 | `tools/upgrade.sh` → `tools/lib/upgrade-{propiedad,transporte,reporte}.sh` · `tools/tests/test_{upgrade,e2e_matrix,verdict}.sh` divididos por contrato · mapa (staging por paths) |
| 3 | solo lectura: telemetría + decisión keep/tune/retire por defensa |

### NO-TOUCH

```text
ios/ android/ web/                     ← sin producto de app aquí; no inventarlo
tools/drift-ratchet.json · tools/mutation-ratchet.json
.gitleaks.toml salvo lo ya acordado    ← sin cambio de política de secretos
docs/process/prds/0001..0004           ← histórico; 0004 SOLO status/checklist
contratos públicos: exit codes 0/1/3, nombres de escenarios golden, formato de markers
```

## 5b. Fases entregables

| Fase | Entrega | Gate de salida |
|---|---|---|
| 0a | WF-01: causa raíz del timeout macOS, test rojo determinista, 124 siempre propagado, descendientes reaped | 30 runs macOS consecutivos sin rerun |
| 0b | WF-02: mapa sin cifras derivables + test que falla si vuelven; PRD 0004 reconciliado | `check-execution-map.sh` caza un claim derivable plantado |
| 0c | WF-07: rotador idempotente (bytes idénticos en N pasadas), un separador, headroom ≥25 líneas | dos ejecuciones seguidas → diff vacío |
| 1a | WF-03: emisor JSON único + escritura atómica; consumidores parsean, no grepean | rojos previos con `"` `\` tab CR/LF en agent_id/scope/nota |
| 1b | WF-05: `project_kind` declarado con verificación contra evidencia (ver §6) | fixtures harness/iOS/monorepo/doc-repo; ausente ⇒ diagnóstico, no silencio |
| 1c | WF-06: detector KMP sintáctico (semgrep kotlin, exit 3 honesto); el grep actual queda como fallback DECLARADO cuando semgrep falte | bloque `/* */` y string `"""` con import dentro NO disparan; import real sí |
| 2a | WF-04: upgrade y los tres tests divididos por contrato; hook sobre libs puras | todo <400 líneas; mutantes equivalentes antes/después |
| 2b | WF-08: staging por paths en docs canónicos; `git add -A` solo tras `git status --short` limpio de fuera-de-scope | ningún doc canónico recomienda `-A` sin precondición |
| 3 | WF-09: reporte de valor por gate desde telemetría; keep/tune/retire | decisión escrita por defensa; el finding de mutation-score no se cierra sin evidencia del adoptante |

Una ola por sesión de agente, cada una revertible.

## 6. Decisiones de diseño ya tomadas (para el design-review)

- **WF-05, síntesis de las dos posturas.** La inferencia por ausencia se eligió a
  propósito ("no depende de un flag que alguien pueda poner mal") y el hallazgo tiene
  razón en que un monorepo `packages/` la rompe. Ninguna de las dos sola:
  `project_kind` **declarado** en conf estructurada + **verificado contra la evidencia**
  — si declara `application` y no hay una sola fuente de app, o declara `harness` y las
  hay, el gate lo dice en voz alta (exit 3, no silencio). Un flag verificado no es un
  flag que alguien pueda poner mal sin enterarse.
- **WF-06.** El agujero (`/* */`, `"""`) es real y es del autor de este PRD. Semgrep
  kotlin como detector primario con contrato 0/1/3; el grep actual NO se retira sin
  reemplazo operativo demostrado (riesgo: semgrep ausente ⇒ nivel mudo).
- **WF-08, con confesión.** El `git add -A` del mapa no llegó solo: el flujo que este
  mismo bucle ha estado dictando lo usaba en cada commit. El fix incluye los ejemplos
  del propio bucle de trabajo.
- **WF-07 resuelto:** son **12** separadores (re-verificado dos veces); la cifra "8/15
  líneas" del informe original estaba mal. El objetivo de headroom se fija sobre 12.

## 8. Anti-features

Sin anillos ni perfiles nuevos · sin sandbox obligatorio · sin fuzzing/formales · sin
proveedor de agentes obligatorio · sin relajar reviewer/verify/seguridad/ratchets/Anillo 3
· sin cerrar findings bloqueados por evidencia externa · sin subir timeouts como arreglo.

## 9. Escenarios golden

1. 30 runs macOS consecutivos verdes sin rerun; el timeout devuelve 124 con diagnóstico.
2. Plantar "hay 999 tests" en el mapa ⇒ `check-execution-map.sh` falla nombrando la línea.
3. `agent_id` con `"` y CR/LF ⇒ historial parsea con `jq -e`, dedupe intacto.
4. Monorepo `packages/` declarado `application` ⇒ review de app; sin declarar ⇒ diagnóstico.
5. `import android.net.Uri` dentro de `/* */` en commonMain ⇒ 0; fuera ⇒ 1; sin semgrep ⇒ 3.
6. Rotador dos veces seguidas ⇒ bytes idénticos; contexto ≤225.
7. Todo ejecutable y test <400 líneas con la misma matriz golden verde y mutantes equivalentes.

## 12. Riesgos

Los ocho del informe §8, más uno propio: **este PRD lo redactó el mismo agente cuyos
añadidos recientes motivan WF-04/05/06.** Mitigación: el design-review del CÓMO lo hace
otro (adoptante o design-reviewer en sesión limpia), y cada fase lleva reviewer GREEN.

## 13. Open Questions

- [ ] ¿Ola 0 empieza ya (es confiabilidad, exenta del freeze WF-09) o tras la ventana?
- [ ] WF-05: ¿dónde vive `project_kind`? (candidato: `tools/capabilities.json`, ya existe y viaja)
- [ ] WF-01: sin acceso a macOS desde este entorno, ¿quién reproduce bajo carga: el owner en su Mac o CI con matrix repetida?

## 15. Definition of Done

- [ ] La DoD del informe (§7) completa, sin contradicciones mapa/PRD/health-check.
- [ ] Cada fase: test rojo antes del fix, reviewer GREEN, finding en estado terminal.
- [ ] Verificado en ambas topologías de upgrade y después en el adoptante.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-19 | Draft desde la evaluación externa + re-verificación de cifras (518 vs 477; 12 separadores; tamaños exactos) | agente del template |
