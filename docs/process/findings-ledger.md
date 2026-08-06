# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **0** · Cerrados: 11 · Total: 11

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| — | | | | (ninguno) |

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
