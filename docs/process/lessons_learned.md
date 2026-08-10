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
- **Segunda vuelta (mismo día): un gate correcto puede ser el instrumento equivocado.** El gate
  bloqueó DOS commits seguidos por la misma causa, y las dos veces el remedio era idéntico y
  mecánico: `chmod +x` sobre unos archivos concretos. Ahí el gate estaba haciendo pagar a un
  humano por un problema del CANAL de entrega. **Un gate bloquea cuando la respuesta correcta
  requiere JUICIO; cuando el remedio es determinista y único, repara** — la misma lógica por la
  que un formateador formatea en vez de quejarse. Lo innegociable es que reparar NUNCA sea
  silencioso: el aviso ruidoso conserva la señal de que el canal pierde permisos, que es el
  problema de verdad. Modo estricto intacto para CI y auditoría.
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

### [2026-08-09] La review llegaba a ciegas al final, y por eso cada vuelta costaba lo mismo
- **Qué pasó:** en el primer proyecto real, un commit de adopción necesitó **tres vueltas de
  ~150k tokens y 17 minutos cada una**. Los tres RED eran correctos y distintos, así que el
  problema no era el reviewer. Partido por naturaleza, el mismo trabajo costó 62k y salió GREEN
  a la primera. Pero nada en el harness empujaba a partir ni a anticipar: el owner tuvo que
  decirlo a mano.
- **Causa raíz:** el reviewer se invocaba SOLO al final, sin saber de antemano qué importaba en
  ese cambio. Cada vuelta re-verificaba el diff entero desde cero, así que el coste escalaba con
  el tamaño del lote y no con lo que había cambiado desde la vuelta anterior. Una review
  exploratoria es cara por construcción.
- **Regla:** el evaluador y el generador **acuerdan qué significa "hecho" ANTES de escribir
  código** (modo `CONTRATO` del `reviewer`, paso 1b del runner): riesgos que aplican, qué se
  comprobará, qué sería RED. Va en la sección `## Contrato de review` de la historia. La review
  final verifica primero contra el contrato y luego hace su pasada — el contrato acota la
  prioridad, nunca la responsabilidad: lo grave no anticipado sigue siendo hallazgo.
  Invariante que lo hace seguro: un contrato **jamás** escribe marker. Si lo hiciera, pedirlo
  desbloquearía el commit del código que todavía no existe.
- **Detector:** tools/tests/test_verdict.sh (`test_contrato_no_es_veredicto`,
  `test_veredicto_no_es_contrato`, `test_contrato_mencionado_en_prosa_no_cuenta`)
- **Área:** .claude/agents/reviewer.md · tools/backlog/run.sh · scripts/agent-hooks/lib/verdict.sh

### [2026-08-09] El camino de upgrade estaba roto justo para la ruta de adopción que la doc recomienda
- **Qué pasó:** el primer `bash tools/upgrade.sh` real sobre un proyecto adoptado murió con
  `fatal: refusing to merge unrelated histories`. La cabecera del script asumía *"tu proyecto
  nació de un clone del template"*, pero `docs/ADOPTION.md` documenta —y la realidad impone—
  **copiar el harness dentro de un proyecto que ya existe**: la app siempre existe antes que el
  harness. Esos dos repos no comparten ancestro y `git merge` se niega. El upgrade llevaba
  meses roto para su propia ruta principal, y nadie lo supo porque nunca se había usado.
- **Segundo defecto, encadenado:** el script trató el fallo FATAL como si fueran conflictos.
  Imprimió una lista de archivos vacía y pidió "resuélvelos". Un diagnóstico equivocado cuesta
  más que ninguno: manda al humano a buscar un problema que no existe mientras el real sigue ahí.
- **Regla:** (1) toda herramienta que asume una TOPOLOGÍA de repo debe detectarla, no darla por
  supuesta — aquí: con ancestro común → merge de 3 vías; sin él → sync de maquinaria + registro
  del SHA en `tools/.template-sync` para que la próxima vez se aplique solo el delta.
  (2) Un fallo de una herramienta externa nunca se reetiqueta como el error que esperábamos:
  si `git merge` falla y no hay archivos en conflicto, **no son conflictos** — dilo, aborta y
  deja el árbol como estaba. (3) El sync trae MAQUINARIA y jamás pisa contenido del proyecto,
  y no commitea: stagea y enseña el diff, porque commitear lo que nadie ha visto es una
  sobreescritura silenciosa con otro nombre.
- **Detector:** tools/tests/test_upgrade.sh (`test_sync_trae_la_maquinaria_sin_ancestro_comun`,
  `test_sync_jamas_pisa_contenido_del_proyecto`, `test_sync_registra_la_base_para_el_delta_futuro`,
  `test_sync_deja_los_cambios_staged_para_revision`)
- **Área:** tools/upgrade.sh · docs/ADOPTION.md

### [2026-08-09] Escribí el detector de "falla a medias y dice OK" y cometí ese error dos veces seguidas
- **Qué pasó:** el modo sync de `upgrade.sh`, estrenado el mismo día, falló a medias dos veces
  y reportó éxito las dos. (1) `git checkout -- <pathspec>` es **atómico**: un patrón sin
  coincidencias abortaba TODO, y el `2>/dev/null` se comía el error — trajo los tests de tres
  herramientas SIN las herramientas. (2) Al arreglarlo apareció el mismo fallo una capa más
  abajo: `$SYNC_GLOBS` sin comillas lo expandía **bash contra el árbol LOCAL** antes de que git
  lo viera, así que una herramienta nueva del template nunca entraba en la lista; y con
  comillas, `git ls-tree` (plumbing) hace match por PREFIJO, no wildmatch, y devolvía menos
  archivos sin error. Tres capas del mismo error.
- **Causa raíz:** delegar el matching en semántica implícita de otra herramienta y creerse su
  silencio. `2>/dev/null` sobre una operación cuyo resultado importa no es "limpiar ruido": es
  apagar la única señal de que no hizo lo que creías.
- **Regla:** (1) prohibido `2>/dev/null` sobre una operación cuyo éxito importa — captura el
  error y decláralo. (2) Toda operación por lotes reporta **cuántos elementos procesó**, no
  solo que "terminó": un resumen que no cuenta no puede detectar una ejecución parcial.
  (3) Cuando el matching de rutas importa, **fíltralo tú** con reglas explícitas y testeables
  en vez de confiar en el globbing del shell o en el pathspec de un comando plumbing.
- **Detector:** tools/tests/test_upgrade.sh (`test_sync_no_se_salta_herramientas_en_silencio`,
  `test_sync_no_pisa_maquinaria_con_fill`)
- **Área:** tools/upgrade.sh

### [2026-08-09] Maquinaria con secciones que el template espera que personalices
- **Qué pasó:** el sync trajo `canon-enforce.sh` entero del template y **devolvió a comentario
  el guard del `.pbxproj`** que un proyecto real había escrito en su §CHECK 5. Lo delataron los
  tests de ese guard al fallar — la regla "una divergencia local sobrevive si lleva test" se
  cobró su valor por primera vez.
- **Causa raíz:** la clasificación binaria maquinaria/contenido no cubre los archivos de
  **propiedad compartida**: `canon-enforce.sh`, `post-edit-verify.sh`, `lefthook.yml`, `ci/`
  traen secciones `FILL` que el template ESPERA que el proyecto rellene. Son maquinaria en su
  estructura y contenido del proyecto en su interior.
- **Regla:** regla mecánica, sin listas que mantener — **si la versión del TEMPLATE trae un
  marcador `FILL`, ese archivo no se pisa jamás: se reporta**. El template está declarando por
  escrito que espera personalización; sobrescribirlo es siempre incorrecto.
- **Detector:** tools/tests/test_upgrade.sh::test_sync_no_pisa_maquinaria_con_fill
- **Área:** tools/upgrade.sh · scripts/agent-hooks/canon-enforce.sh

### [2026-08-09] Pedirle ayuda al CLI del ledger corrompía el ledger
- **Qué pasó:** `findings.sh add --help` interpretaba `--help` como flags de un alta y escribía
  un hallazgo basura con `title="(sin título)"`. Además, `add` con un `--id` existente conservaba
  el título viejo, así que **corregir un título fallaba en silencio** y el humano acababa
  editando el `.jsonl` a mano — dos veces en un mismo día, en un archivo generado.
- **Causa raíz:** el dispatch trataba cualquier argumento como datos. En un CLI que escribe la
  fuente de accountability del proyecto, eso es fail-open en su forma más traicionera: el daño
  lo hace la operación que el humano creía inofensiva.
- **Regla:** `--help` cortocircuita SIEMPRE antes del dispatch; `add` exige `--title` y `--area`
  y falla ruidoso en vez de inventar defaults; un `add` con id existente falla y apunta a
  `update`; y existe `drop ID --reason` para retirar lo que nunca fue un hallazgo (distinto de
  `close`, que afirma que hubo un problema y se resolvió). Retirar sin razón se rechaza:
  quitar del ledger sin explicar por qué es borrar evidencia.
- **Detector:** tools/tests/test_findings_cli.sh (`test_add_help_no_crea_hallazgo_basura`,
  `test_add_sin_titulo_ni_area_falla_ruidoso`, `test_add_con_id_existente_falla_y_apunta_a_update`,
  `test_drop_sin_razon_se_rechaza`)
- **Área:** tools/findings/findings.sh

### [2026-08-09] La matriz de skills solo vigilaba las tools de edición, no Bash
- **Qué pasó:** `skill-reminder` cuelga de `PreToolUse Edit|Write`, así que la matriz §11 solo
  veía las tools de edición. Escribir con `sed -i`, `tee`, una redirección o un `python3 -c`
  es escribir igual — y pasaba sin que NADIE mirara. Por ahí se coló una decisión de
  arquitectura real (el cambio del aislamiento de actores del target) en el primer proyecto.
  El agente no evadió nada a propósito: usó la herramienta equivocada para el trabajo.
- **Causa raíz:** el gate se ató a una TOOL concreta en vez de a la ACCIÓN que quería vigilar.
  Cualquier otra ruta hacia la misma acción queda fuera por construcción, y no se nota porque
  el camino vigilado sigue funcionando perfectamente.
- **Regla:** un gate se define por la acción (**escribir en un path de la matriz**), no por la
  herramienta. Al añadir una defensa, la pregunta obligatoria es *¿de cuántas formas se puede
  hacer esto?* — y hay que cubrirlas todas o declarar cuál queda fuera. Diseño: conservador en
  la DETECCIÓN (solo formas de escritura inequívocas: `>`, `>>`, `sed -i`, `perl -i`, `tee`,
  destino de `cp`/`mv`), no en el bloqueo. Un `cat` o un `grep` sobre el mismo archivo NO
  disparan: bloquear lecturas legítimas es la vía más rápida a que alguien apague el gate
  entero (ley del 10%). La lógica de la matriz vive en `lib/skill-matrix.sh`, compartida con
  `skill-reminder` — implementarla dos veces habría reproducido el problema que la matriz
  resolvió cuando vivía en cinco sitios y divergía.
- **Detector:** tools/tests/test_bash_matrix.sh (9 tests, 5 de ellos de falso positivo)
- **Área:** scripts/agent-hooks/reviewer-gate.sh §0c · scripts/agent-hooks/lib/skill-matrix.sh

### [2026-08-09] Un test verde en Linux y rojo en macOS: dependía de los PERMISOS del archivo que sobrescribía
- **Qué pasó:** cinco tests de `test_ratchets.sh` fallaban en la máquina del owner (macOS) y
  pasaban en el contenedor (Linux), con `Permission denied` **al escribir el stub**, no al
  ejecutarlo. Los tests hacían `printf '...' > tools/drift-ratchet.sh` sobre el archivo que el
  sandbox había COPIADO del repo: una redirección sobre un archivo existente hereda su modo y
  sus flags, y esos archivos habían llegado al repo por un canal que los dejó en modo 700.
- **Causa raíz:** el test dependía de una propiedad del entorno que nadie había declarado — los
  permisos del archivo copiado. Verde o rojo según la máquina es la peor clase de fallo: no
  señala un defecto real y erosiona la confianza en la suite entera, que es justo lo que hace
  que alguien acabe ignorando un rojo legítimo.
- **Regla:** un stub se **crea limpio**, nunca se sobrescribe: `rm -f` + escribir + `chmod +x`.
  Está en el helper `stub` de `run-tests.sh` para que no haya que recordarlo. Y la regla
  general: si el resultado de un test depende de algo que el test no creó, ese algo es una
  entrada no declarada. Corolario del helper: usa `printf '%b'`, no `'%s'` — con `%s` los `\n`
  se escriben literales y el stub "funciona" de formas absurdas.
- **Detector:** tools/tests/run-tests.sh (helper `stub`, usado por los 28 stubs de la suite) +
  la propia suite corriendo en Linux y macOS en `.github/workflows/harness-ci.yml`
- **Área:** tools/tests/

### [2026-08-09] El template arrastraba un secreto que disparaba su propio detector
- **Qué pasó:** un comentario de `validate-harness.sh` —escrito por mí para explicar **por qué
  no usar** la clave canónica de AWS en el fixture del selftest— contenía esa clave **entera**.
  Casa con el patrón `AKIA[0-9A-Z]{16}` de `canon-enforce` CHECK 2, así que bloqueaba el cierre
  de turno cada vez que ese archivo entraba en un cambio: en cada sync de cada proyecto.
- **Causa raíz:** un texto que advierte sobre una clave contiene, por necesidad, algo con forma
  de clave. Es la misma familia que la lección del doc que enseñaba el simulacro de gitleaks y
  llevaba el secreto contiguo dentro. La advertencia y el ejemplo son el mismo objeto para un
  detector léxico.
- **Regla:** cualquier literal con forma de secreto —**también en comentarios y en prosa**— se
  parte (`'AKIA' 'XXXX'`, o describirlo en palabras). Lo que NO se hace jamás es añadir el
  archivo a `is_detector_definition()` para silenciarlo: eso lo dejaría ciego a un secreto REAL
  para siempre, cambiando un aviso molesto por un agujero permanente.
- **Detector:** scripts/agent-hooks/canon-enforce.sh CHECK 2 (el propio gate que lo cazó, con
  su test en tools/tests/test_canon_enforce.sh)
- **Área:** tools/validate-harness.sh · docs/

### [2026-08-09] La guía de adopción decía dos cosas incompatibles sobre el mismo flujo
- **Qué pasó:** `ADOPTION.md` §1 mandaba `rm -rf .git && git init` —que corta el parentesco con
  el template— y §9b prometía que el upgrade sería "un merge de 3 vías normal", que necesita
  justo ese parentesco. Un adoptante seguía el paso 1 al pie de la letra y se quedaba con un
  camino de actualización imposible.
- **Causa raíz:** las dos secciones se escribieron en momentos distintos y nadie leyó el
  documento como lo lee un adoptante: de principio a fin y haciendo lo que dice. Arreglar la
  HERRAMIENTA (el modo sync de `upgrade.sh`) no arregló el DOCUMENTO — y el documento es lo que
  la gente ejecuta.
- **Regla:** cuando un flujo tiene dos caminos posibles, la doc los nombra **los dos**, dice a
  cuál pertenece el lector y qué implica cada uno más adelante. Y al arreglar una herramienta
  por un caso de uso, se revisa qué documento prometía otra cosa sobre ese mismo caso.
- **Detector:** n/a-manual — es coherencia de prosa entre secciones, no un patrón mecanizable
  (un grep produciría ruido). La red real: `tools/tests/test_upgrade.sh` fija que AMBAS
  topologías funcionan, así que el documento puede describirlas sin mentir.
- **Área:** docs/ADOPTION.md §1 y §9b

### [2026-08-09] Sin `.semgrepignore`, el nivel 2 escaneaba copias del propio proyecto
- **Qué pasó:** semgrep escaneaba 22 `.swift` de más, entre ellos una copia `_mutated` de muter
  de 20 MB que vive **dentro** del repo, y los worktrees del backlog runner. El daño real no
  fue el tiempo: los avisos de `PartialParsing` salían mezclados con archivos ajenos al cambio.
- **Causa raíz:** el harness genera copias del proyecto dentro del propio repo (worktrees para
  aislar historias, copias mutadas para el nivel 4) y nunca le dijo al escáner que las ignorara.
  Una herramienta que crea artefactos tiene que declararlos a las que leen el árbol.
- **Regla:** `.semgrepignore` versionado con las copias y artefactos. Y el criterio para
  ampliarlo: ahí van COPIAS y ARTEFACTOS, **jamás** código fuente que excluyas porque "da
  muchos hallazgos" — eso es desactivar el gate con otro nombre. El corolario general:
  **un aviso ruidoso se deja de leer, y así es como se pierde el aviso de verdad.**
- **Detector:** .semgrepignore versionado + tools/semgrep-scan.sh (documenta que
  `--no-git-ignore` NO desactiva el ignore) + tools/tests/test_shell_hygiene.sh
- **Área:** .semgrepignore · tools/semgrep-scan.sh

### [2026-08-09] Un test que se cuelga es peor que un test que falla
- **Qué pasó:** al inyectar un mutante en el guard de reentrada de un ViewModel, el test entró
  en deadlock y **colgó la suite** en vez de fallarla. Hubo que repetir con
  `-test-timeouts-enabled YES`. En CI eso habría consumido el job entero sin decir nada.
- **Causa raíz:** el runner asumía que un test termina. Un rojo te dice qué pasa en segundos;
  un cuelgue no dice nada durante una hora, y encima parece "está trabajando".
- **Regla:** todo runner de tests impone un límite por test. En el harness lo hace un perro
  guardián en segundo plano (`_run_test` en `run-tests.sh`), no `timeout`: los tests son
  FUNCIONES de shell y `timeout` solo ejecuta binarios. Y ojo al detalle que colgó el primer
  intento — los hijos en background deben ir con stdout DESATADO del pipe del llamador, o la
  sustitución de comandos espera al perro guardián y el mecanismo anti-cuelgue cuelga la suite.
  En proyectos Swift: `-test-timeouts-enabled YES` en el comando de tests de AGENTS.md §2.
- **Detector:** tools/tests/run-tests.sh (`_run_test`, verificado con un test que duerme más
  que el límite: devuelve 124 y explica que se colgó)
- **Área:** tools/tests/run-tests.sh · AGENTS.md §2

### [2026-08-09] Denegar la herramienta segura no impide la escritura: la empuja al camino inseguro
- **Qué pasó:** `findings.sh` no estaba en el `allow` de permisos, así que un run headless no
  podía usar el CLI del ledger — y escribió el JSONL **a mano**. Salió bien (28 entradas, 0
  inválidas), pero por suerte: la escritura directa no valida esquema, no deduplica por id y no
  protege los estados terminales.
- **Causa raíz:** se confundió el ledger con la evidencia. El harness desconfía —con razón— de
  los archivos de evidencia escritos por el modelo (el marker de review, los trinquetes). Pero
  el ledger **no es evidencia: es un inventario que §10 OBLIGA al agente a mantener**. Aplicarle
  la desconfianza del marker prohibió la vía segura sin prohibir la escritura.
- **Regla:** antes de denegar una herramienta, pregunta **qué hará el agente si no la tiene**.
  Si la respuesta es "lo mismo, peor y sin validación", el `deny` no protege: degrada. Denegar
  tiene sentido cuando la alternativa es *no hacerlo*, no cuando es *hacerlo a mano*.
- **Detector:** tools/tests/test_hook_events.sh::test_permissions_sin_sintaxis_inerte (valida el
  bloque) + el propio `_comment_findings_allow` de .claude/settings.json, que documenta por qué
  este allow no contradice el invariante nº1
- **Área:** .claude/settings.json · tools/findings/
