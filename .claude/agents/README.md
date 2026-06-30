# Sub-agentes — <PROJECT>

> Roles especializados. Cada `.md` define un agente con su prompt, sus tools y su modelo
> recomendado. Claude Code los invoca con la tool `Agent`; Cursor los ve vía el symlink
> `.cursor/agents` → `.claude/agents` (formato compatible). Codex no tiene sub-agentes nativos:
> usa estos `.md` como checklists que el agente principal sigue.

## Catálogo

| Agente | Cuándo invocar | Modelo sugerido | Escribe código |
|---|---|---|---|
| `design-reviewer` | PRD mediano/grande, ANTES de implementar (gate de diseño) | alto razonamiento | no |
| `reviewer` | ANTES de cada commit de código de producto | medio | no |
| `security-reviewer` | commits que tocan secretos/datos/authz/deps | medio | no |
| `tester` | cuando falta cobertura de tests | medio/rápido | solo tests |
| `prd-writer` | diseñar una feature mediana/grande como PRD | alto razonamiento | no (escribe el PRD) |
| `process-judge` | al cerrar un PR/sesión, o nocturno | alto razonamiento | no (reporta + ledger) |

## Reglas para TODOS los sub-agentes

1. **Scope exclusivo.** Solo los archivos que el prompt/PRD listan. Fuera de scope → reportar, no tocar (`AGENTS.md` §8).
2. **Errores preexistentes:** se registran en el ledger, NUNCA se silencian ni se "arreglan de paso".
3. **Sin `git push`, sin `--amend`, sin `--no-verify`.**
4. **Reporte final estructurado:** qué hizo, commits, tests, desviaciones del prompt + razón.
5. Los agentes de review/judge **NO modifican código** — solo reportan y/o anexan al ledger.

> `model:` en el frontmatter es orientativo: <!-- FILL: ajusta a los modelos que tu org tenga habilitados. -->
