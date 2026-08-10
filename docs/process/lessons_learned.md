# Lecciones aprendidas — no repetir

> **Léelo antes de escribir código.** Registro de trampas CONCRETAS ya pisadas. Si tocas un área
> cubierta aquí, sus reglas son obligatorias. Si cazas un patrón de error nuevo, **agrégalo en el
> mismo cambio** (no en un follow-up que nunca llega).

## Cómo usar este doc

- Cada entrada = un error real + la regla para no repetirlo + **el detector que lo previene**.
- El racional largo vive aquí; las reglas duras destiladas viven en `AGENTS.md`.

### ⚠️ El campo `Detector:` es OBLIGATORIO y está verificado

`tools/lesson-detector-link.sh` (Anillo 3) **falla** si una entrada no lo tiene.

**Por qué es duro:** una lección sin detector es prosa. Nadie la relee, y un agente no la
aplica de forma fiable — sobre todo después de una compactación de contexto. La filosofía es
la de Tricorder (Google): **todo comentario de review que se repite es un bug en tu tooling.**

Este es, literalmente, el mecanismo por el que la necesidad de revisión humana **decrece**
en vez de mantenerse plana:

```
error cometido → lección escrita → detector mecánico → error IMPOSIBLE de repetir
```

Sin el tercer paso, el ciclo no cierra y cada proyecto nuevo repite los mismos errores.

**Dónde va el detector**, por orden de preferencia (más barato arriba):

| Tipo de lección | Detector |
|---|---|
| Patrón de código | `tools/semgrep/rules/*.yaml` (AST — 0 falsos positivos por comentarios) |
| Regla de dependencias/capas | `tools/layers.conf` |
| Patrón de seguridad | `.claude/security-patterns.yaml` (coste 0 tokens, per-edit) |
| Regla irrompible barata | `scripts/agent-hooks/canon-enforce.sh` §CHECK 5 |
| Comportamiento concreto | un test en el área |

**Excepción legítima:** hay lecciones que de verdad no son mecanizables (juicio de producto,
criterio de diseño). Forzar un detector sobre ellas produce ruido, y un detector ruidoso se
ignora entero. Decláralo explícitamente para que no se confunda con un olvido:

```
- **Detector:** n/a-manual — <por qué no se puede automatizar>
```

## Plantilla de entrada

```
### [AAAA-MM-DD] <título corto del error>
- **Qué pasó:** <síntoma observable>
- **Causa raíz:** <por qué>
- **Regla:** <qué hacer/no hacer a partir de ahora>
- **Detector:** <ruta del check que lo previene, o `n/a-manual — razón`>
- **Área:** <path o módulo>
```

---

## Lecciones del harness

> Estas seis salieron de construir el propio harness (PRD 0001 §18). Se dejan en el template
> porque son **universales**: le pasan a cualquiera que monte gates para agentes. Bórralas si
> montas otro sistema; consérvalas si usas este.

### [2026-08-05] Un gate anunciado pero no implementado (peor que ausente)
- **Qué pasó:** `canon-enforce.sh` estaba enteramente comentado mientras el `SessionStart` lo
  anunciaba como guardrail activo. Nadie lo habría notado: un gate que nunca dispara y uno que
  no existe se ven exactamente igual desde fuera.
- **Regla:** el health-check debe reportar lo que **NO** cubre, no solo lo que sí. La falsa
  confianza es un modo de fallo, no un estado neutro.
- **Detector:** `scripts/agent-hooks/session-start.sh` declara qué niveles de la pirámide están
  MUDOS en cada arranque
- **Área:** scripts/agent-hooks/canon-enforce.sh

### [2026-08-05] Arreglar un hallazgo introdujo uno peor
- **Qué pasó:** las cuatro rondas de review sobre este PRD produjeron una cadena: el reviewer
  señaló que semgrep no bloqueaba en local → lo arreglé → creé el deadlock de la lección
  anterior. Y antes: hice que un trinquete corrupto degradara a 0 → eso convirtió corromper el
  archivo en una forma de desactivar el gate → hubo que revertirlo, test incluido.
- **Regla:** **una corrección es un cambio, y merece el mismo escrutinio que el código original.**
  La tentación es tratarla como "solo el fix", saltarse el análisis de impacto y no escribir su
  test. En un bucle de review con agentes esto es especialmente peligroso, porque la presión por
  cerrar el hallazgo empuja al arreglo apresurado. Corolario práctico: cuando un fix cambia el
  comportamiento que un test ya fijaba, **revisa si el test codificaba una decisión, no un hecho**
  — si es lo primero, cambia ambos y explica por qué en el propio test.
- **Detector:** n/a-manual — es disciplina de proceso. La red mecánica que sí existe: `canon-enforce`
  CHECK 4 exige que los tests del harness pasen si el turno tocó los gates, y cada corrección de
  esta serie entró con su test de regresión.
- **Área:** proceso

### [2026-08-05] Confundimos "el agente no se equivocará" con "el agente no podrá"
- **Qué pasó:** el README y el PRD describían el marker de review como **infalsificable**. El
  sub-agente `reviewer`, revisando el commit que introducía el mecanismo, lo desmintió con un
  repro ejecutable: escribió el archivo de marker a mano con `source: hook` y el gate lo aceptó.
- **Causa raíz:** `check-review-marker.sh` valida el **contenido** del marker, no su
  **procedencia**. En una máquina de un solo usuario, un agente con Bash puede hacer lo que
  puede hacer el usuario. Una firma HMAC no arregla nada: el secreto tiene que ser legible por
  el hook, que corre en el mismo entorno.
- **Regla:** al diseñar un gate, **declara cuál de las dos garantías das**: ¿defiende contra
  *error de proceso* (olvidos, atajos, reglas perdidas al compactar) o contra *intención*?
  Casi siempre es la primera, y está bien — pero anunciar la segunda es falsa confianza, el
  mismo modo de fallo que un gate no implementado. La defensa contra intención es el **Anillo 3**:
  en CI el marker no viaja y la review corre en una máquina que el agente no controla. Por eso
  un harness de un solo anillo no basta.
- **Detector:** n/a-manual — es una propiedad del modelo de amenaza, no un patrón de código. La
  mitigación es documental (README §"Qué garantiza y qué no", `verification-loop.md` nivel 8,
  cabecera de `capture-review-verdict.sh`) + `f-marker-spoof` como owner-decision en el ledger.
- **Área:** tools/check-review-marker.sh

### [2026-08-05] Observar un script lo modificó
- **Qué pasó:** ejecutar `session-start.sh` para *verificar su salida* borró los markers de
  skills leídas a mitad de sesión, y el siguiente Edit quedó bloqueado.
- **Causa raíz:** el script mezcla "informar" con "resetear estado".
- **Regla:** un script que un humano va a ejecutar para inspeccionar debe tener un modo **sin
  efectos secundarios**. Si no lo tiene, observarlo lo altera.
- **Detector:** n/a-manual — el fix (separar `--report` de `--reset`) requiere decisión del
  owner y quedó fuera del scope del PRD 0001 (§8). Registrado en §18 G6.
- **Área:** scripts/agent-hooks/session-start.sh

---

### [2026-08-08] "Puro" era ambiguo: el agente revirtió el default de concurrencia del target entero
- **Qué pasó:** en el primer proyecto real, el agente detectó `SWIFT_DEFAULT_ACTOR_ISOLATION
  = MainActor` (default Xcode 26) y, leyendo "Logic puro" en la skill de arquitectura, cambió
  el default del TARGET a `nonisolated` — revirtiendo el Approachable Concurrency que la skill
  del lenguaje manda, y creando drift spec↔código desde el día cero. Informó, pero no esperó.
- **Causa raíz:** dos docs internos en tensión aparente ("MainActor por defecto" vs "Logic
  puro") + un término ambiguo ("puro") sin definición operativa. Ante el conflicto, el agente
  eligió en vez de preguntar.
- **Regla:** "puro" = puro en DEPENDENCIAS, no en aislamiento (definido ya en ambas skills);
  los defaults de build del target son decisión de OWNER; y conflicto entre docs internos =
  Open Question, jamás elección unilateral (§1.4).
- **Detector:** n/a-manual — es juicio de diseño; la prevención real es la definición
  operativa añadida a `swift-estado-del-arte.md` y `platforms/ios.md`, y el ítem del
  design-reviewer sobre decisiones de build settings.
- **Área:** .agents/skills/architecture/ · settings del target

---

### [2026-08-08] El doc que enseña el simulacro de secretos CONTENÍA el secreto del simulacro
- **Qué pasó:** primer commit del harness sobre un proyecto real → gitleaks bloqueó: 1 leak.
  Era `docs/ADOPTION.md` §7 — el ejemplo del "commit de prueba" traía un AWS key de formato
  real y contiguo. En el template nunca mordió porque su primer commit entró SIN el Anillo 1
  (hecho desde un entorno sin lefthook) y los diffs posteriores no tocaban esa línea: el gate
  solo ve deltas, y la adopción en un proyecto nuevo stagea TODO → primer escaneo completo.
- **Causa raíz:** doble — un doc con un patrón de secreto contiguo (contra la doctrina del
  propio `.gitleaks.toml`: "formatos obviamente inválidos o allowlist por PATH"), y la
  ceguera de "el gate solo ve deltas": lo que entra sin escanear queda invisible hasta que
  alguien lo re-stagea entero.
- **Regla:** los strings de simulacro en docs se CONSTRUYEN en runtime (`printf 'AKIA%s'
  RESTO`) — el doc nunca contiene el patrón contiguo, el archivo del drill sí. Y tras montar
  el Anillo 1 en un repo con historia, corre un escaneo COMPLETO una vez
  (`gitleaks detect --source .`), no confíes en que los deltas te cubren lo viejo.
- **Detector:** .gitleaks.toml — el propio scan del Anillo 1 sobre el staging completo (así
  se cazó); el drill de ADOPTION §7 verifica que sigue vivo.
- **Área:** docs/ADOPTION.md · flujo de adopción

---


---

## Lecciones mecanizadas (índice)

> Estas ya NO dependen de tu memoria: cada una tiene un test en `tools/tests/` que corre en el
> Anillo 3, así que violarlas hace fallar la suite. Se listan para que sepas que existen; el
> relato completo (síntoma, causa raíz, racional) vive en `docs/process/lessons_archive.md`.
> Si necesitas el detalle de una, búscala ahí — no la reescribas.

- [2026-08-05] Un gate bloqueó editar la documentación de su propia área — `tools/tests/test_skill_reminder.sh`
- [2026-08-05] La ausencia de una herramienta se contaba como deuda técnica — `tools/tests/test_drift_aggregation.sh`
- [2026-08-05] El escape hatch de emergencia relajaba más de lo declarado — `tools/tests/test_ratchets.sh`
- [2026-08-05] Un detector heurístico era trivial de gamear — `tools/tests/test_drift_aggregation.sh`
- [2026-08-06] Las reglas de semgrep nunca habían cargado, y `--validate` decía que sí — `tools/tests/test_shell_hygiene.sh`
- [2026-08-05] Escribir el harness en español rompió tres scripts en silencio — `tools/tests/test_shell_hygiene.sh`
- [2026-08-05] Un gate no distinguía "tu código falla" de "yo no pude mirar" — `tools/tests/test_fail_closed.sh`
- [2026-08-05] Una regla implementada en dos sitios divergió en cuanto un tercero la llamó — `tools/tests/test_review_marker_preset.sh`
- [2026-08-05] El detector de secretos se bloqueó a sí mismo — `tools/tests/test_canon_enforce.sh`
- [2026-08-07] Hooks registrados sobre eventos que NO existen — `tools/tests/test_hook_events.sh`
- [2026-08-07] Dos emisores del "mismo" JSON con espaciado distinto — `tools/tests/test_findings_cli.sh`
- [2026-08-07] El fallback de `stat` que nunca corría (y solo rompía en CI) — `tools/tests/test_ratchets.sh`
- [2026-08-09] Anillo 0: dos sintaxis inertes, delatadas por la voz del propio cliente en los logs — `tools/tests/test_hook_events.sh`
- [2026-08-09] El gate del marker no conocía los commits de MERGE (el owner atascado en su propio flujo) — `tools/tests/test_review_marker_preset.sh`
- [2026-08-09] La matriz exigía leer un archivo que el tracker no sabía registrar (bucle infinito) — `tools/tests/test_skill_matrix.sh`
- [2026-08-08] El clasificador producto/meta-doc no conocía AGENTS.md (y el marker stale lo empeoró) — `tools/tests/test_review_marker_preset.sh`
- [2026-08-07] Un trinquete cuyo propio script podía aflojarlo — `tools/tests/test_ratchets.sh`
- [2026-08-09] Un merge "concluido" commiteó los marcadores de conflicto y ningún gate lo vio — `tools/tests/test_conflict_markers.sh`
- [2026-08-09] Tres gates parecían sanos y ninguno había demostrado jamás que VE — `tools/tests/test_ratchets.sh`
- [2026-08-09] Un archivo llegado por fuera de upgrade.sh revirtió un arreglo en silencio — `tools/tests/test_shell_hygiene.sh`

---

### [2026-08-09] El fail-open local estaba justificado por un backstop que nadie comprobaba
- **Qué pasó:** auditando el template salió una contradicción doctrinal en su propia doc.
  `AGENTS.md` §14.3 justifica que un detector roto (exit 3) NO bloquee en local con la frase
  *"CI sí lo bloqueará"*, y §13 afirma que el marker lo verifican "los tres anillos"; mientras
  tanto `ADOPTION.md` declaraba el CI **opcional**. En el primer proyecto real, el repo no
  tenía ni remoto: cada exit 3 era fail-open DEFINITIVO y nada lo decía.
- **Causa raíz:** el harness había aprendido a declarar sus **niveles** mudos (semgrep, mutación,
  build) y seguía ciego a su **anillo** mudo. El `--selftest` tampoco podía verlo: valida
  detectores, y un anillo ausente no es un detector roto — es un razonamiento roto.
- **Regla:** toda exención, fail-open o degradación justificada por otra capa exige **verificar
  mecánicamente que esa capa existe**. Si la justificación de un diseño es "ya lo caza X",
  entonces "¿existe X?" es un check obligatorio, no un supuesto. Aplicado: Anillo 3 obligatorio
  en preset `full` (§14.4), declarado a gritos en `lite`.
- **Detector:** tools/tests/test_ring3.sh (gate: `tools/check-ring3.sh`, exigido por
  validate-harness §8b y declarado por session-start)
- **Área:** AGENTS.md §14.4 · docs/ADOPTION.md · tools/check-ring3.sh

### [2026-08-09] La métrica que probaba que el harness sirve no la invocaba nadie
- **Qué pasó:** `tools/metrics/escape-rate.sh` —descrito en el propio README como *LA métrica
  del proyecto*— tenía **cero** referencias desde `harness-report.sh`, `ci/run-gates.sh` y el
  workflow de CI. Existía, estaba bien escrito, se alimentaba solo de la telemetría... y solo
  se citaba en documentación. La tesis central ("la revisión humana decrece") era la única
  afirmación sin evidencia de un sistema que exige evidencia para todo.
- **Causa raíz:** una métrica que hay que ACORDARSE de correr no se corre nunca. Nadie la puso
  en la superficie que un humano lee de verdad (el informe) ni en la que corre sola (CI).
  Agravante: la telemetría que la alimenta venía contaminada por ráfagas de eventos idénticos
  (un SubagentStop puede dispararse 8-10 veces), así que además habría mentido.
- **Regla:** una métrica que no sale en un informe que alguien lee, o en un job que corre solo,
  **no existe**. Y antes de confiar en una métrica, revisa que su fuente no cuente el mismo
  evento diez veces. Informativa siempre: bloquear con ella penalizaría al que más detecta.
- **Detector:** tools/tests/test_harness_report.sh + tools/tests/test_findings_cli.sh
  (`test_rafaga_del_mismo_evento_cuenta_una_vez`, `test_eventos_distintos_seguidos_se_registran_todos`)
- **Área:** tools/harness-report.sh · ci/run-gates.sh · scripts/agent-hooks/lib/io.sh

### [2026-08-09] Las lecciones no caducaban, y eso contradecía su propio mecanismo
- **Qué pasó:** `lessons_learned.md` llegó a 26 entradas y ~4.800 palabras, creciendo cada día
  y **heredándose entero** por cada proyecto nuevo nacido del template. El propio `AGENTS.md`
  advierte contra el monolito mientras este archivo caminaba a serlo, y cada sesión de cada
  agente pagaba el peaje de contexto.
- **Causa raíz:** el bucle estaba implementado a medias. Se aceptó "lección → detector", pero
  no su corolario: si el detector es un test que corre en el Anillo 3, la regla está garantizada
  por una máquina y **ya no depende de que nadie la lea**. Seguir exigiendo leerla es cobrar dos
  veces el mismo seguro.
- **Regla:** una lección cuyo `Detector:` es un `tools/tests/test_*.sh` existente se archiva en
  `lessons_archive.md` dejando **una línea de índice** en el doc vivo (la señal se conserva, el
  volumen no). Nunca se archivan las `n/a-manual` (ahí la prosa ES el mecanismo), ni las de
  garantía parcial, ni las marcadas `<!-- KEEP-VISIBLE -->`. El archivo se verifica igual que el
  doc vivo: si borras el test, la lección VUELVE al doc vivo.
- **Detector:** tools/tests/test_lessons.sh (`test_rotacion_archiva_mecanizadas_y_respeta_manuales`,
  `test_rotacion_deja_indice_de_una_linea`, `test_lecciones_archivadas_siguen_verificadas`)
- **Área:** tools/lessons-rotate.sh · tools/lesson-detector-link.sh · docs/process/

### [2026-08-09] Avisar cinco veces no impidió que el problema entrara en la historia
- **Qué pasó:** los archivos que llegan al repo por fuera de git (puente, `cp`, descarga)
  pierden el bit `+x`. Se reportó cinco veces como "ruido menor de cada diff", se añadió un
  AVISO en `validate-harness` §9... y el commit siguiente del propio harness incluyó **seis
  `mode change 100755 => 100644`**. Ya no es ruido: quedó en la historia, y quien clone recibe
  scripts no ejecutables.
- **Causa raíz:** se clasificó por MOLESTIA (cosmético, todo se invoca con `bash x.sh` igual)
  en vez de por REINCIDENCIA. Un aviso informa a quien ya está mirando; no detiene nada. Y la
  reincidencia era el dato importante: cinco repeticiones significaban que ninguna disciplina
  humana lo iba a arreglar.
- **Regla:** un problema que reaparece **tres veces** deja de ser candidato a aviso y pasa a
  gate — es la doctrina de Tricorder aplicada a nosotros mismos (*todo comentario de review que
  se repite es un bug en tu tooling*). Corolario del diseño: el gate necesitó su exención desde
  el minuto uno (las libs que se SOURCEAN no llevan `+x`), porque un gate con falso positivo
  permanente se desactiva entero y protege menos que el aviso al que sustituyó.
- **Detector:** tools/tests/test_exec_bits.sh (gate: `exec-bits` en lefthook →
  `tools/check-exec-bits.sh`; auditoría del repo entero en validate-harness §9)
- **Área:** lefthook.yml · tools/check-exec-bits.sh · flujo inverso

### [2026-08-09] El harness solo sabía crecer: ningún mecanismo preguntaba si algo ya sobraba
- **Qué pasó:** auditando el template salió que todos sus mecanismos son monótonos crecientes.
  Cada error añade un detector, cada lección un test, cada incidente un anillo; los trinquetes
  tienen dirección fija; las lecciones se acumulaban sin caducar. No existía ningún momento del
  proceso en el que se preguntara si una defensa sigue haciendo falta.
- **Causa raíz:** se optimizó por no perder cobertura y nunca por el coste de mantenerla. Pero
  la ceremonia no es neutra: cobra tiempo de gate, tokens de contexto y fricción, y es
  exactamente lo que lleva a un equipo a desactivar el harness entero. Un gate que existía
  para un error que el modelo ya no comete es peaje puro.
- **Regla:** revisar periódicamente (mensual, no diario) qué componentes siguen siendo
  *load-bearing*. Y el matiz sin el cual el informe miente: **cero detecciones es ambiguo** —
  puede ser disuasión perfecta o gate mudo, y los datos no los distinguen. Lo desempata el
  `--selftest`: cero eventos + selftest verde = disuasión, se queda; cero eventos + sin
  selftest = nadie ha demostrado nunca que ese gate vea. Retirar es decisión del owner (§8);
  la herramienta solo hace la pregunta respondible con datos en vez de con intuición.
  Corolario simétrico: un gate que dispara CONSTANTEMENTE tampoco está bien — pide que la capa
  de arriba haga imposible ese error (§14.1).
- **Detector:** tools/metrics/gate-value.sh (ritual mensual; sale en el harness-report §5c, que
  es la superficie que el humano sí lee — una métrica que hay que recordar correr no se corre)
- **Área:** tools/metrics/ · docs/process/ · ritual de mantenimiento
