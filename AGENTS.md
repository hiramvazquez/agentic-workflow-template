# <PROJECT> — Reglas de trabajo con agentes (FUENTE CANÓNICA)

> Única fuente de verdad de las reglas para agentes de IA. La leen nativamente
> **Cursor, Codex, Copilot, Gemini y otros**; Claude Code la recibe vía
> `CLAUDE.md`. Si una regla aquí choca con otra fuente, **gana esta**.
>
> **Terso a propósito.** Este fichero entra en el contexto de cada turno, así que
> aquí va la REGLA y el nombre de quien la hace cumplir; el **racional** (las
> mediciones y los incidentes que la produjeron) está en
> `docs/process/agents-rationale.md`, y el detalle en `.agents/skills/`.
> Una regla sin detector se escribe entera: leerla es lo único que la cumple.

---

## 0. Antes de escribir código

1. Lee la parte viva de `docs/process/lessons_learned.md` — detente en “Lecciones mecanizadas (índice)”.
   El índice y `lessons_archive.md` se consultan solo si una señal relevante
   exige su racional; el histórico no se carga por defecto. Si cazas un patrón
   nuevo, agrégalo.
2. Lee `docs/process/current_execution_map.md` — fase actual y próximo paso.
3. Carga **solo** la skill del área que tocas (§11).
4. Si la skill no cubre tu caso: **NO improvises** — pregunta al owner y actualiza la skill.
5. Feature mediana/grande → **PRD obligatorio antes del primer commit** (§12).

## 1. Las reglas de oro (filosofía no negociable)

1. **Detectar no basta — CERRAR.** Cada hallazgo llega a estado terminal y visible (`tools/findings/`).
2. **Defensa en capas.** Detector mecánico + design-review + reviewer + juez + lecciones. Ninguno solo basta.
3. **El que toca, cierra lo que bloquea.** Los `high` de tu scope, en el mismo PR; el resto se registra (§10).
4. **Open Question > suposición silenciosa.** Si no sabes (una columna, un catálogo, un contrato), preguntas; no inventas un default.
5. **Scope = lo explícitamente pedido.** Nada de "aprovechar el viaje" (§8).

## 2. Stack y comandos

- **Plataformas:** <!-- FILL: ios / android / web / backend -->
- **Lenguajes / versiones:** <!-- FILL: ej. Swift 6 / Kotlin 2 / TypeScript 5 -->
- **Build:** `<!-- FILL -->`  ·  **Tests:** `<!-- FILL -->`  ·  **Lint/format:** `<!-- FILL -->`
- **Backend/DB:** <!-- FILL -->  ·  **Idiomas de la app (i18n):** <!-- FILL -->
- **Modo estricto (nivel 0 — OBLIGATORIO):** `<!-- FILL: los flags de tu stack. Ej.:
  Swift: -warnings-as-errors + StrictConcurrency=complete · TS: "strict": true +
  noUncheckedIndexedAccess · Kotlin: allWarningsAsErrors · Python: mypy --strict -->`
  El compilador es el primer reviewer y el único que no se cansa. Prioriza hacer
  el error **imposible por tipo** antes que detectarlo después: un agente que no
  puede expresar el estado inválido no lo escribe.

## 3. Arquitectura (capas + límites)

- **Patrón de pantalla/módulo:** <!-- FILL -->  ·  **Navegación:** <!-- FILL -->  ·  **DI:** <!-- FILL -->
- **Dominio aislado:** entidades, puertos de repositorio y errores de dominio NO
  dependen de UI ni de infraestructura. — `tools/check-layers.sh`
- **i18n:** NUNCA ramifiques lógica sobre texto en lenguaje natural
  (`if texto == "diaria"`). Eso rompe en otros idiomas — clasifica en el
  servidor/LLM o con tablas keyed por idioma.

## 4. Límites de tamaño (soft = revisar / hard = dividir en el mismo PR)

| Tipo | Soft | Hard |
|---|---:|---:|
| Archivo | 200 | 400 |
| Función | 40 | 60 |
| Clase orquestadora (ViewModel/Controller) | 150 | 250 |

— `tools/check-drift.sh`

## 5. TDD obligatorio + aserciones (🔴 red → 🟢 green → ♻️ refactor)

**Ninguna lógica/orquestación nueva sin un test que falle PRIMERO.** Escribe el
test y míralo fallar → implementación mínima → refactor en verde. La matriz de
tests sale del contrato y del riesgo: happy path si existe + cada rama que
cambie comportamiento observable, recuperación, permisos o límites. No inventes
casos para cumplir una cuota. Bug fix = primero un test que reproduce el bug.
Antes de marcar terminado: tests del área + build verde + `bash tools/check-drift.sh`
sin errores nuevos. Playbook: `.agents/skills/process/references/tdd-workflow.md`.

- **Un test que pasa con cualquier implementación no es un test.** La prueba de
  bolsillo: *si rompo a propósito la línea que dice cubrir, ¿falla?*
  El mecanismo son **mutantes dirigidos, a mano**: quien escribe el test rompe
  esa línea, comprueba que el test muere, y **escribe en el PR qué mutantes
  lanzó y cuáles murieron**. El `reviewer` lo verifica y busca uno que
  **sobreviva** — el valor está en el que al autor no se le ocurrió.
  ⚠️ El mutation score automático está **DORMIDO** y nunca ha medido; el árbitro
  es este. Racional: `docs/process/agents-rationale.md` §5.
- **Aserciones / Design by Contract:** toda frontera pública expresa las
  precondiciones e invariantes que realmente tiene; una función sin precondición
  no inventa dos. Sin efectos secundarios. Input recuperable se valida con
  tipos/errores explícitos, no con un crash. — checklist del `reviewer` (ítem DbC).
- **Invariantes → property-based tests.** Si la regla vale para todos los
  valores, no la compruebes con tres ejemplos.
- **Todo fake pasa la MISMA suite de conformidad que el adapter real** (`domain/SKILL.md`).

## 6. Seguridad (gate de cada commit)

> El Anillo 1 (`lefthook` + `gitleaks`) bloquea secretos mecánicamente. Esto es
> lo que el scanner no ve y el `security-reviewer` sí. Detalle en `.agents/skills/security/SKILL.md`.

- **Cero secretos en código.** API keys, tokens, claves privadas, connection
  strings → variables de entorno / secret manager. Nunca hardcoded.
- **Cero secretos en logs / telemetría / mensajes de error** que lleguen al cliente.
- **Datos sensibles (PII/PHI) al almacenamiento seguro** de la plataforma
  (Keychain/Keystore/cifrado), nunca en claro (UserDefaults/localStorage planos).
- **DB:** RLS/authz por fila donde aplique; cifrado at-rest verificado; sin
  tablas sensibles sin política de acceso.
- **Dependencias:** sin paquetes no auditados para manejar secretos/cripto; revisa el lockfile.
- **Authn/authz, cripto y validación sensible fallan cerradas:** ante error o duda, deniega; nunca continúes con permisos o defaults permisivos. Los fallos de observabilidad se hacen visibles (sin datos sensibles) y solo pueden preservar la operación principal si sigue siendo seguro. Fail-silent nunca.

## 7. Convenciones Git (duras)

- Jamás `git commit --amend` sin orden explícita del owner. Jamás `--no-verify`,
  `--force` a main, ni `git add -A` con cambios fuera de scope. — git-guard (`reviewer-gate.sh`)
- Un cambio coherente = un commit. `git push` solo con aprobación explícita del owner.
- Formato: `<tipo>(<área>): <qué hizo>` — feat/fix/refactor/docs/chore/sec/test.

## 8. Disciplina de scope

Scope **limitado a lo que el PRD/prompt lista explícitamente**. Prohibido sin
aprobación del owner: tocar tooling compartido (`tools/`, `ci/`, `lefthook.yml`),
meta-doc (este archivo, `.agents/skills/**`, `_template.md`), o refactorizar
archivos fuera de scope. **Errores preexistentes: se reportan al ledger, NO se
silencian ni se "arreglan de paso".**

## 9. Drift policy + trinquetes

- Cambio que toca un **enum/contrato compartido** o un **puerto de repositorio**
  → actualiza todas las capas afectadas + su doc en el **mismo PR**.
- **Los trinquetes tienen dirección fija y NO se editan a mano.** Solo los
  actualiza su propio script; están en `permissions.deny` de escritura.

| Archivo | Métrica | Dirección | Actualiza con |
|---|---|---|---|
| `tools/drift-ratchet.json` | errores + warnings | **solo baja** | `tools/drift-ratchet.sh --update` |
| `tools/mutation-ratchet.json` | mutation score | **solo sube** | `tools/mutation-score.sh --update` — ⚠️ **DORMIDO** (§5) |

- Ni el preset `lite` ni `REVIEWER_OVERRIDE` relajan un trinquete. Ese override
  es para el **marker de review** (juicio humano), nunca para un detector
  mecánico. — `tools/tests/test_ratchets.sh`

## 10. Cero-deuda-nueva (ownership de findings)

"No es mío, lo dejo" está **prohibido**: cualquier gap que detectes (incluido uno
preexistente) queda **registrado en el ledger** con tier+área (`tools/findings/`).
Reportar = loguear al ledger, no mencionarlo en prosa.

**Pero registrar no es arreglar, y solo una clase bloquea el turno:** el que es
`high` **y** cae dentro del scope declarado. Todo lo demás —severidad menor, o
fuera de scope— se registra y el turno **sigue**.

**Y un hallazgo de revisión no es trabajo hasta que sobrevive a una refutación.**
Antes de entrar al ledger, todo hallazgo de un agente revisor pasa por un intento
explícito de tumbarlo: **¿hay un caso concreto —entradas y estado— en el que el
código haga lo que el hallazgo afirma?** Sin ese caso, no entra.

**Y toda lección aprendida se convierte en un detector.**
`docs/process/lessons_learned.md` exige el campo `Detector:` y
`tools/lesson-detector-link.sh` lo verifica en CI. Excepción legítima y
explícita: `n/a-manual — <razón>`. Racional: `agents-rationale.md` §10.

## 11. Skills enforcement — matriz path → lectura obligatoria

Antes de editar un archivo, debes haber leído la referencia que aplica. La
**fuente única** es `tools/skill-matrix.conf`, que el hook `skill-reminder` lee
en runtime y con la que BLOQUEA. Esta tabla es su **vista humana**; si cambias el
conf, actualiza la tabla en el mismo commit. — `tools/check-skill-matrix-doc.sh`

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift`, `**/*Screen*.swift` | `architecture/SKILL.md` + `architecture/platforms/ios.md` |
| `**/*ViewModel*.swift`, `**/*Logic*.swift`, `**/*UseCase*.swift` | `architecture/SKILL.md` + `domain/SKILL.md` + `process/references/tdd-workflow.md` + `platforms/swift-estado-del-arte.md` |
| `**/Domain/**` | `.agents/skills/domain/SKILL.md` + `process/references/tdd-workflow.md` |
| `**/Data/**`, `<migraciones-db>/**` | `domain/SKILL.md` (puertos) + `security/SKILL.md` |
| `docs/process/prds/[0-9]*.md` | `process/references/prd-lifecycle.md` + `feature-workflow.md` |

**Exactamente el conf, ni una fila más.** Tocar `tools/**`, `ci/**` o
`scripts/agent-hooks/**` NO está en la tabla a propósito; su gate es §8.
Racional: `agents-rationale.md` §11.

## 12. PRD obligatorio para features medianas/grandes

Criterio (≥2 de): >3 días dev · >1 módulo · cambia schema · cambia contrato de
API · decisión de privacy/security/pricing · decisión arquitectónica reusable.
Flujo: `.agents/skills/process/references/feature-workflow.md`. Template:
`docs/process/prds/_template.md`. **El design-review del CÓMO (`design-reviewer`)
es un gate distinto del "Approved" del owner** — no salteable para arquitectura o PHI.

## 13. Reviewer-gate pre-commit

Todo commit que toque código de producto requiere ejecución previa del
sub-agente `reviewer`.

**Tope de DOS rondas por unidad de trabajo. La tercera no se revisa: se parte.**
O se **divide por naturaleza** (`bash tools/check-diff-nature.sh`) y cada mitad
entra limpia, o se sube un nivel y se revisa el **DISEÑO** (`design-reviewer`,
§12) en vez del código. Los datos que fijan el tope: `agents-rationale.md` §13.

**El `reviewer` reporta solo lo que rompe algo:** corrección, seguridad, o un
requisito explícito del encargo. Preferencias de estilo, refactors oportunistas y
defensas para casos que no pueden ocurrir se mencionan en una línea como
opcionales y **no generan findings ni bloquean**. Esta regla es canónica aquí;
`.claude/agents/reviewer.md` la implementa y si divergen, gana esta.

**El veredicto no lo emite el modelo, lo deriva el sistema.** El `reviewer`
termina con `VERDICT: GREEN|AMBER|RED` y el hook `SubagentStop` escribe el marker
a partir de esa línea real. `tools/check-review-marker.sh` solo acepta markers
con `source: hook`.

**Y el mismo invariante para los TESTS.** `tools/verify-run.sh` ejecuta el
comando de `tools/verify.conf` y, solo si sale 0, firma ese diff;
`tools/check-verify-marker.sh` lo exige.

**Flujo (el mismo para los dos):** stagea → invoca al `reviewer` / corre
`verify-run` → commitea en un comando aparte. Los markers ligan
`sha256(diff staged)`, así que `git add X && git commit` en una línea o
`commit -a/-am` los evaden y el gate los rechaza.

Overrides auditados, que relajan el marker y **nunca** un trinquete (§9):
`REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..."` y `VERIFY_OVERRIDE=1
VERIFY_OVERRIDE_REASON="..."`.

Lo verifican los **tres anillos**: `lefthook` (1), `reviewer-gate` (2, vía
`gate-adapter.sh` en Cursor y Codex) y `ci/run-gates.sh` + `ci/ai-review.sh` (3).

**Presets:** con `tools/preset = lite` este gate y el `skill-reminder` AVISAN en
vez de bloquear; trinquetes, capas y `canon-enforce` siguen duros. `full` es el default.

## 14. El bucle de verificación

Referencia completa: **`.agents/skills/process/references/verification-loop.md`**.

1. **Cázalo en la capa más barata.** Cada nivel que un defecto sube sin
   detectarse multiplica ~10× el coste. Un error que el compilador podía cazar y
   llega a un juez de IA es un fallo de diseño del harness, no del agente.
2. **El que escribe nunca es el que aprueba, y "aprobar" es presentar
   evidencia.** Un veredicto es la salida de un comando, un exit code o un
   score — nunca una afirmación del modelo.

```
9 Métricas + lección→detector     8 Gate por evidencia      7 Review adversarial de IA
6 Arquitectura (imports directos; ciclos si hay adapter) 5 Contratos (fake ≡ real) 4 CALIDAD del test (mutantes dirigidos, a mano — el score automático está DORMIDO, §5)
3 Spec ejecutable (TDD + DbC)     2 Patrón AST (Semgrep)    1 Lint/typecheck in-loop
0 Imposibilitar (tipos)
```

- **§14.2 — La ley del 10%:** un detector con más de ~10% de falsos positivos se
  descarta, y un agente aprende a evadirlo. Patrones en Semgrep (AST), no en `grep`.
- **§14.3 — Contrato de exit codes:** `0` limpio · `1` tu código tiene un
  problema (bloquea) · `3` **el detector no pudo mirar** (ausente, reglas rotas,
  crash). El 3 AVISA en local y BLOQUEA en CI (`GATES_REQUIRE_*=1`). Corolario:
  un bug del hook nunca debe trabar el commit en local; **un gate que no corrió
  nunca debe parecer un gate que pasó**.
- **§14.4 — El Anillo 3 es OBLIGATORIO en preset `full`**, y es lo que hace
  verdadero el fail-open de §14.3. — `tools/check-ring3.sh` + `validate-harness`.
  En `lite` no bloquea, pero se DECLARA en cada arranque de sesión.

## 15. Cómo entrar a una sesión nueva

1. Lee este archivo. 2. `docs/process/current_execution_map.md`. 3. El tramo vivo
de `lessons_learned.md` (§0). 4. La skill del área (§11). 5. El PRD/ADR relevante.
6. **Verifica los hechos contra el código/DB antes de editar.**

> Tras una compactación, el hook `SessionStart(source: compact)` reinyecta el
> digest de reglas y los findings abiertos. Si algo de §11 no lo recuerdas con
> precisión, reléelo — el `skill-reminder` te lo exigirá igualmente.
