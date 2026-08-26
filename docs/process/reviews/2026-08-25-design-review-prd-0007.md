# Design-review del PRD 0007 — las rondas del 2026-08-25

> **Por qué existe este archivo:** los reportes originales del `design-reviewer` viven en
> `.agents/state/reviews/`, que `.gitignore` excluye entero — no sobreviven a otro clon. Peor:
> ambas rondas se invocaron sin diff staged, así que comparten identidad
> (`e3b0c44298fc` = sha256 de la cadena vacía) y se acumularon en el mismo archivo local
> (`f-35ef4b81` registra la mitad harness de ese problema). Este documento es la copia durable
> que el PRD cita: condensada de los reportes reales del mismo día, suficiente para revalidar
> cada hallazgo. Provenance (campos pegados aquí porque `review-history.jsonl` es gitignored y
> no puede comprobarse desde otro clon — `f-9855ecb`): sub-agente `design-reviewer` ·
> ronda 1 `ts=2026-08-26T01:35:34Z head=db371f2 verdict=RED findings=15` ·
> ronda 2 `ts=2026-08-26T02:17:24Z head=b5a41bb verdict=AMBER findings=13` ·
> (ronda 3, posterior a este doc: `ts=2026-08-26T05:34:53Z head=d847c76 verdict=AMBER
> findings=12`, sobre la v2.2 — sus hallazgos NEW-1..12 están en el ledger y los cierra la
> v2.3). Las tres comparten `staged_sha=e3b0c44298fc…` (el sha de vacío — `f-35ef4b81`).

---

## Ronda 1 — sobre el Draft v1 · VERDICT: RED · 15 hallazgos

Juicio global: el approach es sólido (el §4 del PRD — "un módulo, varias skills; la completitud
se mide en decisiones cubiertas" — es la mejor parte); lo roto eran quince agujeros de diseño,
tres bloqueantes, dos de ellos sobre las afirmaciones centrales del PRD.

| # | Sev. | Hallazgo (qué estaba mal → fix propuesto) |
|---|---|---|
| F1 | **BLOQ.** | `docs/process/decisions/` NO era nuevo: ya existía con formato ADR y numeración `NNNN-*` propia (`decisions/README.md`), y el PRD metía un segundo formato en el mismo directorio → colisión de numeración y FP del futuro check el día 1. Fix: decidir si registro=ADR (ampliar formato, campos opcionales) o directorio aparte. |
| F2 | **BLOQ.** | El criterio de autonomía no era falsable: (1) invocaba al `design-reviewer`, cuyo contrato es revisar PRDs, no código; (2) "sin desviaciones" no mapeaba a ninguna salida parseable — §14.2 prohíbe veredictos que sean afirmación del modelo; (3) sin independencia declarada del hilo constructor; (4) N=1 sobre un instrumento de varianza medida 4.0–9.0. Fix: procedimiento — mecánica primero (layers+skills+cobertura), luego reviewer de código en contexto limpio con línea `ARCH_DEVIATIONS: <n>`, tarea elegida por el owner, N=2. |
| F3 | **BLOQ.** | §5 listaba UN detector y §9 exigía tres comportamientos; faltaba `test_meta_fp.sh` (su glob `tools/check-*.sh` clasifica el detector como gate) → "no es un gate, no choca con el freeze" era mecánicamente falso, también en el mapa. Fix: un solo detector cubriendo los goldens, declarado gate y condicionado al freeze; corregir el mapa en el mismo commit del Approved. |
| F4 | ALTA | `Referencia: ruta:línea` genera drift (toda inserción desplaza las citas → rojo perpetuo) y el precedente citado (`lesson-detector-link`) tiene `f-74be77fe` abierto: verifica existencia, no cobertura. Fix: ancla por símbolo o marcador `@decision:NNNN`, delimitada con acentos graves; heredar el mecanismo de excepción de `criteria-link.sh`; declarar el defecto heredado en §12. |
| F5 | ALTA | La fase 2 prometía "harness cableado" y su gate solo medía cobertura de decisiones: podía cerrar con `verify.conf` sin cablear y la pirámide muda — §5 omitía `verify.conf`, `post-edit-verify`, `mutation-score`, `ci/`, `project.conf`. Fix: gate de conjunción + listar los archivos del cableado. |
| F6 | ALTA | La absorción de `/adoptar` no declaraba qué muere ni quién manda el orden de relleno → dos comandos y un doc con dos órdenes (la lección del 2026-08-09 con nombre). Fix: stub de redirección; `ADOPTION.md` §4 sigue mandando; DoD con grep verificable; heredar Anillo 3, honestidad FILL y evidencia before/after. |
| F7 | ALTA | El módulo de referencia es una vertical de authn/PII y no pasaba por `security-reviewer` antes de ser el patrón que todos citan y copian. Fix: gate de 1c + `security/SKILL.md` en §5 + golden de secretos/PII + DoD con gitleaks. |
| F8 | MEDIA | §5b sin columna Responsable, y los gates "el owner firma"/"lo declara canónico" no dejaban artefacto — indistinguibles de no ejecutados. Fix: columna + firmas en `tools/project.conf` (adopter-owned, fuera de SYNC). |
| F9 | MEDIA | NO-TOUCH prohibía tocar el archivo que la fase 1 manda escribir, y el `reviewer` trata NO-TOUCH como bloqueo. Fix: sacarlo de NO-TOUCH; el principio ("las decisiones no las toma el agente") va a §4 con formulación operativa. |
| F10 | MEDIA | La fase 1 era red+dominio+UI en una — contra la regla de tamaño del propio `_template.md`, con el coste medido en `f-15089319`. Fix: partir en 1a contrato / 1b lógica / 1c vertical. |
| F11 | MEDIA | Golden 7 era insatisfacible contra el conf multistack del template; "se rellena `layers.conf`" contradecía `test_layers.sh` (se AMPLÍA, no se reescribe); tocar `skill-matrix.conf` exige AGENTS.md §11 en el mismo commit. |
| F12 | MEDIA | Campos de máquina en español y con acentos (`decidida`, `una-sola-dirección`) — locale C y adoptantes no hispanohablantes. Fix: ASCII estable (`state: decided|pending`, `door: one-way|two-way`), prosa en el idioma del adoptante, y el check salta `_template.md`/`README.md` por construcción. |
| F13 | MEDIA | "Tocar el módulo exige design-review" era una defensa anunciada sin mecanismo — y sostenía un riesgo de §12. Fix: `modulo_referencia` en `project.conf` + fila en `skill-matrix.conf` → el `skill-reminder` existente bloquea; el design-review queda como recomendación declarada. |
| F14 | BAJA | `Caduca:` prometía un aviso sin emisor; §10 medía sin decir dónde se anota. Fix: declarar informativo (emisor candidato: `session-start`, post-freeze); la medición al change log. |
| F15 | BAJA | El PRD propagaría a cada proyecto nuevo el orden reviewer-antes-que-verify (`f-f0f40763` abierto). Fix: `/arrancar` CITA el flujo canónico en vez de copiarlo. |

Open questions que dejó para el owner: registro↔ADR (→F1), quién juzga la prueba de fuego (→F2),
si el detector espera al freeze (→F3), cierre de fase 2 con niveles mudos (→F5), destino de
`/adoptar` (→F6), partir la fase 1 (→F10). **Recomendación:** aprobar acotado a fases 0–1 (los
bloqueantes no las tocan) y una v2 que atienda F1–F7 antes de aprobar 2–3.

## Ronda 2 — sobre la v2 · VERDICT: AMBER · 13 hallazgos

Verificó F1–F15 uno a uno contra el texto real (no contra el change log): **los tres bloqueantes
cerrados de verdad**; F4/F5/F12 parciales (secciones sin re-coser); el resto atendido. Halló
nueve problemas nuevos:

| # | Sev. | Hallazgo nuevo |
|---|---|---|
| N1 | ALTA | El gate de conjunción de fase 2 nombraba "niveles {0,1,3}" que `session-start` **no emite** (habla por avisos: `NIVEL 4`, `ANILLO 3 AUSENTE`, `SIN COMPILADOR EN LOS GATES`…) → la condición se cumplía sola y la conjunción degeneraba. Fix: formular sobre los avisos reales del instrumento. |
| N2 | MEDIA | §12 mitigaba el riesgo con precedente citando el detector que la propia v2 aplazó al freeze. |
| N3 | MEDIA | El discriminador `state:` convertía a `_template.md` en FP garantizado del día 1 — la cláusula de exclusión por construcción no sobrevivió a la v2. |
| N4 | MEDIA | Golden 1 no decía QUÉ agente juzga, y `capture-review-verdict.sh` tiene allowlist literal de agentes: uno nuevo no persiste reporte. Fix: reusar `reviewer` y listar sus archivos de contrato para la fase 3. |
| N5 | MEDIA | La fusión registro↔ADR dejaba dos ciclos de vida sin declarar interacción: un ADR `Status: Reemplazado` con `state: decided` exigiría ancla a código borrado → rojo perpetuo. Fix: Reemplazado exime. |
| N6 | BAJA→MEDIA | Las firmas usaban `CLAVE=valor` y `project.conf` declara `clave: valor` (su único parser real lee así); además, quien lea el conf para juzgar un diff debe leerlo del índice (bypass documentado en `scope.sh`). |
| N7 | BAJA | El grep de la DoD casaba la propia RUTA del stub → delimitar con acentos graves (doctrina `check-finding-refs`). |
| N8 | BAJA | Golden 4 solo es cierto en preset `full` — declararlo. |
| N9 | BAJA | Tres nits: la nota de migración citaba el §5 de ADOPTION (es §4); el gate de 1b sin artefacto; renumeración de OQs entre rondas sin tabla de equivalencia. |

**Recomendación explícita:** las fases 2–3 pueden pasar a Approved sin otra ronda, con N1
arreglado antes de que la fase 2 arranque; el bloque de re-cosido (una línea por ítem) en el
mismo pase.

## Qué pasó después (contexto para el revalidador)

La v2.1 aplicó el re-cosido y el owner extendió el Approved el mismo día (`40c981b`, `a20be1c`).
La auditoría externa del mismo día (`2026-08-25-auditoria-prd-0007-workflow.md`) encontró que
dos fixes de estas rondas introdujeron problemas nuevos (la evidencia TDD imposible de 1b, el
waiver `pending` demasiado ancho) y tres contradicciones residuales — confirmadas y atendidas
en la v2.2 con sus entradas de ledger (`f-54470c4d`, `f-8928fa5b`, `f-2269e8b`, `f-61dcbb8b`,
`f-f90ccab3`, `f-75d10804`, `f-35ef4b81`, `f-62d2ac5b`). La **ronda 3** verificó la v2.2 contra
el criterio de cierre de esa auditoría (AMBER, 12 hallazgos → la v2.3 los atendió) y su
**delta-check final dio GREEN**: las siete condiciones satisfechas, auditoría declarada
ATENDIDA, con seis residuos de higiene al ledger (`f-e1fb4dd2`, `f-dc1e5406`) cerrados en la
misma pasada. El detalle de la ronda 3 vive en el change log del PRD y en esas entradas.
