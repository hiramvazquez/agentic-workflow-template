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

## Qué corre `run-gates.sh`

1. **secret-scan** (gitleaks, historial) — obligatorio en CI.
2. **drift-ratchet** — el conteo de deuda no puede haber subido.
3. **build & tests** — `<!-- FILL: tu stack -->`.
4. **checks de proyecto** — contratos/schemas opcionales.

> Recomendación: corre también un job **nocturno** con `GATES_SECRET_MODE=history` para validar
> que el scrub histórico de secretos se mantiene.
