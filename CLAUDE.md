# <PROJECT> — Claude Code

> **Adaptador delgado.** La fuente canónica de reglas es `AGENTS.md`. Este archivo solo
> la importa y añade la maquinaria que es exclusiva de Claude Code (skills, sub-agentes,
> hooks vía `settings.json`). NO dupliques reglas aquí — si una regla es de producto, va en
> `AGENTS.md` para que TODOS los clientes la vean.
>
> Alternativa equivalente: `rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md` (symlink). Usamos el
> import porque permite añadir la sección Claude-only de abajo.

@AGENTS.md

---

## Maquinaria exclusiva de Claude Code

- **Skills:** `.claude/skills` es un symlink a `.agents/skills` (la base compartida). Cárgalas según la matriz §11 de `AGENTS.md`.
- **Sub-agentes:** viven en `.claude/agents/*.md`. Invócalos con la tool `Agent` según su `description`. Catálogo en `.claude/agents/README.md`.
- **Hooks (Anillo 2):** definidos en `.claude/settings.json`. Llaman a los scripts compartidos en `scripts/agent-hooks/`:
  - `SessionStart` → resetea markers + imprime estado.
  - `PreToolUse Edit|Write` → `skill-reminder` (BLOQUEA si no leíste la skill requerida).
  - `PreToolUse Bash` → `reviewer-gate` (BLOQUEA `git commit` sin review reciente + drift-ratchet).
  - `PostToolUse Read` → registra lecturas de skills. `PostToolUse *` → captura trayectoria (sin secretos).
  - `Stop` → `canon-enforce` + `drift-stop` (bloquean si introdujiste violaciones/errores nuevos).

> Los mismos scripts los reusa Cursor vía `.cursor/hooks.json`. La lógica vive una sola vez
> en `scripts/agent-hooks/`; cada cliente solo aporta el wrapper de su contrato de I/O.
