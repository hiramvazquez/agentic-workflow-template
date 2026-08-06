# ci/ — Anillo 3 (CI), opcional y provider-agnóstico

> **No imponemos ningún proveedor de CI.** El Anillo 3 es un único script,
> `ci/run-gates.sh`, que corre los mismos gates server-side. Lo invocas desde el CI que uses —
> o desde ninguno (te quedas con los Anillos 1 y 2).

## Por qué existe (aunque sea opcional)

Es el **backstop independiente del cliente**. Cubre lo que los hooks locales no pueden:

- **Codex** no tiene hooks → este es su único enforcement automático.
- Commits con `git commit --no-verify` (saltan el Anillo 1).
- Máquinas/CI sin `lefthook` instalado.

## Cómo conectarlo

Copia el ejemplo de tu proveedor desde `ci/examples/` y bórrale el `.example`:

| Proveedor | Destino |
|---|---|
| GitHub Actions | `.github/workflows/gates.yml` |
| GitLab CI | `.gitlab-ci.yml` |
| Bitbucket | `bitbucket-pipelines.yml` |
| Azure | `azure-pipelines.yml` |
| Jenkins | `Jenkinsfile` |

Todos hacen lo mismo: instalan `gitleaks` y ejecutan `bash ci/run-gates.sh`. La lógica vive en
el script, no en el YAML → cambiar de proveedor no cambia los gates.

## Qué corre `run-gates.sh` (barato → caro)

1. **tests del harness** (`tools/tests/`) — si los gates están rotos, el resto no significa nada.
2. **secret-scan** (gitleaks, historial) — obligatorio en CI.
3. **semgrep** (patrones AST) — fail-closed: aquí "no pude mirar" también falla.
4. **check-layers** — fitness function de arquitectura sobre el grafo de imports.
5. **drift-ratchet** — el conteo de deuda no puede haber subido.
6. **build & tests** — `<!-- FILL: tu stack -->`.
7. **mutation-score** — informativo con piso 0; **obligatorio automáticamente** en cuanto el
   piso sube de 0 (si no, desinstalar el runner sería una forma de "aprobar").
8. **review + evidencia** — `check-review-marker --range`, `ci/ai-review.sh` (review de IA
   headless con contexto fresco: cubre Codex y commits humanos) y `lesson-detector-link.sh`
   (toda lección tiene detector).

## FAIL-CLOSED por defecto

Este es el único anillo que no depende de que el agente se porte bien, así que una herramienta
ausente **no** se lee como "gate aprobado". Renunciar a un gate es explícito y visible en la
config del CI: `AI_REVIEW_REQUIRED=0`, `GATES_REQUIRE_SEMGREP=0`, `GATES_SKIP_TESTS=1`.
(En local la política es la inversa para los fallos del propio detector — exit 3 avisa sin
bloquear — porque un typo en las reglas no puede impedir el commit que lo arregla: §4.4.)

`ci/ai-review.sh` necesita el binario `claude` + `ANTHROPIC_API_KEY` en el runner, y emite el
mismo contrato `VERDICT:` que el sub-agente local: GREEN/AMBER pasan, RED falla el job.

> Recomendación: corre también un job **nocturno** con `GATES_SECRET_MODE=history` para validar
> que el scrub histórico de secretos se mantiene.
