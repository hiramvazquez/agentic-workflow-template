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

### [2026-08-05] Un gate bloqueó editar la documentación de su propia área
- **Qué pasó:** editar `.agents/skills/domain/SKILL.md` casaba con el glob `*/domain/*` de la
  matriz §11, así que el hook exigía **leer la skill de dominio para poder editarla**.
- **Causa raíz:** la matriz de §11 habla de código de producto, pero el glob no distinguía
  código de documentación.
- **Regla:** todo gate necesita **tests de sus falsos positivos**, no solo de sus detecciones.
  Es la mitad del contrato que casi nadie escribe. Un gate ruidoso se desactiva entero, y un
  agente además aprende a evadirlo (ley del 10%).
- **Detector:** `tools/tests/test_skill_reminder.sh` (4 de 7 tests son casos de falso positivo)
- **Área:** scripts/agent-hooks/skill-reminder.sh

### [2026-08-05] La ausencia de una herramienta se contaba como deuda técnica
- **Qué pasó:** `semgrep-scan.sh` avisaba "semgrep no instalado" por stdout; `check-drift.sh`
  agrega stdout contando líneas `⚠️`. No tener semgrep **subía el trinquete** y bloqueaba el commit.
- **Causa raíz:** el mismo canal para datos y para diagnóstico.
- **Regla:** cuando un script alimenta un contador, **separa el canal de datos (stdout) del de
  diagnóstico (stderr)**. Mezclarlos convierte un problema de entorno en deuda de código.
- **Detector:** `tools/tests/test_drift_aggregation.sh::test_infraestructura_ausente_no_infla_el_conteo`
- **Área:** tools/semgrep-scan.sh, tools/check-drift.sh

### [2026-08-05] El escape hatch de emergencia relajaba más de lo declarado
- **Qué pasó:** `REVIEWER_OVERRIDE=1` se evaluaba antes que el trinquete, así que saltarse el
  marker de review también saltaba el trinquete. La doc decía que el trinquete es duro siempre.
- **Regla:** un escape hatch necesita un **alcance declarado y testeado**. "Es para emergencias"
  no define qué relaja. Aquí: relaja **juicio humano** (el marker), nunca un **número objetivo**.
- **Detector:** `tools/tests/test_ratchets.sh::test_override_no_relaja_el_ratchet`
- **Área:** scripts/agent-hooks/reviewer-gate.sh

### [2026-08-05] Un detector heurístico era trivial de gamear
- **Qué pasó:** el check de "lógica sin test" hacía `grep "$base" --include='*Tests.swift'`.
  Mencionar el nombre en un comentario lo satisfacía.
- **Regla:** todo detector heurístico debe pasar la prueba **"¿cómo lo gamearía yo?"**. Si la
  respuesta es fácil, mide adherencia, no calidad. Por eso la existencia del test es solo una
  señal y el veredicto real lo da el mutation score.
- **Detector:** `tools/tests/test_drift_aggregation.sh::test_mencion_en_comentario_no_cuenta_como_test`
- **Área:** tools/check-drift.sh

### [2026-08-05] Un gate anunciado pero no implementado (peor que ausente)
- **Qué pasó:** `canon-enforce.sh` estaba enteramente comentado mientras el `SessionStart` lo
  anunciaba como guardrail activo. Nadie lo habría notado: un gate que nunca dispara y uno que
  no existe se ven exactamente igual desde fuera.
- **Regla:** el health-check debe reportar lo que **NO** cubre, no solo lo que sí. La falsa
  confianza es un modo de fallo, no un estado neutro.
- **Detector:** `scripts/agent-hooks/session-start.sh` declara qué niveles de la pirámide están
  MUDOS en cada arranque
- **Área:** scripts/agent-hooks/canon-enforce.sh

### [2026-08-06] Las reglas de semgrep nunca habían cargado, y `--validate` decía que sí
- **Qué pasó:** `tools/semgrep/rules/universal.yaml` tenía **tres** errores distintos y ninguna
  de sus 6 reglas se había ejecutado jamás. Se descubrió cuando el gate corrió por primera vez
  con semgrep instalado, en un `git commit` real.
  1. `- pattern: rejectUnauthorized: false` → el `:` del patrón hace que YAML lo lea como
     mapping anidado. Hay que citarlo.
  2. `$X === "..."` en una regla que declara `csharp` → `===` no existe en C#.
  3. `pattern-inside: def $F(...):` en una regla que declara `java` → sintaxis Python.
- **Causa raíz doble:** (a) `semgrep --validate` solo valida el **YAML**, no el parseo de cada
  patrón contra cada lenguaje declarado; (b) un patrón inválido para **uno** de los `languages`
  de una regla **rompe la carga del archivo entero**, no solo de esa regla.
- **Regla:** `--validate` no es suficiente. La única verificación real de una regla de semgrep
  es **ejecutarla**. Y al escribir una regla multi-lenguaje, sepárala por familia sintáctica:
  un solo patrón incompatible tumba todo el fichero.
- **Detector:** `tools/tests/test_shell_hygiene.sh::test_las_reglas_de_semgrep_cargan` (ejecuta
  el scan real y falla con exit 3, que es "el detector no pudo correr")
- **Área:** tools/semgrep/rules/universal.yaml

### [2026-08-05] Escribir el harness en español rompió tres scripts en silencio
- **Qué pasó:** `fail "STALE (HEAD cambió $MARKED_HEAD→$CUR_HEAD)"`. Bash consume los bytes de
  `→` como parte del nombre de variable, expande `$MARKED_HEAD→` (inexistente) y con `set -u`
  mata el script. Lo mismo con `«$SCOPE»` en dos sitios más.
- **Causa raíz:** los mensajes en español usan `→`, `«»`, `…`, `·` de forma natural pegados a
  variables, y bash solo falla en la RAMA que imprime ese mensaje. En `check-review-marker.sh`
  esa rama era *"el marker está stale"* — se rompía **justo cuando el gate tenía que bloquear**.
  En `capture-review-verdict.sh` era la confirmación tras escribir el marker: el marker se
  escribía, el hook moría después, y el agente nunca veía el acuse.
- **Cómo se descubrió:** por accidente, al intentar commitear. Ningún test lo cazó porque los
  85 tests ejercitaban caminos felices y de fallo *lógico*, no las ramas de mensaje.
- **Regla:** en scripts con texto no-ASCII, **usa siempre `${VAR}` con llaves**. Y la regla
  general: una rama que solo imprime un mensaje sigue siendo código, y en shell no se
  verifica hasta que se ejecuta.
- **Detector:** `tools/tests/test_shell_hygiene.sh::test_sin_variables_pegadas_a_caracteres_no_ascii`
  (barre todos los `.sh` del harness, no es un caso puntual)
- **Área:** tools/check-review-marker.sh, scripts/agent-hooks/capture-review-verdict.sh

### [2026-08-05] Un gate no distinguía "tu código falla" de "yo no pude mirar"
- **Qué pasó:** al meter semgrep en el Anillo 2 (arreglando otro hallazgo), enganché su exit code
  crudo en la sección de detectores duros. Como devolvía el mismo `exit 1` para un hallazgo real
  y para "no pude cargar mis reglas", un typo en `universal.yaml` habría bloqueado **todos los
  commits del equipo, en ambos presets, sin escape** — incluido el commit que arreglaría el typo,
  porque la carga de reglas falla mires lo que mires. Deadlock.
- **Causa raíz:** un único código de error para dos categorías con consecuencias opuestas.
- **Regla:** todo detector debe distinguir **hallazgo** de **fallo del propio detector**. Un
  hallazgo bloquea siempre; un fallo de infraestructura avisa en local y bloquea en CI. Si los
  confundes, eliges entre dos desastres: pasar por limpio lo que no miraste, o trabar al equipo
  con un bug del tooling (`AGENTS.md §14.3`). Contrato adoptado: `0` limpio · `1` hallazgo ·
  `3` el detector no pudo correr.
- **Detector:** `tools/tests/test_fail_closed.sh::test_reglas_rotas_no_bloquean_el_commit` +
  `::test_hallazgo_real_da_exit_1_no_3` (fijan las dos mitades del contrato)
- **Área:** tools/semgrep-scan.sh, scripts/agent-hooks/reviewer-gate.sh, lefthook.yml

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

### [2026-08-05] Una regla implementada en dos sitios divergió en cuanto un tercero la llamó
- **Qué pasó:** la lógica del preset `lite` vivía en `reviewer-gate.sh` (Anillo 2). Al hacer que
  `lefthook.yml` (Anillo 1) invocara `check-review-marker.sh` directamente, el preset dejó de
  aplicar ahí: el agente recibía luz verde del Anillo 2 y el `git commit` fallaba después,
  contradiciendo lo que `AGENTS.md §13` promete.
- **Causa raíz:** la comprobación estaba en el **llamador**, no en la implementación compartida.
  Añadir un segundo llamador la saltó sin que nada avisara.
- **Regla:** una regla vive en **un solo sitio**: la implementación compartida, no cada llamador.
  Y el corolario de testing: **testea cada CAMINO de invocación, no cada función.** Los 60 tests
  pasaban con la regresión dentro porque solo ejercitaban el camino del Anillo 2.
- **Detector:** `tools/tests/test_review_marker_preset.sh` (compara los dos anillos en paralelo)
- **Área:** tools/check-review-marker.sh, lefthook.yml

### [2026-08-05] El detector de secretos se bloqueó a sí mismo
- **Qué pasó:** `canon-enforce.sh` bloqueó el cierre de turno señalando como secretos a
  `canon-enforce.sh` y a `.claude/security-patterns.yaml` — es decir, a los dos archivos que
  **definen** qué es un secreto.
- **Causa raíz:** un archivo que declara "esto parece una credencial" contiene, por necesidad,
  algo que parece una credencial. El detector no distinguía entre **usar** un patrón y
  **definirlo**.
- **Regla:** todo detector debe excluir los archivos que lo configuran (sus reglas, sus tests y
  su propia implementación). Es un caso particular de la regla general: **un detector nuevo
  necesita tests de falsos positivos el mismo día que se escribe**, porque el primero suele
  aparecer en el propio repo del detector.
- **Detector:** `tools/tests/test_canon_enforce.sh` (5 de 8 tests son casos de falso positivo)
- **Área:** scripts/agent-hooks/canon-enforce.sh

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

### [2026-08-07] Hooks registrados sobre eventos que NO existen
- **Qué pasó:** `PostCompact` y `PostToolUseFailure` estuvieron semanas en `settings.json` — no
  son eventos de Claude Code, así que `post-compact.sh` y `track-failure.sh` **jamás dispararon**.
  En Cursor, tres hooks más usaban nombres inventados (`sessionStart`/`preToolUse`/`postToolUse`).
  Peor aún: `SessionStart` sin matcher disparaba también en `source: compact` y **borraba el
  baseline de drift a mitad de sesión** — los errores recién introducidos pasaban a baseline.
- **Causa raíz:** asumir el esquema de eventos de memoria en vez de verificarlo contra la doc
  del cliente — y no tener NINGÚN check que compare lo registrado contra lo que existe.
- **Regla:** todo hook nuevo se registra SOLO con eventos de la lista blanca del cliente, y
  ningún gate cuenta como existente hasta verlo bloquear algo una vez (`tools/validate-harness.sh`
  tras cada update del cliente).
- **Detector:** tools/tests/test_hook_events.sh
- **Área:** .claude/settings.json · .cursor/hooks.json · .codex/hooks.json

---

### [2026-08-07] Dos emisores del "mismo" JSON con espaciado distinto
- **Qué pasó:** `findings.sh` escribía `"status": "open"` (json.dumps, con espacio) y los hooks
  grepeaban `"status":"open"` (formato JSON.stringify del CLI anterior). Resultado: "findings
  abiertos: 0" SIEMPRE — en el estado vivo, el post-compact y el session-start. Silenciosamente.
- **Causa raíz:** tratar un formato de serialización como detalle sin contrato. Dos emisores
  del mismo archivo deben ser byte-idénticos, o todos los consumidores deben ser tolerantes.
- **Regla:** ambas cosas a la vez — el emisor escribe compacto (`separators=(',',':')`) Y los
  consumidores grepean tolerante (`'"status": ?"open"'`). Y `grep -c X || echo 0` está prohibido:
  grep -c ya imprime 0 al no matchear; el echo extra produce `0\n0`.
- **Detector:** tools/tests/test_findings_cli.sh::test_ledger_se_escribe_compacto
- **Área:** tools/findings/findings.sh · scripts/agent-hooks/inject-context.sh

---

### [2026-08-07] El fallback de `stat` que nunca corría (y solo rompía en CI)
- **Qué pasó:** `stat -f %m || stat -c %Y` funcionaba en macOS… y en Linux `stat -f` NO falla:
  imprime datos del *filesystem* con exit 0, el fallback jamás corría, el TTL del marker se
  corrompía y **un marker válido se rechazaba siempre en el runner de CI**.
- **Causa raíz:** un fallback solo existe si el primer comando FALLA de verdad en la otra
  plataforma. "Funciona en mi máquina" + fallback no ejercitado = bug latente en CI.
- **Regla:** orden GNU-primero (`stat -c %Y || stat -f %m`) + guard numérico del resultado. Y
  la suite del harness corre en Linux (CI) además de macOS: la diferencia de plataforma ES el test.
- **Detector:** tools/tests/test_ratchets.sh::test_marker_de_hook_es_aceptado (en CI Linux)
- **Área:** tools/check-review-marker.sh

---

### [2026-08-08] El clasificador producto/meta-doc no conocía AGENTS.md (y el marker stale lo empeoró)
- **Qué pasó:** un commit de solo-reglas (AGENTS.md + skills + tooling) fue BLOQUEADO por el
  review-marker en el Anillo 1 — primer bloqueo en vivo del gate, pero injusto. Doble causa:
  `AGENTS.md` no estaba en la lista `NON_PRODUCT` (es meta-doc, no producto; su gate humano
  ya existe en permissions.ask), y un marker viejo de otra sesión convirtió el error en un
  confuso "EXPIRADO" — un marker stale presente hacía el commit de docs MÁS difícil que no
  tener marker.
- **Causa raíz:** el clasificador se construyó enumerando directorios y olvidó los meta-doc
  de la raíz; y el orden del script evalúa el marker sin re-considerar la exención.
- **Regla:** todo archivo que AGENTS.md §8 llama "meta-doc" debe estar en `NON_PRODUCT`; y
  al añadir una exención, testear también el caso "con marker stale presente" — el estado
  residual cambia el mensaje de error y despista al humano.
- **Detector:** tools/tests/test_review_marker_preset.sh::test_meta_doc_no_exige_marker
- **Área:** tools/check-review-marker.sh

---

### [2026-08-07] Un trinquete cuyo propio script podía aflojarlo
- **Qué pasó:** `drift-ratchet.sh --update` reescribía el techo con el conteo actual SIN
  comparar dirección, y además estaba en `permissions.allow` — un agente podía legalizar la
  deuda nueva con un solo comando permitido. El deny de Write/Edit sobre el JSON era teatro.
- **Causa raíz:** proteger el ARCHIVO pero no el CAMINO AUTORIZADO de escritura. La dirección
  de un trinquete se impone donde se escribe, no donde se lee.
- **Regla:** todo `--update` de un trinquete compara y rehúsa en la dirección prohibida (espejo
  de `mutation-score.sh`); en `allow` va solo `--check`.
- **Detector:** tools/tests/test_ratchets.sh::test_drift_update_nunca_sube_el_techo
- **Área:** tools/drift-ratchet.sh · .claude/settings.json

---

<!-- FILL: aquí van TUS lecciones. Ejemplos de categorías universales que casi todo proyecto acumula: -->

<!--
### [AAAA-MM-DD] Secreto de prueba con formato real commiteado
- Qué pasó: un fixture de test tenía una API key con formato válido; gitleaks la marcó tarde.
- Causa raíz: usar formato real "para que parezca de verdad".
- Regla: en fixtures usa formatos OBVIAMENTE inválidos (AKIAFAKE…); secretos reales van por env en CI.
- Detector: gitleaks + allowlist por PATH (no por categoría).
- Área: tests/fixtures
-->

<!--
### [AAAA-MM-DD] Lógica ramificó sobre texto en lenguaje natural
- Qué pasó: `if frecuencia == "diaria"` rompió al añadir un segundo idioma.
- Regla: clasifica por enum/clave keyed por idioma, nunca por el texto visible.
- Detector: check-drift grep por comparaciones de strings de UI en la capa de lógica.
-->
