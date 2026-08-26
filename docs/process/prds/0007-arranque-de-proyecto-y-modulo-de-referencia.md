# PRD — El arranque real de un proyecto: decisiones, módulo de referencia y autonomía medida

> **Tipo:** Forward · **Status:** **Approved ACOTADO a fases 0–1** (owner, 2026-08-25) — las
> fases 2–3 siguen en **Draft** hasta que esta v2 pase re-review del `design-reviewer`
> **Autor:** agente del template · **Fecha:** 2026-08-24 · **Tracking:** pendiente
> **Design-review:** hecha 2026-08-25 — **RED, 15 hallazgos** (reporte persistido en
> `.agents/state/reviews/e3b0c44298fc-design-reviewer.md`). Esta v2 los aplica con las decisiones
> del owner del mismo día (§13). Los tres bloqueantes (F1 registro-vs-ADR, F2 criterio de
> autonomía no falsable, F3 el detector sí es un gate) no tocan las fases 0–1 — por eso el
> Approved acotado es honesto y no un bypass del gate de §12.

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
  produjo. Formulación operativa (antes vivía mal puesta en NO-TOUCH, donde el `reviewer` la
  leería como bloqueo del archivo que la fase 1 manda escribir): *las DECISIONES del módulo —qué
  patrón, dónde vive cada responsabilidad— no las toma el agente; el código lo escribe él, con
  aceptación explícita del owner por archivo*.
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
.claude/commands/adoptar.md             ← queda en STUB de ~3 líneas que redirige a /arrancar
docs/ADOPTION.md                        ← §4 SIGUE siendo el dueño del ORDEN de relleno; /arrancar
                                          lo cita, no lo copia (§5 de ADOPTION gana la nota de la
                                          migración). /arrancar hereda de /adoptar: el paso del
                                          Anillo 3 (§14.4), la honestidad FILL/OPEN QUESTION, y la
                                          evidencia antes/después con session-start --report
.agents/skills/architecture/SKILL.md    ← se reescribe CITANDO el módulo de referencia real
.agents/skills/security/SKILL.md        ← cita del módulo real cómo entran las llaves y qué no se loguea
docs/process/decisions/README.md        ← SE AMPLÍA (el directorio NO es nuevo: ya define ADRs con
                                          numeración NNNN): el formato ADR existente gana los campos
                                          de §6 como OPCIONALES. Un artefacto, una numeración, un
                                          formato — decisión del owner 2026-08-25 (F1)
docs/process/decisions/_template.md     ← NUEVO, instancia del formato ampliado
tools/check-decision-coverage.sh        ← NUEVO y CONDICIONADO AL FREEZE (Q1 resuelta): su nombre lo
                                          clasifica como detector (el glob de test_meta_fp.sh) y por
                                          tanto ES un gate nuevo. Se entrega cuando el freeze se
                                          levante; cubre los goldens 2, 3, 6 y 7 (un solo detector
                                          con tres comprobaciones, no tres detectores)
tools/tests/test_decision_coverage.sh   ← ídem + guards de FP
tools/tests/test_meta_fp.sh             ← el manifiesto gana la fila del detector nuevo (su glob
                                          recorre tools/check-*.sh y falla si falta)
tools/layers.conf                       ← se AMPLÍA con las capas reales — los globs universales se
                                          CONSERVAN (test_layers.sh los fija; ADOPTION §4.5)
tools/skill-matrix.conf                 ← se PODA al stack real Y AGENTS.md §11 se actualiza en el
                                          mismo commit (check-skill-matrix-doc.sh compara ambos)
tools/project.conf                      ← gana MODULO_REFERENCIA=<ruta> + las firmas de cierre de
                                          fases 0/1 (adopter-owned, fuera de SYNC — PRD 0005 §6)
tools/verify.conf · scripts/agent-hooks/post-edit-verify.sh · tools/mutation-score.sh · ci/
                                        ← el cableado real que la fase 2 cierra o declara PENDIENTE (§5b)
AGENTS.md                               ← §2 y §3 dejan de ser FILL; §11 acompaña a la poda del conf
docs/process/current_execution_map.md   ← su línea sobre este PRD se corrige junto con el Approved
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```text
tools/lib/scope.sh · la superficie      ← PRD 0006, On hold
ratchets                                ← §9
PRDs 0001-0006                          ← histórico
```

> El módulo de referencia NO está aquí: la fase 1 manda escribirlo (con aceptación del owner por
> archivo — §4). Ponerlo en NO-TOUCH hacía que el `reviewer` bloqueara el diff de la propia fase.

## 5b. Fases entregables

> La fase 1 va partida en 1a/1b/1c (decisión del owner 2026-08-25): la regla de tamaño del
> `_template.md` §5b —"si una fase toca red + dominio + UI a la vez, son DOS"— aplica con más
> razón al diff que se convierte en patrón, y el coste de no partir está medido (`f-15089319`).
> El flujo de commit que `/arrancar` documenta CITA el flujo canónico del mapa en vez de copiarlo
> (tercera copia = drift); el orden interno de ese flujo tiene hoy `f-f0f40763` abierto y se
> resuelve allí, no aquí.

| Fase | Entrega (mergeable) | Depende de | Gate de cierre | Responsable |
|---|---|---|---|---|
| 0 | **Decisiones.** Entrevista sobre las puertas de una sola dirección + investigación de lo que caduca (versiones, APIs, SPM propios leídos y documentados). Sale el registro en `docs/process/decisions/` con el porqué, y los pins con fecha. | — | el owner firma el registro y la firma DEJA ARTEFACTO: `ARRANQUE_FASE0=<fecha>` en `tools/project.conf`; lo pendiente está marcado `pending`, no como decidido | owner |
| 1a | **El contrato.** Puerto + modelos request/response + fake, y la suite de conformidad que el fake comparte con el adapter real (`domain/SKILL.md`). | 0 | compila; la suite de conformidad pasa contra el fake | implementador + owner acepta |
| 1b | **La lógica.** Validación y mapeo con TDD contra el fake (rojo-primero por comportamiento). | 1a | tests vistos en rojo primero; verde | implementador + owner acepta |
| 1c | **La vertical completa.** Orquestador + vista + navegación + camino de error. | 1b | compila, sus tests pasan, **`security-reviewer` GREEN o AMBER-atendido** (es authn/PII: el patrón que todos copiarán — decisión del owner 2026-08-25), y el owner lo declara canónico dejando artefacto: `MODULO_REFERENCIA=<ruta>` en `tools/project.conf` | implementador + owner |
| 2 | **Extracción y cableado.** Las skills citan el código real; `layers.conf` ampliado y `skill-matrix.conf` podado (con AGENTS.md §11 en el mismo commit); suite de conformidad de fakes; FILL de `AGENTS.md` cerrados; `verify.conf` con el build+tests REAL del proyecto; `post-edit-verify` con su lint/typecheck. | 1c | **Conjunción** (decisión del owner 2026-08-25): cobertura de decisiones verificada (con `check-decision-coverage.sh` si el freeze ya se levantó; a mano contra el registro si no) **Y** `session-start --report` sin niveles MUDOS entre {0, 1, 3} — o cada nivel que siga mudo declarado como decisión `pending` en el registro, con su disparador. Certificar "listo para delegar" sobre un harness que no compila nada es el pecado de §14.4 | implementador + verificación del adoptante |
| 3 | **La prueba de fuego.** El SEGUNDO módulo lo construye la IA sola con las skills puestas, y se compara contra el de referencia. | 2 | el procedimiento de §9 golden 1 — mecánica primero, juicio después, N=2 | owner |

## 6. Modelo de datos

**El registro de decisión ES un ADR** (decisión del owner 2026-08-25, F1): `docs/process/decisions/`
ya existía con formato ADR y numeración `NNNN-<slug>.md` propia. No se crea una segunda serie: el
README existente se amplía y los campos nuevos son OPCIONALES sobre el formato ADR (Contexto /
Decisión / Alternativas / Consecuencias). Un ADR clásico sin los campos nuevos sigue siendo válido —
así el check no muerde los ADRs históricos (el discriminador es la presencia de `state:`).

```
# Decisión NNNN — <qué se decide>
state: decided | pending        (máquina: ASCII estable, sin acentos — la suite corre en locale C
door: one-way | two-way          y el template se adopta en equipos que no documentan en español)
Decisión: <qué>                 (prosa: el idioma que el adoptante quiera)
Por qué: <el racional, que es lo que evita re-litigarla en 3 meses>
Pendiente-hasta: <disparador, si state: pending>
Referencia: `<ruta>::<símbolo>` o el marcador `// @decision:NNNN` en el código
Caduca: <versión pinneada + fecha de revisión, si aplica — campo INFORMATIVO: hoy nadie emite el
        aviso de caducidad y decirlo es la diferencia entre documentar y fingir (§14.4). Si el
        freeze se levanta, el emisor natural es session-start --report, con N concreto>
```

**`Referencia:` ancla a un SÍMBOLO, no a un número de línea** (F4): una inserción cualquiera por
encima desplazaría todas las citas del registro y dejaría el check en rojo perpetuo — y *"un gate
en rojo perpetuo es peor que un gate ausente"* (`test_secret_scan.sh`). El ancla nombra la cosa
(`Registro/RegistroViewModel.swift::validar(email:)`) o la marca en el código (`// @decision:0003`),
así renombrar o borrar falla y reformatear no. La cita va entre acentos graves por la misma doctrina
de `check-finding-refs.sh`: si un detector puede dispararse con el texto que HABLA de la cosa, no
está mirando la cosa.

El patrón es el de `lesson-detector-link.sh` — toda decisión exige referencia — **con su defecto
conocido comprado a la vista**: ese precedente tiene `f-74be77fe` (high) abierto porque verifica que
el destino EXISTA, no que CUBRA. Aquí igual: el check no puede saber si el símbolo citado de verdad
instancia la decisión — eso lo mira el design-review del módulo, y decirlo es parte del contrato.
Las excepciones se declaran explícitas (patrón `tools/backlog/criteria-link.sh`): un check
ineludible acaba desactivado.

## 7. Flujo de la solución

- Como **owner que arranca un proyecto**, quiero decidir una vez las cosas caras de cambiar, para no
  re-litigarlas en cada tarea ni descubrirlas en el PR 5.
- Como **agente que recibe la primera tarea**, quiero que *"¿dónde va esto?"* tenga respuesta
  consultable —**como en Registro**— en vez de tener que decidirlo con mi criterio.
- Como **owner en el mes 3**, quiero saber por qué se decidió algo, no solo qué se decidió.

### Edge cases

- **Aparece una decisión que la fase 0 no previó.** El agente para y pregunta (§1.4); no inventa
  default. La decisión nueva entra al registro con su referencia.
- **El módulo de referencia tiene que cambiar.** Deja de ser una edición normal, y la defensa tiene
  MECANISMO, no solo prosa (F13): `MODULO_REFERENCIA=<ruta>` vive en `tools/project.conf` y la fase
  2 añade a `skill-matrix.conf` la fila que mapea esa ruta a `architecture/SKILL.md` + el registro
  de decisiones — con eso el `skill-reminder` que YA bloquea exige haber leído la skill y el
  registro antes de tocar el módulo. Reúsa el hook existente: cero gates nuevos. El design-review
  previo al cambio sigue siendo la recomendación — *"recomendación, no bloqueo — y decirlo así es
  la diferencia entre documentar un gate y fingirlo"* (AGENTS.md §11).
- **Un pin caduca.** El registro trae fecha. El aviso automático NO existe hoy (§6, campo
  `Caduca:`): queda como candidato para `session-start --report` cuando el freeze se levante.
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

1. **El criterio de salida, como PROCEDIMIENTO ejecutable** (reescrito en v2 — la versión anterior
   era una afirmación de modelo, que §14.2 prohíbe como veredicto; decisión del owner 2026-08-25):
   - **Objeto:** el diff del módulo nuevo + las decisiones nuevas que haya registrado.
   - **Tarea:** la elige el OWNER, no el agente que va a ser juzgado, y debe cruzar las mismas
     capas con fila en `skill-matrix.conf` que el módulo de referencia.
   - **Capa 1, mecánica y gratis primero (§14.1):** `check-layers.sh` verde + el `skill-reminder`
     habiendo exigido las skills + cobertura de decisiones verificada. Si esto falla, ni se invoca
     al juez.
   - **Capa 2, el juicio:** un **reviewer de CÓDIGO en contexto limpio** — invocación separada del
     hilo que construyó el módulo ("el que escribe nunca es el que aprueba") — cuyo contrato de
     salida gana una línea parseable: `ARCH_DEVIATIONS: <n>`, contando solo desviaciones del
     patrón de referencia (no todo hallazgo). El archivo del agente que lo emita entra a §5 cuando
     la fase 3 se implemente.
   - **Criterio:** `ARCH_DEVIATIONS: 0` en **DOS módulos consecutivos** (Q5 resuelta: N=1 sobre un
     instrumento de varianza medida 4.0–9.0 es suerte, no señal).
   - Si el juez encuentra que la validación acabó en el sitio equivocado o que se inventó un
     patrón, **no es fallo del agente: es un agujero de la fase 2**, y se vuelve a ella.
2. Una decisión `decidida` sin `Referencia:` válida hace fallar `check-decision-coverage.sh`.
3. Una decisión marcada `PENDIENTE` **no** lo hace fallar (guard de falso positivo: lo pendiente es
   un estado legítimo, no una omisión).
4. Editar un ViewModel sin haber leído la skill de arquitectura lo **bloquea** el hook — o sea, la
   fase 2 cableó `skill-matrix.conf` de verdad y no solo escribió prosa.
5. Preguntado por algo que la fase 0 marcó pendiente, el agente **para y pregunta** en vez de
   elegir un default.
6. Una skill que cita `` `<ruta>::<símbolo>` `` (o `@decision:NNNN`) que ya no existe en el módulo
   **falla el check**. Y el guard de falso positivo: una skill que solo *menciona* el módulo en
   prosa, sin ancla entre acentos graves, no falla. (Anclas por símbolo, no por línea — §6.)
7. Cada capa con fila en `skill-matrix.conf` **ya podado al stack real** (la poda es entrega de la
   fase 2 — contra el conf multistack del template este golden sería insatisfacible por
   construcción) tiene al menos una cita al módulo de referencia. Una capa con skill y sin
   referencia es un agujero declarado, no un descubrimiento del mes 3.
8. El módulo de referencia no contiene secretos ni escribe PII en logs, verificado con el escaneo
   que ya existe (gitleaks + `security-reviewer` del gate de 1c) — es el módulo que todos copiarán.

> Los goldens 2, 3, 6 y 7 los cubre UN detector (`check-decision-coverage.sh`, §5), condicionado al
> freeze. Hasta que exista, la fase 2 los verifica a mano contra el registro — y esa verificación
> manual se declara como tal en el cierre de la fase, no se presenta como mecánica.

## 10. Métricas de éxito

- **Desviaciones de arquitectura** que el `design-reviewer` encuentra en el módulo N: debe **bajar**
  con N. Si el tercero tiene tantas como el segundo, las skills no están sirviendo.
- **Preguntas del agente que la doc no responde**, por módulo: cada una es un agujero de fase 2 y se
  cierra ahí, no se resuelve improvisando.
- **Tiempo hasta la primera tarea delegable.** Se mide una vez para saber cuánto cuesta de verdad
  este arranque, y **se anota en el change log de este PRD** (§17) — una medición N=1 sin registro
  es una anécdota.

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
  arquitectura. Mitigación con mecanismo (F13): la fila de `skill-matrix.conf` sobre
  `MODULO_REFERENCIA` hace que el `skill-reminder` existente bloquee editarlo sin haber leído la
  skill y el registro; el design-review previo queda como recomendación declarada como tal.
- **Riesgo heredado del patrón de `Referencia:`** (F4): el precedente que copiamos
  (`lesson-detector-link.sh`) tiene `f-74be77fe` abierto — el check verifica que el ancla EXISTA,
  no que CUBRA la decisión. La cobertura semántica la mira el design-review del módulo; el check
  solo garantiza que la cita no apunte al vacío.

## 13. Open Questions

- [x] **Q1 — ¿`check-decision-coverage.sh` cuenta como "gate nuevo" bajo el freeze de WF-09?**
      RESUELTA 2026-08-25 por el owner, y el design-review zanjó la parte mecánica: **SÍ es un
      gate** — el glob de `test_meta_fp.sh` clasifica como detector todo `tools/check-*.sh`, así
      que "no es un gate" era falso por construcción. Decisión: **espera al levantamiento del
      freeze**; las fases 0–1 no lo necesitan y la fase 2 lo entrega condicionado (§5).
- [x] **Q2 — ¿Qué módulo es el de referencia?** RESUELTA 2026-08-24 por el owner: **lo elige él**,
      no lo prescribe el template. Prescribir "Registro" no sirve porque hay apps que no lo tienen.
      El criterio no es *qué* módulo sino **qué flujo cruza todas las capas** — algo con
      vista + orquestador + servicio + request/response + API — porque es lo que se va a repetir en
      todos los demás. La herramienta ayuda listando los cruces que el candidato debe contener
      (§7), y el check de cobertura de decisiones dice qué se quedó fuera: con eso el owner decide
      si amplía la vertical, añade una segunda, o declara esas decisiones pendientes.
- [x] **Q3 — ¿El registro de decisiones vive en `docs/process/decisions/` o dentro de la skill?**
      RESUELTA 2026-08-25: separado, y además **es el mismo artefacto que los ADRs existentes**
      (formato ampliado con campos opcionales, una sola numeración — F1). La skill lo cita.
- [ ] **Q4 — Para el adoptante iOS actual, ¿se hace retroactivo?** Elegir un módulo existente como
      referencia es la vía barata, pero puede consagrar deuda ya existente como si fuera el patrón.
- [x] **Q5 — ¿Cuántos módulos autónomos hacen falta para declarar la autonomía?** RESUELTA
      2026-08-25: **dos consecutivos** con `ARCH_DEVIATIONS: 0` (§9 golden 1 ya lo dice igual —
      antes este doc decía dos cosas distintas sobre su propio criterio de salida).
- [x] **Q7 — ¿Quién juzga la prueba de fuego y con qué contrato?** RESUELTA 2026-08-25: mecánica
      primero, luego reviewer de código en contexto limpio con línea parseable `ARCH_DEVIATIONS:`
      (§9 golden 1). Ni el design-reviewer actual (contrato de PRDs) ni el juicio a mano.
- [x] **Q8 — ¿Puede cerrar la fase 2 con niveles de la pirámide mudos?** RESUELTA 2026-08-25: no,
      salvo declarados como decisión `pending` con disparador (§5b, gate de conjunción).
- [x] **Q9 — ¿Qué pasa con `/adoptar`?** RESUELTA 2026-08-25: stub de redirección;
      `docs/ADOPTION.md` §4 sigue mandando sobre el orden de relleno y `/arrancar` lo cita.
- [x] **Q10 — ¿La fase 1 se parte?** RESUELTA 2026-08-25: sí — 1a contrato, 1b lógica, 1c
      vertical (§5b), con `security-reviewer` en el gate de 1c.
- [ ] **Q6 — ¿Cuál es el techo de intentos de la prueba de fuego?** Se propone **tres**: a partir
      de ahí, en vez de seguir puliendo skills, hay que decidir si el problema es la doc o si esa
      parte de la arquitectura simplemente no se delega (§7, edge cases).

## 15. Definition of Done

- [ ] **Todos** los escenarios golden de §9 pasan. (Sin número: §9 crece, y un conteo aquí caduca
      solo — es literalmente `f-wf02-mapa-cifras-podridas`, cazado por el reviewer en este PRD.)
- [ ] El registro de decisiones existe, con el porqué y con las pendientes marcadas.
- [ ] El módulo de referencia compila, sus tests pasan (TDD: rojo-primero en 1b) y **toda decisión
      de puerta única cita su ancla** dentro de él (§6: símbolo o marcador, no línea).
- [ ] `security-reviewer` GREEN o AMBER-atendido sobre el módulo de referencia (gate de 1c) y
      gitleaks limpio sobre sus commits.
- [ ] `skill-matrix.conf` (podado, con AGENTS.md §11 al día) y `layers.conf` (ampliado) reflejan la
      arquitectura real, y el hook bloquea (golden 4).
- [ ] Los `<!-- FILL -->` de `AGENTS.md` §2 y §3 cerrados; `verify.conf` con el build+tests real.
- [ ] Cero referencias vivas a `/adoptar` fuera de change logs y del stub — verificable con
      `grep -rn "/adoptar" --include="*.md" .`
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
| 2026-08-25 | **v2 tras el design-review (RED, 15 hallazgos — reporte en `.agents/state/reviews/e3b0c44298fc-design-reviewer.md`)**, con las 8 decisiones del owner del mismo día: registro=ADR ampliado (F1) · criterio de autonomía como procedimiento con `ARCH_DEVIATIONS:` parseable, contexto limpio y N=2 (F2) · el detector reconocido como gate y condicionado al freeze (F3) · ancla por símbolo, no línea (F4) · gate de fase 2 en conjunción con la pirámide (F5) · `/adoptar` a stub con ADOPTION.md §4 al mando (F6) · `security-reviewer` en el gate de 1c (F7) · columna Responsable + firmas con artefacto en `project.conf` (F8) · NO-TOUCH corregido (F9) · fase 1 partida en 1a/1b/1c (F10) · layers se amplía / matrix se poda con §11 (F11) · campos de máquina en ASCII (F12) · mitigación de envejecimiento con mecanismo (F13) · `Caduca:` declarado informativo y §10 con registro (F14) · el flujo de commit se cita, no se copia (F15). **Status: Approved ACOTADO a fases 0–1 por el owner; fases 2–3 en Draft hasta re-review de esta v2** | agente del template + owner |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._ Uno ya identificado: la tentación al escribir esto fue documentar la arquitectura del
owner como la canónica del template. Se resistió (§8) porque el template se adopta en iOS, Android,
web y backend — pero es una tensión real y volverá cada vez que alguien pida "más ejemplos".
