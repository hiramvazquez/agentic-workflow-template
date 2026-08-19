# Evaluación ejecutiva y plan de mejora del workflow agéntico

> **Estado:** Draft para decisión del owner
>
> **Fecha de evaluación:** 2026-08-18 (America/Merida)
>
> **Repositorio evaluado:** `agentic-workflow-template`
>
> **Baseline:** `cab2f4c` (`main`, alineado con `origin/main` al iniciar la revisión)
>
> **Alcance:** workflow, gates, CI, hooks, upgrade, documentación operativa y pruebas del harness
>
> **Fuera de alcance:** implementación de cambios, modificación del ledger y decisiones del adoptante
>
> **Preparado para:** owner, engineering leadership, platform engineering y responsables de adopción

---

## 1. Resumen ejecutivo

El workflow alcanzó un nivel de madurez alto en control de cambios asistidos por agentes. Sus
fortalezas principales son la defensa en capas, la evidencia ligada al diff, la distinción entre
capacidad declarada y capacidad operativa, el scope mecánico del backlog y una matriz E2E que
prueba integraciones completas en lugar de componentes aislados.

La prioridad ya no debe ser añadir más gates. El riesgo dominante cambió: ahora es la complejidad
operativa del propio sistema, seguida por drift documental y señales intermitentes de CI. En otras
palabras, el harness es fuerte para detectar errores, pero comienza a pagar un coste elevado por
mantener, explicar y ejecutar sus defensas.

La recomendación ejecutiva es aprobar una iniciativa de estabilización y simplificación, con tres
objetivos:

1. recuperar una señal CI determinista;
2. restablecer una única fuente de verdad para estados y métricas derivables;
3. reducir complejidad interna sin retirar garantías ni cambiar contratos públicos.

La implementación debe formalizarse en un PRD nuevo antes de tocar código, porque cruza CI,
hooks, scripts compartidos, documentación canónica y contratos portables. Este informe es el
insumo de decisión; no sustituye ese PRD.

### Evaluación de madurez

| Dimensión | Evaluación | Lectura ejecutiva |
|---|---:|---|
| Corrección y defensa en capas | 9/10 | Las garantías críticas tienen evidencia mecánica y backstop en CI. |
| Portabilidad | 8/10 | Hay backends y probes portables; persisten heurísticas ligadas a estructura de carpetas. |
| Observabilidad y trazabilidad | 8/10 | Reviews, eventos y findings son trazables; algunos formatos internos necesitan endurecimiento. |
| Consistencia documental | 7/10 | El diseño es correcto, pero ya existen cifras y estados divergentes. |
| Mantenibilidad | 6/10 | La cobertura creció junto con archivos monolíticos y lógica concentrada. |
| Madurez global | 8/10 | Adecuado para adopción controlada; requiere estabilización antes de escalar. |

---

## 2. Alcance y metodología

La evaluación fue de solo lectura y combinó:

- inspección del código y documentación en `main`;
- comparación entre el mapa de ejecución, PRD 0004 y el estado real del árbol;
- inventario estático de tests y tamaños de archivos;
- revisión de los contratos de review, source sets, scope y CI;
- consulta read-only de GitHub Actions para validar la promesa macOS/Linux;
- contraste con las reglas canónicas de `AGENTS.md` y las lecciones vivas.

No se ejecutaron cambios de producto, no se modificó el ledger y no se creó commit.

### Evidencia de baseline

| Evidencia | Resultado observado |
|---|---|
| Funciones `test_*` presentes en `tools/tests/` | 522 |
| Contexto obligatorio antes del índice de lecciones | 250 líneas, exactamente el límite actual |
| Findings abiertos | 1: `f-mutation-score-nunca-medido`, bloqueado en el adoptante |
| CI de HEAD `cab2f4c` | suites macOS y Ubuntu verdes; job de gates Linux seguía en curso al cerrar el snapshot |
| CI inmediatamente anterior | suite Ubuntu y gates Linux verdes; suite macOS roja |
| Fallo macOS observado | `test_review_tambien_respeta_timeout` no propagó 124 |
| Working tree antes de crear este informe | limpio |

Runs consultados:

- HEAD: <https://github.com/hiramvazquez/agentic-workflow-template/actions/runs/32217407840>
- run anterior con fallo macOS: <https://github.com/hiramvazquez/agentic-workflow-template/actions/runs/32214253577>

---

## 3. Fortalezas que deben preservarse

| Fortaleza | Garantía que aporta | Decisión recomendada |
|---|---|---|
| Matriz E2E ligada al PRD | Cruza manifiesto, probes, scope, review, métricas, caché y CI; el meta-test evita una DoD declarativa. | Preservar contrato y cobertura; modularizar sin cambiar semántica. |
| Autoaplicación del harness | `tools/`, `scripts/`, `ci/`, `lefthook.yml` y `AGENTS.md` cuentan como producto aquí. | Conservar el resultado; sustituir solo la heurística por una declaración explícita. |
| Review observable | Conserva cuerpo, diff, re-reviews y corta la retroalimentación de `SubagentStop`. | Mantener el lifecycle; separar responsabilidades internas. |
| Probes funcionales | Distinguen `missing`, `broken`, `unsupported` y `operational`. | Usar el contrato como estándar de capacidades nuevas. |
| Upgrade por propiedad | Cubre sync/merge, template/adoptante, FILL y report-only; registra conflictos. | Conservar la matriz y reducir duplicación. |

---

## 4. Registro de observaciones y recomendaciones

### WF-01 — Señal CI intermitente en macOS

**Prioridad:** P0 · **Estado:** confirmado externamente · **Área:** runner, su test y CI.

Dos runs recientes fueron rojos en macOS; en el último, el único fallo fue
`test_review_tambien_respeta_timeout`, aunque HEAD pasó después. Esto incentiva reruns hasta verde
y degrada la confianza en todo el gate.

**Recomendación:** reproducir bajo carga en macOS, capturar el exit obtenido y stderr en la
aserción, y separar sincronización de arranque del tiempo de ejecución. No aumentar el timeout
como único arreglo: primero debe identificarse si falla el watchdog, el fixture o la observación
del proceso.

**Criterios de aceptación:**

- prueba roja determinista contra la causa anterior;
- al menos 30 ejecuciones consecutivas macOS sin rerun-to-green;
- timeout de `run` y `review` devuelve siempre 124;
- descendientes quedan terminados y reaped;
- el test imprime exit real y diagnóstico cuando falla.

### WF-02 — Drift en el estado canónico y cifras derivables

**Prioridad:** P0 · **Estado:** confirmado · **Área:** mapa, PRD 0004 y detector de frescura.

El mapa declara 477 tests frente a 522 funciones `test_*`, y 236 líneas de contexto frente a 250.
Todos los agentes reciben automáticamente estos datos caducados con autoridad canónica.

El mapa también declara PRD 0004 completamente Shipped mientras su Definition of Done conserva
pendientes Linux/reviewer. La evidencia Linux ya existe en descendientes y el commit de fase 10
declara review GREEN, pero el documento no fue reconciliado.

**Recomendación:** eliminar cifras derivables de documentos vivos. Sustituirlas por comandos,
artefactos generados o evidencia ligada a commit y fecha. Reconciliar el status del PRD con un
criterio terminal único.

**Criterios de aceptación:**

- cero conteos de tests copiados en el mapa actual;
- cero métricas de contexto copiadas sin commit/fecha;
- status y checklist del PRD no se contradicen;
- un test falla si vuelve a introducirse un claim derivable no permitido;
- el mapa conserva solo fase, siguiente decisión y bloqueos no derivables.

### WF-03 — Riesgo de corrupción del historial JSONL de reviews

**Prioridad:** P1 · **Estado:** riesgo estático; requiere reproducción roja · **Área:** hook e I/O.

El hook construye JSON mediante `printf` y no todos los campos externos pasan por un encoder
completo. Comillas, barras inversas o controles pueden invalidar historial, dedupe o auditoría.

**Recomendación:** crear un único emisor JSON compartido y materializar cada registro de forma
atómica. Los consumidores deben parsear JSON, no buscar campos mediante `grep` sobre texto.

**Criterios de aceptación:**

- tests rojos con comillas, `\\`, tab, CR/LF y controles en `agent_id`, scope y notas;
- todas las líneas son válidas para `jq -e` o el parser Python canónico;
- deduplicación basada en campos parseados;
- corrupción preexistente produce estado explícito, nunca falso verde;
- compatibilidad documentada o migración de schema versionada.

### WF-04 — Archivos por encima de los límites canónicos

**Prioridad:** P1 · **Estado:** confirmado · **Riesgo:** review costosa, acoplamiento y regresiones laterales.

| Archivo | Líneas observadas | Límite hard |
|---|---:|---:|
| `tools/upgrade.sh` | 664 | 400 |
| `tools/tests/test_upgrade.sh` | 633 | 400 |
| `tools/tests/test_e2e_matrix.sh` | 618 | 400 |
| `tools/tests/test_verdict.sh` | 484 | 400 |
| `scripts/agent-hooks/capture-review-verdict.sh` | 371 | 400, próximo al límite |

**Recomendación:** dividir por contrato, no por número de líneas. Propuesta de fronteras:

- upgrade: inventario/propiedad, transporte, merge y reporting;
- E2E: fixture común + escenarios 01–05 + escenarios 06–10 + meta-matriz;
- verdict: parser, historial/reporte, markers/overrides y tests correspondientes;
- hook: orquestación del evento sobre librerías puras pequeñas.

**Criterios de aceptación:**

- ningún archivo ejecutable o test supera 400 líneas;
- ninguna función nueva supera el hard limit aplicable;
- contratos públicos y nombres de escenarios se conservan;
- la matriz E2E sigue probando maquinaria real;
- mutation checks o mutantes equivalentes demuestran que la división no debilitó pruebas.

### WF-05 — Clasificación implícita del tipo de repositorio

**Prioridad:** P1 · **Estado:** riesgo de diseño; impacto por validar · **Área:** `tools/lib/scope.sh`.

El tipo “harness” se infiere por ausencia de fuentes en directorios fijos. Monorepos bajo
`packages/`, `services/` o `modules/`, además de repos documentales, pueden clasificarse mal.

**Recomendación:** declarar `project_kind: harness|application` en una fuente estructurada ya
existente, con fallback explícito solo para compatibilidad. Una configuración ausente no debe
convertirse silenciosamente en una decisión de seguridad.

**Criterios de aceptación:**

- fixtures para harness, iOS, backend, monorepo y repo sin producto;
- el tipo declarado gobierna review y verify de forma idéntica;
- valor ausente produce diagnóstico accionable;
- upgrade transporta el default sin pisar la elección local;
- no aumenta falsos positivos en adoptantes existentes.

### WF-06 — Detector KMP basado en texto para una propiedad sintáctica

**Prioridad:** P1 · **Estado:** riesgo; requiere test rojo · **Área:** `check-source-sets.sh`.

El detector usa `grep` para imports y promete ignorar comentarios/strings. Un import al inicio de
línea dentro de comentario multilínea o string triple puede producir falso positivo.

**Recomendación:** mover el patrón a Semgrep Kotlin o a un parser/tokenizador con contrato de
exit 0/1/3. Mantener el estado `no-aplica` para repos sin KMP.

**Criterios de aceptación:**

- imports reales de plataforma en `commonMain` bloquean;
- el mismo import en `androidMain` pasa;
- comentarios multilínea, KDoc y strings triples no disparan;
- aliases e imports con whitespace válido se clasifican correctamente;
- tasa observada de falsos positivos menor al 10%.

### WF-07 — Contexto vivo sin margen y separadores acumulados

**Prioridad:** P1 · **Estado:** confirmado · **Área:** rotador y lecciones vivas.

Ocho separadores lógicos antes del índice consumen 15 líneas y dejan el tramo obligatorio
exactamente en 250. La próxima lección manual rompe el presupuesto o fuerza poda reactiva.

**Recomendación:** hacer que el rotador produzca una forma canónica con un solo separador y fijar
un objetivo operativo de 225 líneas, conservando 25 líneas de headroom.

**Criterios de aceptación:**

- una y diez ejecuciones del rotador producen bytes idénticos;
- existe exactamente un separador antes del índice;
- contexto vivo ≤225 líneas después de la limpieza;
- lecciones manuales permanecen visibles;
- lecciones mecanizadas siguen en archivo e índice.

### WF-08 — Instrucción operativa demasiado amplia para staging

**Prioridad:** P2 · **Estado:** confirmado · **Área:** mapa de ejecución.

El mapa recomienda `git add -A`, mientras AGENTS.md prohíbe incluir cambios fuera de scope. Un
árbol sucio puede incorporar trabajo ajeno o no revisado.

**Recomendación:** documentar staging explícito por paths del cambio y permitir `git add -A`
solo tras una comprobación visible de que el árbol contiene exclusivamente el scope autorizado.

**Criterios de aceptación:**

- camino feliz usa paths explícitos;
- el ejemplo incluye `git status --short` y `git diff --cached --check`;
- ningún documento canónico recomienda staging indiscriminado sin precondición;
- los flujos de upgrade que necesitan staging amplio declaran su scope exacto.

### WF-09 — Crecimiento de controles sin ventana suficiente de valor

**Prioridad:** P2 · **Estado:** riesgo estratégico confirmado · **Área:** gobierno y métricas.

El PRD pide 2–4 semanas de datos y la fase 10 aún no completa esa ventana. Añadir defensas antes
de medir latencia, falsos positivos y escapes aumenta ceremonia sin demostrar reducción de riesgo.

**Recomendación:** congelar nuevos gates generales durante la ventana de observación. Se permiten
únicamente correcciones de confiabilidad, falsos positivos, seguridad y drift de verdad.

**Criterios de aceptación:**

- dashboard o reporte con p50/p95 de gates y reviews;
- first-pass CI success rate y rerun rate;
- findings por fase, escapes y tiempo de remediación;
- cobertura de `triage` distinta de `unknown`;
- decisión explícita keep/tune/retire por cada defensa relevante;
- `f-mutation-score-nunca-medido` no se cierra sin evidencia del adoptante.

---

## 5. Roadmap propuesto

| Ola | Duración | Scope | Entregables y gate de salida |
|---|---:|---|---|
| 0 — estabilización | 2–4 días | WF-01, 02, 07 | CI macOS determinista; mapa/PRD reconciliados; rotación canónica. Salida: 30 runs macOS, Linux/macOS verdes y cero contradicciones. |
| 1 — contratos | 4–7 días | WF-03, 05, 06 | JSONL seguro, `project_kind` explícito y detector KMP sintáctico. Salida: reds previos, upgrade compatible y reviewer GREEN. |
| 2 — complejidad | 5–10 días | WF-04, 08 | Archivos bajo hard limit, fixtures con ownership y staging seguro. Salida: misma matriz golden y contratos públicos, sin degradar tiempo. |
| 3 — decisión | semanas 2–4 | WF-09 | Valor por gate, keep/tune/retire, backlog por riesgo y decisión sobre mutation score. |

---

## 6. Gobierno de implementación

### Roles recomendados

| Rol | Responsabilidad |
|---|---|
| Owner | Aprueba PRD, cambios de contrato, excepciones y retirada de defensas. |
| Implementer | Ejecuta TDD, conserva scope y aporta evidencia reproducible. |
| Reviewer independiente | Revisa riesgos lógicos y compara reportes previos hallazgo por hallazgo. |
| CI | Verifica Linux/macOS y niega falsos verdes. |
| Adoptante | Confirma upgrade, latencia y comportamiento en un proyecto real. |
| Process judge | Evalúa adherencia al workflow y coste de ceremonia. |

### Política de entrega

- un finding o grupo coherente por commit;
- test rojo antes del fix para todo comportamiento;
- toda corrección nueva recibe la misma revisión que el hallazgo original;
- findings en estado terminal antes de cerrar la ola;
- lección→detector→rotación cuando corresponda;
- ninguna cifra derivable se copia a documentación viva;
- cada ola puede revertirse de forma independiente.

### Definition of Done de la iniciativa

- [ ] PRD nuevo aprobado y con design-review del approach.
- [ ] WF-01 a WF-09 cerrados, aceptados o diferidos con owner y razón.
- [ ] Suite completa verde en macOS y Linux sin reruns manuales.
- [ ] Cero archivos ejecutables/tests por encima del hard limit acordado.
- [ ] Mapa, PRD y health-check no se contradicen.
- [ ] Historial de reviews siempre parseable y con schema explícito.
- [ ] Detector KMP cumple la ley de falsos positivos.
- [ ] Contexto vivo con al menos 25 líneas de headroom.
- [ ] Upgrade verificado en ambas topologías y luego en el adoptante.
- [ ] Métricas de valor recogidas durante la ventana acordada.
- [ ] Reviewer y process-judge presentan evidencia final.

---

## 7. KPIs y SLOs propuestos

| Indicador | Objetivo |
|---|---:|
| First-pass CI success sobre cambios sin defectos | ≥99% en ventana móvil de 30 runs |
| Reruns necesarios para obtener verde | 0 |
| Archivos ejecutables/tests sobre hard limit | 0 |
| Contexto obligatorio vivo | ≤225 líneas; hard cap 250 |
| JSONL inválido en review history | 0 líneas |
| Falsos positivos por detector | <10% |
| Defensas obligatorias con selftest | 100% |
| Claims operativos derivables copiados en docs vivas | 0 |
| Findings sin estado terminal al cerrar una ola | 0 |
| Runs `in-review` con scope mecánico demostrado | 100% |

Los tiempos p50/p95 de gates y reviews deben establecerse a partir de la telemetría real antes de
fijar objetivos numéricos. Inventar un SLO sin baseline repetiría el mismo problema de los conteos
hardcodeados.

---

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| La modularización cambia semántica | Characterization tests, mutantes y commits pequeños. |
| El nuevo schema rompe historial existente | Lectura backward-compatible y migración explícita. |
| Configurar `project_kind` añade fricción | Default transportado, diagnóstico claro y fallback temporal auditado. |
| Semgrep Kotlin no está disponible/operativo | Probe funcional; exit 3 honesto; no retirar el detector anterior hasta demostrar reemplazo. |
| La búsqueda de estabilidad oculta bugs aumentando timeouts | Exigir causa raíz y señal de arranque, no solo ampliar tiempos. |
| El programa vuelve a crecer durante la remediación | Scope cerrado, límites hard y reporte de LOC/latencia por ola. |

---

## 9. Decisiones solicitadas al owner

1. Aprobar la creación de un PRD de estabilización y simplificación basado en WF-01…WF-09.
2. Confirmar que Ola 0 tiene prioridad sobre nuevas capacidades del harness.
3. Aprobar `project_kind` explícito como dirección preferida frente a heurística.
4. Confirmar el objetivo de 225 líneas de contexto vivo.
5. Definir responsable del baseline de métricas durante las semanas 2–4.
6. Mantener `f-mutation-score-nunca-medido` abierto hasta confirmación del adoptante.

---

## 10. No objetivos

Esta iniciativa no debe introducir:

- nuevos anillos o perfiles de riesgo;
- sandbox obligatorio por defecto;
- fuzzing, fault injection o métodos formales;
- un proveedor de agentes obligatorio;
- cambios de producto en adoptantes;
- relajación de reviewer, verify marker, seguridad, ratchets o Anillo 3;
- cierre artificial de findings bloqueados por evidencia externa.

El resultado esperado no es “más harness”. Es un harness igual de estricto, más estable, más
pequeño y cuyas afirmaciones operativas vuelvan a coincidir con la evidencia.
