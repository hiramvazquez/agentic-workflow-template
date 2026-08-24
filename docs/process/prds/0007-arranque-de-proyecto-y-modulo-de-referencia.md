# PRD — El arranque real de un proyecto: decisiones, módulo de referencia y autonomía medida

> **Tipo:** Forward · **Status:** **Draft** (§13 tiene decisiones del owner, pero ninguna bloquea empezar la fase 0)
> **Autor:** agente del template · **Fecha:** 2026-08-24 · **Tracking:** pendiente
> **Design-review:** pendiente — obligatorio antes de `Approved` (§12 de AGENTS.md)

---

## 1. Contexto

Hoy, cuando alguien clona el template, `/adoptar` le hace una entrevista **superficial**: pregunta el
stack, rellena los `<!-- FILL -->` de `AGENTS.md` y comprueba qué niveles quedaron mudos. Útil, pero
no responde ninguna de las preguntas que un agente se hace de verdad al escribir la primera línea:

> *"Me piden un modelo de Login. ¿Struct o class? ¿Dónde van las validaciones? ¿Dónde vive el
> `toRequest()`? ¿Cómo convive esto con SwiftUI? ¿Qué es lo más óptimo aquí?"*

Sin respuesta escrita, el agente responde con **el criterio de su entrenamiento**, produce algo
localmente plausible, y dos PRs después aparece el *"ah, esto tenía que ser una class; se sabía
desde el día 1"*. Eso no es un fallo de previsión: es una **decisión que nadie tomó por escrito**.

El owner ya tiene una práctica que funciona y que este PRD formaliza: antes de meter IA en un
proyecto, construye **un módulo entero a su manera** —Login o Registro— y lo pule hasta que sirva de
patrón. *"Este es el módulo vanguardia; cualquier duda, mira cómo se hizo en Registro."*

## 2. Problema

**2.1 — Dos fallos distintos que hoy se tratan igual.**

| Fallo | Ejemplo | Lo que NO lo arregla | Lo que sí |
|---|---|---|---|
| **Decisión no tomada** | ¿dónde va la validación? | pedirle al agente que "piense un paso adelante" — la previsión no es exigible ni verificable | decidirlo antes y escribirlo, con ejemplo real |
| **Novedad genuina** | ¿`@Observable` u `ObservableObject`? ¿qué cambió en Swift 6? | confiar en el conocimiento del modelo, que tiene fecha de corte | fijar los idiomas con versión y fecha; y para lo no fijado, **preguntar** (§1.4) |

**2.2 — Lo que vive solo en prosa se degrada.** Es la única lección que este repo ha demostrado con
datos propios: `feature-workflow.md` mandaba actualizar el mapa de ejecución "en el mismo commit" y
estuvo **cinco historias sin ejecutarse** hasta que tuvo detector. La matriz de §11 se cumple porque
un hook **bloquea**, no porque esté escrita. Un arranque que termine en documentos preciosos y sin
cableado repite ese patrón a mayor escala.

**2.3 — No hay criterio de "ya podemos delegar".** Hoy se pasa a que la IA trabaje sola por
sensación. Sin criterio falsable, o se delega antes de tiempo y se acumula deuda desde el minuto 1,
o no se delega nunca y el harness no rinde.

## 3. Objetivo

Que un proyecto nuevo llegue a su primera tarea delegada con: las decisiones de arquitectura
**tomadas y escritas**, un **módulo de referencia funcionando** que las instancia todas, el harness
**cableado a esa arquitectura real**, y un criterio **medible** de cuándo la IA puede trabajar sola.

## 4. Filosofía / principios

- **El módulo de referencia lo DECIDE el humano; la IA escribe con él.** El trabajo es conjunto —
  no se trata de que el owner teclee todo—, pero las decisiones y la aceptación son suyas. Si el
  agente decidiera, no habría verdad de base: se estaría evaluando contra un patrón que él mismo
  produjo.
- **Se elige por cruces, no por nombre.** El módulo de referencia es el que **atraviesa todas las
  capas** que el proyecto va a repetir: vista → orquestador → servicio → request/response → API,
  con su validación, su camino de error y su navegación. "Registro" o "Login" suelen cumplirlo, pero
  el criterio es el recorrido, no la pantalla: hay apps que no tienen ninguno de los dos.
- **Puertas de una sola dirección frente a puertas de doble sentido.** Navegación, DI, persistencia,
  entrada de llaves y capas se deciden el día 0 porque cambiarlas al mes 3 cuesta medio proyecto.
  Que un helper sea struct o class se decide cuando aparezca. **Decidir de más es tan caro como
  decidir de menos**: una decisión mala escrita en una skill el agente la sigue.
- **La completitud del módulo se mide en DECISIONES cubiertas, no en código escrito.** Si la app va a
  paginar y el módulo de referencia no pagina, esa decisión no tiene referencia y el agente se la va
  a inventar.
- **El valor del arranque es proporcional a cuánto de él acaba siendo mecánico.**
- **El ejemplo es una vertical completa que compila, no un snippet.** Un manual de estilo se
  malinterpreta; una implementación de referencia, no.
- **Un módulo, varias skills.** El módulo de referencia es el ÚNICO artefacto canónico: es código,
  compila y tiene tests. Las skills son **proyecciones por capa** de ese mismo módulo — la de
  arquitectura cita cómo orquesta el ViewModel, la de dominio cómo se modela y valida, la de
  seguridad cómo entran las llaves y qué no se loguea. Ninguna duplica código: **citan ruta y
  línea**. Así la fuente sigue siendo una sola y el agente carga solo la rodaja de la capa que va a
  tocar, que es lo que la matriz de `§11` ya hace hoy.
- **Y de ahí sale qué capas debe cruzar el módulo, sin adivinarlo:** las que tengan fila en
  `skill-matrix.conf` para este proyecto. Si una capa tiene skill y el módulo no la toca, esa skill
  se queda sin referencia que citar — y ahí es exactamente donde el agente empezará a inventar.

## 5. Estructura de archivos a crear / tocar

```
.claude/commands/arrancar.md            ← NUEVO: conduce las cuatro fases (absorbe /adoptar)
.agents/skills/architecture/SKILL.md    ← se reescribe CITANDO el módulo de referencia real
docs/process/decisions/                 ← NUEVO: registro de decisiones de la fase 0, con el porqué
docs/process/decisions/_template.md     ← NUEVO
tools/check-decision-coverage.sh        ← NUEVO: toda decisión cita su línea de referencia
tools/tests/test_decision_coverage.sh   ← su test + guards de FP
tools/layers.conf                       ← se rellena con las capas REALES del proyecto
tools/skill-matrix.conf                 ← path→skill de la arquitectura real (para que el hook bloquee)
AGENTS.md                               ← §2 y §3 dejan de ser FILL
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```text
El módulo de referencia del adoptante   ← lo escribe y decide ÉL. El agente asiste, no decide.
tools/lib/scope.sh · la superficie      ← PRD 0006, On hold
ratchets                                ← §9
PRDs 0001-0006                          ← histórico
```

## 5b. Fases entregables

| Fase | Entrega (mergeable) | Depende de | Gate de cierre |
|---|---|---|---|
| 0 | **Decisiones.** Entrevista sobre las puertas de una sola dirección + investigación de lo que caduca (versiones, APIs, SPM propios leídos y documentados). Sale el registro en `docs/process/decisions/` con el porqué, y los pins con fecha. | — | el owner firma el registro; lo pendiente está marcado como pendiente, no como decidido |
| 1 | **El módulo de referencia**, elegido por el owner y construido **en conjunto con la IA**: ella escribe, él decide y acepta. Vertical completa: modelo, validación, mapeo, orquestador, vista, fakes, tests, errores, navegación. | 0 | compila, sus tests pasan, y el owner lo declara canónico |
| 2 | **Extracción y cableado.** La skill de arquitectura cita el código real; `layers.conf` y `skill-matrix.conf` reflejan la arquitectura de verdad; la suite de conformidad de fakes existe; los FILL de `AGENTS.md` cerrados. | 1 | `check-decision-coverage.sh` en verde: **toda decisión de la fase 0 cita su línea del módulo** |
| 3 | **La prueba de fuego.** El SEGUNDO módulo lo construye la IA sola con las skills puestas, y se compara contra el de referencia. | 2 | ver §9 golden 1 |

## 6. Modelo de datos

Un registro de decisión (`docs/process/decisions/NNNN-<slug>.md`):

```
# Decisión NNNN — <qué se decide>
Estado: decidida | PENDIENTE (decidir cuando aparezca <disparador>)
Puerta: una-sola-dirección | doble-sentido
Decisión: <qué>
Por qué: <el racional, que es lo que evita re-litigarla en 3 meses>
Referencia: <ruta:línea del módulo de referencia que la instancia>
Caduca: <versión pinneada + fecha de revisión, si aplica>
```

El campo `Referencia:` es el que hace mecanizable la §4: `check-decision-coverage.sh` falla si una
decisión `decidida` de puerta `una-sola-dirección` no cita una línea que exista. Es **el mismo
patrón que `lesson-detector-link.sh`**, que ya lleva meses funcionando: toda lección exige detector,
y sin él, falla. Aquí: toda decisión exige referencia.

## 7. Flujo de la solución

- Como **owner que arranca un proyecto**, quiero decidir una vez las cosas caras de cambiar, para no
  re-litigarlas en cada tarea ni descubrirlas en el PR 5.
- Como **agente que recibe la primera tarea**, quiero que *"¿dónde va esto?"* tenga respuesta
  consultable —**como en Registro**— en vez de tener que decidirlo con mi criterio.
- Como **owner en el mes 3**, quiero saber por qué se decidió algo, no solo qué se decidió.

### Edge cases

- **Aparece una decisión que la fase 0 no previó.** El agente para y pregunta (§1.4); no inventa
  default. La decisión nueva entra al registro con su referencia.
- **El módulo de referencia tiene que cambiar.** Deja de ser una edición normal: exige
  design-review, porque invalida las skills que lo citan. Es la gestión de drift de §9 aplicada al
  artefacto canónico.
- **Un pin caduca.** El registro trae fecha; un aviso —no un bloqueo— cuando lleva N meses.
- **La skill y el módulo se contradicen.** Va a pasar: alguien toca el código y la skill se queda
  vieja, o al revés. **Manda el CÓDIGO** — es lo que compila y lo que tiene tests; una skill que lo
  contradice está equivocada por definición. La divergencia es un finding, no una interpretación, y
  se caza con el mismo patrón que `check-skill-matrix-doc.sh` ya usa para la tabla de §11 y su conf:
  si la skill cita `Registro.swift:42` y ahí ya no hay lo que dice, falla.
- **La prueba de fuego falla tres veces seguidas.** El bucle "falla → tapas el agujero → repites" no
  puede ser infinito. Al tercer intento hay que **distinguir dos causas muy distintas**, porque
  llevan a acciones opuestas: (a) las skills no bastan — se sigue iterando; (b) hay decisiones de la
  arquitectura que **no son expresables como regla**, cosas que el owner resuelve por criterio y que
  nadie puede seguir sin él. La (b) es un hallazgo de primer orden: significa que esa parte no se
  delega, y hay que decir cuál es en vez de seguir puliendo skills contra un techo.

## 8. Anti-features (qué NO entra)

- **Casar el template con UNA arquitectura.** El nivel agnóstico documenta *propiedades* (la lógica
  no vive en la vista; las dependencias entran por el init; nada que necesite montar la app para
  probarse). La arquitectura concreta es del adoptante y vive en SU módulo de referencia.
- **Que el agente construya el módulo de referencia de forma autónoma.** Rompe la verdad de base.
- **Decidir el día 0 las puertas de doble sentido.** Se marcan pendientes con su disparador.
- **Buscar en internet como mecanismo principal.** Es caro por tarea, no verificable y produce
  resultados inconsistentes. La investigación se hace UNA vez en fase 0 y se fija con fecha.
- **Una skill monolítica que pegue el módulo entero.** Duplicaría la fuente y reventaría el
  presupuesto de contexto — el mismo problema que obligó a rotar `lessons_learned`. Las skills
  citan ruta y línea, y solo se carga la de la capa que se toca.
- Retirar o relajar cualquier gate existente.

## 9. Escenarios golden (deben pasar al terminar)

1. **El criterio de salida.** El segundo módulo, construido por la IA sola con las skills puestas,
   pasa el `design-reviewer` **sin desviaciones de arquitectura**. Si el reviewer encuentra que la
   validación acabó en el sitio equivocado o que se inventó un patrón, **no es fallo del agente: es
   un agujero de la fase 2**, y se vuelve a ella. Falsable y repetible con un tercer módulo.
2. Una decisión `decidida` sin `Referencia:` válida hace fallar `check-decision-coverage.sh`.
3. Una decisión marcada `PENDIENTE` **no** lo hace fallar (guard de falso positivo: lo pendiente es
   un estado legítimo, no una omisión).
4. Editar un ViewModel sin haber leído la skill de arquitectura lo **bloquea** el hook — o sea, la
   fase 2 cableó `skill-matrix.conf` de verdad y no solo escribió prosa.
5. Preguntado por algo que la fase 0 marcó pendiente, el agente **para y pregunta** en vez de
   elegir un default.
6. Una skill que cita `<módulo>:<línea>` donde ya no está lo que dice **falla el check**. Y el guard
   de falso positivo: una skill que solo *menciona* el módulo en prosa, sin citar línea, no falla.
7. Cada capa con fila en `skill-matrix.conf` tiene al menos una cita al módulo de referencia. Una
   capa con skill y sin referencia es un agujero declarado, no un descubrimiento del mes 3.

## 10. Métricas de éxito

- **Desviaciones de arquitectura** que el `design-reviewer` encuentra en el módulo N: debe **bajar**
  con N. Si el tercero tiene tantas como el segundo, las skills no están sirviendo.
- **Preguntas del agente que la doc no responde**, por módulo: cada una es un agujero de fase 2 y se
  cierra ahí, no se resuelve improvisando.
- **Tiempo hasta la primera tarea delegable.** Se mide una vez para saber cuánto cuesta de verdad
  este arranque.

## 11. Rollout

`/arrancar` absorbe `/adoptar`. Para un proyecto ya en marcha con el template, las fases 0 y 2 se
pueden hacer **retroactivamente** eligiendo un módulo existente como referencia — probablemente el
camino más común, y hay que probarlo.

## 12. Riesgos

- **El más probable: el arranque se vuelve tan largo que nadie lo hace.** Mitigación: las fases 0 y 1
  son las caras y son las que dan el valor; la 2 se puede hacer incremental. Y §10 mide el tiempo
  real para poder ajustarlo con dato en vez de con opinión.
- **Decidir de más en fase 0** y escribir en una skill una decisión que resulta mala. Mitigación:
  la clasificación puerta-una-dirección / doble-sentido, y que lo pendiente se declare pendiente.
- **Que la fase 2 se quede en documentos.** Es el riesgo con precedente en este repo. Mitigación: el
  gate de cierre de la fase 2 no es "está escrito" sino `check-decision-coverage.sh` en verde y el
  hook de la matriz bloqueando de verdad (golden 4).
- **Que el módulo de referencia envejezca** y las skills citen código que ya no representa la
  arquitectura. Mitigación: tocarlo exige design-review.

## 13. Open Questions

- [ ] **Q1 — ¿`check-decision-coverage.sh` cuenta como "gate nuevo" bajo el freeze de WF-09?**
      Argumento de que no: solo corre en el arranque de un proyecto y responde "¿podemos empezar?",
      no se ejecuta en el commit diario ni añade superficie al Anillo 1. Argumento de que sí: es un
      detector nuevo y el freeze fue explícito. **Decisión del owner**, y hoy la respuesta por
      defecto debería ser la conservadora.
- [x] **Q2 — ¿Qué módulo es el de referencia?** RESUELTA 2026-08-24 por el owner: **lo elige él**,
      no lo prescribe el template. Prescribir "Registro" no sirve porque hay apps que no lo tienen.
      El criterio no es *qué* módulo sino **qué flujo cruza todas las capas** — algo con
      vista + orquestador + servicio + request/response + API — porque es lo que se va a repetir en
      todos los demás. La herramienta ayuda listando los cruces que el candidato debe contener
      (§7), y el check de cobertura de decisiones dice qué se quedó fuera: con eso el owner decide
      si amplía la vertical, añade una segunda, o declara esas decisiones pendientes.
- [ ] **Q3 — ¿El registro de decisiones vive en `docs/process/decisions/` o dentro de la skill?**
      Separado es más rastreable y permite el check; dentro de la skill se lee de una vez. Se
      propone separado, con la skill citándolo.
- [ ] **Q4 — Para el adoptante iOS actual, ¿se hace retroactivo?** Elegir un módulo existente como
      referencia es la vía barata, pero puede consagrar deuda ya existente como si fuera el patrón.
- [ ] **Q5 — ¿Cuántos módulos autónomos hacen falta para declarar la autonomía?** Uno limpio puede
      ser suerte. Se propone: **dos consecutivos** sin desviaciones de arquitectura.
- [ ] **Q6 — ¿Cuál es el techo de intentos de la prueba de fuego?** Se propone **tres**: a partir
      de ahí, en vez de seguir puliendo skills, hay que decidir si el problema es la doc o si esa
      parte de la arquitectura simplemente no se delega (§7, edge cases).

## 15. Definition of Done

- [ ] **Todos** los escenarios golden de §9 pasan. (Sin número: §9 crece, y un conteo aquí caduca
      solo — es literalmente `f-wf02-mapa-cifras-podridas`, cazado por el reviewer en este PRD.)
- [ ] El registro de decisiones existe, con el porqué y con las pendientes marcadas.
- [ ] El módulo de referencia compila, sus tests pasan y **toda decisión de puerta única cita su
      línea** dentro de él.
- [ ] `skill-matrix.conf` y `layers.conf` reflejan la arquitectura real, y el hook bloquea (golden 4).
- [ ] Los `<!-- FILL -->` de `AGENTS.md` §2 y §3 cerrados.
- [ ] `design-reviewer` sobre este PRD **antes** de `Approved`; `reviewer` GREEN en cada fase.
- [ ] Cada afirmación de cobertura del código nuevo existe como test.

## 16. Próximos pasos

- Este PRD **no toca** la calidad de los tests. La conversación que lo originó dejó dos cosas
  pendientes que van aparte: (a) corregir `AGENTS.md` §5, que declara el mutation score *"el
  árbitro"* cuando no ha medido nunca; (b) diseñar la mutación **incremental sobre lo tocado**, con
  los mutantes vivos entrando al ledger para que la presión la ejerza §10 —"el que toca, cierra"—
  en vez de un contador global.
- PRD 0006 sigue On hold por el freeze.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-24 | Draft, salido de una conversación de diseño con el owner sobre por qué los agentes producen artefactos localmente correctos y globalmente equivocados. La aportación central es suya: su práctica de construir un "módulo vanguardia" antes de meter IA en un proyecto. Este PRD la formaliza y le añade un criterio de salida falsable | agente del template |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._ Uno ya identificado: la tentación al escribir esto fue documentar la arquitectura del
owner como la canónica del template. Se resistió (§8) porque el template se adopta en iOS, Android,
web y backend — pero es una tensión real y volverá cada vez que alguien pida "más ejemplos".
