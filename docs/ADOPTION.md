# Adopción del template

> Cómo una empresa (o un proyecto personal) clona este cascarón y lo deja operativo.
> Tiempo estimado: ~30-60 min para el setup mecánico + el tiempo de rellenar las skills
> de tu stack (eso es trabajo de ingeniería real, no mecánico).

---

## 0. Pre-requisitos

| Herramienta | Para qué | Obligatoria |
|---|---|---|
| `git` | todo | sí |
| [`lefthook`](https://github.com/evilmartians/lefthook) | Anillo 1 (git hooks) | sí |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | secret-scan | sí |
| `deno` **o** `node` | findings-ledger CLI | sí (elige uno) |
| `jq` | hooks de IA (parsing JSON) | recomendada |
| Tu CI (GitHub/GitLab/…) | Anillo 3 | opcional |

## 1. Clonar y renombrar

```bash
git clone <este-template> mi-proyecto && cd mi-proyecto
rm -rf .git && git init
bash scripts/bootstrap.sh        # reemplaza <PROJECT>, plataformas, y elige preset full/lite
```

## 2. Instalar los gates locales

```bash
lefthook install                 # Anillo 1 — activa pre-commit / pre-push
gitleaks version                 # verifica que está en PATH
```

## 3. Elegir tu(s) cliente(s) de IA

Todos leen `AGENTS.md` (la fuente canónica). Solo activas el adaptador de los que uses:

- **Cursor** — ya lee `AGENTS.md` + `.cursor/rules/*.mdc`. Activa hooks: deja `.cursor/hooks.json`.
- **Claude Code** — `CLAUDE.md` (importa `AGENTS.md`) + `.claude/settings.json` (hooks) + `.claude/agents/` (sub-agentes) + `.claude/rules/` (reglas path-scoped nativas).
- **Codex** — lee `AGENTS.md` directo. No tiene hooks → su enforcement es el **Anillo 3 (CI)**.
- **Gemini CLI** — NO lee `AGENTS.md` por defecto: añade `context.fileName: ["AGENTS.md", "GEMINI.md"]` en su `settings.json`.

> Puedes borrar los directorios de los clientes que NO uses. El `AGENTS.md` y el Anillo 1
> siguen funcionando igual.

## 4. Rellenar lo que es TUYO (el trabajo de verdad)

Busca todos los marcadores y resuélvelos:

```bash
grep -rn "FILL:" . --include="*.md" --include="*.yml" --include="*.toml" --include="*.sh"
```

Prioridad de relleno:
1. `AGENTS.md` §Stack, §Comandos, §Convenciones — sin esto el agente vuela a ciegas.
2. `.agents/skills/architecture/SKILL.md` + `platforms/<tu-plataforma>.md` — arquitectura, navegación, DI.
3. `.agents/skills/domain/SKILL.md` — entidades/puertos de tu dominio.
4. `tools/check-drift.sh` — los checks mecánicos de TUS convenciones.
5. `docs/process/current_execution_map.md` — estado del proyecto.

> Mi opinión por defecto vive en `<!-- OPINIÓN: ... -->`. Acéptala o cámbiala; no es ley.

## 5. (Opcional) Conectar CI

Copia el ejemplo de tu proveedor y bórrale el `.example`:

```bash
# GitHub:    cp ci/examples/github-actions.yml.example   .github/workflows/gates.yml
# GitLab:    cp ci/examples/gitlab-ci.yml.example         .gitlab-ci.yml
# Bitbucket: cp ci/examples/bitbucket-pipelines.yml.example bitbucket-pipelines.yml
```

Todos invocan el mismo `ci/run-gates.sh`. Si no usas CI, te quedas con Anillos 1 y 2.

## 5b. (Opcional, empresa) Enforcement nativo no anulable + distribución como plugin

- **`enterprise/managed-settings.json`** — capa de precedencia máxima de Claude Code (ni `--no-verify`
  ni flags de CLI la saltan; bloquea force-push, `--no-verify`, lectura de secretos). Despliégala por
  MDM/Ansible a la ruta de OS. Detalle: `enterprise/README.md`.
- **`.claude/rules/`** — reglas path-scoped nativas (espejo de §11) que cargan la skill del área sin el
  coste de re-lectura forzada del hook. Ya vienen para iOS; ajústalas a tus paths.
- **Distribución como plugin** — publica `.claude-plugin/` en un marketplace interno; los devs hacen
  `/plugin install` en vez de clonar. Útil con muchos repos. Valida con `claude plugin validate .`.

## 6. Baseline de secretos (solo si el repo ya tiene historial)

```bash
gitleaks detect --source . --report-format json --report-path .gitleaks-baseline.json
git add .gitleaks-baseline.json
```

Rota cualquier credencial aún válida. El baseline es **deuda**, no exención: encógelo con el tiempo.

## 7. Primer commit de prueba

```bash
echo 'aws_secret_access_key = "AKIA1234567890ABCDEF"' > /tmp/leak.txt && cp /tmp/leak.txt .
git add leak.txt && git commit -m "test"   # debe FALLAR por gitleaks
rm leak.txt
```

Si el commit se bloquea, el Anillo 1 está vivo. Listo.
