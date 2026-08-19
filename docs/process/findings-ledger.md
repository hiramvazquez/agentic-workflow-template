# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **1** · Cerrados: 77 · Total: 78

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-mutation-score-nunca-medido` | high | owner-decision | `tools/mutation-ratchet.json` | El nivel 4 lleva mudo desde el dia uno y un piso de 0 lo disfraza de suelo |

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
