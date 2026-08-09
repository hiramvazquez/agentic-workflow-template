# Lecciones archivadas — mecanizadas, ya no hace falta leerlas

> **Por qué existe este archivo.** Cada lección de aquí tiene un detector que es un
> test de `tools/tests/` y que corre en el Anillo 3. Su cumplimiento NO depende de que
> nadie la recuerde: está garantizado por una máquina. Mantenerlas en el documento vivo
> cobraba dos veces el mismo seguro — en contexto del agente, en cada sesión.
>
> Siguen versionadas, siguen siendo grep-ables y `lesson-detector-link.sh` las sigue
> verificando. Si alguna vez borras su detector, **devuélvela al documento vivo**: sin
> el test, la regla vuelve a depender de la memoria.
>
> Generado/actualizado por `tools/lessons-rotate.sh --apply`.

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

### [2026-08-09] Anillo 0: dos sintaxis inertes, delatadas por la voz del propio cliente en los logs
- **Qué pasó:** el primer proyecto real confirmó f-3c027a85 y añadió el segundo agujero: los
  logs persistidos de los runs traían el aviso del propio Claude Code — "`Write(path)` is not
  matched by file permission checks — only `Edit(path)` rules are". TODAS las reglas Write()
  del deny eran inertes; los Bash con comodín intermedio, también. `git clean -f` quedaba sin
  cubrir por NADIE. El Anillo 0 "determinista" era en gran parte decorativo.
- **Causa raíz:** sintaxis asumida, jamás verificada en vivo (la lección de los hooks
  fantasma, en su tercera forma) — y sin logs persistidos el aviso del cliente se habría
  perdido en la terminal.
- **Regla:** en permissions solo formas GARANTIZADAS (paths Read/Edit, Bash por prefijo);
  las prohibiciones de flags viven en el git-guard, que ve el comando completo. Y todo
  output de un run se persiste — la evidencia que no se guarda no existe.
- **Detector:** tools/tests/test_hook_events.sh::test_permissions_sin_sintaxis_inerte
- **Área:** .claude/settings.json · scripts/agent-hooks/reviewer-gate.sh

---

### [2026-08-09] El gate del marker no conocía los commits de MERGE (el owner atascado en su propio flujo)
- **Qué pasó:** primer merge humano de una rama de historia (GREEN al crearse, gates verdes
  commit a commit) → `check-review-marker` exigió un marker NUEVO para el diff del merge →
  el merge quedó a medias con `MERGE_HEAD` colgado y una cascada de errores confusos detrás.
- **Causa raíz:** el gate se diseñó pensando en commits de CONTENIDO; el commit de merge es
  otra especie — no introduce trabajo nuevo (sin conflictos), y re-revisar lo ya revisado no
  añade verificación. Nadie había mergeado en vivo hasta hoy: el camino feliz del propio
  flujo (backlog → review → merge humano) nunca se había recorrido entero.
- **Regla:** `MERGE_HEAD` presente (modo staged) → exento de marker; el merge es acto del
  owner por doctrina. La exención NO se generaliza: sin MERGE_HEAD, producto staged se gatea
  igual. Y la meta-regla: un flujo no está validado hasta recorrer su camino feliz COMPLETO
  — los caminos de error se prueban solos; el feliz hay que caminarlo.
- **Detector:** tools/tests/test_review_marker_preset.sh::test_merge_de_rama_validada_no_exige_marker
- **Área:** tools/check-review-marker.sh · flujo de merge del backlog

---

### [2026-08-09] La matriz exigía leer un archivo que el tracker no sabía registrar (bucle infinito)
- **Qué pasó:** se añadieron refs `platforms/*.md` a `skill-matrix.conf` sin ampliar el filtro
  estático de `track-reads.sh`. Resultado: el agente leía la skill (obedeciendo al gate), el
  marker jamás se creaba, y `skill-reminder` bloqueaba PARA SIEMPRE la edición de lógica
  Swift. Lo cazó **el agente del primer proyecto real**, depurando el hook al notar que sus
  Reads no producían markers.
- **Causa raíz:** dos piezas acopladas (qué exige la matriz / qué registra el tracker) con
  listas independientes — la misma familia del bug de "la matriz en 5 sitios", en versión
  sutil: unificamos la matriz pero el tracker conservó su propia copia implícita.
- **Regla:** el tracker deriva lo registrable DE LA MATRIZ (la lee en runtime); cualquier
  par gate↔tracker comparte fuente o tiene un test de consistencia que recorra una y
  verifique la otra.
- **Detector:** tools/tests/test_skill_matrix.sh::test_toda_ref_es_registrable_por_track_reads
- **Área:** scripts/agent-hooks/track-reads.sh · tools/skill-matrix.conf

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
- **Regla:** todo archivo que AGENTS.md §8 llama "meta-doc" — y las rutas de CI/config
  (`.github/`, olvido nº2 cazado en vivo al día siguiente) — debe estar en `NON_PRODUCT`; y
  al añadir una exención, testear también el caso "con marker stale presente" — el estado
  residual cambia el mensaje de error y despista al humano. Fix de raíz del zombi: el reset
  de session-start purga markers ya expirados (test_reset_purga_marker_expirado).
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

### [2026-08-09] Un merge "concluido" commiteó los marcadores de conflicto y ningún gate lo vio
- **Qué pasó:** al resolver el conflicto del ledger en un merge, el archivo se stageó con los
  tres marcadores (`<<<<<<<` / `=======` / `>>>>>>>`) todavía dentro y un finding duplicado.
  git no protesta: solo rechaza paths "unmerged", y `git add` del archivo con los marcadores
  "resuelve" el index. El ledger quedó corrupto en develop; `findings.sh` moría al parsearlo y
  el harness-report lo mostró como "(ledger no disponible)" — así se cazó.
- **Causa raíz:** doble. (1) Nadie miraba el CONTENIDO staged en busca de marcadores; (2) la
  exención de MERGE_HEAD del review-marker — correcta — hace los merges menos vigilados a
  propósito, así que el único commit donde este error puede ocurrir es justo el menos mirado.
  Toda exención de un gate necesita un contrapeso mecánico para su caso.
- **Regla:** los merges se concluyen con el conflicto resuelto DE VERDAD; en un JSONL de
  append (ledger) la resolución habitual es conservar AMBAS líneas y deduplicar por id al
  estado más avanzado. Y para citar marcadores en un doc: indentados, nunca a inicio de línea.
- **Detector:** tools/tests/test_conflict_markers.sh (gate: `conflict-markers` en lefthook →
  tools/check-conflict-markers.sh, que exige ambos extremos presentes — ley del 10%).
- **Área:** lefthook.yml · tools/findings/ · merges del owner

---

### [2026-08-09] Tres gates parecían sanos y ninguno había demostrado jamás que VE
- **Qué pasó:** los tres fallos más caros del primer proyecto real tenían la misma forma.
  (1) Nueve niveles en verde con el build de Xcode roto — el paso de build era el único
  `FILL` sin cablear. (2) El nivel 4 pasó de "mudo" a "cableado" sin haber producido nunca
  un score: muter no emite JSON por stdout y el fallo caía al mensaje de "sin runner".
  (3) semgrep podía colgarse indefinidamente por un version-check de red. Ninguno era un
  gate que bloqueó mal: eran gates que NUNCA habían detectado nada y nadie se lo exigió.
- **Causa raíz:** los checks de salud medían CONFIGURACIÓN (¿existe el binario? ¿está el
  conf?) y no EVIDENCIA (¿ha producido este detector una detección real alguna vez, aquí,
  con estos binarios?). Contra esa clase de fallo el resto del harness no puede defender:
  todos los demás niveles dan verde precisamente porque el detector mudo no habla.
- **Regla:** ningún detector cuenta como activo hasta pasar su **selftest**: una detección
  real contra un fixture mínimo, en ESTE repo, emitiendo su contrato (§14.3). Se corre en
  segundos tras cada adopción y cada update de cliente. Y la comprobación más barata de
  todas (¿compila?) grita en session-start y validate-harness mientras siga sin cablear.
- **Regla 2 — *ausente* ≠ *presente-y-roto*:** todo detector debe distinguir "no tengo la
  herramienta" de "la tengo, corrió y falló". Colapsarlos convierte una **avería** en una
  **tarea pendiente**, que es el estado que nadie mira: el nivel 4 respondía "configúralo"
  cuando muter llevaba media hora corriendo y había fallado. Corolario: cuanto más TARDA un
  gate, más ruidoso debe ser su modo de fallo — el coste de un mensaje engañoso se multiplica
  por el tiempo que costó llegar a él.
- **Regla 3 — el fixture del selftest no puede ser famoso:** el primer selftest usaba
  `AKIAIOSFODNN7EXAMPLE`, la clave de ejemplo de la documentación de AWS, que gitleaks ignora
  a propósito. Daba ❌ sobre un gate perfectamente sano. Es la lección del fixture-con-formato-
  real por el otro lado, y en un selftest duele más: **un verificador con falsos positivos se
  ignora entero**, y entonces deja de proteger justo de aquello para lo que existe.
- **Detector:** tools/validate-harness.sh --selftest (y en CI vía harness-ci) ·
  tools/tests/test_ratchets.sh — `test_muter_score_se_lee_del_archivo_no_de_stdout`,
  `test_muter_cero_mutantes_es_ruidoso_y_distinto` y `test_muter_roto_no_se_disfraza_de_sin_runner`
  (fijan la Regla 2: los tres estados nunca vuelven a ser el mismo mensaje).
- **Área:** tools/validate-harness.sh · scripts/agent-hooks/session-start.sh · ci/run-gates.sh ·
  tools/mutation-score.sh

---

### [2026-08-09] Un archivo llegado por fuera de upgrade.sh revirtió un arreglo en silencio
- **Qué pasó:** `semgrep-scan.sh` llegó al proyecto copiado a mano (puente, snapshot anterior
  del template) y aplastó el split de `.errors[]` ya commiteado — el nivel 2 volvió a quedar
  mal clasificado. Lo cazó `test_las_reglas_de_semgrep_cargan`: un test que existía porque el
  arreglo local lo había dejado detrás.
- **Causa raíz:** `upgrade.sh` verifica (suite + selftest) DESPUÉS de su merge, pero un `cp`
  no pasa por `upgrade.sh` — cualquier archivo que entre por fuera se salta la única red.
  Y el "por qué" de una divergencia local vivía en prosa (comentario, lección): un `cp`
  aplasta prosa sin protestar.
- **Regla:** (1) los archivos del harness entran por `upgrade.sh`; si por lo que sea entran a
  mano, corre `run-tests.sh` + `validate-harness --selftest` INMEDIATAMENTE, no "luego".
  (2) Toda divergencia local deliberada respecto al template lleva **su propio test** — es la
  única forma de la divergencia que sobrevive a un `cp` descuidado. (3) Quien entrega por
  fuera (humano o IA) diffea contra lo commiteado ANTES de escribir, y mergea — no clobberea.
- **Detector:** tools/upgrade.sh (verificación post-merge con --selftest) + el test propio de
  cada arreglo local (ejemplar: tools/tests/test_shell_hygiene.sh::test_las_reglas_de_semgrep_cargan)
- **Área:** tools/upgrade.sh · flujo template↔proyecto

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
