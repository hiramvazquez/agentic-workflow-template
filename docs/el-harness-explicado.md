# El harness, explicado

> **Qué es este documento.** Una explicación completa y honesta del workflow agéntico de este
> repositorio, escrita para una audiencia mixta —dirección, programadores, PMs— que debe
> responder una pregunta concreta: **¿esto es digno de usarse en proyectos empresariales para
> apoyarnos en la IA, o está todavía muy verde?** Las dos mitades de la respuesta están aquí,
> con ejemplos reales. Es una **fotografía al 2026-08-25**: las cifras citadas son de ese día
> y caducan; las vivas las imprimen las propias herramientas del repo.

---

## 1. Qué es (y qué no es)

Esto **no** es un modelo de IA, ni un plugin, ni un asistente. Es un **harness** (un arnés):
la estructura de proceso, permisos y verificación mecánica que rodea a un agente de IA
—Claude Code, Cursor, Codex o el que sea— para que el código que produce llegue a `main`
**con evidencia, no con confianza**.

La analogía más corta: un asistente de IA sin harness es un desarrollador junior brillante,
rapidísimo y con exceso de confianza al que le das acceso directo a `main`. El harness es
todo lo que un equipo serio pondría alrededor de esa persona: revisión obligatoria,
tests que no puede saltarse, permisos que no puede escalar, un registro de sus errores
y un mecanismo para que cada error cometido una vez sea imposible la segunda.

La pieza incómoda y central: **el harness desconfía del propio agente que lo usa**. No por
malicia — porque un modelo de lenguaje *afirma* con la misma fluidez lo verificado y lo no
verificado. Todo el diseño se deriva de ahí.

## 2. El problema que ataca, con ejemplos

Cualquiera que haya usado IA para programar en serio reconoce estas cuatro escenas:

**Escena 1 — el código plausible.** Le pides un modelo de Login. Te da algo que compila,
tiene buena pinta y está mal *para tu proyecto*: la validación quedó en la vista, cuando en
tu arquitectura vive en el dominio. Nadie lo decidió: el agente rellenó el hueco con el
criterio de su entrenamiento. El error aparece dos PRs después, ya copiado en tres sitios.

**Escena 2 — la afirmación sin evidencia.** El agente dice "los tests pasan" o "esto está
cubierto por el test X". A veces es verdad. A veces el test no existe, o pasa con cualquier
implementación. En este mismo repo, un informe afirmó que una división de código estaba
"verificada" citando un test **que no cubría lo que la frase decía** — lo cazó una revisión
posterior, y hoy hay una regla mecánica: *toda afirmación de cobertura es un test*.

**Escena 3 — el hallazgo que se evapora.** Durante una tarea, el agente nota un problema
("ojo, este endpoint no valida el input"). Lo menciona en el chat… y el chat se pierde. Dos
semanas después nadie lo recuerda. El harness lo convierte en regla: **detectar no basta —
cada hallazgo se registra en un ledger y llega a estado terminal** (arreglado, aceptado
con razón escrita, o descartado con razón escrita).

**Escena 4 — el gate que se finge.** Un documento dice "todo commit pasa por revisión".
¿Seguro? ¿Quién lo impide mecánicamente? En la mayoría de los equipos, nada: es prosa. La
doctrina de este harness: **anunciar una defensa que no existe es el único pecado
imperdonable** — cada regla o tiene un mecanismo que la hace cumplir, o dice explícitamente
que es una recomendación.

## 3. Las dos reglas que gobiernan todo lo demás

1. **Caza el defecto en la capa más barata.** Cada nivel que un defecto sube sin detectarse
   multiplica ~10× su coste. Un error de tipos que llega a la revisión humana no es un error
   del agente: es un fallo de diseño del sistema de verificación. Corolario: el compilador
   en modo estricto es el primer revisor, y el único que no se cansa.

2. **El que escribe nunca es el que aprueba — y "aprobar" es presentar evidencia.** Un
   veredicto es la salida de un comando, un exit code o un score. **Nunca** la afirmación
   del modelo. De aquí sale el detalle más característico del harness: cuando el agente
   revisor emite su veredicto, el marcador de "revisado" **no lo escribe el modelo — lo
   deriva el sistema** (un hook) del texto real del veredicto, y queda ligado
   criptográficamente (`sha256`) al diff exacto que se revisó. Un marcador escrito a mano
   se rechaza. Si cambias una línea después de la revisión, el marcador deja de valer.

## 4. La arquitectura de defensa: cuatro anillos

Pensad en anillos concéntricos alrededor del código. Cada uno cubre lo que el anterior no puede.

**Anillo 0 — Permisos nativos (lo que la IA no puede hacer, ni queriendo).**
`git push --force`, `git commit --amend`, `--no-verify`, leer `.env`, editar los trinquetes
de calidad: **denegados a nivel de plataforma**, no dependen de que el modelo "se porte
bien". Es la diferencia entre "el agente no se equivocará" y "el agente no podrá".

**Anillo 1 — Git hooks clásicos (cubren a humanos y a cualquier herramienta).**
En cada commit: escaneo de secretos (gitleaks), validación de capas arquitectónicas,
marcadores de conflicto, los marcadores de review y de verificación, y el trinquete de
drift. En cada push: la suite completa del harness — *antes* de publicar, porque un CI que
corre después de publicar no es un gate, es una alarma.

**Anillo 2 — Hooks del agente (defensa en vivo, mientras trabaja).**
Esto es lo que no existe en un setup normal de IA:
- *Antes de editar un archivo*, un hook **bloquea** la edición si el agente no leyó la
  documentación del área (la "skill") que aplica a ese archivo. No es una sugerencia: el
  edit falla.
- *Antes de cada commit*, otro hook exige que exista revisión válida ligada a ese diff
  exacto, y que una ejecución verde de build+tests haya firmado ese mismo diff.
- *Después de cada edición*, lint y typecheck del archivo tocado vuelven al agente como
  señal inmediata (el bucle "in-loop").
- *Al terminar la sesión*, un gate bloquea si se introdujeron violaciones nuevas.

**Anillo 3 — CI (el backstop que no depende de la máquina de nadie).**
La misma suite y los mismos gates, en un servidor neutral, en otro sistema operativo. Su
papel es filosófico además de práctico: los gates locales *avisan* en algunos fallos de
entorno (para no bloquear el trabajo por un scanner roto), y ese "fail-open local" **solo
es aceptable porque el CI existe como bloqueo final**. Más abajo veréis qué pasó cuando
esa premisa falló — es uno de los mejores ejemplos de honestidad del sistema.

## 5. La pirámide de verificación (niveles 0–9)

Dentro de los anillos, la verificación se organiza por coste: lo barato y determinista
primero, lo caro y probabilístico al final.

| Nivel | Qué es | Ejemplo concreto |
|---|---|---|
| 0 | **Imposibilitar por tipos** | Un estado inválido que no se puede expresar no se escribe. Swift 6 estricto / TS `strict`. |
| 1 | **Lint/typecheck in-loop** | El agente recibe el error a los segundos de editar, no en el commit. |
| 2 | **Patrones AST (Semgrep)** | "Nunca `try!` en producción" como regla sintáctica real, no como grep — la *ley del 10%*: un detector con >10% de falsos positivos se descarta, porque se aprende a ignorar (y un agente aprende a evadirlo). |
| 3 | **TDD + contratos** | Ninguna lógica nueva sin un test que falló primero. Bug = primero el test que lo reproduce. |
| 4 | **Calidad del test (mutación)** | ¿Este test fallaría si rompo el código que dice cubrir? El "mutation score" lo responde mecánicamente. **Hoy este nivel está mudo** — ver §11. |
| 5 | **Contratos fake ≡ real** | Todo fake de repositorio pasa la misma suite de conformidad que el adapter real. |
| 6 | **Arquitectura mecánica** | Las capas se validan con un checker de imports, no con un diagrama en Confluence. |
| 7 | **Review adversarial de IA** | Sub-agentes revisores independientes, con contexto limpio (§7). |
| 8 | **Gate por evidencia** | El cierre lo decide la evidencia presentada, no la sensación de terminado. |
| 9 | **Métricas + lección→detector** | Cada lección aprendida se convierte en detector mecánico (§8). |

## 6. El viaje de un cambio, narrado

Así se ve una tarea real de principio a fin:

1. **El agente arranca la sesión** y recibe automáticamente: el estado del proyecto, los
   hallazgos abiertos de su área, y las reglas. Si el contexto se compacta a mitad de
   sesión, un hook reinyecta el digest — el agente no "olvida" las reglas.
2. **Toca un archivo de dominio** → el hook exige que haya leído la skill de dominio y la
   guía de TDD. Si no, el edit se bloquea con el mensaje de qué leer.
3. **Escribe el test primero**, lo ve fallar, implementa, ve verde. Cada edición le
   devuelve lint/typecheck al instante.
4. **Prepara el commit**: stagea por paths explícitos (`git add -A` a ciegas está
   prohibido), y un comando le avisa si el lote mezcla naturalezas (código + docs +
   tooling) — los lotes mezclados son los que más rondas de review queman.
5. **Corre `verify-run`**: ejecuta EL comando de build+tests del proyecto y, solo si sale
   verde, firma el diff staged. Sin esa firma, el commit se rechaza: **es imposible
   commitear un árbol que nadie compiló**.
6. **Invoca al `reviewer`** — otro agente, contexto limpio, sin el sesgo de haber escrito
   el código. Este emite `VERDICT: GREEN|AMBER|RED` y el *sistema* deriva el marcador. Si
   el veredicto es RED, hay lista concreta de qué arreglar, y el ciclo se repite sobre el
   diff corregido.
7. **Commit** — los nueve gates del Anillo 1 corren. **Push** solo con aprobación explícita
   del dueño, y el pre-push corre la suite completa antes de que nada salga de la máquina.
8. Lo que el agente detectó por el camino y no era suyo → **al ledger**, no al olvido.

La fricción es real y está a la vista: la suite en pre-push cuesta ~4 minutos, y un commit
de código exige review. Es el precio del diseño; se paga a propósito.

## 7. Los revisores especializados, y lo que miden los datos

El harness trae cinco agentes con roles separados — y aquí está uno de los resultados más
interesantes del proyecto, porque se midió (informe de 2026-08-24, sobre 127 hallazgos
históricos):

| Agente | Rol | Rendimiento medido |
|---|---|---|
| `design-reviewer` | Revisa el **CÓMO** de un diseño ANTES de escribir código | **4–9 hallazgos por invocación** — el mayor del sistema, y era el menos usado |
| Jueces adversariales | Se les pide **refutar**, no revisar — para la maquinaria crítica | 3.3 por invocación; encontraron en una pasada lo que 8 rondas de review normal no vieron |
| `reviewer` | La red de seguridad de cada commit | 0.84 por invocación / 1.5 por diff — el volumen |
| `security-reviewer` | Lo que un scanner de secretos no ve: PII en logs, authz faltante | — |
| `process-judge` | Único que lee **CÓMO se trabajó** (la trayectoria), no solo el diff | Su primera pasada real destapó que el 95% del trabajo de una sesión entraba por un canal que el nivel 1 no vigilaba |

La conclusión del informe cabe en una frase y es aplicable a cualquier equipo: **las
defensas que mejor rinden —revisar el diseño antes de escribir, y pedir refutación sobre lo
crítico— son las que menos se usan, mientras el volumen se lo lleva la más cara por ronda.**

## 8. El bucle que hace decrecer la revisión humana

Esta es la apuesta de fondo, y lo que distingue el harness de una lista de buenas prácticas:

- **Toda lección aprendida exige un campo `Detector:`** — el mecanismo que la hace
  imposible de repetir. Sin detector, una lección es prosa que nadie relee. Un verificador
  en CI comprueba que cada detector citado *existe de verdad* (aprendieron por las malas
  que se puede citar un test que no existe — y ahora eso también se verifica).
- Cuando el detector es un test que corre en CI, la lección **se archiva sola**: ya no hace
  falta leerla, porque una máquina la garantiza. El contexto que el agente carga por
  defecto se mantiene acotado por un test (hoy: 112 lecciones, todas con detector o con
  excepción declarada).
- **Los trinquetes solo giran en una dirección.** El contador de errores/warnings solo
  puede bajar; el mutation score solo puede subir. Ningún override los relaja — el
  override de emergencia existe para el marcador de review (juicio humano), nunca para un
  detector mecánico. Un número que se puede aflojar no es un trinquete: es una sugerencia.
- **"El que toca, cierra lo que bloquea":** si tocas un módulo con hallazgos abiertos, los `high`
  de tu scope los arreglas en el mismo cambio; el resto se registra y no bloquea. "No es mío, lo
  dejo" sigue prohibido —todo queda en el ledger—, pero registrar no es arreglar: la versión que no
  distinguía severidad convertía cada ronda de review en más trabajo bloqueante, y el ledger
  divergió durante tres semanas por eso (§10).

Este bucle es el único mecanismo conocido por el que la necesidad de revisión humana
**decrece** con el tiempo en vez de mantenerse plana.

## 9. Un día real con el harness (2026-08-25)

Nada explica mejor el sistema que verlo funcionar contra su propio autor. Todo esto pasó
el mismo día, documentado en commits:

- **El test que defendió una promesa.** Se decidió reducir la matriz de CI (quitar la pata
  macOS por coste). El agente hizo el cambio… y un test lo puso en ROJO: existe un test que
  **lee el workflow real** y falla si la promesa "corremos en dos plataformas" deja de ser
  código. Hubo que actualizar el contrato *en el mismo commit*, con tres mutantes
  demostrando que el test nuevo sigue defendiendo algo. La promesa nunca quedó en prosa.
- **El id fantasma.** El agente escribió en un mensaje de commit el identificador de un
  hallazgo **de memoria**, y era incorrecto. Ningún gate lee mensajes de commit (hoy), así
  que pasó. Se detectó al releer, se anotó una fe de erratas en el ledger *(el `--amend`
  está denegado — la historia no se reescribe)*, y el juez de proceso propuso el detector
  que faltaba. La clase de error ("afirmar sin releer la fuente") ya tenía lección escrita
  — y reincidió igualmente. Moraleja del sistema, no del agente: **la defensa no puede ser
  recordar la lección; tiene que ser un mecanismo.**
- **El design-reviewer pagó su fama.** Un PRD importante (el protocolo de arranque de
  proyectos nuevos) pasó por design-review antes de aprobar: **RED, 15 hallazgos** — tres
  bloqueantes, incluido que su criterio central de éxito no era medible tal y como estaba
  escrito, y que una afirmación del mapa del proyecto ("esto no es un gate") era
  mecánicamente falsa. Dos rondas después quedó aprobado. Coste: unas horas de revisión.
  Ahorro: semanas de construir sobre un criterio de éxito que no se podía medir.
- **El backstop caído que nadie declaraba.** Al hacer push se descubrió que el CI llevaba
  una semana sin ejecutarse (presupuesto de GitHub Actions agotado) — y que el verificador
  del Anillo 3 validaba que la *configuración* existiera, no que el CI *ejecutara*. Quedó
  registrado como hallazgo high con su fix propuesto. El sistema no evitó el problema:
  **lo hizo visible, con evidencia, el mismo día** — que es exactamente su trabajo.

## 10. ¿En qué se diferencia de "usar Copilot/Cursor y ya"?

| | IA "a pelo" | Con este harness |
|---|---|---|
| ¿Quién aprueba el código? | El mismo que lo escribió (el agente, o tú con prisa) | Un revisor independiente + evidencia mecánica ligada al diff |
| "Los tests pasan" | Una frase del modelo | Una firma criptográfica sobre el diff, emitida solo tras una corrida verde real |
| Reglas del proyecto | En un README que el agente puede ignorar | Bloqueos en vivo: sin leer la doc del área, el edit falla |
| Errores repetidos | Se repiten | Lección → detector mecánico → imposible la segunda vez |
| Hallazgos sueltos | Se evaporan en el chat | Ledger con estados terminales y ownership |
| Calidad de los tests | Se asume | Mutation score con piso que solo sube *(hoy mudo — §11)* |
| Deuda de calidad | Crece en silencio | Trinquetes de una sola dirección |
| ¿Qué puede romper el agente? | Todo lo que tu usuario pueda | `--force`, `--amend`, secretos, trinquetes: denegados nativamente |

## 11. Lo que sigue verde (léase antes de decidir)

Esta sección existe porque el documento la necesita para ser creíble. En orden de importancia:

1. **El nivel 4 (mutation testing) está MUDO.** El score es 0 y nunca ha medido. Hoy,
   nada mecánico distingue un test real de uno decorativo — lo cubre el revisor, que es
   justo la capa cara. El propio reglamento declara al mutation score "el árbitro" de la
   calidad de tests: mientras no mida, esa frase es prosa (y está registrada como tal).
2. **El template llega sin stack cableado, a propósito.** Build, tests, lint del proyecto
   concreto son huecos `FILL` que el arranque rellena. Hasta entonces, el nivel 1 es
   parcial y `verify-run` verifica el harness, no tu producto. El protocolo de arranque
   (PRD 0007, aprobado el 25-08) existe exactamente para esto — pero **se aprobó ayer y no
   se ha ejecutado nunca contra un proyecto real**. Su criterio de autonomía es falsable
   (un juez con salida parseable, dos módulos consecutivos limpios), pero aún no tiene ni
   una corrida.
3. **El Anillo 3 estuvo caído una semana sin que nadie lo declarara** (presupuesto de
   Actions), y el razonamiento fail-open local dependía de él. Se detectó, se registró y
   se mitigó — pero demuestra que el backstop puede caerse en silencio, y el detector de
   esa caída es hoy un fix propuesto, no implementado.
4. **Las mediciones tienen muestras pequeñas.** El 4–9 del design-reviewer viene de n=3
   invocaciones; los jueces, de n=3. La telemetría de los gates mecánicos empezó a
   acumular el 24-08 (antes, los bloqueos no dejaban rastro — el instrumento estaba roto y
   se descubrió al intentar medir). La regla del proyecto: 2–4 semanas de datos antes de
   retirar o endurecer nada.
5. **Un solo adoptante real** (un proyecto iOS/Swift 6) ha usado el harness en producción.
   Su bucle funciona —25 hallazgos reportados a coste cero— pero un n=1 de adopción es un
   n=1.
6. **El coste es real.** Review por commit, suite completa en cada push (~4 min), consumo
   de tokens de los sub-agentes revisores (una sesión intensa quema millones), y una curva
   de aprendizaje: el flujo stagea→verifica→revisa→commitea tiene que volverse hábito.
7. **El propio proyecto está en fase de digestión.** Hay un freeze de gates nuevos vigente
   porque en agosto el ledger abría 2–3× más hallazgos de los que cerraba: el proyecto
   pasó de construir a auditar, y la decisión fue cerrar y medir antes de seguir
   añadiendo. Hay 41 hallazgos abiertos hoy — la lista es pública dentro del repo, con
   dueño y estado. Que se vea es una feature; que existan es trabajo pendiente.
8. **Fricción menor conocida:** un test intermitente en macOS (raro, ~3% observado,
   registrado y acotado), y detectores de texto que ya fallaron y se están migrando a
   parsers reales — con la política explícita de que un detector ruidoso se descarta.

## 12. ¿Es digno de uso empresarial? El criterio, no la respuesta

La respuesta honesta es **"sí, condicionado — y el condicionante es vuestro, no del
harness"**. Los criterios para decidirlo:

**Úsalo si:**
- El equipo ya cree en CI, code review y tests — el harness *mecaniza* esa cultura para
  la IA; no puede instalarla donde no existe.
- Hay un dueño con criterio técnico dispuesto a jugar su rol: aprobar PRDs, decidir
  arquitectura (fase 0 del arranque), y revisar lo que los gates escalen.
- El proyecto es nuevo, o tiene un módulo que pueda servir de patrón de referencia.
- Aceptáis el coste de fricción del §11.6 a cambio de trazabilidad total: cada commit con
  su review firmada, cada hallazgo con su estado, cada lección con su detector.

**Todavía no, si:**
- Esperáis "IA autónoma sin supervisión desde el día 1". El harness tiene un criterio
  medible de cuándo delegar (y su valor por defecto es *todavía no*): la IA trabaja sola
  cuando dos módulos consecutivos salen sin desviaciones de arquitectura, juzgados por un
  revisor independiente con salida parseable. Antes de eso, es trabajo asistido con gates.
- Nadie va a rellenar el stack (§11.2) — un harness sin cablear avisa de que está sin
  cablear, pero no verifica vuestro producto.
- El equipo ve el review y los tests como burocracia. El harness les dará la razón:
  bloqueará, y lo vivirán como fricción sin entender qué compra.

**La prueba barata que recomienda este documento:** no decidir en abstracto. Ejecutar el
protocolo de arranque (fases 0–1: decidir arquitectura + construir el módulo de referencia
con el dueño) sobre **un** proyecto piloto, medir el tiempo real hasta la primera tarea
delegable —el propio protocolo exige anotarlo— y decidir con ese dato. Si el piloto no
justifica el coste, lo sabréis en semanas y con evidencia, que es exactamente como este
sistema toma todas sus decisiones.

## 13. La fotografía en cifras (2026-08-25)

- **644 tests** verifican el propio harness (la suite corre en cada push, en ~4 min).
- **166 hallazgos** históricos en el ledger; **41 abiertos**, todos con área y estado.
- **112 lecciones**, cada una con detector mecánico o excepción declarada y justificada.
- **9 gates** en cada commit; push solo con aprobación explícita del dueño.
- **5 agentes revisores** especializados; el marcador de review lo firma el sistema, nunca
  el modelo.
- **2 trinquetes** de una sola dirección (drift ↓ · mutation ↑ — el segundo, aún en 0).
- **1 adoptante real** en producción (iOS/Swift 6), fuente de 25 hallazgos a coste cero.
- **1 protocolo de arranque** (PRD 0007) aprobado tras dos rondas de design-review (RED de
  15 hallazgos → AMBER de 13 → aprobado), pendiente de su primera ejecución real.

## Glosario mínimo

- **Harness**: el conjunto de permisos, hooks, gates y agentes que rodea al asistente de IA.
- **Gate**: verificación que bloquea (no avisa) cuando falla.
- **Hook**: código que se ejecuta automáticamente en un evento (editar, commitear, terminar).
- **Marker**: evidencia firmada de que algo ocurrió (una review, una corrida verde) ligada
  por hash al diff exacto sobre el que ocurrió.
- **Trinquete (ratchet)**: métrica que solo puede moverse en la dirección buena.
- **Ledger**: registro versionado de hallazgos con estado terminal obligatorio.
- **Skill**: documentación operativa de un área que el agente debe leer antes de tocarla
  (y un hook lo hace obligatorio).
- **Mutation testing**: romper el código a propósito para comprobar que los tests lo notan.
- **Fail-open / fail-closed**: si la herramienta de verificación falla, ¿deja pasar o
  bloquea? Local avisa, CI bloquea — y por eso el CI no puede estar caído en silencio.

---

*Documento generado el 2026-08-25 sobre el estado real del repositorio. Las afirmaciones
sobre mecanismos son verificables en el código; las cifras son la foto de ese día. Si algo
de aquí contradice al repo, manda el repo — y el hallazgo va al ledger.*
