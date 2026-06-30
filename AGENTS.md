# <PROJECT> — Reglas de trabajo con agentes (FUENTE CANÓNICA)

> Este archivo es la **única fuente de verdad** de las reglas del proyecto para agentes de IA.
> Lo leen nativamente **Cursor, Codex, Copilot, Gemini y otros**. Claude Code lo recibe vía
> `CLAUDE.md` (que hace `@AGENTS.md`). Si una regla aquí choca con cualquier otra fuente, **gana esta**.
>
> Mantenlo **terso**. El detalle vive en `.agents/skills/` y en `docs/process/`. El racional
> histórico / post-mortems van en `docs/process/lessons_learned.md`, NO aquí (evita el monolito).

---

## 0. Antes de escribir código

1. Lee `docs/process/lessons_learned.md` — trampas ya pisadas. Si tocas un área cubierta ahí,
   sus reglas son obligatorias. Si cazas un patrón nuevo, **agrégalo en el mismo cambio**.
2. Lee `docs/process/current_execution_map.md` — fase actual y próximo paso.
3. Carga **solo** la skill del área que tocas (ver §11 matriz path→lectura).
4. Si la skill no cubre tu caso: **NO improvises** — pregunta al owner y actualiza la skill antes de seguir.
5. Feature mediana/grande → **PRD obligatorio antes del primer commit** (§12).

## 1. Las reglas de oro (filosofía no negociable)

1. **Detectar no basta — CERRAR.** Cada hallazgo llega a estado terminal y visible (`tools/findings/`).
2. **Defensa en capas.** Detector mecánico + design-review + reviewer + juez + lecciones. Ninguno solo basta.
3. **El que toca, cierra.** Tocas un módulo con findings abiertos → los arreglas o los registras, en el mismo PR.
4. **Open Question > suposición silenciosa.** Si no sabes (una columna, un catálogo, un contrato), preguntas; no inventas un default.
5. **Scope = lo explícitamente pedido.** Nada de "aprovechar el viaje" para refactorizar lo de al lado (§8).

## 2. Stack y comandos

<!-- FILL: el agente NO puede inferir esto. Sin esta sección, vuela a ciegas. -->

- **Plataformas:** <!-- FILL: ios / android / web / backend -->
- **Lenguajes / versiones:** <!-- FILL: ej. Swift 6 / Kotlin 2 / TypeScript 5 -->
- **Build:** `<!-- FILL: comando de build -->`
- **Tests:** `<!-- FILL: comando de tests -->`
- **Lint/format:** `<!-- FILL -->`
- **Backend/DB:** <!-- FILL: ej. Supabase / Postgres / Firebase / propio -->
- **Idiomas de la app (i18n):** <!-- FILL: ej. ES + EN. Afecta reglas de §3. -->

## 3. Arquitectura (capas + límites)

<!-- FILL: define TU arquitectura. Detalle en .agents/skills/architecture/SKILL.md. -->
<!-- OPINIÓN: separa SIEMPRE presentación / orquestación / lógica-pura en archivos distintos.
     La lógica de negocio testeable NO vive en la capa de UI ni en el orquestador. Toda
     dependencia que cruza capa va por interfaz/protocolo + inyección por constructor. -->

- **Patrón de pantalla/módulo:** <!-- FILL: ej. View+ViewModel+Logic / MVVM / MVI / Clean -->
- **Navegación:** <!-- FILL -->  ·  **Inyección de dependencias:** <!-- FILL -->
- **Dominio aislado:** las entidades, puertos de repositorio y errores de dominio NO dependen de UI ni de infraestructura (DB/SDK).
- **i18n:** NUNCA ramifiques lógica sobre texto en lenguaje natural (`if texto == "diaria"`). Eso rompe en otros idiomas — clasifica en el servidor/LLM o con tablas keyed por idioma.

## 4. Límites de tamaño (soft = revisar / hard = dividir en el mismo PR)

<!-- OPINIÓN: defaults razonables; ajusta a tu lenguaje. -->

| Tipo | Soft | Hard |
|---|---:|---:|
| Archivo | 200 | 400 |
| Función | 40 | 60 |
| Clase orquestadora (ViewModel/Controller) | 150 | 250 |

## 5. TDD obligatorio (🔴 red → 🟢 green → ♻️ refactor)

**Ninguna lógica/orquestación nueva sin un test que falle PRIMERO.** Ciclo: escribe el test y
míralo fallar → implementación mínima que lo pasa → refactor en verde. Cada unidad: **mínimo
1 happy path + 2 ramas de error/borde**. Bug fix = primero un test que reproduce el bug (falla),
luego el fix. Antes de marcar terminado: tests del área + build verde + `bash tools/check-drift.sh`
sin errores nuevos. Playbook + ejemplos iOS: `.agents/skills/process/references/tdd-workflow.md`.

## 6. Seguridad (gate de cada commit)

> El Anillo 1 (`lefthook` + `gitleaks`) bloquea secretos mecánicamente. Estas reglas son lo
> que el scanner no ve y el `security-reviewer` sí. Detalle en `.agents/skills/security/SKILL.md`.

- **Cero secretos en código.** API keys, tokens, claves privadas, connection strings → variables de entorno / secret manager. Nunca hardcoded, nunca en commits.
- **Cero secretos en logs / telemetría / mensajes de error** que lleguen al cliente.
- **Datos sensibles (PII/PHI) al almacenamiento seguro** de la plataforma (Keychain/Keystore/cifrado), nunca a almacenamiento en claro (UserDefaults/SharedPreferences/localStorage planos).
- **DB:** RLS/authz por fila donde aplique; cifrado at-rest (default del proveedor) verificado; sin tablas sensibles sin política de acceso.
- **Dependencias:** sin paquetes no auditados para manejar secretos/cripto; revisa el lockfile.
- **Errores fail-open OK, fail-silent NO** en paths sensibles: loguea la señal (sin el dato).

## 7. Convenciones Git (duras)

- Jamás `git commit --amend` sin orden explícita del owner. Jamás `--no-verify`, `--force` a main, ni `git add -A` con cambios fuera de scope.
- Un cambio coherente = un commit. `git push` solo con aprobación explícita del owner.
- Formato de mensaje: `<tipo>(<área>): <qué hizo>` — tipos: feat/fix/refactor/docs/chore/sec/test.

## 8. Disciplina de scope

El agente que ejecuta una tarea/PRD tiene scope **limitado a lo que el PRD/prompt lista explícitamente**.
Prohibido sin aprobación del owner: tocar tooling compartido (`tools/`, `ci/`, `lefthook.yml`),
meta-doc (este archivo, `.agents/skills/**`, `_template.md`), o refactorizar archivos fuera de scope.
**Errores preexistentes: se reportan al ledger, NO se silencian ni se "arreglan de paso".**

## 9. Drift policy + ratchet

- Cambio que toca un **enum/contrato compartido** o un **puerto de repositorio** → actualiza
  todas las capas afectadas + su doc en el **mismo PR**.
- `tools/drift-ratchet.json` es el **techo committeado** de warnings/errores: **solo baja**.
  Ningún commit puede subirlo (lo bloquea el Anillo 1). Subirlo a mano = esconder deuda (§8).

## 10. Cero-deuda-nueva (ownership de findings)

"No es mío, lo dejo" está **prohibido**. Cualquier gap que detectes (incluido uno preexistente)
se resuelve en el mismo turno: o lo arreglas, o lo **registras en el ledger** con tier+área
(`tools/findings/`). Reportar = loguear al ledger, no solo mencionarlo en prosa.

## 11. Skills enforcement — matriz path → lectura obligatoria

Antes de editar un archivo, debes haber leído la referencia que aplica. El hook
`skill-reminder` (Anillo 2) lo bloquea automáticamente; esta tabla es el fallback humano.

<!-- iOS de referencia. Ajusta los globs a tus carpetas reales si difieren. -->

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift`, `**/*Screen*.swift` | `architecture/SKILL.md` + `architecture/platforms/ios.md` |
| `**/*ViewModel*.swift`, `**/*Logic*.swift`, `**/*UseCase*.swift` | `architecture/SKILL.md` + `domain/SKILL.md` + `process/references/tdd-workflow.md` |
| `**/Domain/**` | `.agents/skills/domain/SKILL.md` + `process/references/tdd-workflow.md` |
| `**/Data/**`, `<migraciones-db>/**` | `domain/SKILL.md` (puertos) + `security/SKILL.md` |
| `docs/process/prds/[0-9]*.md` | `process/references/prd-lifecycle.md` + `feature-workflow.md` |

## 12. PRD obligatorio para features medianas/grandes

Criterio "mediano/grande" (≥2 de): >3 días dev · >1 módulo · cambia schema · cambia contrato
de API · decisión de privacy/security/pricing · decisión arquitectónica reusable.
Flujo completo en `.agents/skills/process/references/feature-workflow.md`. Template:
`docs/process/prds/_template.md`. **El design-review del CÓMO (sub-agente `design-reviewer`)
es un gate distinto del "Approved" del owner** — no es salteable para cambios de arquitectura o PHI.

## 13. Reviewer-gate pre-commit

Todo commit que toque código de producto requiere ejecución previa del sub-agente `reviewer`
(verdict GREEN/AMBER → marca con `scripts/mark-reviewer-run.sh`). El hook `reviewer-gate`
(Anillo 2) y `ci/run-gates.sh` (Anillo 3) lo verifican. Override de emergencia auditado:
`REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..." git commit ...`.
**Presets:** con `tools/preset = lite` (uso personal) este gate y el `skill-reminder` AVISAN en vez
de bloquear; el drift-ratchet y los detectores siguen duros. `full` (equipo) es el default.

## 14. Cómo entrar a una sesión nueva

1. Lee este archivo. 2. Lee `docs/process/current_execution_map.md`. 3. Carga la skill del área (§11).
4. Abre el PRD/ADR relevante. 5. **Verifica los hechos contra el código/DB antes de editar.**
