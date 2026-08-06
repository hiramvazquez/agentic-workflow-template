# PRD — Cerrar el bucle de aprendizaje (el harness que aprende)

> **Tipo:** Forward · **Status:** Shipped
> **Autor:** Hiram (owner) · **Fecha:** 2026-08-06 · **Tracking:** PRD 0002 · commits `feat(findings)`, `feat(process)`
> **Design-review:** OK (2026-08-06) — la solución sale del audit post-PRD-0001: se verificó
> qué niveles de la pirámide están vivos y qué flujos de datos están desconectados, en vez de
> diseñar sobre suposiciones.

---

## 1. Contexto

El PRD 0001 construyó la pirámide de verificación: veredictos derivados por el sistema,
detectores AST, trinquetes, fail-closed en CI, y el principio "toda lección tiene detector".
Los 3 anillos funcionan (verificado en commits reales, con lefthook y semgrep vivos).

Un audit posterior contra el código —no contra el plan— encontró el gap estructural:

- **Cuatro archivos LEEN el ledger. Cero lo ESCRIBEN.** Los gates detectan (canon-enforce,
  semgrep, post-edit-verify, el `reviewer` con 13 hallazgos en 5 rondas) y todo se descarta.
  Solo llega al ledger lo que alguien añade a mano.
- `tools/findings/findings.ts` exige Deno/Node, que esta máquina no tiene → **el ledger es
  inoperable localmente**. Hay 9 findings esperando en `pending-import.json`.
- El `process-judge` existe y **nunca corre solo**: nada lo invoca ni recuerda invocarlo.
- La regla DbC de `AGENTS.md §5` no tiene mecanismo (nota registrable del reviewer en P2).
- La lección más repetida del PRD 0001 (tres detectores se auto-detectaron; "escribe los tests
  de falso positivo el mismo día que el detector") es prosa: nada la exige.

## 2. Problema

**El nivel 9 de la pirámide —el único mecanismo por el que la revisión humana decrece— está
construido pero desconectado por el lado de la entrada.** `escape-rate.sh` nunca tendrá datos;
"el que toca, cierra" (§10) depende de memoria; el ciclo error→lección→detector depende de que
alguien se acuerde. Sin esto, el harness verifica pero no aprende: la curva de esfuerzo humano
queda plana, que es exactamente lo que el proyecto existe para evitar.

Si no se construye: en 3 meses el ledger seguirá con los mismos 9 findings, la métrica de
contención seguirá vacía, y las decisiones sobre bajar revisión humana seguirán siendo
sensaciones.

## 3. Objetivo

- El ledger es **operable en esta máquina** (shell+python3, sin Deno/Node) y los 9 findings
  pendientes están importados, con vista humana regenerada.
- **Todo gate que detecta, registra.** Cada detección lleva `source`, y `escape-rate.sh`
  produce números reales por fase.
- El `process-judge` tiene **cola mecánica**: las sesiones que tocaron código quedan
  pendientes de juicio y visibles en cada turno hasta que el juez corre.
- **Todo detector tiene tests de falso positivo, verificado mecánicamente** (meta-detector).
- La regla DbC de §5 tiene mecanismo declarado (checklist del `reviewer` + mutation score).

Medible: `escape-rate.sh` con n>0 real · 0 detectores sin test de FP · cola de juicio visible.

## 4. Filosofía / principios

1. **Un mecanismo que existe y no está cableado es un mecanismo que no existe.** (Es la
   lección G5 del PRD 0001 aplicada al flujo de datos, no a los gates.)
2. **Eventos ≠ findings curados.** Las detecciones de los gates son *eventos* de métrica
   (alta frecuencia, se resuelven en el turno); el ledger es el inventario *curado* con
   estado terminal. Mezclarlos ahogaría el ledger — van a canales distintos que la métrica
   agrega.
3. **Sin dependencias nuevas.** La razón de que el ledger fuera inoperable es exigir un
   runtime que no estaba. El reemplazo usa lo que este repo ya asume: bash + python3.

## 5. Estructura de archivos a crear / tocar

```
── B: el bucle de datos ────────────────────────────────────────────────
tools/findings/findings.sh          ← NUEVO. CLI shell+python3: add/close/import/list/render.
                                       Mismo JSONL y mismos invariantes que findings.ts
                                       (add nunca resucita un estado terminal).
tools/findings/ledger.jsonl         ← importa pending-import.json (vía el CLI, no a mano)
docs/process/findings-ledger.md     ← vista regenerada (vía render)
scripts/agent-hooks/lib/io.sh       ← + hook_log_detection() (append de evento, best-effort)
scripts/agent-hooks/canon-enforce.sh    ← registra sus violaciones como eventos
scripts/agent-hooks/capture-review-verdict.sh ← registra veredicto+findings de cada review
scripts/agent-hooks/post-edit-verify.sh ← registra cuándo la señal in-loop encontró algo
scripts/agent-hooks/reviewer-gate.sh    ← registra hallazgos de semgrep/capas al bloquear
tools/metrics/escape-rate.sh        ← agrega ledger (curado) + eventos locales

── D3: el juez con cola ────────────────────────────────────────────────
scripts/agent-hooks/session-end.sh  ← NUEVO. SessionEnd: si la sesión tocó código y no hubo
                                       juicio → encola en .agents/state/judge-queue.txt
scripts/agent-hooks/inject-context.sh ← muestra la cola pendiente cada turno
scripts/agent-hooks/capture-review-verdict.sh ← matcher +process-judge: su veredicto
                                       escribe marker propio y VACÍA la cola
.claude/settings.json               ← + SessionEnd · matcher SubagentStop ampliado

── E1: la regla del falso positivo, mecanizada ─────────────────────────
tools/tests/test_meta_fp.sh         ← NUEVO. Manifiesto detector→archivo de test; exige que
                                       exista y contenga tests de FALSO POSITIVO
tools/tests/test_findings_cli.sh    ← NUEVO. Tests del CLI (TDD)
tools/tests/test_judge_queue.sh     ← NUEVO. Tests de la cola (TDD)
(tests existentes)                  ← etiquetas "FALSO POSITIVO" donde falten

── D1/E2: reglas con mecanismo declarado ───────────────────────────────
AGENTS.md                           ← §2 modo estricto (nivel 0) · §5 enforcement de DbC
.claude/agents/reviewer.md          ← checklist +DbC
.agents/skills/process/references/multi-agent-orchestration.md ← patrón N-jueces para alto riesgo
docs/process/current_execution_map.md ← estado actualizado
```

### NO-TOUCH

```
tools/findings/findings.ts          ← sigue siendo el CLI para quien tenga Deno/Node;
                                       findings.sh es el equivalente portable, no un reemplazo
tools/drift-ratchet.json · tools/mutation-ratchet.json  ← trinquetes (solo sus scripts)
docs/process/prds/_template.md · 0001-*.md
scripts/agent-hooks/skill-reminder.sh · drift-stop.sh   ← fuera de scope
```

## 6. Modelo de datos

**Ledger (curado, committeado)** — mismo esquema que `findings.ts`:
`{id,title,area,severity,tier,status,source,detail,effort,resolution,links,createdAt,updatedAt}`.
Invariante heredado: add/import **nunca** resucitan un estado terminal.

**Eventos de detección (métrica, local)** — `.agents/state/metrics/detections.jsonl`:
`{ts,source,rule,area,n}`. Gitignored a propósito (como la trayectoria): es telemetría de esta
máquina, alta frecuencia, sin estado terminal. `escape-rate.sh` la agrega junto al ledger y
etiqueta qué parte es local.

**Cola de juicio** — `.agents/state/judge-queue.txt`: una línea por sesión pendiente
(`ts · session_id · branch · archivos tocados`). La vacía el veredicto real del `process-judge`
(vía SubagentStop), no el modelo.

## 7. Flujo de la solución

```
gate detecta ──► hook_log_detection (evento, best-effort, jamás bloquea)
                          │
escape-rate.sh ◄── ledger (curado) + detections.jsonl (local)
                          ▲
reviewer/judge emiten VERDICT ──► capture-review-verdict ──► marker + evento
                          │
SessionEnd con código tocado y sin juicio ──► judge-queue ──► visible cada turno
                          │                                        │
                          └────────── process-judge corre ─────────┘
                                       (su VERDICT vacía la cola)
```

### Edge cases

- **`hook_log_detection` falla** (disco, python3 ausente) → silencio y sigue: la telemetría
  jamás puede romper un gate. (Es métrica, no enforcement.)
- **python3 ausente** → `findings.sh` falla con mensaje claro; `findings.ts` sigue disponible
  para quien tenga Deno/Node. Dos CLIs, un esquema.
- **Import repetido** → idempotente (upsert por id; terminal no resucita).
- **SessionEnd sin cambios de código** → no encola. **Sesión ya juzgada** → no encola.
- **Cola con entradas de sesiones viejas** → se muestran igual; el juicio es por lote de
  trabajo, no por sesión exacta.

## 8. Anti-features

- **No** se auto-invoca el `process-judge` (`claude -p` desde un hook = coste no consentido).
  La cola hace el trabajo visible; invocarlo sigue siendo decisión del humano/agente.
- **No** se escriben eventos en archivos committeados (dirtiaría el árbol en cada hook).
- **No** se implementa el detector de densidad de aserciones por grep: sin parser real por
  lenguaje sería ruido (ley del 10%). El mecanismo de DbC es el checklist del `reviewer` +
  mutation score, declarado como tal.
- **No** se resuelven los owner-decision abiertos (f-marker-spoof, f-harness-no-autogate…).
- **No** se tocan A2/A3 del plan (lint in-loop y mutación del stack): necesitan el stack real.

## 9. Escenarios golden

1. `bash tools/findings/findings.sh import tools/findings/pending-import.json` deja el ledger
   con 9 findings (5 open), es idempotente, y `f-8145599c` queda `fixed` sin resucitar.
2. Un `Stop` bloqueado por canon-enforce deja un evento `source=canon-enforce` en
   `detections.jsonl`, y `escape-rate.sh` lo cuenta en el bucket `gate`.
3. Un VERDICT RED del `reviewer` con `FINDINGS: 3` deja un evento `source=reviewer n=3`.
4. Una sesión que editó código y termina sin juicio aparece en la cola; el siguiente turno la
   muestra; un VERDICT del `process-judge` la vacía y escribe `process-judge_run.txt`.
5. `test_meta_fp` falla si un detector del manifiesto no tiene archivo de test o su archivo no
   contiene tests de falso positivo; pasa con el estado actual (tras etiquetar).
6. Todos los invariantes previos se mantienen: suite completa verde, drift 0, capas 0.

## 10. Métricas de éxito

| Métrica | Antes | Después |
|---|---|---|
| Scripts que ESCRIBEN al ledger/eventos | 0 | ≥4 gates + CLI |
| Ledger operable sin Deno/Node | no | sí |
| `escape-rate.sh` con datos | 0 eventos | eventos reales por fase |
| Detectores con test de FP verificado | 0 mecanizado | 100% del manifiesto |
| process-judge con recordatorio mecánico | no | cola visible por turno |

## 11. Rollout

Dos commits: (1) `feat(findings)` — CLI + import + eventos + métrica; (2) `feat(process)` —
cola de juicio + meta-FP + DbC/N-jueces en doc. Cada uno revertible. Sin gates bloqueantes
nuevos (los eventos son best-effort), así que el riesgo de sobre-bloqueo es cero.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| Telemetría rompe un gate | `hook_log_detection` con `|| true` total; test que lo fija |
| Dos CLIs divergen (ts/sh) | mismo esquema + test de idempotencia; findings.ts queda NO-TOUCH |
| Ledger ahogado por eventos | eventos van a canal local separado (principio §4.2) |
| Cola de juicio como ruido | una línea por sesión, se vacía con un juicio; sin bloqueo |
| Meta-FP con falsos positivos | manifiesto explícito, no heurística de nombres |

## 13. Open Questions

- [x] ¿Eventos al ledger o canal aparte? → canal aparte local (§4.2).
- [x] ¿Auto-invocar el judge? → No: cola visible, invocación humana (§8).
- [x] ¿Detector de aserciones por grep? → No: reviewer checklist + mutación (§8).

## 14. Mockups / referencias

Salida objetivo de `escape-rate.sh` tras una semana de uso: buckets in-loop/gate/review con
n>0 provenientes de eventos, y la línea "ESCAPE RATE" calculada sobre datos, no sobre cero.

## 15. Definition of Done

- [ ] Escenarios golden 1-6 pasan
- [ ] TDD: findings.sh, log-detection, judge-queue y meta-FP con tests escritos primero
- [ ] Suite completa verde · check-drift sin errores nuevos · gitleaks limpio
- [ ] `reviewer` GREEN/AMBER atendido (el diff toca AGENTS.md = producto)
- [ ] Ledger importado, `f-8145599c` cerrado, vista regenerada
- [ ] Execution map actualizado

## 16. Próximos pasos (fuera de este PRD)

A2/A3 del plan (lint in-loop y mutación) al fijar stack · decisiones owner de los 5 findings
abiertos · N-jueces como workflow ejecutable · fuzzing/DST/SBOM (PRD 0001 §16).

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-06 | Draft + Approved (audit-driven) · arranca implementación | Hiram/Claude |
| 2026-08-06 | Shipped: commits 6454f69 (findings) + 44d319f (process) + fix -F. 105 tests | Claude |

## 18. Gaps detectados (durante la implementación)

### G1 — Un test verde por el motivo equivocado
El dedup de la cola grepeaba el SID en un marker que **nunca lo contenía** — código muerto.
Su test pasaba porque el fixture metía el SID en el `SCOPE:` del mensaje simulado: el test
verificaba el artefacto del fixture, no el contrato. Lo cazó el `reviewer` trazando el flujo,
no ejecutando los tests (los 102 estaban verdes).
- **Fix:** campo `session:` explícito en el marker + match exacto + 2 tests del contrato real.
- **Lección transferible:** cuando un test necesita fabricar un dato para pasar, pregúntate si
  el sistema real produce ese dato. Si no, el test verifica tu fixture.

### G2 — Los datos no son patrones (grep sin -F)
`grep -qx "session: ${SID}"` interpreta el SID como regex BRE: con "s-aXc" juzgada, el cierre
de "s-a.c" (distinta, sin juzgar) matcheaba y se saltaba el encolado en silencio. Reproducido
por el reviewer en la verificación del fix anterior — **un hallazgo encontrado revisando la
corrección de otro hallazgo**, tercera vez que pasa en este repo (PRD 0001 §18 "arreglar un
hallazgo introdujo uno peor").
- **Fix:** `grep -qxF`. Test `test_el_sid_es_dato_no_patron`, verificado por mutación manual:
  revertir el `-F` lo hace fallar. Un test que no mata su mutante es decorativo.
- **Lección transferible:** todo `grep`/`sed` cuyo patrón venga de una VARIABLE debe usar
  match literal (`-F`) salvo intención explícita. Candidata a regla de `test_shell_hygiene`
  (registrada como ampliación futura, no implementada: detectarlo sin FPs requiere distinguir
  patrones intencionales, y un detector ruidoso se descarta entero).

### G3 — El typo cirílico
Al editar `reviewer.md` se coló "входe" (cirílico) por "entrada". Sin consecuencia mecánica
(prosa), pero ilustra el mismo modo de fallo que G14 del PRD 0001: texto no-ASCII donde no se
espera. Detectado a ojo — ningún gate mira la prosa, y está bien que así sea.

### Validación del propio bucle
Los 2 hallazgos registrables de esta implementación (`f-meta-fp-manifiesto`, `f-meta-fp-self`)
se registraron **con el CLI construido en este PRD**, y el criterio bloqueante-vs-registrable
del patrón N-jueces se aplicó en su propia review. El bucle se usó para cerrarse a sí mismo.
