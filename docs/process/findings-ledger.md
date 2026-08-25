# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **33** · Cerrados: 131 · Total: 164

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-12fcc211` | high | auto-fix | `tools/agent-prompts/review.md + tools/agent-runner.sh + tools/agent-backends/` | El prompt del reviewer de IA es editable sin review: el archivo de mas leverage del repo esta exento |
| `f-1ae68da7` | high | owner-decision | `tools/upgrade.sh + lefthook.yml` | lefthook.yml esta congelado para adoptantes por copia: ninguna mejora del Anillo 1 les llega |
| `f-20ed9b44` | high | owner-decision | `gobierno del harness · proceso de trabajo` | Tres RED seguidos por la misma causa: afirmar cobertura que no se verifico |
| `f-298e3cd2` | high | owner-decision | `tools/mutation-score.sh + tools/mutation-ratchet.json` | mutation-score.sh no tiene runner para shell, que es el lenguaje del harness: el nivel 4 no esta sin medir, esta sin poder medir aqui |
| `f-5a4e0204` | high | auto-fix | `tools/verify-run.sh:97` | verify-run firma un arbol que nadie compilo si el archivo nuevo esta sin trackear |
| `f-bbe0a7e` | high | owner-decision | `tools/tests/test_scope_superficie.sh:105` | Octava via: la regla anti-indireccion se evade con un espacio de mas, y da FP con comentarios de cola |
| `f-cb48c808` | high | owner-decision | `scripts/agent-hooks/capture-review-verdict.sh + .claude/agents/reviewer.md` | El marker se firma al PARAR el sub-agente, no al revisar: un agente que termina tarde valida un diff que nunca miro |
| `f-mutation-score-nunca-medido` | high | owner-decision | `tools/mutation-ratchet.json` | El nivel 4 lleva mudo desde el dia uno y un piso de 0 lo disfraza de suelo |
| `f-wf01-ci-macos-intermitente` | high | auto-fix | `tools/tests/test_agent_runner.sh:91` | Senal CI intermitente en macOS: test_review_tambien_respeta_timeout no propago 124 |
| `f-25df51c3` | medium | owner-decision | `docs/ + README.md (detector ausente)` | Ninguna capa verifica que las rutas citadas en la doc existan: el README apuntaba a un archivo fantasma |
| `f-44331722` | medium | owner-decision | `tools/upgrade.sh + docs/ADOPTION.md` | upgrade.sh no crea tools/project.conf con kind inferido y ADOPTION.md no pide el flip |
| `f-4ce1b697` | medium | auto-fix | `tools/tests/test_execution_map.sh` | El detector de git add -A no protege el archivo para el que se escribio, y no ve add -u ni commit -am |
| `f-58ce4bd3` | medium | owner-decision | `ci/run-gates.sh:184` | El exit code de check-review-marker --range se descarta en CI: el Anillo 3 no lo hace cumplir |
| `f-6d4e01b8` | medium | auto-fix | `scripts/agent-hooks/reviewer-gate.sh:210-225` | El git-guard bloquea escribir un test cuyo TEXTO contiene git add y git commit |
| `f-76d2a144` | medium | owner-decision | `tools/lib/scope.sh + tools/*-ratchet.json` | Los trinquetes *-ratchet.json no casan ninguna forma de la superficie: su unica defensa es un Anillo 0 de un solo cliente |
| `f-86b1f53e` | medium | auto-fix | `tools/lib/scope.sh` | Un project_kind invalido se ignora en silencio y vuelve a la heuristica |
| `f-98ab9c19` | medium | owner-decision | `tools/drift-ratchet.json` | El _note de drift-ratchet.json cambio sin autor identificable durante la sesion |
| `f-9b5d63f1` | medium | auto-fix | `scripts/agent-hooks/post-compact.sh:46` | post-compact.sh nunca reinyecta la fase: su grep no casa la negrita del mapa |
| `f-a192a98a` | medium | auto-fix | `tools/check-source-sets.sh` | Espacios alrededor del punto evaden los DOS motores del detector KMP |
| `f-a2f82cec` | medium | owner-decision | `tools/check-drift.sh` | El chequeo de tamano de check-drift solo mira SRC_DIRS, asi que no vigila tools/ ni scripts/ |
| `f-b968a740` | medium | auto-fix | `ci/run-gates.sh` | La auto-escalada de source-sets en CI es inerte: el exit 3 bloquea con o sin registro |
| `f-be953d0c` | medium | auto-fix | `tools/lib/scope.sh` | La evidencia de scope no poda .claude/, asi que los worktrees de agentes disparan un aviso falso en cada gate |
| `f-d6aeef75` | medium | owner-decision | `tools/lib/scope.sh` | tools/tests/test_*.sh no son producto: el runner esta protegido y los 40 archivos con la verdad no |
| `f-wf04-archivos-sobre-el-limite` | medium | auto-fix | `tools/upgrade.sh + 8 tests + validate-harness.sh + capture-review-verdict.sh` | Archivos del harness sobre o rozando su propio hard limit de 400 lineas |
| `f-wf09-ventana-de-valor` | medium | owner-decision | `gobierno del harness` | Congelar gates nuevos hasta completar la ventana de observacion del PRD 0004 y decidir keep/tune/retire con telemetria |
| `f-210cee72` | low | owner-decision | `tools/check-source-sets.sh` | Un segmento de import escapado con backticks evade los dos motores del detector KMP |
| `f-58cb672b` | low | auto-fix | `ci/run-gates.sh` | Las ramas de auto-escalada de run-gates no tienen test que las ejercite end-to-end |
| `f-752b706e` | low | auto-fix | `scripts/agent-hooks/reviewer-gate.sh` | El git-guard del reviewer-gate casa git add/commit dentro de un heredoc, que es texto y no comando |
| `f-7e00dbd` | low | owner-decision | `tools/tests/test_semgrep_rules.sh` | El detector de invocaciones de semgrep no ve exec, xargs, subshell sin $ ni subprocess con shell=True |
| `f-a5f3e17c` | low | auto-fix | `tools/check-diff-nature.sh (clasificador)` | check-diff-nature parte el ledger en dos naturalezas y llama producto al .gitignore |
| `f-aaa2fb66` | low | owner-decision | `tools/lib/scope.sh + tools/tests/test_review_marker_preset.sh` | Decision revertida: .github/workflows deja de ser meta-doc exento y pasa a exigir review |
| `f-bd45663` | low | auto-fix | `tools/upgrade.sh:484,522` | upgrade.sh recomienda git add -A al usuario en dos mensajes de conflicto |
| `f-c7a05f92` | low | owner-decision | `.agents/state/markers/override_log.txt + scripts/agent-hooks/ (worktrees)` | Un override auditado dentro de un worktree se registra donde nadie lo lee |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-8145599c` | fixed | PRD 0001: cubierto por tools/tests/test_ratchets.sh::test_ratchet_duro_incluso_en_preset_lite y ::te |
| `f-marker-spoof` | accepted | Limite del modelo de amenaza ACEPTADO: el marker defiende contra error de proceso (el caso comun), n |
| `f-hook-payload` | fixed | CONFIRMADO END-TO-END en el commit 3b66e7e (P0). Una invocacion real del sub-agente reviewer con VER |
| `f-harness-no-autogate` | accepted | ACEPTADO para el template: tools/ y scripts/ quedan fuera del gate de review-marker porque en un pro |
| `f-ratchet-corrompible` | accepted | Mismo limite que f-marker-spoof, aceptado por la misma razon. Mitigado: corromper el archivo ya no d |
| `f-semgrep-validate` | fixed | RESUELTO en el commit de cierre del PRD 0001. Las reglas tenian TRES errores y ninguna habia cargado |
| `f-semgrep-latencia` | fixed | MEDIDO: `bash tools/semgrep-scan.sh --staged` tarda 1.32s reales sobre un commit tipico de este repo |
| `f-deny-bloquea-lectura` | accepted | Se MANTIENE la regla: es la unica friccion contra la falsificacion naive del marker (cat > marker),  |
| `f-session-start-fx` | fixed | session-start.sh separa --report (puro, sin efectos) del modo hook (reset). Fijado por test_session_ |
| `f-meta-fp-manifiesto` | fixed | Manifiesto ampliado de 11 a 16 entradas: post-edit-verify, drift-stop, session-start, drift-ratchet  |
| `f-meta-fp-self` | fixed | test_el_parser_del_manifiesto_ignora_comentarios fija el strip de comentarios/lineas vacias del prop |
| `f-upgrade-autoparcheo` | fixed | Arreglado en el template. Fijado por test_upgrade.sh::test_sync_aplica_un_delta_que_incluye_al_propi |
| `f-fill-mencion` | fixed | FILL_MARKER anclado a la forma del comentario. Fijado por test_upgrade.sh::test_fill_es_un_marcador_ |
| `f-lessons-strip-html` | fixed | Fijado por test_lessons.sh::test_mencionar_un_comentario_html_no_abre_un_comentario_html (comprueba  |
| `f-validate-divergencia` | fixed | Parrafo incorporado al template. La divergencia local desaparece en el proximo sync. |
| `f-sync-no-cubre-claude` | fixed | tools/merge-claude-settings.sh + _fundir_settings en upgrade.sh + _report_no_sincronizado en cada ex |
| `f-4d2b0e51` | fixed | tools/check-skill-matrix-doc.sh compara el conjunto de refs de ambos lados. Las dos divergencias arr |
| `f-25418f4c` | fixed | Convertida en detector: test_layers.sh::test_layers_conf_conserva_los_globs_universales falla con la |
| `f-meta-fp-cobertura` | fixed | Los cinco declarados + test_ningun_detector_se_queda_fuera_del_manifiesto, que recorre tools/check-* |
| `f-runner-retrabaja` | fixed | next.sh lee el estado desde la rama. Cuatro tests en test_backlog.sh, incluida la otra cara (una his |
| `f-leak-en-historia` | fixed | El paso 2 escanea el RANGO del cambio (una pregunta por gate); el historial pasa a un job programado |
| `f-range-failopen` | fixed | El rango se resuelve y se valida antes de escanear (RANGE, luego GATES_BASE_REF...HEAD, luego @{push |
| `f-jq16-guard-inerte` | fixed | Comprobacion explicita [ ! -s ] antes de consultar a jq. Fijado por test_el_guard_de_json_no_depende |
| `f-run-a-medias-exit0` | fixed | run.sh comprueba el worktree antes de cerrar: si hay algo sin commitear, respalda lo pendiente en .a |
| `f-semgrep-as-cast-fp` | fixed | Misma interseccion pattern + pattern-regex que swift-force-try, subida al template. Y lo que impide  |
| `f-criterio6-sin-test` | fixed | tools/backlog/criteria-link.sh exige que cada criterio cite el test que lo fija (con excepcion expli |
| `f-semgrepignore-no-aplica-a-targets` | fixed | El corpus se filtra de la lista de TARGETS en semgrep-scan.sh. Fijado por test_semgrep_rules.sh::tes |
| `f-sync-maquinaria-nueva` | fixed | Anadidos a SYNC_PATHS (backlog/_template.md por nombre exacto: backlog/ es del proyecto, solo la pla |
| `f-informe-sync-miente` | fixed | El informe filtra con _es_maquinaria, la misma funcion que decide el sync. Fijado por test_el_inform |
| `f-gate-bash-lee-texto` | fixed | Se desnudan cuerpos de heredoc y cadenas entrecomilladas antes de analizar; cp/mv anclados a inicio  |
| `f-gate-sin-evidencia-de-build` | fixed | tools/verify.conf (fuente unica del comando, consumida por el gate local y por el paso 6 de CI) + to |
| `f-hook-roto-brickea` | fixed | scripts/agent-hooks/run-hook.sh valida con bash -n el hook Y sus libs antes de exec; si no parsean a |
| `f-verify-run-lows` | fixed | command -v sobre el primer token antes de ejecutar (exit 3 propio); check-verify-marker llama a veri |
| `f-merge-hooks-duplicados` | fixed | La identidad se calcula sobre el comando normalizado (fuera 'bash ' y el lanzador); cambiar de lanza |
| `f-main-rojo-publicable` | fixed | Job harness-suite en pre-push de lefthook.yml: la suite corre en la maquina de quien publica, con lo |
| `f-merge-settings-crashea-con-comentarios` | fixed | Se saltan las claves cuyo valor no es lista, conservandolas (saltar != borrar), y el test ahora fund |
| `f-judge-cola-sesion-equivocada` | fixed | session-start guarda el HEAD de arranque; session-end encola por commits producidos (el arbol sucio  |
| `f-id-de-finding-fantasma` | fixed | tools/check-finding-refs.sh en el paso 8e del Anillo 3 y en la suite. Una cita es un span entre acen |
| `f-gestor-de-paquetes-no-es-la-fuente` | fixed | tools/check-version-claims.sh: un hallazgo que declare una herramienta incapaz por version debe cita |
| `f-nivel4-dos-estados-un-cajon` | fixed | mutation-score.sh --state responde medido | sin-cablear | runner-incompleto | sin-medir, y session-s |
| `f-state-lanzaba-el-runner` | fixed | El estado se DERIVA de una ejecucion real (invariante n1): cada corrida escribe .agents/state/mutati |
| `f-detector-cita-un-test-fantasma` | fixed | Toda referencia archivo::test_x de la linea Detector se resuelve contra las funciones del archivo, l |
| `f-template-sin-verify-cableado` | fixed | verify.conf cableado con bash tools/tests/run-tests.sh (el producto del template es el harness). El  |
| `f-version-claims-fp-en-espanol` | fixed | Verbos de posesion y cobertura fuera (tiene, trae, cubre); solo quedan los de soporte. El sujeto no  |
| `f-mapa-de-ejecucion-rancio` | fixed | Mapa reescrito con el estado real (bucle con el adoptante, 347 verde, 1 finding abierto y por que si |
| `f-event-dedup-dimensiones` | fixed | La clave incluye phase+commit; regresión test_anti_rafaga_no_colapsa_fases_ni_commits_distintos. |
| `f-event-json-leading-zero` | fixed | Normalización decimal textual antes de serializar; regresión test_evento_v2_normaliza_ceros_iniciale |
| `f-reviewer-duration-as-count` | fixed | Emite n=1 y duración en milisegundos en el quinto argumento; regresión test_reviewer_gate_registra_u |
| `f-event-unborn-head` | fixed | El rc fallido descarta stdout y fija unknown; regresión test_evento_v2_repo_sin_head_usa_unknown_sin |
| `f-source-event-sin-valor` | fixed | Validación fail-closed para argumento ausente o vacío antes de escribir; regresión test_source_event |
| `f-event-json-control-chars` | fixed | El emisor reemplaza U+0001–U+001F por espacios antes de escapar JSON; regresión test_evento_v2_reemp |
| `f-metrics-corrupt-jsonl-empty-green` | fixed | Los lectores abortan con exit 3 ante cualquier línea inválida, incluso después de registros válidos; |
| `f-read-events-partial-on-corrupt` | fixed | El CLI materializa y valida todo el stream antes de imprimir; la regresión de JSONL corrupto exige e |
| `f-metrics-timestamp-prefix` | fixed | Se parsea el timestamp ISO completo, se exige zona horaria y se cuantifican como invalid_dates los v |
| `f-metrics-window-timezone` | fixed | El timestamp válido se normaliza a UTC antes de derivar el día; la regresión usa dos representacione |
| `f-metrics-default-window-local-tz` | fixed | La ventana por defecto parte del día UTC; una regresión compara hosts TZ=Pacific/Kiritimati y TZ=Etc |
| `f-metrics-invalid-date-silent` | fixed | Cada parse inválido emite una señal genérica sin filtrar el dato; Semgrep staged vuelve a 0 warnings |
| `f-metrics-invalid-date-guard-silent` | fixed | Todos los paths inválidos emiten la misma señal genérica; la regresión exige cuatro warnings para cu |
| `f-lessons-duplicate-index-after-append` | fixed | El índice se elimina antes de clasificar y se regenera desde todo lessons_archive; el archivo se ded |
| `f-lessons-live-context-over-budget` | fixed | La cabecera se condensó sin perder contratos y el tramo vivo quedó en 240 líneas; un test sobre el d |
| `f-readme-hardcoded-evidence-counts` | fixed | Se reemplazaron cifras copiadas por los comandos canónicos que calculan deuda y verifican detectores |
| `f-lessons-heading-collision-data-loss` | fixed | El corpus combinado acepta retries solo si el cuerpo completo coincide y aborta antes de escribir an |
| `f-lessons-archive-never-restored` | fixed | Cada corrida reclasifica el corpus live+archive y restaura al tramo vivo cualquier entrada que perdi |
| `f-gate-cache-stdin-payload` | fixed | Put recibe el unico resumen verde canonico como argumento explicito; get rechaza payloads distintos  |
| `f-gate-cache-key-race` | fixed | Las consultas ejecutables ocurren antes del snapshot final HEAD+diff; el boundary recalcula la key y |
| `f-gate-cache-target-race` | fixed | El scanner compara y vuelve a resolver targets tras consultar cache y antes de publicar; una regresi |
| `f-stat-f-orden-invertido` | fixed | Orden invertido a GNU primero. Detector nuevo en test_shell_hygiene.sh que barre todo el repo y exig |
| `f-run-gates-sin-test` | fixed | test_golden_09 stubbea cada gate para que firme su paso y exige los 12 del contrato; ademas fija que |
| `f-adapter-readonly-declarado` | fixed | test_golden_05 corre el ciclo autonomo completo contra un stub hermetico del CLI y verifica el argv  |
| `f-golden-sin-vinculo` | fixed | test_matriz_e2e_cubre_los_diez_escenarios_golden lee los escenarios del PRD y exige un test_golden_N |
| `f-gate-cache-falso-positivo-gitleaks` | fixed | Allowlist por PATH en .gitleaks.toml para .agents/state/gate-cache/, con la razon escrita: el campo  |
| `f-inventario-de-gates-duplicado` | fixed | Inventario unico en _G9_INVENTARIO, con la marca informativo explicita para el unico gate que se stu |
| `f-review-sin-reporte-persistido` | fixed | capture-review-verdict escribe .agents/state/reviews/<sha>-<agente>.md con cabecera ligada al diff y |
| `f-eje-de-source-sets-sin-detector` | fixed | tools/check-source-sets.sh en pre-commit junto a check-layers y en el paso 4b del Anillo 3, con su e |
| `f-b3cf4f74` | fixed | Idempotencia por (agente, HEAD, diff, veredicto) contra review-history.jsonl; el camino de exito y e |
| `f-a8bcb235` | fixed | El discriminador es la identidad de la INVOCACION, no el contenido ni el tiempo: las vueltas de un b |
| `f-reporte-previo-sin-lector` | fixed | La instruccion va estatica en el prompt del rol (tools/agent-prompts/review.md) con el comando exact |
| `f-fill-sin-proteccion-en-el-delta` | fixed | La comprobacion vive en una sola funcion _propiedad_compartida que usan los dos caminos. En el delta |
| `f-sync-no-avisa-al-ledger` | fixed | Al terminar el delta se cruzan las rutas traidas contra area/links/title de los findings abiertos y  |
| `f-non-product-ciego-al-harness` | fixed | tools/lib/scope.sh como fuente unica de los dos markers: si el repo no tiene fuentes de aplicacion s |
| `f-wf02-mapa-cifras-podridas` | fixed | PRD 0005 fase 0b, implementada por subagente y verificada: mapa sin cifras derivables (los conteos v |
| `f-wf03-jsonl-sin-encoder` | fixed | Emisor unico scripts/agent-hooks/lib/json.sh (jq, fallback python3; sin runtime degrada declarandolo |
| `f-wf05-project-kind-inferido` | fixed | Fase 1b entregada: la declaracion gobierna (tools/project.conf, propiedad del adoptante, verificado  |
| `f-wf06-kmp-detector-textual` | fixed | PRD 0005 fase 1c COMPLETA, gate de cierre incluido. Semgrep con regla kotlin generada en runtime des |
| `f-wf07-contexto-sin-headroom` | fixed | PRD 0005 fase 0c, implementada por subagente y verificada: rotador canonico e idempotente (canonical |
| `f-wf08-git-add-A-canonico` | fixed | PRD 0005 fase 2b. El paso 4 del bucle del mapa pasa a staging por PATHS con los tres comandos separa |
| `f-watchdog-filtra-un-sleep-por-test` | fixed | pkill -P sobre el guardian antes de matarlo: mueren sus hijos primero. Medido tras el fix: 0 huerfan |
| `f-test-0a-verde-linux-rojo-macos` | fixed | Inyeccion por PATH: stub de mktemp que falla, identico en ambos sistemas. Verificado verde en Linux; |
| `f-ab0d8266` | fixed | Arreglado en el mismo turno: export SEMGREP_ENABLE_VERSION_CHECK=0 y SEMGREP_SEND_METRICS=off al arr |
| `f-31f757c0` | fixed | Arreglado: dedupe por archivo:linea con awk en vez de sort -u de linea entera. Test nuevo (test_una_ |
| `f-9b77444e` | fixed | Cerrado por la mitad 1 del arreglo, en este mismo cambio: scope.sh lee la declaracion del INDICE (gi |
| `f-f387276` | fixed | Cerrado en este mismo cambio: lefthook.yml envuelve check-source-sets con el mismo wrapper de exit 3 |
| `f-9024b380` | fixed | Cerrado con la otra mitad del arreglo. scope.sh exporta scope_siempre_producto() con las tres rutas  |
| `f-1b033530` | fixed | Cerrado cambiando la FORMA del arreglo, no alargando la lista. La lista se quedo corta cuatro veces  |
| `f-80e8df8c` | fixed | Arreglado en este diff: la superficie incluye .gitleaks (sin ancla, cubre .gitleaks.toml), .semgrepi |
| `f-28006397` | fixed | Cerrado construyendo el detector que proponia, en vez de alargando la lista otra vez. tools/tests/te |
| `f-e1293daa` | fixed | Arreglado en este diff: el helper usa git -C con el sandbox explicito y ruta absoluta, asi que un cd |
| `f-d467930f` | fixed | Arreglado en este diff: prefijo lesson- y la ruta explicita de tools/tests/run-tests.sh en la superf |
| `f-1f559fc7` | fixed | El bucle de ci/run-gates.sh quedo desenrollado a invocaciones literales y el extractor pasa de ver 1 |
| `f-18f51176` | fixed | Cerrado por 35f9a8f. Las TRES primitivas de bloqueo de lib/io.sh registran por _hook_log_block; veri |
| `f-9e0e21b0` | fixed | Cerrado por 35f9a8f. El informe corrige la atribucion y DECLARA el error en su §2: la primera versio |
| `f-24968270` | fixed | Dejo de ser perecedero: las cuatro divisiones estan commiteadas en la rama de su propio worktree (7b |
| `f-945ee54a` | fixed | Cerrado por 35f9a8f. 'Estado actual' —la unica seccion que session-start extrae e inyecta— dice que  |
| `f-fa194587` | fixed | Cerrado por 35f9a8f. El informe ya no declara absolutos sobre un contador vivo: marca esas cifras co |
| `f-2bd11525` | fixed | Instrumentadas las TRES primitivas de bloqueo de lib/io.sh en un unico punto (_hook_log_block), no p |
| `f-658e2533` | fixed | Los tres defectos corregidos. (1) La linea de 'Estado actual' decia 'dos gates siguen abiertos' y en |
| `f-6c1a0f6a` | fixed | El mapa dice ahora los DOS hechos y los separa, que era lo que faltaba desde el principio: en CI el  |
| `f-3ab77c21` | fixed | Se abandono el parser escrito a mano: BASH ES EL PARSER. tools/tests/lib/primitivas-de-bloqueo.sh so |
| `f-b0e4d952` | fixed | El test corre el hook con DETECTION_DEDUP_WINDOW=0, lo que aisla el guard del dedup anti-rafaga y lo |
| `f-7d21e4b3` | fixed | El informe nombra ahora la ubicacion exacta del mutante ('dentro de _hook_log_block') y dedica un pa |
| `f-9f30ac55` | fixed | El informe declara 13, dice explicitamente contra que se cuenta (HEAD, o sea lo que se commitea), im |
| `f-4e8a1c37` | fixed | Anadido '< /dev/null' a la invocacion. Fijado por test_analizar_un_archivo_que_lee_stdin_no_cuelga,  |
| `f-51c9d0ea` | fixed | Ninguna de las dos se ACTUALIZO — se quitaron, que es lo unico que cierra la clase. (1) El informe y |
| `f-8c2f57b1` | fixed | Las tres lineas del informe remiten a 'wc -l < .agents/state/judge-queue.txt' en vez de dar un numer |
| `f-2f6b90c4` | fixed | Quitado el '**' sobrante; el conteo vuelve a 184, par. NO se anade detector: validar markdown entero |
| `f-783ff97a` | fixed | Los cuatro cerrados en este mismo cambio, tras verificar uno a uno contra el arbol. La causa comun:  |
| `f-ee9787d9` | fixed | post-edit-verify cuelga ahora tambien de Bash (matcher Edit|Write|MultiEdit|Bash) y sabe QUE archivo |
| `f-153aef5b` | fixed | track-trajectory registra ahora un campo 'writes' con los archivos que el comando cambio de verdad,  |
| `f-e416ab5e` | fixed | process-judge-context.sh cumple ahora el contrato de §14.3: sale 3 —y lo DICE en la salida, que es l |
| `f-3ccb2aca` | fixed | Los dos atendidos. (1) La resolucion de f-8c2f57b1 sobregeneralizaba: decia que 'las tres lineas rem |
| `f-15089319` | fixed | El paso entra en el bucle de trabajo del mapa (seccion 'Como se trabaja aqui', paso 4), ANTES de sta |
| `f-18a2c2ef` | fixed | La cabecera separa ahora las dos cosas que confundia: la MEDICION fue solo lectura, el COMMIT que tr |
| `f-70b2ca19` | fixed | El test escribe un archivo ANTES de borrar la foto, asi que si el borrado no surtiera efecto habria  |
| `f-b91ee6f0` | fixed | (1) El modo degradado pasa a SOBRE-reportar: una linea sin huella se reporta SIEMPRE, porque sin hue |
| `f-1d7c33a5` | fixed | Espacio anadido y '${REVISADOS# }' aplicado tambien en el mensaje, igual que ya se hacia en la telem |
| `f-75b0eb42` | fixed | Se distinguen los dos consumidores, que era el fondo: piden cosas distintas a la misma senal. writes |
| `f-c4f8a71d` | fixed | (1) La leccion ya no da un numero: remite a 'grep -c ^test_ tools/tests/test_bash_writes.sh' y conse |
| `f-30ad6c92` | fixed | (1) Las rutas viajan separadas por SALTO DE LINEA y jq parte por '\n' con map(select(length>0)): el  |
| `f-a6d21f84` | fixed | (1) El contrato pasa a estar escrito al reves de como estaba: la ruta SI puede traer tabuladores, lo |
| `f-2e94db73` | fixed | (1) Dos tests end-to-end nuevos que pasan por los hooks REALES con un tabulador en el nombre: test_e |
| `f-fb03e5d1` | fixed | writes_mark barre los temporales al dejar la marca, con 'find -mmin +10 -delete'. El umbral NO es co |
