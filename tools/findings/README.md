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
  findings.ts     CLI + librería (portable Deno/Node, sin deps)
  ledger.jsonl    ← FUENTE DE VERDAD (1 hallazgo = 1 línea JSON)
  README.md       este archivo
docs/process/
  findings-ledger.md  ← VISTA HUMANA generada (NO editar a mano)
```

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
