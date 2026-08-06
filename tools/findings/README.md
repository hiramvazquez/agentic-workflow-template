# Findings Ledger — inventario único de hallazgos

> El eslabón que cierra el loop **detección → seguimiento**. Audits, `reviewer`, `process-judge`,
> `check-drift` y advisors producen hallazgos; sin un lugar único con estado terminal, se evaporan
> en resúmenes. Este ledger los hace **durables, machine-writable y con cierre garantizado**.

## Filosofía

La meta NO es "arreglar todo". Es que **cada hallazgo llegue a un estado terminal y visible** —
arreglado **o** explícitamente aceptado/descartado-con-razón. "Nada se evapora" se logra cerrando
cada item, no fijando todos.

Triage en 3 buckets (`tier`):

| tier | qué es | quién lo acciona |
|---|---|---|
| `auto-fix` | mecánico / seguro | el agente, en convergencia |
| `owner-decision` | producto / seguridad / negocio — necesita juicio humano | **el owner** |
| `accepted` | riesgo aceptado / won't-fix | cerrado con razón |

## Arquitectura

```
tools/findings/
  findings.sh     CLI PORTABLE (bash+python3) — el camino por defecto
  findings.ts     CLI alternativo (Deno/Node) — mismo esquema, mismos ids
  ledger.jsonl    ← FUENTE DE VERDAD (1 hallazgo = 1 línea JSON)
  README.md       este archivo
docs/process/
  findings-ledger.md  ← VISTA HUMANA generada (NO editar a mano)
.agents/state/metrics/
  detections.jsonl    ← EVENTOS de los gates (local, gitignored — telemetría,
                        no findings curados; los agrega tools/metrics/escape-rate.sh)
```

> **¿Por qué dos CLIs?** `findings.ts` exigía Deno/Node y hubo máquinas sin ellos → el ledger
> era inoperable y los hallazgos se acumulaban en archivos sueltos. `findings.sh` usa lo que el
> repo ya asume (bash+python3). Ambos comparten esquema, hash de ids y el **invariante clave**:
> `add`/`import` jamás resucitan un estado terminal — cerrar es explícito.

## Uso diario

```bash
bash tools/findings/findings.sh add --title "..." --area "file:line" \
     --severity high|medium|low --tier auto-fix|owner-decision --source reviewer
bash tools/findings/findings.sh close f-xxxx --resolution "commit abc123"
bash tools/findings/findings.sh list --status open
bash tools/findings/findings.sh render      # regenera la vista humana
bash tools/metrics/escape-rate.sh           # contención por fase (ledger + eventos)
```

Los gates escriben **eventos** solos (`hook_log_detection`); al ledger curado se añade con el
CLI — normalmente lo hace el agente al cerrar una review o un juicio (AGENTS.md §10).

## Invariante clave (auto-flow)

`add`/`import` (detección) **nunca** regresan un hallazgo terminal (`fixed`/`accepted`/`wontfix`)
a abierto; solo refrescan `updatedAt`. Cambiar estado es **explícito** (`close`/`accept`/`triage`).
Esto evita que la re-detección nocturna infle el ledger o "des-haga" un fix.

## Comandos

```bash
F="deno run --allow-read --allow-write tools/findings/findings.ts"   # o: node ... findings.ts
$F add --title "Token en logs" --area "src/auth.ts:42" --severity high --tier owner-decision
$F import /tmp/batch.json          # ingesta masiva (salida de un sub-agente)
$F list --status open --tier owner-decision [--json]
$F triage <id> --tier auto-fix     $F close <id> --resolution "commit abc"     $F accept <id> --reason "..."
$F stats                           $F render      # regenera la vista md
```

## Convención: cada productor anexa (lo que cierra la fuga)

| Productor | Cómo anexa |
|---|---|
| Sesión manual que cierra un audit | `add` por hallazgo, o `import batch.json` → `render` → commit |
| `process-judge` (nocturno) | emite JSON → `import` → triar → `render` |
| `reviewer` (gate) | findings AMBER/RED que no bloquean → `add --tier ...` |
| `check-drift` | (opcional) cada WARN nueva → `add --source check-drift` |

Tras cualquier `add`/`import`/`close`/`accept`: **siempre** `render` y commitea `ledger.jsonl` +
`findings-ledger.md` juntos.
