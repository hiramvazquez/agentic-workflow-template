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
| [`semgrep`](https://semgrep.dev) | detectores AST (nivel 2 de la pirámide) | sí — sin él el nivel 2 está MUDO (local avisa, CI bloquea) |
| `python3` | `tools/findings/findings.sh` (ledger) + utilidades | sí (viene en macOS/Linux) |
| `jq` | hooks de IA (parsing JSON) | sí para el Anillo 2 |
| Runner de mutación (muter/Stryker/PIT/mutmut) | nivel 4: calidad real de los tests | recomendada — sin él nada distingue un test real de uno decorativo |
| Tu CI (GitHub/GitLab/…) | Anillo 3 | opcional |

> `bash scripts/agent-hooks/session-start.sh` (o abrir cualquier sesión de Claude/Cursor) te
> dice **qué niveles de la pirámide están MUDOS** en tu máquina. Confía en ese reporte, no en
> tu memoria: un gate anunciado y no operativo es peor que uno ausente.

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
bash tools/validate-harness.sh   # ¿los gates EXISTEN de verdad? (estático + checklist en vivo)
```

> **Regla de confianza:** ningún gate cuenta como existente hasta que lo has visto bloquear
> algo una vez. `validate-harness` verifica eventos, permisos, scripts y matriz en estático,
> e imprime el checklist de lo que solo una sesión real puede probar. Repítelo tras cada
> update de Claude Code / Cursor / Codex — sus contratos de hooks versionan rápido.

## 3. Elegir tu(s) cliente(s) de IA

Todos leen `AGENTS.md` (la fuente canónica). Solo activas el adaptador de los que uses:

- **Claude Code** — el cliente de primera clase (único con la historia completa): `CLAUDE.md`
  (importa `AGENTS.md`) + `.claude/settings.json` (Anillo 0 + hooks) + `.claude/agents/`
  (sub-agentes) + `.claude/commands/goal.md` + `.claude/rules/`.
- **Codex** — lee `AGENTS.md` directo, y desde 2026 **sí tiene hooks** (PreToolUse/PostToolUse):
  `.codex/hooks.json` conecta el reviewer-gate vía `gate-adapter.sh` (requiere
  `[features] codex_hooks = true`, ver `.codex/config.toml`). Sin Stop/SubagentStop: el marker
  de review se genera con `scripts/mark-reviewer-run.sh` (auditado) o preset `lite`; el
  backstop es Anillo 1 + 3.
- **Cursor** — lee `AGENTS.md` + `.cursor/rules/*.mdc`; `.cursor/hooks.json` da
  reviewer-gate (vía adapter), verificación in-loop y canon-enforce. Sin evento pre-edición
  denegable ni SubagentStop: skill-reminder es instrucción ahí, y el marker igual que en Codex.
- **Gemini CLI** — NO lee `AGENTS.md` por defecto: añade `context.fileName: ["AGENTS.md", "GEMINI.md"]`
  en su `settings.json`. (Tiene hooks desde v0.26 con contrato similar a Claude; wrapper
  pendiente — si lo usas, calca el patrón de `.codex/hooks.json`.)

> Puedes borrar los directorios de los clientes que NO uses. El `AGENTS.md` y el Anillo 1
> siguen funcionando igual.

## 4. Rellenar lo que es TUYO (el trabajo de verdad)

Busca todos los marcadores y resuélvelos:

```bash
grep -rn "FILL:" . --include="*.md" --include="*.yml" --include="*.toml" --include="*.sh"
```

Prioridad de relleno (en orden de impacto — es la pirámide de
`.agents/skills/process/references/verification-loop.md` de abajo arriba):

1. `AGENTS.md` §2 — stack, build, tests, lint **y el modo estricto (nivel 0)**. Sin esto el
   agente vuela a ciegas y el compilador no te defiende de nada.
2. `scripts/agent-hooks/post-edit-verify.sh` §FILL — **el gate de mayor ROI**: lint/typecheck
   del archivo tocado, de vuelta al agente en el mismo turno. Media hora de trabajo, cambia
   el bucle entero.
3. `tools/mutation-score.sh` §FILL — el runner de mutación de tu stack, y una primera
   medición (`--update` fija el piso, que a partir de ahí SOLO sube). Es lo único que
   distingue un test que verifica de uno escrito para pasar.
4. `.agents/skills/architecture/SKILL.md` + `platforms/<tu-plataforma>.md` + `domain/SKILL.md`.
5. `tools/layers.conf` — las reglas de capas de TUS rutas (grafo de imports).
6. `tools/semgrep/rules/` — tus anti-patrones como reglas AST. **Ejecuta el scan una vez**
   (`bash tools/semgrep-scan.sh`): `--validate` solo valida el YAML, no el parseo por
   lenguaje — nos pasó (PRD 0001 §18 G15).
7. `docs/process/current_execution_map.md` — estado del proyecto.
8. `CODEOWNERS` — sustituye los `@owner`.

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

Si el commit se bloquea, el Anillo 1 está vivo.

## 8. Entender el flujo de review (el corazón del harness)

Con preset `full`, un commit de código de producto exige que el sub-agente `reviewer` haya
revisado **ese diff exacto**. El orden importa — el marker liga `sha256(diff staged)`:

1. **Stagea primero** (`git add …`). Lo que no está staged no queda ligado al marker.
2. El agente (o tú) invoca el sub-agente `reviewer` sobre el diff staged.
3. El reviewer termina con `VERDICT: GREEN|AMBER|RED` — y **el hook** `SubagentStop` escribe el
   marker a partir de ese veredicto real, ligado al `sha256` del diff. El modelo no puede
   escribirlo (un marker manual se rechaza; `source: hook` es obligatorio).
4. `git commit` **en un comando aparte** pasa los gates (capas, semgrep, secretos, trinquete,
   marker). `git add X && git commit` en una línea o `commit -a/-am` se RECHAZAN: stagean
   después de la validación y se commitearía contenido distinto del revisado.
5. Si cambias lo staged después de la review, el marker caduca. Re-revisa.

Escape auditado para emergencias: `REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..."` —
relaja **solo el marker** (juicio humano), jamás un trinquete o las capas.

## 9. El bucle que hace que esto mejore solo

- Los gates registran cada detección → `bash tools/metrics/escape-rate.sh` te dice en qué
  fase se caza cada defecto. **La tendencia de ese número es la única evidencia real de que
  puedes bajar la revisión humana.**
- Todo hallazgo va al ledger: `bash tools/findings/findings.sh add|close|list`.
- Toda lección de `docs/process/lessons_learned.md` exige su campo `Detector:` (verificado en
  CI): error cometido → lección → detector → **imposible repetirlo**. Ese es el mecanismo
  completo; sin el tercer paso, las lecciones son prosa.
- Las sesiones que tocan código quedan encoladas para el `process-judge` hasta que su
  veredicto las cierra (visible en cada turno).

- **Trabajo desatendido**: escribe historias en `backlog/` (formato `_template.md`, con
  criterios de aceptación Dado/cuando/entonces) y `bash tools/backlog/run.sh` las trabaja una
  a una en ramas `story/NNNN` que TÚ revisas antes de mergear. Detalle: `backlog/README.md`.

## 10. Cómo se ve el día a día (empieza por aquí)

**`docs/EXAMPLES.md`** — 4 escenarios end-to-end en iOS con los prompts literales y qué hace
cada gate: un bug con el flow corto, una feature mediana con PRD + design-review, un run
autónomo con `/goal`, y el backlog de historias. Es la mejor forma de entender el método
antes de escribir tu primera línea.

Listo. El detalle conceptual de por qué cada pieza existe: 
`.agents/skills/process/references/verification-loop.md`.
