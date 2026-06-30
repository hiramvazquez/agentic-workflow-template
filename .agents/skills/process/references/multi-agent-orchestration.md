# Multi-agent orchestration

> Patrón para lanzar sub-agentes. Aplica a Cursor (subagents 2.4+), Claude Code (`.claude/agents`)
> y, en general, cualquier cliente que permita delegar. Codex orquesta distinto pero los principios valen.

## Cuándo usar sub-agentes vs sesión principal

| Tarea | Path |
|---|---|
| 1-3 ediciones quirúrgicas | Sesión principal |
| PRD completo (muchos archivos) | Sub-agente |
| Trabajo paralelo independiente | Varios sub-agentes (scopes disjuntos) |
| Discovery / exploración sin escritura | Agente read-only / explore |
| Auditoría / review | Sub-agente dedicado |
| **Decisiones de producto** | **Siempre sesión principal** — los sub-agentes no conocen intent |

**Regla de oro:** si el trabajo se describe como "haz estos N pasos en estos M archivos", es
candidato a sub-agente. Si requiere "decide qué pedirle al owner", **NO** delegues.

## Estructura de un prompt de sub-agente (6 bloques)

1. **Header cold-start** — repo, branch, política de worktree. El agente arranca sin contexto.
2. **Trabajo en fases ordenadas** — bullets con archivos exactos; marca lo paralelizable.
3. **Hardening — skill reads obligatorios** (los refs que debe leer antes de tocar código).
4. **Reglas duras** — scope exclusivo (qué SÍ / qué NO), sin push, sin `--amend`, errores preexistentes se reportan no se tocan.
5. **Validación obligatoria** — build + tests + check-drift + secret-scan.
6. **Reporte final** — resumen, commits, tests, desviaciones del prompt + justificación.

## Paralelización — disjoint-scope rule

Dos agentes corren en paralelo **solo si sus paths NO se intersectan**. Verifica antes de lanzar.
Riesgos del paralelo: race en el índice de git (mitiga con `git add <path>` explícito, nunca `-A`),
build concurrente que corrompe artefactos, drift de schema/codegen (un solo agente dueño de eso).

## Default: SECUENCIAL con ciclo completo cerrado

> Lección dura: paralelismo agresivo + ciclos incompletos = drift acumulado. Una unidad de trabajo
> a la vez, con su ciclo cerrado (design-review → implementación → reviewer → tests → ship), es más
> lento por unidad pero produce ~cero bugs de coordinación. Usa paralelo solo con scopes 100%
> disjuntos y aprobación explícita del owner.

## Modelo por tarea (orientativo)

- **Razonamiento alto** (PRD, design-review, refactor cross-cutting, auditoría) → el modelo más capaz.
- **Mecánico siguiendo patrón** (implementación con PRD detallado, tests, tooling) → modelo rápido/barato.
- **Repetitivo** (i18n, formato) → el más barato.
