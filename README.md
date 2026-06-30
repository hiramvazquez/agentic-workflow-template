# Agentic Workflow Template

> Un **cascarón reutilizable** para trabajar con agentes de IA (Cursor, Claude Code, Codex)
> de forma disciplinada, segura y portable — en proyectos **iOS, Android, web o backend**.
>
> No es un framework de código: es una **forma de trabajar** codificada en archivos que
> los agentes leen y en *gates* que se ejecutan solos. La empresa lo clona, rellena los
> placeholders de su stack, y arranca con governance desde el día 1.

---

## Qué resuelve

Cada equipo que adopta agentes de IA tropieza con lo mismo: el agente inventa cuando no sabe,
mete secretos en el código, ignora las convenciones, hace scope creep, y la "memoria" del
proyecto se pierde entre chats. Este template impone un **flujo de principio a fin** con
defensa en capas, y lo hace **compatible con los tres clientes que usan los devs hoy**.

## Filosofía (no negociable)

1. **Detectar no basta — hay que CERRAR.** Cada hallazgo llega a un estado terminal y visible
   (arreglado o aceptado-con-razón). Ver `tools/findings/`.
2. **Defensa en capas.** Ningún método solo encuentra el 100%: detector mecánico + design-review
   + reviewer + juez + lecciones, en capas.
3. **Una fuente de verdad, muchos clientes.** `AGENTS.md` es canónico; cada cliente tiene un
   adaptador delgado. Nada se duplica.
4. **El que toca, cierra.** Si tocas un módulo con findings abiertos, los resuelves o los registras.
5. **Open Question > suposición silenciosa.** Si el agente no sabe, pregunta; no inventa un default.

## Los 3 anillos de enforcement (el "plus" cross-tool)

| Anillo | Mecanismo | Dispara en | Para qué |
|---|---|---|---|
| **1 — git-nativo** | `lefthook.yml` | Cursor, Claude, Codex, **humano**, todo `git commit` | Gates deterministas: secretos, drift-ratchet, lint, tamaño. **La única capa universal.** |
| **2 — hooks de IA** | `.claude/settings.json` + `.cursor/hooks.json` → `scripts/agent-hooks/` | Claude Code / Cursor | Gates *AI-aware*: leer-skill-antes-de-editar, reviewer-gate, captura de trayectoria. |
| **3 — CI (opcional, BYO)** | `ci/run-gates.sh` invocado desde *tu* CI | server, cada push/PR + nocturno | Backstop independiente del cliente. Cubre Codex (sin hooks) y commits humanos. |

> **Por qué 3 anillos:** Codex no tiene hooks → su enforcement vive en CI. Los hooks de IA
> bloquean rápido y local pero solo en su cliente. Los git hooks nativos disparan para *todos*
> los clientes y humanos, pero se pueden saltar con `--no-verify` → por eso CI es el backstop final.
>
> **CI es "bring your own".** No imponemos GitHub. El Anillo 3 es un único script
> (`ci/run-gates.sh`) que corre los mismos gates; lo invocas desde GitHub Actions, GitLab CI,
> Bitbucket, Azure, Jenkins o nada. En `ci/examples/` hay stubs opcionales para varios proveedores.

## Mapa de archivos

```
AGENTS.md                  ← FUENTE CANÓNICA (la leen Cursor, Codex, Copilot, Gemini…)
CLAUDE.md                  ← adaptador delgado: @AGENTS.md + maquinaria Claude-only
ios|android|web/AGENTS.md  ← overrides por plataforma (el más cercano gana)
.cursor/                   ← rules/*.mdc (glob-scoped) + hooks.json (Anillo 2)
.claude/                   ← settings.json (Anillo 2) + agents/ (sub-agentes) + skills→.agents/skills
.codex/config.toml         ← config Codex (lee AGENTS.md directo)
ci/run-gates.sh + ci/examples/  ← Anillo 3 (CI opcional, provider-agnóstico — NO obliga GitHub)
lefthook.yml + .gitleaks.toml  ← Anillo 1
scripts/agent-hooks/       ← UNA implementación de los gates, compartida por Claude+Cursor
tools/                     ← check-drift, drift-ratchet, findings-ledger, secret-scan
.agents/skills/            ← base de conocimiento (rellenable por la empresa)
docs/process/              ← PRD template, lessons, execution map, ledger view
```

## Cómo se adopta

Ver **`docs/ADOPTION.md`**. En corto: clona → corre `scripts/bootstrap.sh` → rellena los
`<!-- FILL: ... -->` de tu stack → `lefthook install` → empieza a trabajar.

## Convenciones de placeholders

- `<!-- FILL: ... -->` — la empresa DEBE completarlo con su stack (arquitectura, navegación, DI…).
- `<!-- OPINIÓN: ... -->` — mi recomendación por defecto; bórrala o cámbiala.
- `<PROJECT>` / `<project>` — reemplaza por el nombre real (hay un script que lo hace).
- `<PLATFORM>` — `ios` | `android` | `web` | `backend`.
