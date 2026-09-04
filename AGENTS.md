# <PROJECT> — Reglas de trabajo con agentes (FUENTE CANÓNICA)

> Única fuente de verdad para agentes de IA. La leen nativamente **Cursor, Codex,
> Copilot, Gemini y otros**; Claude Code la recibe vía `CLAUDE.md`. Si una regla
> aquí choca con otra fuente, **gana esta**.
>
> **Terso a propósito**, porque entra en el contexto de cada turno. El criterio: una
> regla **con detector** se escribe en una línea que lo nombra; una **sin detector**
> se escribe entera, porque leerla es lo único que la cumple. Racional en
> `docs/process/agents-rationale.md`, detalle en `.agents/skills/`.
>
> Los números de sección son API: los citan scripts, tests y docs. No se renumeran.

---

## 0. Antes de escribir código

1. Lee la parte viva de `docs/process/lessons_learned.md` — detente en “Lecciones mecanizadas
   (índice)”; el histórico no se carga por defecto. Patrón nuevo → agrégalo.
2. Lee `docs/process/current_execution_map.md` — fase actual y próximo paso.
3. Carga **solo** la skill del área que tocas (§11), y el PRD/ADR relevante.
4. **Verifica los hechos contra el código o la DB antes de editar.**
5. Si la skill no cubre tu caso: **NO improvises** — pregunta al owner y actualiza la skill.
6. Feature mediana/grande → **PRD obligatorio antes del primer commit** (§12).

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
  Haz el error **imposible por tipo** antes que detectable después. Racional:
  `agents-rationale.md` §2.

## 3. Arquitectura (capas + límites)

- **Patrón de pantalla/módulo:** <!-- FILL -->  ·  **Navegación:** <!-- FILL -->  ·  **DI:** <!-- FILL -->
- **Dominio aislado:** entidades, puertos de repositorio y errores de dominio NO
  dependen de UI ni de infraestructura. — `tools/check-layers.sh`
- **i18n:** NUNCA ramifiques lógica sobre texto en lenguaje natural
  (`if texto == "diaria"`): rompe en otros idiomas. Clasifica en el servidor/LLM
  o con tablas keyed por idioma.

## 4. Límites de tamaño

Soft = revisar · hard = **dividir en el mismo PR**. Archivo 200/400 · función
40/60 · clase orquestadora (ViewModel/Controller) 150/250. — `tools/check-drift.sh`

## 5. TDD obligatorio + aserciones (🔴 red → 🟢 green → ♻️ refactor)

> Sin detector mecánico: el mutation score automático está **DORMIDO** y nunca ha
> medido (§9). Estas reglas se cumplen leyéndolas.

**Ninguna lógica/orquestación nueva sin un test que falle PRIMERO.** Escribe el
test y míralo fallar → implementación mínima → refactor en verde. La matriz de
tests sale del contrato y del riesgo: happy path si existe + cada rama que cambie
comportamiento observable, recuperación, permisos o límites. No inventes casos
para cumplir una cuota. Bug fix = primero un test que reproduce el bug. Antes de
marcar terminado: tests del área + build verde + `bash tools/check-drift.sh` sin
errores nuevos. Playbook: `.agents/skills/process/references/tdd-workflow.md`.

- **Un test que pasa con cualquier implementación no es un test.** La prueba de
  bolsillo: *si rompo a propósito la línea que dice cubrir, ¿falla?* El mecanismo
  son **mutantes dirigidos, a mano**: rompe esa línea, comprueba que el test
  muere, y **escribe en el PR qué mutantes lanzaste y cuáles murieron**. El
  `reviewer` lo verifica y busca uno que **sobreviva** — ahí está el valor.
  Y un mutante que "sobrevive" sin comprobar que llegó a aplicarse es un falso
  negativo de la técnica, no una laguna del test. Racional: `agents-rationale.md` §5.
- **Aserciones / Design by Contract:** toda frontera pública expresa las
  precondiciones e invariantes que realmente tiene; una función sin precondición
  no inventa dos. Sin efectos secundarios. Input recuperable se valida con
  tipos/errores explícitos, no con un crash. — checklist del `reviewer` (ítem DbC).
- **Invariantes → property-based tests.** Si la regla vale para todos los valores,
  no la compruebes con tres ejemplos.
- **Todo fake pasa la MISMA suite de conformidad que el adapter real** (`domain/SKILL.md`).

## 6. Seguridad (gate de cada commit)

> El Anillo 1 (`lefthook` + `gitleaks`) bloquea secretos mecánicamente. Esto es lo
> que el scanner no ve y el `security-reviewer` sí. Detalle: `.agents/skills/security/SKILL.md`.

- **Cero secretos en código.** API keys, tokens, claves privadas, connection
  strings → variables de entorno / secret manager. Nunca hardcoded.
- **Cero secretos en logs / telemetría / mensajes de error** que lleguen al cliente.
- **Datos sensibles (PII/PHI) al almacenamiento seguro** de la plataforma
  (Keychain/Keystore/cifrado), nunca en claro (UserDefaults/localStorage planos).
- **DB:** RLS/authz por fila donde aplique; cifrado at-rest verificado; sin tablas
  sensibles sin política de acceso.
- **Dependencias:** sin paquetes no auditados para manejar secretos/cripto; revisa el lockfile.
- **Authn/authz, cripto y validación sensible fallan CERRADAS:** ante error o duda,
  deniega; nunca continúes con permisos o defaults permisivos. Los fallos de
  observabilidad se hacen visibles (sin datos sensibles) y solo pueden preservar la
  operación principal si sigue siendo seguro. **Fail-silent nunca.**

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

- Cambio que toca un **enum/contrato compartido** o un **puerto de repositorio** →
  actualiza todas las capas afectadas + su doc en el **mismo PR**.
- **Los trinquetes tienen dirección fija y NO se editan a mano**: solo los actualiza
  su propio script, y están en `permissions.deny` de escritura.
  `tools/drift-ratchet.json` (errores+warnings, **solo baja**, `drift-ratchet.sh --update`) ·
  `tools/mutation-ratchet.json` (mutation score, **solo sube**, `mutation-score.sh --update`
  — ⚠️ **DORMIDO**, §5).
- Ni el preset `lite` ni `REVIEWER_OVERRIDE` relajan un trinquete: ese override es
  para el **marker de review** (juicio humano), nunca para un detector mecánico.
  — `tools/tests/test_ratchets.sh`

## 10. Cero-deuda-nueva (ownership de findings)

"No es mío, lo dejo" está **prohibido**: cualquier gap que detectes (incluido uno
preexistente) queda **registrado en el ledger** con tier+área (`tools/findings/`).
Reportar = loguear al ledger, no mencionarlo en prosa.

**Pero registrar no es arreglar, y solo una clase bloquea el turno:** el que es
`high` **y** cae dentro del scope declarado. Todo lo demás —severidad menor, o
fuera de scope— se registra y el turno **sigue**.

**Y un hallazgo de revisión no es trabajo hasta que sobrevive a una refutación:**
antes de entrar al ledger se intenta tumbarlo. **¿Hay un caso concreto —entradas y
estado— en el que el código haga lo que el hallazgo afirma?** Sin él, no entra.

**Y toda lección aprendida se convierte en un detector.** `lessons_learned.md`
exige el campo `Detector:`; excepción legítima y explícita: `n/a-manual — <razón>`.
— `tools/lesson-detector-link.sh`. Racional: `agents-rationale.md` §10.

## 11. Skills enforcement — matriz path → lectura obligatoria

Antes de editar un archivo debes haber leído la referencia que aplica. La **fuente
única** es `tools/skill-matrix.conf`, que el hook `skill-reminder` lee en runtime y
con la que BLOQUEA **nombrando las referencias que te faltan** — por eso la matriz
no se copia aquí: la vista humana vive en `agents-rationale.md` §11, y
`tools/check-skill-matrix-doc.sh` la compara contra el conf.

`check-skill-matrix-doc.sh` verifica que las dos declaren **las mismas
combinaciones de lecturas**, en los dos sentidos. Lo que NO verifica —y está
declarado, no supuesto— es de qué fila cuelga cada una: permutar dos conjuntos
enteros entre filas es invisible (`f-8b74d177`, abierto).

Tocar `tools/**`, `ci/**` o `scripts/agent-hooks/**` NO está en la matriz a
propósito; su gate es §8.

## 12. PRD obligatorio para features medianas/grandes

Criterio (≥2 de): >3 días dev · >1 módulo · cambia schema · cambia contrato de API ·
decisión de privacy/security/pricing · decisión arquitectónica reusable. Flujo:
`.agents/skills/process/references/feature-workflow.md`. Template:
`docs/process/prds/_template.md`. **El design-review del CÓMO (`design-reviewer`) es
un gate distinto del "Approved" del owner** — no salteable para arquitectura o PHI.

## 13. Reviewer-gate pre-commit

Todo commit que toque código de producto requiere ejecución previa del sub-agente
`reviewer`.

**Tope de DOS rondas por unidad de trabajo. La tercera no se revisa: se parte.** O
se **divide por naturaleza** (`bash tools/check-diff-nature.sh`) y cada mitad entra
limpia, o se sube un nivel y se revisa el **DISEÑO** (`design-reviewer`, §12) en vez
del código. Los datos que fijan el tope: `agents-rationale.md` §13.

**El `reviewer` reporta solo lo que rompe algo:** corrección, seguridad, o un
requisito explícito del encargo. Preferencias de estilo, refactors oportunistas y
defensas para casos que no pueden ocurrir se mencionan en una línea como opcionales
y **no generan findings ni bloquean**. Esta regla es canónica aquí;
`.claude/agents/reviewer.md` la implementa y si divergen, gana esta.

**El veredicto lo deriva el sistema, no lo emite el modelo** — y el mismo
invariante para los tests. Los markers ligan `sha256(diff staged)`, y el flujo es
stagea → revisa/verifica → commitea **en un comando aparte**, porque `git add X &&
git commit` en una línea o `commit -a/-am` los evaden. — `check-review-marker.sh`
(solo `source: hook`, escrito por `SubagentStop` desde el `VERDICT:` real) ·
`verify-run.sh` + `check-verify-marker.sh` (firma solo si el comando de
`tools/verify.conf` sale 0) · `reviewer-gate.sh` · los **tres anillos**: `lefthook`,
`gate-adapter.sh` (Cursor/Codex) y `ci/run-gates.sh` + `ci/ai-review.sh`.

Overrides auditados, que relajan el marker y **nunca** un trinquete (§9):
`REVIEWER_OVERRIDE` / `VERIFY_OVERRIDE`, cada uno con su `_REASON`. Con preset
`lite` este gate y el `skill-reminder` AVISAN en vez de bloquear; trinquetes, capas
y `canon-enforce` siguen duros. `full` es el default.

## 14. El bucle de verificación

Los nueve niveles, con qué cubre cada uno:
**`.agents/skills/process/references/verification-loop.md`**.

1. **Cázalo en la capa más barata.** Cada nivel que un defecto sube sin detectarse
   multiplica ~10× el coste: un error que el compilador podía cazar y llega a un juez
   de IA es un fallo de diseño del harness, no del agente.
2. **El que escribe nunca es el que aprueba, y "aprobar" es presentar evidencia** —
   un comando, un exit code o un score, nunca una afirmación del modelo.

- **§14.2 — La ley del 10%:** un detector con más de ~10% de falsos positivos se
  descarta, y un agente aprende a evadirlo. Patrones en Semgrep (AST), no en `grep`.
- **§14.3 — Contrato de exit codes:** `0` limpio · `1` tu código tiene un problema
  (bloquea) · `3` **el detector no pudo mirar** (ausente, reglas rotas, crash). El 3
  AVISA en local y BLOQUEA en CI (`GATES_REQUIRE_*=1`). Dos corolarios, y los dos
  son regla: **un bug del hook nunca debe trabar al dev** —el enforcement roto falla
  hacia `allow`, no hacia `deny`— y **un gate que no corrió nunca debe parecer un
  gate que pasó**. Lo segundo vale igual para un informe: el hueco se declara con su
  razón, y esa razón tiene que ser VERDADERA. Nunca un `0`.
- **§14.4 — El Anillo 3 es OBLIGATORIO en preset `full`**, y es lo que hace verdadero
  el fail-open de §14.3. En `lite` no bloquea, pero se DECLARA en cada arranque de
  sesión. — `tools/check-ring3.sh` + `validate-harness`

## 15. Cómo entrar a una sesión nueva

El orden está en §0, y se aplica igual tras una compactación: el hook
`SessionStart(source: compact)` reinyecta el digest de reglas y los findings
abiertos, pero **eso no sustituye a releer** lo que necesites con precisión — el
`skill-reminder` te lo exigirá igualmente (§11).
