# PRD — Backlog runner: historias de usuario → ramas trabajadas solas

> **Tipo:** Forward · **Status:** Shipped
> **Autor:** Hiram (owner) · **Fecha:** 2026-08-06 · **Tracking:** PRD 0003
> **Design-review:** OK — diseño validado contra las primitivas reales (claude -p headless,
> hooks en headless, worktrees/ramas, scheduled tasks) y contra la política SECUENCIAL de
> `multi-agent-orchestration.md`.

## 1-2. Contexto y problema

El harness protege el CÓMO, pero arrancar cada tarea sigue siendo manual: alguien abre una
sesión, pega la historia, lanza el flujo. El owner quiere el ciclo Jira-like: **pego historias
en `.md` → algo las toma una a una → rama por historia desde develop → los gates hacen su
trabajo → un humano revisa la rama antes de mergear**. Sin esto, el cuello de botella es
teclear, no decidir.

## 3. Objetivo

`backlog/*.md` como cola de trabajo declarativa. Un runner (`tools/backlog/run.sh`) toma la
siguiente historia `ready` sin dependencias pendientes, crea `story/<id>-<slug>` desde la rama
base, lanza `claude -p` con la historia + el contrato del harness, deja los commits EN LA RAMA
(jamás push, jamás merge) y marca la historia `in-review`. El ciclo lo repite un schedule o el
humano. **El merge a develop siempre es humano.**

## 4. Filosofía

1. **La historia es el contrato.** Criterios de aceptación = escenarios golden; sin ellos, el
   runner la rechaza (`blocked`), no la improvisa (§1.4: Open Question > default inventado).
2. **SECUENCIAL, una historia por invocación** (política de `multi-agent-orchestration.md`).
   El paralelismo es mergear ramas independientes, no correr dos agentes a la vez.
3. **El runner no añade confianza: la hereda.** Los mismos gates (TDD, reviewer VERDICT,
   trinquetes, capas) aplican dentro del run headless. El humano revisa una rama que YA pasó
   todo — su review es la última capa, no la primera.

## 5. Archivos

```
backlog/README.md · backlog/_template.md          ← formato de historia (frontmatter parseable)
backlog/0001-ejemplo-*.md · 0002-*                ← 2 ejemplos (status: ejemplo → ignorados)
tools/backlog/next.sh                             ← selector: primera ready sin deps pendientes
tools/backlog/run.sh                              ← orquestador: rama + claude -p + estados
tools/tests/test_backlog.sh                       ← TDD del selector y los guards
docs/EXAMPLES.md                                  ← ejemplos iOS end-to-end + este flujo
```
NO-TOUCH: gates existentes, trinquetes, PRDs previos.

## 6-7. Modelo y flujo

Frontmatter de historia: `id`, `titulo`, `status: ready|in-progress|in-review|done|blocked|ejemplo`,
`depends_on: []`, `base: develop`, `scope` (archivos). Estados: el runner marca `in-progress`
al arrancar y `in-review`/`blocked` al terminar (commit en la propia rama); una dependencia
cuenta como satisfecha solo cuando su historia está `done` en la rama base — **es decir, tras
el merge humano**, lo que ordena el grafo sin coordinación extra.

```
schedule/humano → run.sh → next.sh elige → rama story/NNNN desde base →
claude -p (historia + contrato) → TDD + gates + reviewer VERDICT + commits →
historia in-review → humano revisa la rama → merge → done → desbloquea dependientes
```

Edge: árbol sucio → aborta · sin `claude` → exit 3 con instrucción · historia sin criterios →
`blocked` · sin historias ready → exit 0 silencioso (apto para cron).

## 8. Anti-features

NO paraleliza agentes · NO mergea ni pushea · NO reintenta solo una historia `blocked` (eso
es decisión humana) · NO estados en base de datos: frontmatter + git.

## 9. Golden

1. `next.sh` elige la primera `ready` sin deps; ignora `ejemplo/done/in-review`.
2. Historia con `depends_on` a una no-`done` NO se elige; al pasar a `done`, sí.
3. `run.sh` con árbol sucio aborta sin tocar nada.
4. Sin binario `claude` → exit 3 y la historia queda intacta.
5. Suite completa verde.

## 12. Riesgos

Coste de runs no atendidos → una historia por invocación + `--max-turns` configurable ·
run headless sin validar end-to-end aún → documentado como pendiente (misma honestidad que
tools/tests/README) · permisos en headless → hereda settings.json (deny rules incluidas);
flags extra vía `BACKLOG_CLAUDE_FLAGS`.

## 15. DoD

- [ ] Golden 1-5 · TDD del selector · suite verde · docs/EXAMPLES.md publicado

## 17. Change log

| 2026-08-06 | Draft+Approved+implementación · Shipped: runner+selector+tests (9)+ejemplos+EXAMPLES.md | Hiram/Claude |

## 18. Gaps
- El guard de árbol sucio contaba archivos UNTRACKED como suciedad — una historia recién
  pegada abortaba su propio run. Fix: solo modificaciones tracked cuentan; lo untracked viaja
  con el checkout y se commitea en la rama de su historia (ciclo de vida correcto).
- PENDIENTE (documentado en backlog/README): validar en vivo un run headless completo.
  Primera historia real con /loop mirando, no con cron a ciegas.
