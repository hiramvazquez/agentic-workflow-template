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

### [2026-08-12] El único entrypoint sin test propio era el que aprueba todo lo demás
- **Qué pasó:** `ci/run-gates.sh` —el Anillo 3, el backstop que cubre a Codex, a los commits
  humanos y a las máquinas sin lefthook— no tenía ni un test. Cada gate del harness tenía el
  suyo; el script que los ORQUESTA se auditaba leyéndolo. Borrar un paso del script no habría
  puesto nada en rojo.
- **Causa raíz:** los tests se escriben por unidad y un orquestador no parece una unidad ("no
  tiene lógica, solo llama a otros"). La lógica que sí tiene —a quién llama, en qué orden y qué
  hace cuando uno falta— es exactamente la que sostiene la promesa "el preset full no reduce
  ningún gate".
- **Regla:** si un script decide QUÉ se ejecuta, su lista de invocaciones es comportamiento y se
  fija con un test. Patrón barato: stubs que firman su paso, un caso con un gate en rojo y —el
  que de verdad importa— un caso con un gate AUSENTE, que nunca puede leerse como aprobado.
- **Detector:** `tools/tests/test_e2e_matrix.sh` (`test_golden_09_preset_full_no_reduce_ningun_gate`)
- **Área:** ci/run-gates.sh

### [2026-08-12] Una capacidad declarada no es una capacidad demostrada
- **Qué pasó:** `claude.sh` declaraba `read_only=true`, `agent-runner` exigía esa capacidad antes
  de cada review y el backlog la pedía en su preflight. Nada comprobaba que la invocación real
  fuera de solo lectura: cambiar `--permission-mode plan` por `acceptEdits` habría pasado los
  tres anillos, y la review habría podido escribir en el árbol que juzgaba.
- **Causa raíz:** el preflight pregunta al backend y el backend responde lo que dice su propio
  `case`. Es una declaración sobre sí mismo — el mismo modo de fallo que "instalado ≠ operativo",
  ya cerrado para las herramientas externas y no para los adapters.
- **Regla:** toda capacidad que un adapter declare necesita un test que observe el EFECTO, no la
  declaración. Para un CLI, el efecto observable más barato es su propio argv: un stub del
  binario que registre con qué lo llamaron.
- **Detector:** `tools/tests/test_e2e_matrix.sh` (`test_golden_05_autonomia_completa_contra_cli_stub`)
- **Área:** tools/agent-backends/claude.sh · tools/agent-runner.sh

### [2026-08-12] Una lista de garantías sin vínculo mecánico a sus tests es prosa
- **Qué pasó:** la Definition of Done del PRD 0004 decía "los escenarios golden 1–10 pasan" y no
  existía forma de comprobarlo: ni mapa escenario→test, ni nada que fallara si un escenario se
  quedaba sin demostración.
- **Causa raíz:** la lista y su demostración vivían en documentos distintos, y lo único que las
  ataba era que un humano leyera los dos. Es el mismo patrón que obligó al campo `Detector:` de
  este archivo, un nivel más arriba.
- **Regla:** cuando un documento enumera garantías, algo tiene que fallar si la enumeración crece
  sin su demostración. Aquí la lista es la fuente y el test la persigue: lee los escenarios del
  PRD y exige un `test_golden_NN_` por cada uno.
- **Detector:** `tools/tests/test_e2e_matrix.sh` (`test_matriz_e2e_cubre_los_diez_escenarios_golden`)
- **Área:** docs/process/prds/0004-reconciliar-workflow-agentico.md · tools/tests/

---

### [2026-08-12] `stat -f` de GNU no falla, y el orden del fallback ERA el bug
- **Qué pasó:** `main` se publicó en rojo. `test_write_atomico_conserva_el_modo_del_documento`
  fallaba con un mensaje que lo dice todo y no dice nada: **"--write dejó modo 644, esperaba 644"**.
  Los dos valores coincidían. Lo que estaba roto no era el código probado —`--write` conservaba
  el modo perfectamente— sino **la forma de leerlo**.
- **Causa raíz:** el helper hacía `stat -f '%Lp' … || stat -c '%a' …`, BSD primero. En macOS eso
  funciona. En GNU, `stat -f` **no es "formato": es "estado del FILESYSTEM"**, y sale con **exit 0**.
  El `||` nunca llega al fallback, la variable se llena con un volcado del filesystem, y la
  comparación falla contra un modo que sí era correcto. Verde en el Mac de quien lo escribió,
  rojo en cualquier runner Linux.
- **Lo que convierte esto en lección y no en anécdota:** el orden correcto **ya estaba escrito en
  este repo, con este mismo comentario, en `tools/check-review-marker.sh` y en
  `tools/check-verify-marker.sh`**. Tercera implementación de la misma regla, tercera copia, y la
  tercera divergió — *una regla implementada dos veces diverge*, ahora medido a la tercera.
  Y el modo de fallo es el más caro que existe en un harness multiplataforma: **el gate es verde
  en la máquina de quien publica y rojo donde nadie está mirando**, así que el pre-push local dio
  luz verde honestamente. No falló el gate: falló que la regla viviera en tres sitios.
- **Regla:** GNU primero, BSD después, siempre:
  `stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null`. Y más general: **cuando un
  fallback existe porque una herramienta cambia de significado entre plataformas, el orden no es
  estilo — es la lógica.** Ponerlo al revés no da un error, da un resultado equivocado con exit 0.
- **Detector:** tools/tests/test_shell_hygiene.sh::test_stat_lee_gnu_primero_y_bsd_despues —
  barre todos los `.sh` del repo y exige el `stat -c` delante. Verificado reproduciendo el fallo
  publicado contra la versión anterior. Su guard de falso positivo va integrado y se ganó solo:
  el test se cazó **a sí mismo** en la primera pasada, porque imprime la forma incorrecta dentro
  de su mensaje de error. Se desnudan comentarios y cadenas entrecomilladas antes de mirar — y
  aquí esa exención es legítima, a diferencia de la de la prosa del ledger: quien dictamina que
  lo entrecomillado es dato no es nuestro criterio, es el parser de bash.
- **Área:** tools/tests/test_capabilities.sh · tools/tests/test_shell_hygiene.sh

## Lecciones mecanizadas (índice)

> Estas ya NO dependen de tu memoria: cada una tiene un test en `tools/tests/` que corre en el
> Anillo 3, así que violarlas hace fallar la suite. Se listan para que sepas que existen; el
> relato completo (síntoma, causa raíz, racional) vive en `docs/process/lessons_archive.md`.
> Si necesitas el detalle de una, búscala ahí — no la reescribas.

- [2026-08-12] El programa embebido consumía el mismo stdin reservado para el payload — `tools/tests/test_gate_cache.sh`
- [2026-08-12] Reconciliar un archivo exige identidad no ambigua y clasificación bidireccional — `tools/tests/test_lessons.sh`
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
- [2026-08-09] El fail-open local estaba justificado por un backstop que nadie comprobaba — `tools/tests/test_ring3.sh`
- [2026-08-09] La métrica que probaba que el harness sirve no la invocaba nadie — `tools/tests/test_harness_report.sh`
- [2026-08-09] Avisar cinco veces no impidió que el problema entrara en la historia — `tools/tests/test_exec_bits.sh`
- [2026-08-09] La review llegaba a ciegas al final, y por eso cada vuelta costaba lo mismo — `tools/tests/test_verdict.sh`
- [2026-08-09] El camino de upgrade estaba roto justo para la ruta de adopción que la doc recomienda — `tools/tests/test_upgrade.sh`
- [2026-08-09] Escribí el detector de "falla a medias y dice OK" y cometí ese error dos veces seguidas — `tools/tests/test_upgrade.sh`
- [2026-08-09] Maquinaria con secciones que el template espera que personalices — `tools/tests/test_upgrade.sh`
- [2026-08-09] Pedirle ayuda al CLI del ledger corrompía el ledger — `tools/tests/test_findings_cli.sh`
- [2026-08-09] La matriz de skills solo vigilaba las tools de edición, no Bash — `tools/tests/test_bash_matrix.sh`
- [2026-08-09] El template arrastraba un secreto que disparaba su propio detector — `tools/tests/test_canon_enforce.sh`
- [2026-08-09] Sin `.semgrepignore`, el nivel 2 escaneaba copias del propio proyecto — `tools/tests/test_shell_hygiene.sh`
- [2026-08-09] Denegar la herramienta segura no impide la escritura: la empuja al camino inseguro — `tools/tests/test_hook_events.sh`
- [2026-08-10] La herramienta que reparte los arreglos no puede parchearse a sí misma — `tools/tests/test_upgrade.sh`
- [2026-08-10] Un marcador es una FORMA, no una palabra: `grep FILL` congeló media maquinaria — `tools/tests/test_upgrade.sh`
- [2026-08-10] Un literal partido a propósito lleva escrito POR QUÉ, o el siguiente lo junta — `tools/tests/test_secret_scan.sh`
- [2026-08-10] El filtro del propio verificador de lecciones se tragó una lección — `tools/tests/test_lessons.sh`
- [2026-08-10] `.claude/settings.json` es maquinaria viviendo en una carpeta de contenido — `tools/tests/test_settings_merge.sh`
- [2026-08-10] "Esto lo caza el test X" — y el test X no lo cazaba — `tools/tests/test_skill_matrix.sh`
- [2026-08-10] Un manifiesto mantenido a mano no puede vigilarse a sí mismo — `tools/tests/test_meta_fp.sh`
- [2026-08-10] Una regla de adopción que solo vive en un doc se descubre tarde — `tools/tests/test_layers.sh`
- [2026-08-10] El estado real de una historia no vive donde el selector miraba — `tools/tests/test_backlog.sh`
- [2026-08-10] Un `||` que no distingue "no pude mirar" de "encontré algo" — `tools/tests/test_secret_scan.sh`
- [2026-08-10] Un gate en rojo perpetuo es peor que un gate ausente — `tools/tests/test_secret_scan.sh`
- [2026-08-10] El guard colgaba del exit code de jq, y jq cambió de opinión entre versiones — `tools/tests/test_fail_closed.sh`
- [2026-08-10] Un run puede salir con 0 y no haber terminado — `tools/tests/test_backlog.sh`
- [2026-08-10] Se arregló un caso del parser y no se buscó el hermano — `tools/tests/test_semgrep_rules.sh`
- [2026-08-10] Un criterio de aceptación «verificado con un grep» es decoración — `tools/tests/test_backlog.sh`
- [2026-08-11] El informe de "no lo he traído" mentía, y empujaba justo al flujo que prohíbe — `tools/tests/test_upgrade.sh`
- [2026-08-11] El invariante nº1 estaba aplicado al reviewer y no a los tests — `tools/tests/test_verify_marker.sh`
- [2026-08-11] Un gate que lee TEXTO como si fuera sintaxis enseña a evadirlo — `tools/tests/test_bash_matrix.sh`
- [2026-08-11] Un hook roto dejó al agente sin poder ni diagnosticarlo — `tools/tests/test_run_hook.sh`
- [2026-08-11] Un piso de 0 no es un suelo: es una medición que nunca ocurrió — `tools/tests/test_ratchets.sh`
- [2026-08-12] "Sin cablear" y "cableado, pero el runner no termina" no son el mismo estado — `tools/tests/test_ratchets.sh`
- [2026-08-12] El archivo de tests existía; el test citado no — `tools/tests/test_lessons.sh`
- [2026-08-12] El gestor de paquetes contesta a otra pregunta — `tools/tests/test_finding_refs.sh`
- [2026-08-12] Un id de finding que no existe LEE COMO CERRADO — `tools/tests/test_finding_refs.sh`
- [2026-08-12] La cuarta vez del mismo falso positivo no pide otra lección — `tools/tests/test_bash_matrix.sh`
- [2026-08-11] Cambiar de lanzador habría duplicado todos los hooks de todos los proyectos — `tools/tests/test_settings_merge.sh`
- [2026-08-11] La suite corría DESPUÉS del push, así que `main` se publicó en rojo — `tools/tests/test_run_hook.sh`
- [2026-08-11] Un test con fixture inventado prueba la invención, no la herramienta — `tools/tests/test_settings_merge.sh`
- [2026-08-11] Un RED sin huella hace indistinguible la remediación del reintento — `tools/tests/test_verdict.sh`
- [2026-08-11] La cola del juez premiaba dejar basura — `tools/tests/test_judge_queue.sh`
- [2026-08-12] El repo que escribe el gate era el único sin cablearlo — `tools/tests/test_verify_marker.sh`
- [2026-08-12] El detector se validó contra el único ledger que no lo iba a romper — `tools/tests/test_finding_refs.sh`
- [2026-08-12] Un fallback añadió un segundo cero a un resultado válido — `tools/tests/test_metrics.sh`
- [2026-08-12] Añadir campos al evento no migra a sus productores — `tools/tests/test_findings_cli.sh`
- [2026-08-12] Omitir una línea corrupta convirtió “no pude medir” en cero — `tools/tests/test_metrics.sh`
- [2026-08-12] Validar el prefijo de un timestamp no valida el instante — `tools/tests/test_metrics.sh`
- [2026-08-12] Normalizar los datos a UTC no basta si la ventana sigue siendo local — `tools/tests/test_metrics.sh`
- [2026-08-12] Cuantificar un descarte no reemplaza la señal de su causa — `tools/tests/test_metrics.sh`
- [2026-08-12] Una vista generada no puede convertirse en entrada de su propio generador — `tools/tests/test_lessons.sh`

### [2026-08-12] El programa embebido consumía el mismo stdin reservado para el payload
- **Qué pasó:** `gate-cache.sh put` invocaba `python3 -` con el programa en un heredoc y a la vez
  esperaba leer el resumen verde con `sys.stdin.read()`. El programa ocupaba stdin, así que el
  payload siempre llegaba vacío y el caché nunca publicaba una entrada utilizable.
- **Causa raíz:** se diseñó el transporte mirando cada redirección por separado; en un proceso
  solo existe un stdin efectivo y el heredoc reemplaza al pipe del caller.
- **Regla:** si `python3 -` recibe código por stdin, los datos del caller viajan por argumentos,
  descriptor separado o archivo; nunca por ese mismo stdin. El consumidor valida además el
  payload canónico, no solo que sea texto.
- **Detector:** tools/tests/test_gate_cache.sh (`test_mismo_diff_verde_reutiliza_cache`,
  `test_cache_solo_acepta_payload_verde_canonico`)
- **Área:** tools/gate-cache.sh · tools/semgrep-scan.sh

### [2026-08-12] Reconciliar un archivo exige identidad no ambigua y clasificación bidireccional
- **Qué pasó:** el rotador prefería una entrada archivada si otra nueva reutilizaba su encabezado,
  aunque el cuerpo fuera distinto; además, jamás reconsideraba las archivadas cuando desaparecía
  el test que justificaba sacarlas del contexto vivo.
- **Causa raíz:** se modeló la operación como append+dedup de una sola dirección, no como
  reconciliación de dos vistas del mismo corpus.
- **Regla:** combina ambas fuentes antes de escribir; un retry solo es duplicado si coincide el
  cuerpo completo, mientras identidad igual con cuerpo distinto falla cerrado. Reclasifica todo
  el corpus en cada corrida, de modo que perder una garantía devuelve la lección al tramo vivo.
- **Detector:** tools/tests/test_lessons.sh::test_rotacion_no_deduplica_cuerpos_distintos_bajo_el_mismo_titulo
  + ::test_rotacion_reclasifica_archivada_si_su_test_desaparece
- **Área:** tools/lessons-rotate.sh

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
  la clave canónica de la documentación de AWS (prefijo `AKIA` + `IOSFODNN7` + `EXAMPLE`,
  partida aquí a propósito), que gitleaks ignora
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

### [2026-08-10] La herramienta que reparte los arreglos no puede parchearse a sí misma
- **Qué pasó:** `tools/upgrade.sh` se auto-actualizaba **escribiendo sobre su propio archivo**
  en el árbol y re-lanzándose desde ahí. Como `tools/*.sh` es maquinaria, el propio script
  entraba en el delta del sync, y `git apply --3way` —que exige worktree == índice para todo lo
  que toca— abortaba el parche ENTERO con `error: tools/upgrade.sh: does not match index`. En la
  otra topología el síntoma era distinto y el diagnóstico peor: `git merge` se negaba con
  *"your local changes would be overwritten"* y el script lo reportaba como fallo fatal del
  merge. Cazado en el segundo proyecto real, en la primera pasada de un upgrade.
- **Causa raíz:** el mecanismo se dio a sí mismo un camino especial. Todo lo demás llega al
  árbol por el sync/merge; solo este archivo se traía a mano, antes de tiempo, y esa excepción
  ensuciaba el índice justo para la operación que venía después. Un caso especial creado para
  resolver un problema de arranque real (una v1 no puede traerse los arreglos de la v2) acabó
  rompiendo el caso normal.
- **Regla:** **un proceso nunca escribe sobre el archivo que está ejecutando.** Si una
  herramienta debe correr una versión más nueva de sí misma, extrae esa versión a una copia
  temporal y `exec` sobre ella (`exec`, no `source`: bash lee los scripts por offset y
  reemplazar el archivo en ejecución produce comportamientos absurdos). El archivo del árbol se
  actualiza por el mismo camino que todas las demás piezas. Corolario de diseño: **cuando algo
  necesita una excepción al camino común, el sitio donde la excepción se cruza con el camino
  común es donde va a romper** — y ahí es donde hay que poner el test.
- **Detector:** tools/tests/test_upgrade.sh::test_sync_aplica_un_delta_que_incluye_al_propio_upgrade
  + ::test_merge_funde_un_delta_que_incluye_al_propio_upgrade
  + ::test_puente_desde_el_mecanismo_viejo_de_autoactualizacion (los tres reproducen el error
  literal contra la versión vieja; el fixture ahora incluye `upgrade.sh` en el template, que es
  lo que escondía la clase entera de fallo)
- **Área:** tools/upgrade.sh

### [2026-08-10] Un marcador es una FORMA, no una palabra: `grep FILL` congeló media maquinaria
- **Qué pasó:** el sync protege de sobreescritura todo archivo que el template marque con un
  `<!-- FILL -->` (la regla de propiedad compartida, escrita tras pisar el guard del `.pbxproj`
  de un proyecto real). Estaba implementada como `grep -q 'FILL'` a secas. Resultado: quedaban
  marcados como "tuyos, no los toco" cinco archivos de maquinaria pura que solo NOMBRAN la
  palabra — `session-start.sh` e `inject-context.sh`, que precisamente **avisan** de FILLs sin
  rellenar; `bootstrap.sh`, que la cita en un `echo`; `validate-harness.sh`, que comprueba si
  `run-gates.sh` sigue en FILL; y el propio `upgrade.sh`, que la menciona en su cabecera. Esos
  cinco no habrían vuelto a recibir un solo arreglo en ningún proyecto adoptado por copia.
- **Causa raíz:** el detector buscaba el **tema** en vez de la **forma**. Es la misma familia
  que `grep 'try!'` matcheando el comentario que dice "no uses try!" (§14.2, por lo que los
  patrones viven en Semgrep y no en grep), pero con el signo del daño invertido: en vez de ruido
  visible, silencio permanente con cara de éxito — el sync reportaba "🔒 no tocados, son tuyos"
  sobre archivos que nadie había personalizado nunca. Y la ironía: los que más lo sufrían eran
  el verificador y el propio actualizador.
- **Regla:** un marcador se reconoce por su forma completa y anclada, no por su palabra clave.
  Aquí: **un marcador FILL es un COMENTARIO QUE EMPIEZA por `<!-- FILL`**
  (`^[[:space:]]*([#;]|//|--)?[[:space:]]*<!--[[:space:]]*FILL`). Una mención en prosa, un
  `grep` que lo busca o un fixture de test NO lo son. Regla general: **si un detector puede
  dispararse con el texto que HABLA de la cosa, no está mirando la cosa.**
- **Detector:** tools/tests/test_upgrade.sh::test_fill_es_un_marcador_no_una_mencion (un archivo
  del template que solo menciona FILL DEBE sincronizarse) junto a ::test_sync_no_pisa_maquinaria_con_fill
  (la otra cara: un marcador de verdad NO se pisa). Los dos juntos fijan la frontera.
- **Área:** tools/upgrade.sh

### [2026-08-10] Un literal partido a propósito lleva escrito POR QUÉ, o el siguiente lo junta
- **Qué pasó:** en `validate-harness.sh` el nombre de la clave AWS del fixture va partido en
  trozos que no forman el literal contiguo. El comentario decía "partida aquí a propósito, ver
  abajo" — y abajo no había nada. Un agente en un proyecto real lo vio, lo unió por prolijidad,
  y `canon-enforce.sh` (CHECK 2, que escanea lo recién escrito) le trabó el cierre de turno. El
  arreglo local que explicaba el porqué no estaba en el template, así que la divergencia
  reaparecía en cada sync y cada vez había que volver a decidir lo mismo.
- **Causa raíz:** el código feo sin su razón se lee como código feo. Una defensa cuyo motivo no
  está a la vista se percibe como un descuido, y limpiarla parece una mejora.
- **Regla:** todo literal deliberadamente partido, silenciado o retorcido lleva **en la línea de
  al lado** qué lo rompe si lo juntas. Y el corolario que ya estaba y ahora está escrito donde
  se necesita: la salida fácil —añadir el archivo a `is_detector_definition()` del secret-scan—
  deja ese archivo CIEGO a secretos de verdad para siempre. Partir el literal cuesta una línea
  fea; cegar el detector cuesta el gate.
- **Detector:** tools/validate-harness.sh (el propio comentario, ahora completo) +
  tools/tests/test_secret_scan.sh (fija que una clave AWS no canónica en un archivo cualquiera
  bloquea, o sea: que juntar el literal aquí volvería a trabar el turno)
- **Área:** tools/validate-harness.sh · docs/ADOPTION.md §7

### [2026-08-10] El filtro del propio verificador de lecciones se tragó una lección
- **Qué pasó:** al escribir la entrada de arriba sobre los marcadores FILL, el texto citaba
  ese marcador entre acentos, en medio de una frase. `lesson-detector-link.sh` filtra los
  ejemplos que viven dentro de comentarios HTML con una máquina de estados por líneas, y esa
  mención le abrió un comentario que nunca se cerraba: se tragó el campo `Detector:` de esa
  lección **y la lección siguiente entera**. El gate reportó huérfana una entrada que sí tenía
  detector, y bajó el total sin que nadie lo notara.
- **Causa raíz:** la misma de la entrada anterior, una capa más arriba y cometida al
  documentarla: un filtro que decide sobre el texto crudo se dispara con el texto que **habla**
  del marcado. Y el modo de fallo elegido —tragarse el resto— convierte un falso positivo local
  en un apagón silencioso del resto del documento.
- **Regla:** un filtro de marcado decide sobre una versión **sonda** de la línea, no sobre la
  línea cruda: fuera los spans de código entre acentos y fuera los comentarios que abren y
  cierran en la misma línea. Y regla de diseño para cualquier máquina de estados que "salta"
  contenido: **prefiere el modo de fallo que muestra de más al que oculta de más** — de más se
  ve y se corrige; de menos se parece a que no había nada.
- **Detector:** tools/tests/test_lessons.sh::test_mencionar_un_comentario_html_no_abre_un_comentario_html
  (una lección que menciona un comentario HTML conserva su Detector Y no borra la siguiente)
- **Área:** tools/lesson-detector-link.sh

### [2026-08-10] `.claude/settings.json` es maquinaria viviendo en una carpeta de contenido
- **Qué pasó:** el sync excluye `.claude/`, `.agents/` y `docs/` a propósito — ahí vive lo del
  proyecto. Pero dentro de `.claude/settings.json` están los **hooks (Anillo 2)** y los
  **permisos (Anillo 0)**. De una tanda de tres arreglos del template, solo uno llegó solo; el
  `allow` de `findings.sh` y una nota de una skill hubo que traerlos a mano, y únicamente
  porque a alguien se le ocurrió comparar contra `template/main`. Peor: en la pasada que acabó
  en conflicto, el informe de "esto cambió y no lo he tocado" no llegó a imprimirse, así que no
  había ni la pista.
- **Causa raíz:** dos. La clasificación era por CARPETA cuando la propiedad es por CONTENIDO —
  un archivo de maquinaria dentro de una carpeta de contenido cae en la grieta. Y el informe de
  honestidad solo salía por el camino feliz: un aviso que aparece solo cuando todo va bien no
  es un aviso, es una felicitación.
- **Regla:** para lo que es maquinaria y vive mezclado, ni `checkout` (pisa lo del proyecto) ni
  exclusión (se queda atrás en silencio): **merge de claves que SOLO AÑADE**, imprimiendo cada
  añadido para que entre en el diff que el humano revisa. En `deny` eso significa que las
  prohibiciones solo crecen, como los trinquetes de §9 — la dirección correcta para
  equivocarse. Y el corolario general: **todo informe de "esto no lo he traído" se imprime en
  TODOS los caminos de salida, sobre todo en los que fallan.**
- **Detector:** tools/tests/test_settings_merge.sh (5 casos: solo añade, idempotente, JSON local
  roto NO se pisa, ausente se copia, template sin el archivo no rompe) +
  tools/tests/test_upgrade.sh::test_sync_funde_settings_sin_pisar_lo_del_proyecto +
  ::test_el_informe_sale_tambien_cuando_la_pasada_falla
- **Área:** tools/upgrade.sh · tools/merge-claude-settings.sh · .claude/settings.json

### [2026-08-10] "Esto lo caza el test X" — y el test X no lo cazaba
- **Qué pasó:** la cabecera de `tools/skill-matrix.conf` afirmaba que la divergencia entre la
  tabla de `AGENTS.md §11` y el conf la cazaba `test_skill_matrix.sh`. No era cierto: ese test
  comprueba que las refs EXISTAN y sean registrables, y nunca compara tabla contra conf. Al
  escribir el detector de verdad, la primera pasada encontró **dos divergencias vivas**: la
  tabla exigía leer `platforms/ios.md` antes de tocar una View y el conf no lo pedía (defensa
  anunciada que no existe), y tenía una fila `tools/**` → `verification-loop.md` que
  `skill-reminder` NO PUEDE cumplir porque excluye esas rutas a propósito.
- **Causa raíz:** una afirmación de cobertura escrita de buena fe y nunca comprobada. Es peor
  que no tener nada: se lee, se cree, y nadie vuelve a mirar — la documentación se convierte en
  el sitio donde el agujero se esconde.
- **Regla:** si escribes "esto lo caza X", **abre X y compruébalo en ese momento**. Y cuando
  mecanices la comparación entre un doc y su fuente, compara el conjunto que IMPORTA (aquí, las
  referencias), no la forma literal: la tabla agrupa globs y usa prosa a propósito, así que
  exigir igualdad literal daría un hallazgo por fila y el detector duraría una semana (ley del
  10%, §14.2). Dirección del fallo: una fila en el doc sin respaldo en el conf es más grave que
  al revés — es anunciar una defensa que no existe (§14.4).
- **Detector:** tools/check-skill-matrix-doc.sh +
  tools/tests/test_skill_matrix.sh::test_la_tabla_y_el_conf_de_ESTE_repo_coinciden (más los tres
  casos de sandbox y el guard de falso positivo del glob que acaba en `.md`)
- **Área:** tools/skill-matrix.conf · AGENTS.md §11

### [2026-08-10] Un manifiesto mantenido a mano no puede vigilarse a sí mismo
- **Qué pasó:** `test_meta_fp.sh` exige que todo detector tenga tests de falso positivo, pero
  solo mira lo que está EN su manifiesto. Al revisarlo había **cinco detectores fuera**
  (`check-conflict-markers`, `check-exec-bits`, `check-diff-nature`, `check-ring3` y el propio
  `check-skill-matrix-doc`), todos con sus tests de FP ya escritos y ninguno declarado. El
  meta-test daba verde porque lo que faltaba no se contaba a sí mismo.
- **Causa raíz:** la lista era la fuente de verdad de su propia cobertura. Un inventario que se
  mantiene a mano mide lo que recuerdas, no lo que hay.
- **Regla:** todo manifiesto/inventario de cobertura necesita un check que lo compare contra la
  **realidad del disco**, no solo contra sí mismo. Y ojo al criterio de exención: aquí no hizo
  falta ninguna (todos los `tools/check-*.sh` son detectores), y eso es bueno — una lista de
  exenciones se convierte enseguida en la vía para silenciar el meta-detector.
- **Detector:** tools/tests/test_meta_fp.sh::test_ningun_detector_se_queda_fuera_del_manifiesto
  (recorre `tools/check-*.sh` del disco y exige que cada uno esté declarado)
- **Área:** tools/tests/test_meta_fp.sh

### [2026-08-10] Una regla de adopción que solo vive en un doc se descubre tarde
- **Qué pasó:** `ADOPTION.md` decía que `tools/layers.conf` se AMPLÍA y no se reescribe.
  Un adoptante lo reescribió con las rutas de su proyecto y le reventaron cinco tests del
  harness, que copian ese conf a un sandbox con rutas genéricas (`src/Domain/`). Cinco rojos
  que no mencionaban `layers.conf` por ninguna parte: perdió una tarde.
- **Causa raíz:** la regla estaba escrita donde se lee UNA vez (la guía de adopción) y se
  necesitaba en el momento de editar, semanas después. Y el fallo aparecía lejos de la causa.
- **Regla:** una regla de adopción con consecuencia mecánica va acompañada de su detector, y el
  mensaje del detector lleva la CAUSA, no solo el síntoma. El doc explica el porqué; el test lo
  dice cuando importa.
- **Detector:** tools/tests/test_layers.sh::test_layers_conf_conserva_los_globs_universales
- **Área:** tools/layers.conf · docs/ADOPTION.md §4

### [2026-08-10] El estado real de una historia no vive donde el selector miraba
- **Qué pasó:** el runner del backlog marca `in-review` **dentro** de la rama `story/NNNN`.
  Desde `develop`, una historia terminada y esperando merge sigue diciendo `ready`, así que
  `next.sh` la devolvía otra vez. `backlog/README` promete que una rama en `in-review` no se
  re-trabaja; el selector no podía cumplirlo porque el marcador vive donde no miraba. Con
  `story/0005` terminada, un run desatendido habría rehecho ~500 líneas ya verificadas — y
  mientras tanto el backlog no avanzaba a la 0006.
- **Causa raíz:** una promesa escrita en un doc cuyo mecanismo estaba en otra capa. Y el
  agravante: cuanto más tarda el humano en mergear, más probable es el destrozo — o sea, el
  fallo escala justo en el escenario para el que existe un runner desatendido.
- **Regla:** cuando un estado se escribe en un sitio y se lee en otro, **lee el hecho
  observable**, no el registro que puede estar desincronizado: aquí, la RAMA. Y ojo al arreglo
  ingenuo, que era mi primer instinto: "saltar si existe la rama" deja huérfana para siempre
  una historia cuyo run se cortó a medias. Hay que distinguir `in-review` (terminada → saltar y
  seguir con la siguiente) de cualquier otro estado (a medias → devolverla para retomar). Ante
  la duda, devolver: retomar es reversible; olvidar una historia, no.
- **Detector:** tools/tests/test_backlog.sh::test_historia_terminada_en_rama_no_se_reofrece_y_avanza
  + ::test_historia_a_medias_se_sigue_ofreciendo_para_retomarla (la otra cara)
  + ::test_mergeada_sin_marcar_done_se_avisa + ::test_sin_ramas_el_selector_no_cambia (FP guard)
- **Área:** tools/backlog/next.sh

### [2026-08-10] Un `||` que no distingue "no pude mirar" de "encontré algo"
- **Qué pasó:** buscando por qué el escaneo de secretos daba rojo perpetuo apareció algo peor
  en el mismo archivo. `secret-scan.sh --range` era
  `gitleaks … --log-opts=RANGO 2>/dev/null || gitleaks --staged …`. Las dos ramas del `||` son
  exit != 0, pero significan cosas opuestas: "el rango no se resuelve" y "gitleaks **encontró
  un secreto**". Ante una fuga real en el rango, el script se iba al fallback, escaneaba el
  índice —vacío en CI— y salía 0. **El gate de secretos daba verde sobre una fuga**, y el
  `2>/dev/null` borraba el motivo.
- **Causa raíz:** el mismo error que el harness persigue todo el día (la operación falla y
  reporta éxito), escrito dentro del gate que más caro sale que falle así. El `||` de shell
  colapsa todos los fallos en uno solo; el contrato de §14.3 existe precisamente para no
  colapsarlos.
- **Regla:** un fallback nunca se cuelga de un exit code genérico. Se valida la
  **precondición** por separado (aquí: resolver el rango con `git rev-list --count`) y, si no
  se cumple, se sale con **3** — "no pude mirar" — que en local avisa y en CI bloquea. Jamás se
  escanea otra cosa en su lugar: un scan que no miró lo que debía no puede parecerse a un scan
  limpio. Corolario para los tests: el fake tiene que **distinguir** los casos que el bug
  confundía. El primer intento de este test devolvía lo mismo siempre y pasaba con el bug
  puesto — un test que no reproduce el fallo no es un test.
- **Detector:** tools/tests/test_secret_scan.sh::test_un_hallazgo_en_el_rango_nunca_sale_verde
  + ::test_rango_irresoluble_devuelve_3_no_0 + ::test_range_usa_gates_base_ref_cuando_no_hay_upstream
- **Área:** tools/secret-scan.sh · ci/run-gates.sh

### [2026-08-10] Un gate en rojo perpetuo es peor que un gate ausente
- **Qué pasó:** el paso 2 de CI escaneaba el historial COMPLETO en cada corrida. El commit de
  scaffold del template contiene el literal del simulacro de `ADOPTION §7` — una clave falsa
  *detectable a propósito*, porque si no lo fuera el simulacro no probaría que el Anillo 1
  bloquea. Resultado: rojo permanente en el template y en todos sus clones.
- **Causa raíz:** el gate respondía la pregunta equivocada. "¿Queda algo enterrado de antes?"
  no es la pregunta de un gate por cambio; la suya es "¿ESTE cambio mete un secreto?". Mezclar
  las dos convierte un hallazgo antiguo en un bloqueo eterno de trabajo ajeno.
- **Regla:** cada gate responde UNA pregunta, y la frecuencia se elige por la pregunta:
  por-cambio lo que depende del cambio, programado lo que depende del historial. Y sobre el
  arreglo tentador: **allowlistear el valor del simulacro habría dejado mudos el propio
  simulacro y el selftest de `validate-harness`**, que usan ese mismo literal para demostrar
  que el detector VE — un gate que se prueba a sí mismo con un valor que ignora no prueba nada.
  Reescribir el historial tampoco: cambiaría todos los SHAs y rompería el remote `template` y
  el `.template-sync` de cada adoptante. Va al baseline, que es deuda DECLARADA.
- **Detector:** tools/tests/test_secret_scan.sh::test_el_valor_del_simulacro_nunca_se_allowlistea
  (falla si alguien mete ese literal en el allowlist de .gitleaks.toml) + tools/secret-baseline.sh
- **Área:** ci/run-gates.sh · .gitleaks.toml · docs/ADOPTION.md §6

### [2026-08-10] El guard colgaba del exit code de jq, y jq cambió de opinión entre versiones
- **Qué pasó:** `semgrep-scan.sh` protege contra el fallo más caro posible —la herramienta
  revienta, no escribe JSON, todos los `jq` caen a su fallback `0` y el resultado es
  indistinguible de "todo limpio"—. El guard era `jq -e . "$OUT"`. Pero **`jq -e .` sobre un
  archivo VACÍO devuelve 0 en jq 1.6 y 4 en jq 1.7**. En cualquier máquina con jq 1.6 (Ubuntu
  22.04, muchos Homebrew) el guard estaba INERTE: un semgrep reventado salía
  `SEMGREP_SUMMARY errors=0 warns=0` con exit 0. Verde sobre un scan que nunca corrió.
  El test que lo cubría existía desde hacía semanas y pasaba — en la máquina de quien lo
  escribió, que tenía jq 1.7. Se cazó al correr la suite completa en OTRA máquina.
- **Causa raíz:** delegar la SEMÁNTICA del guard en el exit code de una herramienta externa. El
  archivo vacío es precisamente el síntoma de "no corrió", y era justo el caso donde las dos
  versiones discrepan. (La basura no-JSON la cazan ambas: 4 y 5.)
- **Regla:** comprueba la condición **con bash** cuando puedas —`[ ! -s "$OUT" ]` es una línea y
  no tiene versiones— y usa la herramienta externa solo para lo que solo ella sabe hacer. Y para
  el test: si el guard depende de una herramienta de terceros, **stubéala con la semántica
  PERMISIVA** en vez de confiar en la que tengas instalada; si no, el test solo prueba tu
  portátil. Tercera vez que un bug de este harness vive únicamente en una plataforma concreta
  (antes: `stat -c/-f`, y los permisos heredados por los stubs).
- **Detector:** tools/tests/test_fail_closed.sh::test_el_guard_de_json_no_depende_de_la_version_de_jq
  (instala un `jq` de mentira que aprueba todo; el gate debe seguir dando exit 3) junto a
  ::test_semgrep_que_revienta_no_pasa_por_limpio
- **Área:** tools/semgrep-scan.sh

### [2026-08-10] Un run puede salir con 0 y no haber terminado
- **Qué pasó:** el agente de una historia lanzó la suite en segundo plano, escribió "me
  notificará al terminar" y ahí acabó su turno. `claude -p` devolvió 0, así que el runner marcó
  la historia `in-review` y salió 0 también. Desde fuera parecía terminada — y no lo estaba:
  691 líneas del adapter sin commitear, el composition root sin cablear, y `git diff
  base...rama` sin mostrar nada de eso porque vivía en el worktree, sin añadir. Si alguien
  podaba el worktree por costumbre, se perdía.
- **Causa raíz:** confundir "el proceso terminó" con "el trabajo está hecho". El exit code de un
  sub-proceso solo dice lo primero. Lo segundo tiene un hecho observable —el árbol de trabajo—
  y nadie lo miraba. Es §14.2 otra vez: el veredicto es la salida de un comando, nunca una
  afirmación de quien lo ejecutó, y aquí el runner estaba tomando por veredicto un `exit 0`.
- **Regla:** antes de declarar terminado, **comprueba el estado observable, no el código de
  salida**. En el runner: si el worktree tiene algo sin commitear, la historia vuelve a
  `in-progress`, el run sale != 0 y lo pendiente se **respalda** en `.agents/state/` — la
  recuperación no puede depender de que nadie pode el worktree. Y al prompt del agente: no
  termines el turno con procesos en vuelo; "me avisará al acabar" no es un resultado.
- **Detector:** tools/tests/test_backlog.sh::test_run_que_deja_trabajo_sin_commitear_no_cierra
  + ::test_run_limpio_si_cierra_en_in_review (el guard de FP: quien hace las cosas bien sigue
  cerrando)
- **Área:** tools/backlog/run.sh

### [2026-08-10] Se arregló un caso del parser y no se buscó el hermano
- **Qué pasó:** la regla `swift-force-cast` (`$X as! $T`) marcaba también el `as?` **seguro**,
  porque el parser Swift de semgrep normaliza `as!`, `as?` y `as` al mismo nodo. Con el
  trinquete de drift en 0, eso hacía literalmente imposible escribir un adapter de URLSession
  correcto: `response as? HTTPURLResponse` no tiene alternativa. El detector castigaba
  exactamente lo que su propio mensaje recomienda. Y el arreglo **ya existía doce líneas más
  arriba**: `swift-force-try` tiene la intersección `pattern` + `pattern-regex` con un
  comentario describiendo el mismo defecto del parser.
- **Causa raíz:** se arregló el caso que dolía y no se buscó la familia. Un defecto de una
  herramienta de terceros casi nunca afecta a una sola regla; afecta a todas las que usan el
  mismo mecanismo. Y lo que había en su lugar era una promesa: la cabecera decía que las reglas
  «se ejecutaron contra fixtures reales antes de commitearse». Una comprobación manual hecha
  una vez no es un detector.
- **Regla:** al arreglar un defecto del parser/motor, **busca los hermanos en el mismo archivo
  antes de cerrar**. Y el nivel 2 tiene corpus, no promesas: `tools/semgrep/fixtures/` con un
  archivo MALO (una forma por regla) y uno BUENO (las formas seguras que se le parecen). El
  bueno es el que importa: es el guard de falsos positivos de toda la capa. Regla de adopción:
  si no se te ocurre ninguna forma segura parecida a la que cazas, mira más fuerte — casi
  siempre existe, y es la que va a bloquear a alguien.
- **Coletazo, y merece leerse:** crear el directorio de fixtures ROMPIÓ el selftest de
  `validate-harness`, que cogía `ls tools/semgrep/fixtures/* | head -1` dando por hecho que
  todo lo de ahí dispara alguna regla. Con un README y un fixture BUENO —que por definición da
  cero— empezó a declarar el nivel 2 MUDO estando sano. Lo cazó el propio selftest en la
  primera pasada. Regla que deja: **nunca elijas "el primero del directorio" cuando el
  directorio puede crecer**; nombra lo que buscas (`*-malo.*`).
- **Detector:** tools/tests/test_semgrep_rules.sh::test_el_fixture_bueno_no_produce_ni_un_hallazgo
  + ::test_el_fixture_malo_dispara_todas_las_reglas + ::test_toda_regla_de_swift_tiene_su_caso_en_los_fixtures
  (el corpus no puede quedarse atrás) + ::test_los_fixtures_estan_fuera_del_scan_normal
  + ::test_el_selftest_elige_un_fixture_MALO_no_el_primero_del_directorio
- **Segundo coletazo, y la lección de verdad:** al commitear el corpus, el hook `semgrep-staged`
  lo BLOQUEÓ con sus seis anti-patrones. Los fixtures estaban en `.semgrepignore` — y ese
  archivo, igual que `--exclude`, solo se aplica a las rutas que semgrep **descubre**; una ruta
  pasada como TARGET explícito (que es literalmente lo que hace `--staged`) gana a ambos. El
  test que lo cubría comprobaba que la línea estuviera en `.semgrepignore`: **verificaba la
  declaración, no el efecto.** Ahora el corpus se filtra de la lista de targets y el test
  STAGEA el fixture y corre el gate de verdad. Regla que deja: cuando pruebes una exclusión,
  ejecuta el gate; que el archivo de configuración diga lo correcto no demuestra que la
  herramienta lo obedezca por el camino que usas.
- **Área:** tools/semgrep/rules/swift.yaml · tools/semgrep/fixtures/ · tools/semgrep-scan.sh · tools/validate-harness.sh

### [2026-08-10] Un criterio de aceptación «verificado con un grep» es decoración
- **Qué pasó:** un criterio ("la lista NO construye su destino") se dio por verificado con un
  `grep` a mano pegado en el informe del run. Se cumplía ese día — comprobado — y nada impedía
  la regresión al siguiente. Los criterios **negativos** son los que más acaban así: afirman lo
  que el código *no* hace, y un grep que devuelve cero parece prueba suficiente.
- **Causa raíz:** el informe del run se estaba tomando como evidencia. Un grep manual demuestra
  un instante; un test demuestra un invariante. La diferencia es exactamente la que separa
  «detectar» de «cerrar» (§1.1).
- **Regla:** todo criterio de aceptación cita el test que lo fija, con la misma mecánica que el
  campo `Detector:` de las lecciones —incluida la excepción explícita `n/a-manual — <razón>`—
  y el runner lo comprueba antes de marcar `in-review`. Y como en las lecciones: el test citado
  tiene que EXISTIR; validar solo que el campo esté relleno deja pasar tests fantasma.
- **Detector:** tools/backlog/criteria-link.sh + tools/tests/test_backlog.sh::test_criterio_sin_test_no_pasa
  + ::test_test_citado_inexistente_no_cuenta + ::test_listas_de_otras_secciones_no_cuentan_como_criterios (FP guard)
- **Área:** tools/backlog/criteria-link.sh · backlog/_template.md

### [2026-08-11] El informe de "no lo he traído" mentía, y empujaba justo al flujo que prohíbe
- **Qué pasó:** tras un sync real, el bloque "📋 El template también cambió esto, y NO lo he
  tocado" listó `tools/backlog/run.sh`, `next.sh`, `criteria-link.sh`, los fixtures y
  `backlog/_template.md` — todos ellos **sí traídos**. El adoptante hizo lo razonable: se los
  copió a mano. O sea que el propio script empujó al **flujo inverso** que su última línea
  prohíbe con todas las letras ("un archivo que entra por fuera de aquí se salta esta red").
- **Causa raíz:** la regla "¿esto es maquinaria?" estaba implementada **dos veces**. El sync
  usaba `_es_maquinaria()`; el informe, una lista de regexes escrita a mano que pretendía decir
  lo mismo. Y decía otra cosa: `^tools/[A-Za-z0-9_-]+\.sh$` no casa `tools/backlog/run.sh` —
  sobra una barra— y ni `tools/semgrep/fixtures/` ni `backlog/_template.md` aparecían. Cada vez
  que se añadió maquinaria en un subdirectorio, la copia de la regla se quedó atrás sin que
  nada lo dijera.
- **Regla:** una regla, una implementación — y cuando dos sitios necesitan la misma decisión,
  el segundo **llama al primero**, no lo reescribe. Ya estaba en el README ("Una fuente de
  verdad") y en `check-review-marker.sh`; esta es la tercera vez. Corolario específico de este
  script: **el informe de lo NO traído se calcula con la misma función que decide lo traído**,
  porque si divergen, el que miente es el que la gente obedece.
- **Detector:** tools/tests/test_upgrade.sh::test_el_informe_de_no_sincronizado_dice_la_verdad
  (el template cambia maquinaria ANIDADA y una skill; el informe debe listar la skill y NO la
  maquinaria). Ojo al matiz que el propio test tuvo que aprender: capturar "hasta el final" de
  la salida incluía el `git diff --cached --stat`, donde lo traído aparece por definición.
- **Área:** tools/upgrade.sh

### [2026-08-11] El invariante nº1 estaba aplicado al reviewer y no a los tests
- **Qué pasó:** `check-review-marker.sh` liga el review a `sha256(diff staged)` — un review de otro
  diff no vale, y eso lleva meses funcionando. Pero **ninguna ejecución de build o de tests estaba
  ligada a ese mismo diff.** Se podía commitear un árbol que nadie llegó a compilar con todos los
  gates en verde, porque el reviewer no compila, los trinquetes no compilan y las capas no
  compilan. El comando de build vivía como un FILL dentro de `ci/run-gates.sh`: solo en CI, y solo
  como plantilla.
- **Causa raíz:** se aplicó el rigor al eslabón que se estaba diseñando (el review, donde la
  desconfianza era obvia porque el que afirma es un modelo) y no al que ya se daba por hecho. Un
  comando que devuelve 0 también es una afirmación si nadie registra CONTRA QUÉ lo devolvió.
- **Regla:** toda evidencia se liga al artefacto que la produce — `sha256(diff staged)` + HEAD +
  TTL — y la firma quien EJECUTA, nunca quien narra. Corolarios que salieron al construirlo y que
  son la mitad del valor: un build que falla **no firma nada** (un marker tras un fallo convierte
  el gate en un sello), y no se firma con cambios **sin stagear**, porque entonces lo compilado no
  es lo que se commitea. Y el comando vive en **un** sitio (`tools/verify.conf`), consumido por el
  gate local y por CI: dos copias del comando de build divergen igual que dos copias de cualquier
  otra regla.
- **Detector:** tools/tests/test_verify_marker.sh (10 casos: sin ejecución no se commitea, el
  marker caduca al cambiar el diff, un marker a mano se rechaza, un build rojo no firma, no firma
  sin stagear; más los cuatro falsos positivos — docs, sin comando cableado, preset lite y merge)
- **Área:** tools/verify-run.sh · tools/check-verify-marker.sh · tools/verify.conf · AGENTS.md §13

### [2026-08-11] Un gate que lee TEXTO como si fuera sintaxis enseña a evadirlo
- **Qué pasó:** el write-gate de Bash extraía rutas del comando CRUDO, así que un `>` o una ruta
  dentro de una cadena entrecomillada o de un heredoc contaban como escritura real. Tres falsos
  positivos en un mismo día en un proyecto real: un mensaje de commit, un comentario dentro de un
  heredoc, y —el que lo retrata— **el propio comando que registraba el hallazgo en el ledger**. El
  agente acabó escribiendo la ruta incompleta para poder pasar.
- **Causa raíz:** confundir el texto de un comando con su sintaxis. Todo lo que va entre comillas
  o en un heredoc son DATOS: el shell no los interpreta, y el gate tampoco debería.
- **Regla:** antes de analizar un comando, quítale lo que es texto — cuerpos de heredoc y cadenas
  entrecomilladas— y analiza lo que queda. Y ancla los patrones de comando al principio de un
  comando (inicio de línea o tras `;` `&&` `||` `|`): `*cp\ *` casaba la subcadena en cualquier
  sitio, así que un `--detail "...cp ..."` convertía el último token en un "destino de copia".
  Lo importante no es el bug: es que **tres falsos positivos en un día ya produjeron evasión**,
  que es exactamente lo que la ley del 10% predice y por lo que un gate ruidoso es peor que
  ninguno. El coste asumido —un destino entrecomillado deja de detectarse— es un fallo hacia el
  lado seguro y está escrito en el propio gate.
- **Detector:** tools/tests/test_bash_matrix.sh::test_redireccion_entre_comillas_no_bloquea +
  ::test_el_cuerpo_de_un_heredoc_no_bloquea + ::test_cp_mencionado_en_prosa_no_bloquea +
  ::test_una_ruta_en_el_mensaje_de_commit_no_bloquea, junto a
  ::test_la_escritura_real_se_sigue_cazando (un gate que deja de detectar por arreglar sus FP
  es un gate borrado)
- **Área:** scripts/agent-hooks/reviewer-gate.sh §0c

### [2026-08-11] Un hook roto dejó al agente sin poder ni diagnosticarlo
- **Qué pasó:** un `upgrade.sh` dejó marcadores de conflicto dentro de `reviewer-gate.sh`, que es
  el hook `PreToolUse` de Bash. El archivo dejó de parsear, bash salió con error, y el cliente
  leyó ese error como **DENY**: `PreToolUse:Bash hook error: … syntax error near unexpected token
  '<<<'`. A partir de ahí toda ejecución de Bash quedó bloqueada — el agente no podía listar los
  conflictos, ni correr `git status`, ni diagnosticar el problema que el propio upgrade acababa de
  crear. Se salvó por tener la tool `Edit`, que va por otro hook; un cliente que edite vía Bash, o
  un run headless, se queda muerto ahí.
- **Causa raíz:** el modo de **fallo** del hook colisiona con su señal de **deny** — los dos son
  "exit distinto de 0". §14.3 ya resolvía ese empate ("un bug del hook nunca debe trabar al dev"),
  pero estaba implementado para los DETECTORES y no para los HOOKS que los invocan. Y es peor que
  el caso que la regla contempla: no bloquea el commit, bloquea el diagnóstico.
- **Regla:** cuando el canal de "algo va mal conmigo" es el mismo que el de "te deniego", hace
  falta alguien FUERA que los distinga. `scripts/agent-hooks/run-hook.sh` valida con `bash -n` el
  hook **y sus libs** (`bash -n` no sigue los `source`: una lib rota es el mismo brick por otra
  puerta) antes de cederle el proceso con `exec`. Si no parsean: aviso ruidoso por stderr y
  **exit 0**. Corolario para cualquier gate: *prefiere dejar pasar sin red a dejar al operador sin
  instrumentos*. Y `upgrade.sh` lo dice ahora en primer plano cuando un conflicto cae dentro de un
  hook — con el aviso de resolverlo **con el editor, no con la terminal**.
- **Detector:** tools/tests/test_run_hook.sh (hook roto y lib rota → avisa y pasa; deny real sigue
  denegando y hook sano pasa igual — sin esos dos guards habríamos borrado el Anillo 2 entero;
  stdin y args llegan intactos; y los tres configs de cliente invocan vía run-hook)
- **Área:** scripts/agent-hooks/run-hook.sh · tools/upgrade.sh · .claude/settings.json

### [2026-08-11] Un piso de 0 no es un suelo: es una medición que nunca ocurrió
- **Qué pasó:** `mutation-ratchet.json` llevaba en `min_score: 0` desde el montaje, cinco
  historias completas sin moverlo, mientras `AGENTS.md §5` declara el mutation score "el veredicto
  mecánico" y "el gate que distingue un test que verifica de uno escrito para pasar".
  > **Rectificación (2026-08-12).** Esta entrada afirmaba, con un experimento controlado detrás,
  > que la causa era que el SwiftSyntax de muter 16 no entiende `throws(...)` (typed throws,
  > SE-0413). **Era falso**, y la lección que deja el error está una entrada más abajo: el 16 es
  > lo que sirve Homebrew, y el repositorio arregla typed throws en `main` desde 2026-07 sin
  > release publicado. Se deja escrito en vez de borrarlo — una causa retirada enseña más que
  > una causa que nunca estuvo. Lo que sí sigue en pie es todo lo de abajo, que no dependía de
  > por qué el nivel 4 estaba mudo, sino de que lo estuviera.
- **Causa raíz:** un 0 en un archivo llamado "piso" se lee como suelo, y lo que dice es "nadie ha
  medido". El número existía, así que nadie preguntó si significaba algo.
- **Regla:** un valor que puede significar "sin medir" **no puede compartir representación con una
  medición legítima**. `--update` se niega a escribir un piso de 0, el ratchet lleva
  `measured: false` explícito, y `session-start` lo dice en cada arranque: *nivel 4 NUNCA MEDIDO*.
  Eso no arregla muter — no está en nuestra mano— pero deja de anunciar una defensa que no
  existe, que es la única parte que sí lo está.
- **Detector:** tools/tests/test_ratchets.sh::test_update_se_niega_a_escribir_un_piso_de_cero +
  ::test_una_medicion_real_sube_el_piso_y_marca_medido (el guard de FP: inicializar de verdad
  tiene que seguir funcionando)
- **Área:** tools/mutation-score.sh · tools/mutation-ratchet.json · scripts/agent-hooks/session-start.sh

### [2026-08-12] "Sin cablear" y "cableado, pero el runner no termina" no son el mismo estado
- **Qué pasó:** el arreglo de arriba dejaba el nivel 4 con dos estados: *medido* y *NUNCA MEDIDO*.
  Con eso, el adoptante que ya había cableado el runner y se quedaba sin score leía en cada
  arranque el mismo mensaje que quien no lo había cableado nunca — y el mensaje le decía que
  cableara el conf. Cableó el conf. Volvió a leer lo mismo. El estado real era un tercero: muter
  arrancaba y no localizaba el `xctestrun` del proyecto, así que **completaba con cero mutantes**.
- **Causa raíz:** un estado agregado que mete en el mismo cajón "no lo has intentado" y "lo
  intentaste y la herramienta no llegó al final". Lo primero se arregla con configuración; lo
  segundo NO, y el mensaje empujaba justo a la acción que no podía funcionar. Es el mismo defecto
  que el piso de 0, un nivel más arriba: **dos situaciones distintas compartiendo representación**.
- **Regla:** cuando un estado agregado pueda venir de causas con remedios OPUESTOS, sepáralos y
  di cuál es. `tools/mutation-score.sh --state` responde con uno de cuatro:
  `medido` · `sin-cablear` · `runner-incompleto` · `sin-medir`, y `session-start` ramifica sobre
  eso — el mensaje de `runner-incompleto` dice explícitamente que **no se arregla cableando más
  conf** y manda a mirar el repositorio de la herramienta, no su release.
- **Coletazo, y es la parte que más enseña:** la primera versión de `--state` resolvía
  `runner-incompleto` **llamando al runner**. O sea que la función cuya cabecera prometía "responde
  sin medir" lanzaba una corrida de decenas de minutos en cada arranque de sesión. Lo cazó su
  propio test de FP, escrito precisamente porque la cabecera prometía esa propiedad. La salida es
  el invariante nº1 otra vez: el estado no se AFIRMA, se DERIVA de una ejecución real — cada
  corrida de verdad deja su resultado en `.agents/state/mutation-last-run.txt` y `--state` lo lee.
  Regla que deja: **cuando una función promete "esto es barato", el test que lo fija es
  obligatorio**; sin él la promesa es documentación de algo que no ocurre.
- **Detector:** tools/tests/test_ratchets.sh::test_state_sin_runner_dice_sin_cablear +
  ::test_state_con_piso_real_dice_medido +
  ::test_state_runner_que_no_completa_no_se_confunde_con_sin_cablear +
  ::test_state_no_dispara_una_corrida_del_runner (el FP guard de la promesa "no mide"), y
  tools/tests/test_session_start.sh::test_los_cuatro_estados_del_nivel4_no_comparten_mensaje.
  El otro guard de FP vive dentro del primero: un repo SIN runner y con una huella vieja sigue
  diciendo `sin-cablear` — acusar a una herramienta ausente de fallar sería el error simétrico.
- **Área:** tools/mutation-score.sh · scripts/agent-hooks/session-start.sh

### [2026-08-12] El archivo de tests existía; el test citado no
- **Qué pasó:** `lesson-detector-link.sh` comprobaba que el archivo citado en `Detector:`
  existiera, y ahí paraba. Escribiendo las lecciones de este mismo día cité
  "`test_session_start.sh` (los cuatro estados, cada uno con su mensaje)" cuando ese archivo no
  tenía **ningún** test de los cuatro estados. El archivo existía → gate en verde → lección
  respaldada por una promesa.
- **Causa raíz:** la comprobación se detuvo en el eslabón barato. Verificar la existencia del
  archivo es fácil; verificar la del test hace falta leer dentro. Es el mismo agujero que un id de
  finding fantasma: **la cita LEE COMO CUBIERTO, y precisamente por eso nadie vuelve a mirarla.**
- **Regla:** toda referencia `archivo::test_x` de una línea `Detector:` se resuelve contra las
  funciones del archivo — la línea entera, no solo el primer token, porque una lección cita varios
  tests y basta uno inventado para que el respaldo sea ficticio.
- **Detector:** tools/lesson-detector-link.sh, fijado por
  tools/tests/test_lessons.sh::test_un_test_citado_que_no_existe_falla +
  ::test_los_tests_que_existen_no_se_acusan +
  ::test_un_detector_que_no_es_un_test_sigue_valiendo (sin este último, exigir un `::` rechazaría
  detectores legítimos —semgrep, layers.conf, un hook— y el gate acabaría desactivado)
- **Área:** tools/lesson-detector-link.sh

### [2026-08-12] El gestor de paquetes contesta a otra pregunta
- **Qué pasó:** el nivel 4 llevaba semanas declarado imposible para Swift 6 sobre esta cadena:
  `brew` sirve muter 16 → muter 16 no parsea typed throws → *no hay upgrade* → el nivel 4 no está
  disponible. Todo el razonamiento era correcto salvo el primer eslabón. El repositorio
  (`https://github.com/muter-mutation-testing/muter`) tiene el arreglo en `main` desde 2026-07:
  el proyecto llevaba meses desarrollando **sin publicar un release**. Y de propina, el único
  score que se llegó a ver (`globalMutationScore = 25`) salió de un artefacto de build viejo:
  una medición inválida que además *tranquilizaba*.
- **Causa raíz:** `brew`/`apt`/`npm` responden "¿cuál es el último RELEASE?". La pregunta era
  "¿qué soporta el proyecto?". Son preguntas distintas y sus respuestas divergen durante meses;
  tomar una por la otra es una inferencia, no una comprobación — y quedó escrita en el ledger
  con la forma de un hecho verificado.
- **Regla:** antes de declarar un gate no disponible por la versión de una herramienta, **mira la
  fuente**: `git ls-remote --tags <repo>`, el issue, el commit. Y el hallazgo cita esa fuente, no
  la salida del gestor. La asimetría es lo que lo hace obligatorio: una capa entera de la
  pirámide se declara imposible, se documenta como tal, y la conclusión negativa **se
  auto-preserva** porque desalienta exactamente la comprobación que la refutaría. No es un error
  que se caiga solo; hay que ir a buscarlo.
- **Detector:** tools/check-version-claims.sh
  (Anillo 3, paso 8e): un hallazgo del ledger que declare una herramienta incapaz por versión
  debe citar un repositorio, un `git ls-remote`, o declarar `n/a-repo — <razón>`. Sus guards de
  falso positivo están en tools/tests/test_finding_refs.sh — el que importa es
  ::test_una_observacion_sobre_versiones_no_exige_repositorio: "jq 1.6 se comporta así" se
  verifica **corriendo jq**, y solo la afirmación de que NO EXISTE una versión capaz necesita
  mirar la fuente, porque es justo lo que tu copia no puede decirte.
- **Área:** tools/findings/ledger.jsonl · tools/check-version-claims.sh

### [2026-08-12] Un id de finding que no existe LEE COMO CERRADO
- **Qué pasó:** nada, todavía — y esa es la mitad interesante. El ledger es el inventario único de
  hallazgos y la doc lo cita por id ("decidido en `f-marker-spoof`"), pero nadie comprobaba que el
  id existiera. Bastaba un typo, un id reconstruido de memoria tras una compactación, o renombrar
  una entrada sin repasar quién la citaba.
- **Causa raíz:** una cita rota, en cualquier otro contexto, se nota. Aquí no: quien encuentra
  "cerrado en `f-xxxxxxx`" **no va a comprobarlo**, da por hecho que hay una entrada con su tier,
  su razón y su fecha, y no vuelve a abrir el tema. El hallazgo se evapora **con el aspecto de
  haberse cerrado**, que es exactamente el modo de fallo contra el que existe el ledger (§10).
- **Regla:** un id citado tiene que resolver contra `ledger.jsonl`. Si el hallazgo es real, se
  crea con el CLI en el mismo cambio; si la cita está mal, se corrige.
- **Detector:** tools/check-finding-refs.sh
  (Anillo 3, paso 8e). Y su primer falso positivo apareció, como manda la ley de este repo,
  **contra este mismo repo**: un `grep 'f-[a-z-]*'` casaba la subcadena **f-nature** dentro de
  `check-diff-nature`. Por eso una cita es solo un span entre acentos graves y fuera de bloques
  de código: los acentos son la marca que el autor pone para decir "esto es un identificador",
  y exigirlos convierte una heurística en una lectura. Coletazo, en la primera pasada: **este
  párrafo disparó el check**, porque el ejemplo iba entre acentos graves. No se le puso excepción
  al doc —eso habría cegado justo al archivo que más cita findings—: se le quitaron los acentos,
  que es literalmente lo que el mensaje del check recomienda hacer. Guards en
  tools/tests/test_finding_refs.sh::test_una_subcadena_dentro_de_otro_nombre_no_es_una_cita +
  ::test_los_ejemplos_de_uso_no_se_confunden_con_citas (el `close f-xxxx` del manual del CLI).
- **Área:** tools/check-finding-refs.sh · docs/**

### [2026-08-12] La cuarta vez del mismo falso positivo no pide otra lección
- **Qué pasó:** el write-gate de Bash volvió a bloquear una lectura. Cuarta vez del mismo patrón,
  con el caso más limpio posible: `sed -n '54,58p' <archivo>` y
  `grep -rc "assert(" Pelis --include="*.swift"`. El gate casaba `*sed*-i*` y `*perl*-i*` como
  subcadenas, así que `--include=` contiene una `i` precedida de guion y `-n '54,58p'` va detrás
  de un `sed`. Dos comandos de LECTURA pura leídos como edición in-place.
- **Causa raíz:** la vez anterior se anclaron `cp` y `mv` al inicio de comando, con un comentario
  explicando por qué. Los patrones hermanos —`sed` y `perl`, cuatro líneas más abajo, con el mismo
  defecto y en la misma función— se quedaron sin tocar. Es literalmente la lección
  *[2026-08-10] Se arregló un caso del parser y no se buscó el hermano*, cometida **en el arreglo
  de otro caso de la misma regla**.
- **Regla:** no hace falta otra lección; hace falta que el arreglo cubra a la familia **en el
  mismo cambio**. Operativamente: al anclar/normalizar un patrón, se releen todos los patrones de
  esa función antes de cerrar, y cada uno estrena su test. Ahora `sed`/`perl` exigen ser el primer
  token de un comando y que `-i` sea un argumento propio (`-i`, `-pi`, `-i.bak`), no una letra
  dentro de un flag largo.
- **Detector:** tools/tests/test_bash_matrix.sh::test_sed_de_lectura_con_flag_que_contiene_i_no_bloquea
  + ::test_un_flag_largo_que_contiene_i_no_es_edicion_in_place +
  ::test_la_edicion_in_place_real_se_sigue_cazando (sin este último, arreglar los FP habría
  borrado el gate)
- **Área:** scripts/agent-hooks/reviewer-gate.sh §0c

### [2026-08-11] Cambiar de lanzador habría duplicado todos los hooks de todos los proyectos
- **Qué pasó:** al envolver los hooks en `run-hook.sh` (el arreglo del brick), el merge de
  `.claude/settings.json` los habría añadido como entradas NUEVAS: el proyecto se quedaba con el
  hook dos veces —el suyo directo y el envuelto— porque las cadenas difieren aunque el hook sea
  el mismo. Dos ejecuciones por evento: `session-start` reseteando markers dos veces, el gate
  opinando dos veces sobre cada comando.
- **Causa raíz:** la identidad del hook se calculaba sobre el comando LITERAL. Pero un hook no es
  su línea de invocación: es lo que ejecuta. El lanzador es envoltorio, y comparar envoltorios es
  comparar la cosa equivocada. La regla "solo añade" —correcta para permisos— aplicada a la
  identidad equivocada convierte un upgrade en una duplicación.
- **Regla:** cuando compares "¿es esto lo mismo?", **normaliza antes de comparar**, y normaliza
  quitando lo que es accidente (aquí: `bash `, el lanzador) y dejando lo que es esencia (el
  script y sus args). Cambiar de envoltorio es un UPGRADE de la entrada existente, no una entrada
  nueva — y se reporta como tal (`(lanzador actualizado)`) para que "solo añade" siga siendo
  cierto en lo que importa: nada del proyecto se pierde. Detalle que costó el primer intento:
  había que quitar el `bash ` de los DOS lados, o `bash …/run-hook.sh X` y `bash X` normalizaban
  a `X` y a `bash X` y seguían sin casar.
- **Detector:** tools/tests/test_settings_merge.sh::test_cambiar_de_lanzador_actualiza_en_vez_de_duplicar
  (exige UNA aparición del hook y que el lanzador nuevo llegue) junto a
  ::test_correrlo_dos_veces_no_duplica_nada
- **Área:** tools/merge-claude-settings.sh

### [2026-08-11] La suite corría DESPUÉS del push, así que `main` se publicó en rojo
- **Qué pasó:** un adoptante clonó `main` limpio, corrió la suite del propio template y le dio
  `310 pasaron, 1 FALLÓ`. El test roto era justo el que avisaba de que el arreglo del brick de
  hooks había quedado cableado en Cursor y Codex pero **inerte en Claude Code**, que es el
  cliente donde ocurrió el brick que motivó todo el trabajo. Causa próxima concreta: el puente
  de entrega no puede escribir en `.claude/`, así que ese archivo quedó fuera del lote y el push
  salió antes de colocarlo a mano.
- **Causa raíz:** el workflow de CI corre la suite en `push: [main]` — **después** de publicar.
  Para cuando suena la alarma, el delta ya está en `main` y ya es sincronizable por cualquiera.
  Eso no es un gate, es un aviso; la misma "defensa anunciada que no existe" que este repo
  persigue en todo lo demás, cometida sobre su propia publicación. Y los otros dos guardias
  tampoco tapaban el hueco: la verificación de `upgrade.sh` vive al final del camino limpio (el
  camino con conflictos sale antes) y `_fundir_settings` solo imprimía un `⚠️`.
- **Regla:** la suite del harness es un **gate de publicación**, y corre en la máquina de quien
  publica, antes del push (`pre-push` en `lefthook.yml`). Un `pre-push` versionado gana a la
  branch protection como primera línea: viaja con el repo, lo hereda cada adoptante, y no
  depende de configurar nada en una web. Corolario que vale para cualquier proyecto: **si tu CI
  te avisa después del push, tu gate está una vuelta por detrás de tu problema.**
- **Detector:** lefthook.yml job `harness-suite` en `pre-push` (corre `tools/tests/run-tests.sh`
  con lo que se va a publicar) + tools/tests/test_run_hook.sh::test_los_tres_clientes_invocan_los_hooks_via_run_hook
  (el test que sí avisó, y que ahora bloquea antes de salir)
- **Área:** lefthook.yml · .github/workflows/ · tools/upgrade.sh

### [2026-08-11] Un test con fixture inventado prueba la invención, no la herramienta
- **Qué pasó:** `merge-claude-settings.sh` reventaba con `AttributeError: 'str' object has no
  attribute 'get'` contra el `.claude/settings.json` **de este mismo repo**: bajo `hooks` hay
  cinco claves `_comment_*` cuyo valor es un string, `enumerate()` sobre un string da caracteres,
  y `g.get("matcher")` explota. Nació roto en su primer commit y **nunca funcionó** — sus seis
  tests pasaban desde el día uno porque los fixtures eran JSON sintéticos que no reproducían el
  archivo real. Como solo se invocaba desde un camino que imprimía `⚠️`, el fallo era invisible.
- **Causa raíz:** el fixture lo escribió quien escribió la herramienta, con la forma que la
  herramienta esperaba. Eso no prueba la herramienta: prueba que el autor es coherente consigo
  mismo. Es la misma ley que ya conocíamos un piso más arriba — *el primer falso positivo de un
  detector aparece en el repo del propio detector* (PRD 0001) — aplicada a la otra mitad.
- **Regla:** **toda pieza que procesa un artefacto del repo tiene, como primer test, ese
  artefacto.** No el que te imaginas: el que está en disco, tal cual, hoy. Y el arreglo tiene su
  propio matiz: ante una clave inesperada, **saltar ≠ borrar** — la documentación del proyecto se
  conserva intacta y solo se copia la del template si falta.
- **Detector:** tools/tests/test_settings_merge.sh::test_funde_el_settings_REAL_del_repo_sin_reventar
  (funde el archivo del repo consigo mismo: exit 0, hooks=+0, `_comment_` conservados, JSON
  válido) + ::test_un_comentario_bajo_hooks_se_conserva_intacto
- **Área:** tools/merge-claude-settings.sh · tools/tests/test_settings_merge.sh

### [2026-08-11] Un RED sin huella hace indistinguible la remediación del reintento
- **Qué pasó:** `capture-review-verdict.sh` guardaba `staged_sha` y hallazgos solo en el camino
  GREEN/AMBER. En RED solo llamaba a `hook_log_detection`. Medido en un proyecto real: **36 RED,
  9 AMBER y CERO GREEN** en todo el historial, con una secuencia RED→RED→GREEN sobre nueve
  archivos cuyo mtime era diez minutos ANTERIOR al primer RED — ni un byte cambió entre los tres
  veredictos. La lectura benigna era la correcta en ese caso (los RED pedían registrar gaps en
  el ledger, §10, y se hizo), y eso es exactamente lo grave: **el harness no podía distinguirla
  de un verdict-shopping.**
- **Causa raíz:** solo se guardaba la evidencia del veredicto que desbloqueaba. El sistema
  contaba veredictos sin verificar que algo cambiara entre ellos, así que "insistir" y "arreglar"
  tenían el mismo aspecto desde fuera.
- **Regla:** el invariante nº1 llevado a su conclusión — si el veredicto lo deriva el sistema de
  una ejecución real, **dos ejecuciones sobre la misma entrada no pueden dar salidas opuestas**
  sin que algo haya cambiado. Un RED deja huella (`last_red.txt` + `review-history.jsonl` con el
  sha), y un GREEN sobre ese mismo sha y ese mismo HEAD no escribe marker: o el RED estaba mal o
  lo está el GREEN, y en ninguno de los dos casos toca desbloquear. Escape auditado
  (`REVIEW_SAME_DIFF_OVERRIDE`) para el RED que se resuelve con un argumento y no con código —
  mismo patrón que `REVIEWER_OVERRIDE`, porque el caso legítimo existe y negarlo produciría el
  deadlock contrario. Corolario práctico: si el hallazgo pedía registrar algo en el ledger, ese
  registro **es parte del diff** y se estagea antes de re-revisar.
- **Detector:** tools/tests/test_verdict.sh::test_un_red_deja_huella_del_diff_juzgado +
  ::test_green_sobre_el_mismo_diff_que_el_red_no_marca +
  ::test_green_tras_cambiar_el_codigo_si_marca (el guard que impide convertir el agujero en un
  deadlock) + ::test_el_override_de_mismo_diff_queda_auditado
- **Área:** scripts/agent-hooks/capture-review-verdict.sh

### [2026-08-11] La cola del juez premiaba dejar basura
- **Qué pasó:** `session-end.sh` encolaba para el `process-judge` si el árbol quedaba SUCIO. O
  sea que la sesión que cierra bien —commitea su trabajo y deja el árbol limpio— era exactamente
  la que **nunca** se encolaba. Reproducido: la cola apuntaba a una sesión con 7 tool-calls y
  cero ediciones (leer el backlog y dos builds), mientras las dos sesiones que escribieron el
  adapter y el composition root no entraron. El juez auditaba sistemáticamente a quien no había
  trabajado.
- **Causa raíz:** se eligió como señal un residuo (el árbol sin limpiar) en vez del resultado
  (los commits producidos). Un residuo mide lo que quedó sin hacer, no lo que se hizo — y aquí
  correlacionaba **al revés** con lo que se quería auditar. Una métrica de calidad sobre la
  muestra equivocada es peor que ninguna: da confianza sin cubrir nada.
- **Regla:** elige como señal el **resultado**, no lo que quedó por el camino. `session-start`
  guarda el HEAD de arranque y `session-end` encola por commits producidos (el árbol sucio sigue
  contando, pero ya no es la condición). Y la línea de la cola lleva el **rango de commits**, no
  solo el id de sesión: es lo que el juez tiene que mirar (`git diff <rango>`), y no tiene los
  huecos de la trayectoria — en el caso real, 13 minutos sin cubrir, justo la ventana de los
  sub-agentes `reviewer` y los dos commits.
- **Detector:** tools/tests/test_judge_queue.sh::test_la_sesion_que_commitea_y_deja_limpio_SI_se_encola
  + ::test_una_sesion_sin_commits_ni_cambios_no_se_encola (el FP guard). Ojo al detalle que costó
  el primer intento: el sandbox necesita el `.gitignore` REAL, porque sin él git reporta
  `?? .agents/` colapsando el directorio y el filtro —que casa `?? .agents/state/`— no lo ve.
- **Área:** scripts/agent-hooks/session-end.sh · scripts/agent-hooks/session-start.sh

### [2026-08-12] El repo que escribe el gate era el único sin cablearlo
- **Qué pasó:** al ir a commitear la tanda que añade dos detectores al ledger, el propio gate de
  evidencia paró el commit: *"no hay comando de build+tests cableado (`tools/verify.conf`)"*.
  El template lleva meses exigiendo a sus adoptantes que aten una ejecución verde al diff que
  commitean — `verify-run.sh`, el paso 6 del Anillo 3, el job `verify-marker` de lefthook — y en
  su propio repo esa línea seguía siendo un FILL. Ninguno de sus commits estuvo nunca ligado a
  una ejecución registrada.
- **Causa raíz:** `verify.conf` nació como plantilla *para otros*, y a nadie le chirrió que el
  template no lo rellenara: "es un template, no tiene build". Sí lo tiene — su producto es el
  harness y su build+tests es `bash tools/tests/run-tests.sh`. Es `f-harness-no-autogate` otra
  vez: la herramienta se exime de la regla que reparte, y el hueco vive justo donde nadie mira
  porque parece que no aplica.
- **Regla:** el template se aplica sus propios gates. `tools/verify.conf` va cableado con la
  suite. Y como eso crea un riesgo NUEVO —quien adopta hereda esa línea y su `verify-run` sale
  verde sin compilar su app—, el riesgo se cierra en el mismo cambio: `verify-run.sh` mira si hay
  código de producto que el comando no toca y sale 3 ("no pude verificar"), que avisa en local y
  bloquea en CI. La pregunta que hace el guard no es "¿eres el template?" sino la que de verdad
  importa: **¿hay producto que este comando no está tocando?**
  Lo que hace obligatorio ese guard es la asimetría: un FILL sin rellenar se anuncia solo en cada
  arranque de sesión; un comando heredado **SALE VERDE**. Un hueco se delata; una respuesta
  equivocada, no.
- **Detector:** tools/tests/test_verify_marker.sh::test_heredar_el_verify_del_template_no_cuenta_como_cableado
  + ::test_un_repo_sin_producto_verifica_con_la_suite (el FP que importa: es el caso del propio
  template, y sin él el harness volvería a no poder atar sus commits a nada)
  + ::test_encadenar_la_suite_al_build_propio_no_avisa (regañar a quien encadena la suite a su
  build le enseñaría a QUITARLA: el gate produciría lo contrario de lo que persigue)
- **Área:** tools/verify.conf · tools/verify-run.sh

### [2026-08-12] El detector se validó contra el único ledger que no lo iba a romper
- **Qué pasó:** `check-version-claims.sh` se midió contra el ledger de este repo —38 entradas,
  disparó en 1, y era la defectuosa— y esa cifra se escribió en su cabecera como prueba de que
  era quirúrgico. El primer adoptante lo corrió contra el suyo: 61 entradas, prosa española
  densa, historias y criterios numerados. **3 disparos, 2 falsos positivos: 67%**, seis veces por
  encima del 10% que el propio detector cita como criterio de diseño, y bloqueando su push.
- **Causa raíz:** dos defectos que por separado eran tolerables y juntos rompen el detector.
  `<palabra> <número>` es, en prosa española real, todas partes (*criterio 6*, *la 0006*, *Los 3
  únicos casts*, *nivel 4*); y `tiene` estaba en la lista de verbos de incapacidad cuando en
  español **"no tiene" es CARECER**, no "no soporta" (*no tiene test*, *no tiene alternativa*).
  Ninguno de los dos podía verse desde dentro: el corpus contra el que se validó lo había
  escrito el mismo que escribió el detector.
- **Regla:** **"contra el artefacto real" incluye el artefacto real de OTRO.** Un detector que
  lee prosa se valida contra prosa que no escribiste tú — otro idioma, otra densidad de números,
  otras muletillas. Es la evolución de la ley anterior (*el primer fallo de una pieza que procesa
  un artefacto del repo aparece contra ESE artefacto*): resulta que hay un fallo posterior, y
  aparece contra el artefacto del primero que lo instale. Mecanismo, no buena intención:
  `tools/findings/fixtures/` con un `ledger-bueno.jsonl` de prosa ajena —entradas `[adoptante]`
  copiadas **literales**, sin "mejorarlas"— y un `ledger-malo.jsonl` con una línea por forma que
  el detector caza. Mismo patrón que `tools/semgrep/fixtures/`, y por el mismo motivo: el fixture
  BUENO es el guard de falsos positivos de toda la capa.
  Corolario para las listas de verbos: distingue **soporte** (`soporta`, `parsea`, `entiende`,
  `admite`, `implementa`) de **posesión y cobertura** (`tiene`, `trae`, `cubre`). Las segundas
  son lenguaje corriente y meterlas en un detector es meter el idioma entero.
- **Detector:** tools/tests/test_finding_refs.sh::test_el_corpus_de_prosa_ajena_no_produce_ni_un_hallazgo
  + ::test_el_corpus_malo_dispara_en_todas_sus_formas (arreglar los FP no puede vaciar el
  detector) + ::test_el_corpus_ajeno_lleva_los_textos_que_produjeron_el_fallo (un corpus que se
  reescribe para que "quede mejor" deja de reproducir nada), y
  tools/tests/test_upgrade.sh::test_sync_trae_la_maquinaria_nueva, porque un corpus que no viaja
  deja al adoptante con el test y sin el archivo que busca.
- **Coletazo, y es una regla nueva:** al cerrar esto, el adoptante propuso un caso más para el
  corpus BUENO — un hallazgo que **cita** una afirmación de versión como ejemplo (*"el informe
  afirmaba «muter 16 no parsea typed throws»"*), invocando dos precedentes reales de este mismo
  harness: el git-guard no salta con `grep "git commit --no-verify" doc.md`, y la matriz de Bash
  desnuda las cadenas entrecomilladas antes de analizar. **Se rechazó, y va al corpus MALO.**
  Aquellos dos se apoyan en una gramática EXTERNA y autoritativa —el shell no ejecuta lo
  entrecomillado, y quien lo dictamina es su parser, no nuestro criterio—. En prosa no existe esa
  gramática: las comillas son estilo. Exentarlas no sería leer mejor, sería regalar una primitiva
  de evasión (envuelve la afirmación en comillas y pasa), y un detector evadible con un truco de
  formato enseña el truco. La confirmación empírica llegó sola: quien encontró el caso lo resolvió
  **citando la fuente**, no pidiendo la excepción, y le costó una URL.
  > **"Texto ≠ sintaxis" solo se puede mecanizar cuando existe un parser que lo dictamine.**
  > Sin gramática externa, esa distinción la controla el evaluado — y un gate cuyo criterio
  > controla el evaluado no es un gate.
- **Detector (del coletazo):** tools/tests/test_finding_refs.sh::test_una_afirmacion_de_version_citada_como_ejemplo_sigue_disparando
  — fija la decisión en las DOS direcciones (la fila está en el corpus malo y NO puede aparecer
  en el bueno), porque una decisión razonada que no se fija la "arregla" el siguiente que pase.
- **Área:** tools/check-version-claims.sh · tools/findings/fixtures/

### [2026-08-12] Un fallback añadió un segundo cero a un resultado válido
- **Qué pasó:** al introducir lectura mixta v1/v2, el caso de stream vacío mostró que
  `gate-value.sh` imprimía `Eventos registrados: 0` y luego otro `0` en la línea siguiente.
  La forma `grep -c ... || echo 0` parecía un fallback normal, pero `grep -c` **ya imprime 0**
  cuando no encuentra líneas y después devuelve exit 1; el `echo` añadía un segundo valor a la
  misma sustitución de comando. El contador de findings tenía el mismo defecto.
- **Causa raíz:** se confundió “el comando no produjo resultado” con “el comando produjo el
  resultado cero y usó exit 1 para decir que no hubo matches”. En herramientas Unix, stdout y
  exit code son contratos distintos; aplicar un fallback de texto solo por rc puede duplicar
  una salida perfectamente válida.
- **Regla:** para contadores, captura la salida con `|| true` y normaliza vacío después
  (`: "${COUNT:=0}"`). No uses `grep -c ... || echo 0`. Fija también el conjunto vacío: es donde
  se ve el salto de línea que los casos con datos ocultan.
- **Detector:** tools/tests/test_metrics.sh::test_gate_value_reporta_cero_una_sola_vez_con_stream_vacio
- **Área:** tools/metrics/gate-value.sh

### [2026-08-12] Añadir campos al evento no migra a sus productores
- **Qué pasó:** el evento v2 tenía campos correctos en el emisor y sus tests unitarios, pero el
  review adversarial encontró roturas en las fronteras: la clave de dedup no incluía las
  dimensiones nuevas; ceros iniciales producían números JSON inválidos; `reviewer-gate` seguía
  pasando duración en la posición antigua de `n`; un repo sin primer commit conservaba stdout
  residual de `git rev-parse`; `--source-event` ausente o vacío terminaba en éxito sin vínculo;
  y caracteres de control admitidos por Bash convertían la línea JSON en inválida.
- **Causa raíz:** se validó el nuevo objeto aislado, no el recorrido completo **caller → emisor
  → almacenamiento → lector → promoción durable**. Un esquema compatible en el centro no
  repara contratos posicionales viejos ni claves de identidad construidas antes de que existieran
  los campos nuevos. Además, stdout y exit code de una dependencia son canales independientes:
  un comando fallido puede haber impreso algo que no debe convertirse en dato.
- **Regla:** toda migración de esquema enumera y prueba sus productores reales, dimensiones de
  deduplicación, serialización de bordes, estado inicial vacío y flags explícitos incompletos.
  Un flag que promete trazabilidad falla cerrado si no puede crearla; una dependencia fallida
  descarta su stdout antes de aplicar el fallback.
- **Detector:** tools/tests/test_findings_cli.sh::test_anti_rafaga_no_colapsa_fases_ni_commits_distintos
  + ::test_evento_v2_normaliza_ceros_iniciales_a_json_valido
  + tools/tests/test_metrics.sh::test_reviewer_gate_registra_una_deteccion_y_duracion_en_ms
  + ::test_evento_v2_repo_sin_head_usa_unknown_sin_stdout_residual
  + ::test_source_event_explicito_sin_valor_falla_sin_escribir
  + ::test_evento_v2_reemplaza_todos_los_controles_que_invalidan_json
- **Área:** scripts/agent-hooks/lib/io.sh · scripts/agent-hooks/reviewer-gate.sh · tools/findings/findings.sh

### [2026-08-12] Omitir una línea corrupta convirtió “no pude medir” en cero
- **Qué pasó:** los lectores de métricas advertían y saltaban una línea JSONL inválida. Si la
  fuente solo contenía esa línea —o si los registros válidos quedaban fuera de la ventana— el
  reporte terminaba con exit 0 y una población vacía indistinguible de “no hubo actividad”.
- **Causa raíz:** se trató una lectura parcial como un dataset válido. La advertencia en stderr
  no cambia el contrato de éxito ni impide que automatización posterior consuma el JSON.
- **Regla:** una fuente de evidencia existente pero estructuralmente corrupta es “no pude
  medir”: el lector aborta con exit 3 y no emite un reporte de éxito, aunque ya haya leído filas
  válidas. Esto aplica también al normalizador standalone: primero valida/materializa el stream
  completo y solo después publica stdout. Los datos semánticamente incompletos que sí se acepten
  deben quedar cuantificados en la salida; la corrupción de transporte no se normaliza a cero.
- **Detector:** tools/tests/test_metrics.sh::test_jsonl_corrupto_es_exit3_no_poblacion_cero
- **Área:** tools/metrics/read-events.py · tools/metrics/metrics-report.py

### [2026-08-12] Validar el prefijo de un timestamp no valida el instante
- **Qué pasó:** `gate-value` recortaba `ts[:10]` y parseaba solo la fecha. Un valor como
  `2026-08-10NOT-A-TIME` entraba en la ventana, sumaba actividad y dejaba `invalid_dates=0`.
- **Causa raíz:** el campo se usó como clave de agrupación antes de validar su contrato completo;
  un prefijo casualmente válido convirtió basura semántica en evidencia medible.
- **Regla:** valida el valor completo antes de derivar una clave parcial. Para eventos v1/v2,
  parsea el timestamp ISO entero, exige zona horaria y normaliza el instante a UTC; solo después
  extrae el día. Dos representaciones del mismo instante deben caer en la misma ventana. Los
  valores inválidos quedan fuera del denominador y cuantificados explícitamente.
- **Detector:** tools/tests/test_metrics.sh::test_gate_value_valida_timestamp_completo_no_solo_prefijo_fecha
- **Área:** tools/metrics/metrics-report.py

### [2026-08-12] Normalizar los datos a UTC no basta si la ventana sigue siendo local
- **Qué pasó:** los eventos ya derivaban su día en UTC, pero el `--until` implícito se calculaba
  con `date.today()` en el timezone del host. Cerca de medianoche, local y CI podían medir rangos
  distintos sobre el mismo log.
- **Causa raíz:** se normalizó solo un lado de la comparación temporal. Un dato UTC comparado con
  límites locales sigue teniendo semántica dependiente del entorno.
- **Regla:** datos y límites comparten la misma base temporal. Si la métrica agrupa por día UTC,
  su ventana por defecto también nace del día UTC; los overrides explícitos siguen siendo fechas
  literales. Verifícalo con zonas cuyo desfase total garantice días locales distintos.
- **Detector:** tools/tests/test_metrics.sh::test_ventana_default_usa_dia_utc_en_cualquier_timezone_del_host
- **Área:** tools/metrics/metrics-report.py

### [2026-08-12] Cuantificar un descarte no reemplaza la señal de su causa
- **Qué pasó:** los reportes contaban `invalid_dates`, pero sus parsers capturaban el error y
  devolvían `None` en silencio. El agregado decía cuántos datos faltaban sin dejar una señal local
  de por qué fueron descartados, y el trinquete de Semgrep bloqueó el commit.
- **Causa raíz:** se confundió observabilidad del resultado con observabilidad del fallo. Son dos
  contratos distintos: el contador sirve al consumidor del reporte; stderr sirve al operador que
  debe diagnosticar una fuente dañada.
- **Regla:** si una entrada inválida se excluye legítimamente, cuantifica el descarte y emite una
  señal genérica sin copiar el dato potencialmente sensible. No tragues la excepción ni relajes el
  detector que la encontró. Enumera también los retornos tempranos: la ruta de excepción no es la
  única forma de descartar una entrada.
- **Detector:** tools/tests/test_metrics.sh::test_gate_value_valida_timestamp_completo_no_solo_prefijo_fecha
- **Área:** tools/metrics/metrics-report.py

### [2026-08-12] Una vista generada no puede convertirse en entrada de su propio generador
- **Qué pasó:** al agregar lecciones después del índice existente, la siguiente rotación trató
  ese índice como cola de la última entrada viva, lo conservó y generó un segundo índice.
- **Causa raíz:** el script hacía append incremental sobre una vista derivada en vez de
  reconstruirla desde sus fuentes canónicas.
- **Regla:** antes de clasificar, elimina todas las vistas generadas; al escribir, reconstruye
  archivo e índice desde el conjunto completo, deduplica por identidad estable y prueba la
  secuencia generar → agregar contenido posterior → regenerar → regenerar otra vez.
- **Detector:** tools/tests/test_lessons.sh::test_rotacion_reconstruye_indice_si_hay_entradas_nuevas_despues
- **Área:** tools/lessons-rotate.sh · docs/process/lessons_*.md
