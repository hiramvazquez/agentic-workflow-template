# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **7** · Cerrados: 4 · Total: 11

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-marker-spoof` | high | owner-decision | `tools/check-review-marker.sh:69-77` | El marker de review valida contenido, no procedencia: falsificable por un agente con Bash |
| `f-harness-no-autogate` | medium | owner-decision | `tools/check-review-marker.sh` | El harness no se auto-aplica: NON_PRODUCT excluye tools/ y scripts/, que en ESTE repo son el producto |
| `f-ratchet-corrompible` | medium | owner-decision | `tools/mutation-ratchet.json, tools/drift-ratchet.json` | Los *-ratchet.json son corrompibles via Bash, y ahora corromperlos desactiva un gate |
| `f-deny-bloquea-lectura` | low | owner-decision | `.claude/settings.json` | permissions.deny Bash(*reviewer_run.txt*) tambien bloquea LEER el marker |
| `f-meta-fp-manifiesto` | low | owner-decision | `tools/tests/test_meta_fp.sh` | El manifiesto de test_meta_fp no cubre todos los detectores del repo |
| `f-session-start-fx` | low | owner-decision | `scripts/agent-hooks/session-start.sh` | session-start.sh mezcla informar con resetear estado |
| `f-meta-fp-self` | info | auto-fix | `tools/tests/test_meta_fp.sh` | test_meta_fp no valida su propio parsing del manifiesto |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-8145599c` | fixed | PRD 0001: cubierto por tools/tests/test_ratchets.sh::test_ratchet_duro_incluso_en_preset_lite y ::te |
| `f-hook-payload` | fixed | CONFIRMADO END-TO-END en el commit 3b66e7e (P0). Una invocacion real del sub-agente reviewer con VER |
| `f-semgrep-validate` | fixed | RESUELTO en el commit de cierre del PRD 0001. Las reglas tenian TRES errores y ninguna habia cargado |
| `f-semgrep-latencia` | fixed | MEDIDO: `bash tools/semgrep-scan.sh --staged` tarda 1.32s reales sobre un commit tipico de este repo |
