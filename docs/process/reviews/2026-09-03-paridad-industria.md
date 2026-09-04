# Paridad con la práctica de la industria — 3 de septiembre de 2026

> Estudio de qué se hace hoy con agentes de código y dónde queda este harness. Alimenta el
> PRD 0008. Las cifras del harness son medidas en este repositorio; las de la industria vienen
> de las fuentes del final, consultadas ese día.
>
> Se clasifica cada práctica con el contrato de exit codes del propio harness (§14.3), porque
> es la vara con la que mide todo lo demás: `0` lo tenemos y lo demuestra · `1` lo tenemos y
> falla · `3` no podemos ni mirar.

---

## Las cinco prácticas

### `1` — `AGENTS.md` como contrato, no como manual

El formato es ya el estándar de hecho: **más de 60 000 repositorios**, leído nativamente por
**30+ herramientas** (Claude Code, Copilot, Cursor, Codex, Gemini CLI, Windsurf, Devin, Aider,
Amazon Q…), formalizado en agosto de 2025 por OpenAI, Google, Cursor, Factory y Sourcegraph, y
con la custodia hoy en la **Agentic AI Foundation, bajo la Linux Foundation**.

La guía de uso va justo contra el instinto de escribir más: **empezar en 30 líneas**, añadir
una sección cuando un agente se equivoque de forma repetida, y **quitar una cuando la
convención cambie**. El error que nombran explícitamente es tratarlo como documentación —
explicaciones largas, filosofía de arquitectura, racional de diseño, historia del proyecto.

**Nosotros.** El criterio aplicado —regla con detector en una línea que lo nombra; regla sin
detector entera; racional fuera— es sólido y coincide con la guía. Dos pasadas lo aplicaron
hasta agotarlo: la segunda sacó la matriz de skills y la pirámide de nueve niveles, que además
estaban DUPLICADAS en sus referencias.

**Y ahí se ve el techo del método.** Lo que queda son en su mayoría reglas que **no tienen
detector mecánico** —TDD y mutantes dirigidos (§5), las seis de seguridad (§6), la disciplina
de scope (§8)— y el propio criterio las protege: leerlas es lo único que las cumple. Recortar
más no es un problema de redacción.

La consecuencia reordena el trabajo: **para adelgazar `AGENTS.md` no se edita `AGENTS.md`, se
mecanizan sus reglas.** Cada detector nuevo convierte párrafos en una línea que lo nombra. El
mutation score dormido (§5) es el ejemplo más caro: despertarlo libera la sección más grande
del fichero.

### `3` — Métricas de entrega, no de actividad

Las cuatro DORA (frecuencia de entrega, lead time, tasa de fallo del cambio, tiempo de
recuperación) siguen siendo la espina dorsal **precisamente porque miden resultados de entrega
y no actividad individual**: son difíciles de inflar con líneas de código o tasas de
aceptación.

Encima se apilan dos específicas de IA:

- **Tasa de aceptación**, con un umbral contraintuitivo: **por encima del 45% se lee como
  aceptación acrítica**, no como calidad de la herramienta. El rango sano es **25–45%**. Por
  encima, conviene auditar si lo aceptado sobrevive a la revisión y al despliegue sin
  retrabajo desproporcionado.
- **Tasa de retrabajo**, que captura lo que el *change failure rate* no ve: los fallos
  pequeños que sí pasaron la revisión.

**Nosotros.** Al escribirse este estudio no había ninguna de las seis ni serie temporal, y el
único dato era uno medido a mano: 27% de aceptación. Desde el PRD 0009 fase 5 hay
`tools/metrics/dora.sh`, que las lee de una vez y apenda una fila a
`.agents/state/metrics/series.jsonl`; el resumen semanal se versiona en
`docs/process/metrics-weekly.md`.

Cuatro de las seis tienen evento en este repo. Las otras dos **salen `n/a` con su razón, nunca
0**: sin merges no hay lead time, y el campo `area` del ledger es texto libre, así que no hay
join para el retrabajo. Esa distinción es el punto entero — un 0 dice "medí y salió cero".

Lo que ya se puede responder, y antes no: la **tasa de aceptación real es 25%** (35 de 139
unidades verdes a la primera), borde inferior del rango sano 25–45%.

### `1` — Evals sobre la trayectoria, corriendo en CI

El consenso es que las evals no son opcionales y que deben probar la **trayectoria completa**,
no solo la respuesta final: elección de herramienta, validez de los argumentos, número de
pasos, tiempo y coste, y cumplimiento de política. Y que **se envían en CI**, no se corren a
mano cuando alguien se acuerda.

**Nosotros.** El sub-agente `process-judge` hace exactamente eso —lee la trayectoria vía
`scripts/process-judge-context.sh`, no solo el diff— pero **no corre en ningún workflow**
(`grep -rl process-judge ci/ .github/workflows/` → 0 ficheros). Hay que invocarlo a mano y la
cola de sesiones sin juzgar ha llegado a once. Un eval que depende de que alguien se acuerde
no es un eval.

### `0` — Guardrails por capas, con presupuesto de latencia

La recomendación es capas de control con presupuesto explícito y **ejecutar en paralelo los
checks independientes** para que la latencia no se apile; el ejemplo citado baja una cadena de
200 ms a 70 ms sin quitar un solo control.

**Nosotros.** Tres anillos, presupuesto declarado y vigilado (`reviewer-gate` avisa si consume
más de la mitad de sus 90 s), gates en paralelo en `lefthook`, y desde el 2026-09-02 la suite
corre en un pool con reposición: **379 s → ~150 s**, con un grupo serie declarado para los
tests sensibles a la carga. Aquí no vamos por detrás.

### `1` — Aislamiento del agente, con puerta humana para lo destructivo

La práctica es un **worktree o contenedor efímero por tarea** y un modelo de ejecución por
niveles donde las **operaciones destructivas de sistema de ficheros y la mutación de historia
de git exigen puerta humana**. No es teoría: entre el **20 y el 24 de julio de 2026**, Claude
Code publicó **cuatro versiones consecutivas** cerrando cuatro fronteras de aislamiento
distintas —directorios de trabajo con symlink, redirección de git fuera del worktree,
worktrees sobrantes de otros proyectos y salida de red no solicitada—. El patrón de fallo que
describen es siempre el mismo: *la capa de aislamiento cree estar mirando una ruta, un
repositorio o una cadena de comando, y el sistema operativo resuelve otra cosa*.

**Nosotros.** Tenemos el Anillo 0 (`permissions.deny` nativo) y el git-guard, que cubren flags
prohibidos y rutas concretas. **No cubren un `rm -rf` dentro de un script.** El 2026-09-03, en
la sesión que produjo este estudio, un sub-agente `reviewer` ejecutó `scripts/bootstrap.sh`
contra el repo real y borró `android/AGENTS.md`, `web/AGENTS.md` y reescribió `tools/preset`.
Los restauró y lo declaró — pero nada mecánico se lo impidió.

---

## Dónde vamos por delante

Tres cosas poco comunes que este harness sí tiene:

1. **La evidencia se ata al contenido exacto del diff.** Los markers de review y de tests
   firman `sha256(diff staged)`. No se puede firmar un árbol que nadie compiló ni reutilizar
   una aprobación de otro cambio.
2. **"No pude mirar" es un estado propio.** El contrato de exit codes distingue `0` limpio de
   `1` hay un problema de `3` el detector no pudo mirar. La mayoría de las cadenas de CI
   colapsan el tercero contra el primero, que es como un scanner roto se vuelve luz verde
   permanente.
3. **Cada detector demuestra que ve.** `validate-harness --selftest` corre los trece contra un
   fixture con una violación real y exige que la cacen. No comprueba que estén configurados:
   comprueba que ven.

## La conclusión, en una línea

Donde vamos por detrás es siempre lo mismo: **nuestra observabilidad es *pull* y la de la
industria es *push***. Te enteras si ejecutas un comando, y todo lo que se obtiene es una
foto, nunca una serie.

---

## Fuentes

Consultadas el 2026-09-03.

- [AGENTS.md Complete Guide 2026](https://codersera.com/blog/agents-md-complete-guide-2026/) — adopción, custodia y formato
- [AGENTS.md Best Practices](https://www.betterclaw.io/blog/agents-md-best-practices) — empezar en 30 líneas; qué no meter
- [AI coding tools' impact: Metrics, ROI, and Review Signals in 2026](https://axify.io/blog/ai-coding-tools-impact) — tasa de aceptación 25–45%, retrabajo
- [AI-Native DORA Metrics](https://larridin.com/blog/ai-native-dora-metrics) — DORA como espina dorsal en la era de agentes
- [AI Agents in 2026: Tools, Memory, Evals, and Guardrails](https://andriifurmanets.com/blogs/ai-agents-2026-practical-architecture-tools-memory-evals-guardrails) — evals de trayectoria, observabilidad de trazas
- [AI Agent Guardrails: Production Guide for 2026](https://authoritypartners.com/insights/ai-agent-guardrails-production-guide-for-2026/) — capas con presupuesto de latencia
- [Your Coding Agent Sandbox Probably Leaks. Here Is Where.](https://www.digitalapplied.com/blog/agent-sandbox-escapes-worktree-symlink-command-filters-2026) — las cuatro fronteras de julio de 2026
- [What Is an Agent Execution Sandbox?](https://www.augmentcode.com/guides/agent-execution-sandbox) — modelo de ejecución por niveles

Informe navegable de este mismo estudio:
<https://claude.ai/code/artifact/0267542c-a842-4e37-ad36-c7dc12b5407f>
