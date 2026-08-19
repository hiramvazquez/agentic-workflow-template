# PRD — Estabilización del harness: señal determinista, verdad única, menos complejidad

- **Status:** Draft v3 — RED (10) atendido y re-review AMBER (6) atendido; **listo para Approved del owner**, que además ratifica las fases 0b/0c ya entregadas
- **Origen:** evaluación externa sobre `cab2f4c` (docs/process/reviews/2026-08-18-*.md),
  re-verificada por el adoptante (11/12 cifras)
- **Owner:** Hiram · **Implementadores:** agentes del template, una fase por sesión/subagente

## 1. Contexto

El harness detecta bien y paga caro mantener, explicar y ejecutar sus defensas. La
evaluación (WF-01…WF-09) no pide gates nuevos: pide señal determinista, verdad única y
menos complejidad. Tres hallazgos caen sobre código de esta misma semana — la revisión
funcionando, no deuda vieja.

**Estado a la fecha de este draft:** fases 0b y 0c YA ENTREGADAS y verificadas
(subagentes, 2026-08-19): mapa sin cifras derivables + detector con FP-guards; rotador
canónico, contexto vivo 250→212 (headroom 38). Se ejecutaron invocando la excepción del
freeze de WF-09 (corrección de drift real y de confiabilidad, no gates de producto nuevos).

## 2. Problema

1. **Señal no determinista:** CI macOS roja dos runs por `test_review_tambien_respeta_timeout`;
   HEAD verde después. Rerun-hasta-verde degrada la confianza entera.
2. **El estado canónico mentía** (RESUELTO en 0b): 477 tests declarados vs ≥518 reales.
3. **Complejidad sobre los límites propios:** upgrade 664, tres tests 484–633, hook 371/400.

## 3. Objetivo

Un harness igual de estricto, más estable y más pequeño, cuyas afirmaciones coincidan con
la evidencia. **Sin gates de producto nuevos durante la ventana de WF-09**; los detectores
de las fases 0b (anti-claims) y 1c (semgrep kotlin) entran por la excepción declarada del
freeze — drift real y corrección de falsos positivos/negativos de defensas existentes — y
este párrafo lo dice en vez de negar el hecho (hallazgo 10 del review).

## 4. Filosofía

- Cifra derivable en doc vivo = mentira futura garantizada.
- Simplificar sin retirar garantías; mutantes ANTES/después desde corpus versionado.
- Timeout que sube "para estabilizar" = bug escondido.
- Un fallback que degrada un bloqueo a un aviso no es un fallback: es el gate apagado.

## 5. Estructura de archivos a tocar

| Fase | Archivos |
|---|---|
| 0a | `tools/tests/test_agent_runner.sh` (+ runner si la causa vive ahí) |
| 0b/0c | entregadas pendientes de ratificación: mapa, check-execution-map, lessons-rotate + tests |
| 1a | `capture-review-verdict.sh` + emisor JSON en `scripts/agent-hooks/lib/json.sh` |
| 1b | `tools/lib/scope.sh` · `tools/project.conf` (NUEVO) · **`tools/check-review-marker.sh` · `tools/check-verify-marker.sh`** (consumidores; hallazgo 7) · `scripts/agent-hooks/session-start.sh` (diagnóstico) · `tools/upgrade.sh` (crear el conf si falta, jamás pisarlo) |
| 1c | `tools/check-source-sets.sh` · regla semgrep kotlin · `ci/run-gates.sh` (toggle) |
| 2a | `tools/upgrade.sh` → orquestador + `tools/lib/upgrade-*.sh` · los tres tests divididos |
| 2b | mapa y docs canónicos: staging por paths |
| 3 | solo lectura: telemetría, keep/tune/retire |

### NO-TOUCH

```text
ios/ android/ web/ · ratchets · .gitleaks.toml (política) · PRDs 0001-0004 (histórico;
0004 ya reconciliado en 0b)
CONTRATOS CONGELADOS (hallazgo 4 — enumerados, no resumidos):
  · detectores: exit 0/1/3            · upgrade.sh: exit 0/1/2 (el 2 = conflictos, SE CONSERVA)
  · nombres de escenarios golden      · formato de markers (source: hook, staged_sha)
  · schema actual de review-history.jsonl: los campos existentes no se renombran;
    la fase 1a puede AÑADIR campos y versionar (campo "v"), con lectura backward
```

## 5b. Fases y gates — entrega ≠ cierre (hallazgo 9)

Cada fase se ENTREGA en una sesión. Su GATE puede cerrar después, con responsable:

| Fase | Entrega | Gate de cierre | Responsable del gate |
|---|---|---|---|
| 0a | causa raíz + test rojo determinista + 124 propagado + reaped | 30 runs macOS consecutivos sin rerun | **owner** (bucle en su Mac) o matriz CI programada; asíncrono |
| 0b | ENTREGADA, pendiente de ratificación | check caza claim plantado ✅ (visto en rojo) | **owner**: el Approved de este PRD ratifica lo ejecutado; sus commits pasan reviewer-gate |
| 0c | ENTREGADA, pendiente de ratificación | bytes idénticos ✅ · headroom 38 ✅ | ídem — se ejecutó antes del Approved (hallazgo AMBER-1: el orden fue el inverso al gate §12; queda escrito, no normalizado) |
| 1a | emisor JSON único + escritura atómica + **migración: campo "v", lectura backward de líneas v1, corrupción preexistente ⇒ estado explícito nunca falso verde** (hallazgo 8) | rojos previos con `"` `\` tab CR/LF en agent_id/scope/nota; historial siempre `jq -e` válido; dedupe sobre campos parseados | implementador |
| 1b | project_kind declarado (§6) | fixtures harness/iOS/monorepo/doc-only/sin-declarar; **cero FPs nuevos en el adoptante existente** (hallazgo 8) | implementador + verificación del adoptante |
| 1c | detector sintáctico con tabla de fallback (§6) | matriz completa §6 incl. "sin semgrep + violación real"; aliases e imports con whitespace; **FP <10% medido contra corpus KMP ajeno** | implementador |
| 2a | división con restricción de bootstrap (§6) | todo <400 líneas; mutantes desde `tools/tests/fixtures/mutantes/` (corpus COMMITEADO con MANIFIESTO mutante→test que la división actualiza en el mismo commit — la equivalencia se comprueba contra el manifiesto, no contra nombres de archivo que la propia división renombra, AMBER-6); **golden nuevo: upgrade con skew de versiones invocando el script viejo del adoptante** | implementador |
| 2b | staging por paths en docs canónicos | ningún doc recomienda `-A` sin precondición | implementador |
| 3 | reporte de valor por gate | keep/tune/retire escrito por defensa; **la ventana de 2–4 semanas EMPIEZA al cerrar la ola 2** — medir el harness pre-estabilización contaminaría la línea base (hallazgo 9); mutation-score no se cierra sin evidencia del adoptante | owner |

Orden dentro de cada ola: el declarado arriba (0b antes que 0c ya se cumplió así).

## 6. Decisiones de diseño (para el re-review)

**WF-05 — la declaración GOBIERNA; la evidencia solo verifica (hallazgo 1, invertido como
pedía el informe).**
- `project_kind: harness|application|other` vive en **`tools/project.conf`** (NUEVO; fuera
  de `SYNC_PATHS`/`SYNC_GLOBS`, propiedad del proyecto — mismo modelo que `tools/preset`,
  que ya resuelve este problema; hallazgo 7). `upgrade.sh` lo CREA con valor inferido y
  comentario si no existe; jamás lo pisa. `capabilities.json` queda descartado: el sync lo
  pisa y un FILL lo congelaría.
- **Función de evidencia, definida:** "fuentes de app" = archivos `*.swift|kt|java|ts|tsx|js|py|go|rb|cs|rs`
  bajo CUALQUIER ruta del repo EXCEPTO `tools/ scripts/ ci/ docs/ .agents/ enterprise/` y
  `**/fixtures/`. Cubre monorepos (`packages/`, `services/`) y no cuenta los `.py`/fixtures
  del propio harness (los dos contraejemplos del hallazgo 1).
- **`other` significa** exención amplia estilo app: en un repo doc-only sus directorios de
  contenido NO exigen review (decisión explícita, AMBER-5; quien quiera review sobre docs
  declara `harness`). Y como el template commitea su `project.conf` con `harness`, la
  adopción POR COPIA lo arrastra: `docs/ADOPTION.md` y el bootstrap piden el flip explícito
  en el primer arranque, y la contradicción con la evidencia lo delata mientras tanto.
- **Tabla completa:**

| Declarado | Evidencia | Resultado |
|---|---|---|
| `application`/`other` | cualquiera | criterio de app (exención amplia). La declaración manda. |
| `harness` | sin fuentes de app | criterio harness |
| `harness` | CON fuentes de app | criterio harness (manda) + `SCOPE_SUMMARY kind=harness evidencia=contradice` + aviso; en CI exit 3 |
| `application` | sin fuentes | ídem invertido: manda, avisa, CI exit 3 |
| ausente | — | fallback = heurística actual (compatibilidad, cero FPs nuevos) + UNA línea de diagnóstico en session-start (`project_kind sin declarar — tools/project.conf`), NUNCA por commit (ley del 10%) |
| doc-only sin declarar | sin fuentes | la heurística dice harness — es el caso que obliga a declarar `other`; el diagnóstico de session-start lo dice explícitamente |

**WF-06 — tabla de fallback que conserva el bloqueo (hallazgo 3).**

| semgrep | grep interno | exit |
|---|---|---|
| operativo | — | 0 ó 1 según semgrep (fuente primaria) |
| ausente/roto | limpio | 3 — aviso local; en CI según `GATES_REQUIRE_SOURCE_SETS` con auto-escalada estilo mutation. El registro "semgrep fue operativo aquí" vive COMMITEADO y adopter-owned: una línea en `tools/project.conf` (AMBER-3 — sincronizado heredaría el estado del template; gitignored no existiría en el checkout de CI y la escalada jamás se activaría) |
| ausente/roto | **encuentra import real** | **1 — el fallback existe exactamente para esto; degradar aquí a 3 sería apagar el gate** |
| repo sin commonMain | — | 0 `no-aplica` (sin cambio) |
| operativo pero SALTA un `.kt` de commonMain (parse error, exit 0 con skip) | — | los archivos saltados pasan por el grep y se reportan — "operativo" no es binario por repo (AMBER-4) |

**WF-04 / fase 2a — restricción de bootstrap (hallazgo 2, bloqueante).** La
auto-actualización copia HOY solo `tools/upgrade.sh` a un temporal y hace `exec`: un
orquestador que sourcee libs inexistentes en el árbol del adoptante rompe a TODOS los
adoptantes en el salto de versión. Restricción de diseño, precisada por el
re-review (AMBER-2): (a) la extracción de libs ocurre en el ARRANQUE del proceso
RE-LANZADO (rama `UPGRADE_SELF_TMP`, antes de cualquier `source`) — el proceso viejo N-1
no se puede retrofitear, así que es el nuevo quien se autoabastece; (b) el version-check
deja de comparar solo `upgrade.sh`: compara orquestador + `tools/lib/upgrade-*.sh` contra
el ref y, ante CUALQUIER diff del conjunto, extrae el conjunto entero al temporal y
ejecuta desde ahí — sin esto, un fix que toque solo una lib nunca llega mecánicamente (la
pescadilla original, ahora para las libs); (c) fallback autocontenido si el ref no trae
libs (salto desde pre-división). Golden obligatorio en la matriz E2E: sandbox con
adoptante en N-1 que invoca SU `upgrade.sh` viejo (no el nuevo) contra template en N → el
upgrade completa.

**WF-07 — rectificación (hallazgo 5, y es mía).** El montón antes del índice eran **8
separadores / 15 líneas, como decía el informe original**; mis "12" contaban 3 colas de
entrada y 1 separador estructural. La "corrección al informe" del draft v1 era el mismo
pecado que motiva WF-02, cometido en el doc que lo arregla. Se deja escrito. (La fase 0c
cumplió su gate igualmente — 212 líneas — porque el grueso vino de arreglar el veto
KEEP-VISIBLE, no del colapso.)

**Escenario anti-claims (hallazgo 6).** La cabecera de `check-execution-map.sh` declara
ahora DOS excepciones con su justificación: literales `grep -F` (FP cero, caza
reincidencias conocidas) y la ERE cerrada `N tests|pruebas|líneas` con sus FP-guards
fijados por test. Honestidad del alcance: caza la CLASE de esa forma cerrada, no cualquier
redacción — un claim derivable con otra sintaxis lo evade, y decirlo es parte del contrato.

## 8. Anti-features

Sin anillos/perfiles nuevos · sin sandbox obligatorio · sin fuzzing/formales · sin
proveedor obligatorio · sin relajar reviewer/verify/seguridad/ratchets/Anillo 3 · sin
cerrar findings bloqueados por evidencia externa · sin subir timeouts como arreglo.

## 9. Escenarios golden

1. 30 runs macOS consecutivos verdes sin rerun; timeout ⇒ 124 con diagnóstico.
2. ✅ "hay 999 tests" plantado ⇒ check falla nombrando la línea (entregado en 0b, visto en rojo).
3. `agent_id` con `"` y CR/LF ⇒ historial `jq -e` válido, dedupe intacto; línea corrupta previa ⇒ estado explícito, nunca verde.
4. Monorepo `packages/` + `project_kind: application` ⇒ criterio de app SIN aviso (la declaración manda). Sin declarar ⇒ una línea en session-start, cero avisos por commit.
5. `import android.net.Uri` en `/* */` o `"""` en commonMain ⇒ 0; real ⇒ 1; sin semgrep y violación real ⇒ 1 vía fallback; sin semgrep y limpio ⇒ 3.
6. ✅ Rotador dos veces ⇒ bytes idénticos; contexto 212 ≤ 225 (entregado en 0c).
7. Todo <400 líneas; mutantes del corpus commiteado equivalentes antes/después; **upgrade con skew de versiones completa**.

## 10. Métricas de éxito (hallazgo 8 — faltaba la sección)

- first-pass CI success y rerun rate, antes/después de la ola 0 (de la API de Actions);
- p50/p95 de gates y reviews desde telemetría (eventos v2), no fijados a priori;
- FP observados de los detectores tocados (<10% o caen);
- LOC de los cinco archivos de WF-04, antes/después;
- findings por fase, escapes y tiempo de remediación durante la ventana de fase 3.

## 12. Riesgos

Los del informe §8, más: el redactor de este PRD escribió parte del código evaluado
(WF-04/05/06) y su draft v1 contenía el error del hallazgo 5 — mitigación: re-review
adversarial obligatorio de este v2, y el process-judge presenta evidencia final antes de
cerrar el programa (hallazgo 8).

## 13. Open Questions

- [x] ¿Ola 0 arranca ya? SÍ — ejecutada (0b/0c) por la excepción del freeze; 0a entregable ya, su gate asíncrono.
- [x] ¿Dónde vive project_kind? `tools/project.conf`, fuera del sync (§6).
- [ ] WF-01: ¿el bucle de 30 runs lo corre el owner en su Mac o una matriz CI programada?

## 15. Definition of Done

- [ ] La DoD del informe (su **§6, política de entrega; los KPIs son su §7**) completa.
- [ ] Cada fase: test rojo antes, reviewer GREEN, finding terminal, evidencia en el ledger.
- [ ] Upgrade verificado en ambas topologías + skew de versiones, y después en el adoptante.
- [ ] El process-judge presenta evidencia final del programa.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-19 | Draft v1 desde la evaluación externa | agente del template |
| 2026-08-19 | Design-review adversarial: RED, 10 hallazgos | design-reviewer (subagente limpio) |
| 2026-08-19 | v2: los 10 atendidos — evidencia de WF-05 definida + tabla de exits; restricción de bootstrap en 2a; tabla de fallback 1c; NO-TOUCH enumerado (exit 2, schema); rectificación del conteo (8, no 12); doctrina del check con 2 excepciones; project.conf fuera del sync + consumidores en ola 1; criterios caídos restaurados + §10; entrega≠cierre con responsables y ventana post-ola-2; §3 invoca la excepción del freeze. Fases 0b/0c entregadas y cerradas. | agente del template |
| 2026-08-19 | Re-review: AMBER, 6 hallazgos (2 bloqueantes del RED resueltos) | design-reviewer |
| 2026-08-19 | v3: los 6 atendidos — 0b/0c "pendientes de ratificación" (no "cerradas" en un Draft); bootstrap con extracción en el proceso re-lanzado + trigger sobre el conjunto + golden con el script viejo; estado de la auto-escalada en project.conf commiteado; archivos saltados por semgrep pasan por el grep; semántica de `other` y flip en adopción por copia; manifiesto mutante→test | agente del template |
