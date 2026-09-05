# Validación externa del bucle de verificación — 5 de septiembre de 2026

> Revisión del harness hecha **desde fuera**, durante una sesión real de trabajo en
> `spm-pro` (los paquetes `AppFoundation` y `CoreNetworking` que este template va a
> consumir). No es un estudio bibliográfico: es qué pasó al aplicar, sin saberlo de
> antemano, los mismos niveles que describe `verification-loop.md`.
>
> **Peso de la evidencia.** Todo lo que aquí se afirma sobre `spm-pro` es **primario**:
> medido ese día, en ese repositorio, con el comando que lo reproduce. Todo lo que se
> afirma sobre este harness sale de leer `AGENTS.md`, `verification-loop.md`,
> `tools/` y `tools/tests/` — es lectura, no ejecución. Ninguna cifra de este informe
> describe el estado de este repo hoy.
>
> **Clasificación**, con el contrato de exit codes de `AGENTS.md` §14.3, que es la vara
> con la que este harness mide todo lo demás: `0` lo tenemos y lo demuestra · `1` lo
> tenemos y falla · `3` no podemos ni mirar.

---

## Por qué esta sesión sirve como validación

Una jornada de trabajo sobre dos paquetes Swift, con nueve sub-agentes, cinco huecos de
seguridad cerrados y cinco bugs corregidos en código ya publicado. El harness **no
estaba instalado**: las reglas se aplicaron por criterio, no por hooks.

Eso la convierte en un experimento útil. Donde el criterio bastó, el nivel es opcional.
Donde el criterio falló, el nivel es necesario — y **falló exactamente en los sitios que
la pirámide predice**.

---

## Lo que la sesión confirmó

### Nivel 0 — el detector que no hizo falta escribir

`APIService.performOnce` tenía un `guard let httpResponse = response as? HTTPURLResponse`
con su rama de error, su código público `.invalidResponse` y su notificación a los
interceptores. Inalcanzable: `HTTPTransport.send` declara `-> (Data, HTTPURLResponse)`,
así que ningún transporte conforme puede entregar otra cosa.

Se estrechó el tipo del closure interno y el `guard` desapareció — no borrado por
criterio, sino **porque el compilador prueba que no puede ejecutarse**. Es literalmente
*"antes de escribir un detector para un error, pregúntate si puedes rediseñar el tipo
para que ese error no exista"*.

Detalle que importa: se descubrió **porque un agente intentó escribirle un test y no
pudo**. El nivel 4 destapó una carencia del nivel 0.

### Nivel 4 — cobertura 100 %, verificación 0

`APIError.isRetryable` tenía dos `guard let ... else { return false }` con **100 % de
cobertura de línea** que ningún test verificaba: mutarlos a `return true` no rompía
nada. Nadie construía un error de transporte sin `underlying` ni uno de status sin
respuesta.

La medición completa en `CoreNetworking`, con `swift-mutation-testing`:

| fecha | score | supervivientes |
|---|---|---|
| 2026-09-04 | 62,2 % (79/127) | 39 |
| 2026-09-04 | 76,4 % (120/157) | 19 |
| 2026-09-05 | *(en curso al cerrar este informe)* | 14 |

Reproducible con `swift-mutation-testing .` sobre una copia del paquete.

### Nivel 7 — el sesgo del revisor, confirmado

El aviso de `verification-loop.md` es correcto y se manifestó: los sub-agentes reportan
hallazgos porque se los pides. Hubo que rechazar sobre-ingeniería y tests para casos
imposibles más de una vez. La contramedida que funcionó fue la que ya está escrita en
`AGENTS.md` §13 — *el reviewer reporta solo lo que rompe algo*.

### Nivel 8 — el hallazgo más fuerte de la sesión

**Tres veces** un sub-agente reportó "resuelto" sobre trabajo que seguía roto:

1. Un endpoint marcado sin autenticación seguía filtrando la credencial, porque el
   arreglo cerró la vía del interceptor y dejó abierta la de `defaultHeaders`.
2. El interceptor pasó a tratar un valor ambiental como si fuera intención explícita del
   endpoint, invirtiendo la precedencia útil.
3. Un test afirmaba cubrir la cancelación por `deinit` y pasaba porque el propio test
   cancelaba la tarea a mano.

Las tres se detectaron **ejecutando código**, nunca leyendo el informe. Ninguna se veía
en el diff.

Esto es la justificación empírica de *"el veredicto lo deriva el sistema, no lo emite el
modelo"*. Un harness cuyo gate final sea la palabra del agente habría dado por buenos los
tres.

### Nivel 9 — una lección que era un bug de tooling

La misma instrucción falló **dos veces seguidas** con dos agentes distintos: al medir
mutación, copiaban el árbol **antes** de escribir su trabajo, y medían la línea base
creyendo medir su mejora. Ambos reportaron una subida que no existía.

Por la propia regla del harness, eso no es un fallo del agente: es un bug en la
instrucción. Las dos órdenes eran correctas por separado —"mide sobre una copia, nunca
sobre el repo" y "lánzalo en background y avanza mientras"— y juntas producen el error.

**Corrección mecánica:** copiar y medir **al final**, o medir dos veces sobre dos copias.
Candidata a entrada en `lessons_learned.md` con `Detector:` — un script que compare el
`sha256` del árbol medido contra el del árbol de trabajo cerraría el hueco.

---

## Los huecos

### `3` — G1. El nivel 4 lleva `measured:false`, y ya es resoluble

`mutation-ratchet.json` declara honestamente que nunca se ha medido, y
`verification-loop.md` lo justifica: *"no hay runner para shell"*.

Cierto para el harness. **Pero el código de producto de un proyecto que use este template
no es shell.** En `spm-pro` el ciclo completo quedó operativo el 2026-09-04 y es
portable:

- medición real antes de fijar nada (62,2 %), y el trinquete **por debajo** del valor
  medido, con la holgura justificada por escrito: el score depende de cuántos mutantes
  agotan el `timeout`, y eso depende de la velocidad de la máquina;
- exclusión explícita del código que **ningún test puede ejecutar** (manifiesto,
  snippets de documentación): aportaban 10 mutantes que sobrevivían siempre y diluían el
  score 4,5 puntos;
- job de CI por `schedule` propio + `workflow_dispatch`, nunca en push/PR — 17 minutos no
  caben en el bucle de un PR;
- serie histórica fechada en el propio fichero de configuración.

Un detalle de esa migración, del harness hacia `spm-pro`: **la distinción
`measured:false` ≠ `min_score: 0` es mejor que guardar el umbral en un comentario**, y se
ha portado en sentido inverso. La ausencia de veredicto no puede parecer un suelo. Es la
misma idea de §14.3 aplicada a un fichero de estado.

### `1` — G2. Los mutantes dirigidos los elige quien escribió el test

`AGENTS.md` §5 define el árbitro vigente del nivel 4: romper la línea a mano, comprobar
que el test muere, y **listar en el PR qué mutantes se lanzaron**. El `reviewer` verifica
y busca uno que sobreviva.

El mecanismo es bueno y funcionó en la sesión. Pero **la lista la produce el mismo agente
que escribió el test**, y ahí se rompe el principio del propio harness: *el que escribe
nunca es el que aprueba*. Un agente que prueba tres mutantes fáciles y reporta tres
muertes es indistinguible, desde el PR, de uno que probó los difíciles.

No es teórico: en la sesión, seis supervivientes se descartaron como equivalentes o
inalcanzables. Cinco de los seis argumentos se verificaron con experimentos aislados
—una clase `NSObject` aparte para comprobar que Swift inserta `super.init()` implícito,
un script para confirmar que `resolvingAgainstBaseURL` solo importa con `baseURL != nil`—
y uno se aceptó por analogía. La diferencia entre un argumento y una excusa es
exactamente esa verificación, y no hay nada en el formato del PR que la exija.

**Corrección barata, sin runner:** que el `reviewer` **elija** los mutantes en vez de
verificar la lista. Ve el diff, escoge las líneas que más le preocupan, y pide que se
rompan. Restaura la independencia con el mecanismo que ya existe.

### `3` — G3. El harness no se aplica a sí mismo su propio principio

80 tests para 33 scripts de `tools/` y 14 hooks es una proporción sana, y responde a la
primera pregunta que uno se hace al ver 169 scripts que vigilan calidad ajena.

Pero *"el que escribe nunca es el que aprueba"* no se cumple ahí: el mismo agente que
escribe un detector escribe su test. Y `AGENTS.md` §8 pone `tools/`, `ci/` y
`scripts/agent-hooks/` detrás de aprobación del owner — un gate **humano**, que es
precisamente lo que el sistema existe para reducir.

No es fácil de resolver y quizá no compense. Pero el harness declara con precisión el
límite del nivel 8 y el de `f-marker-spoof`; este merece la misma franqueza en
`verification-loop.md`, aunque sea para decir *"aceptado, y por esto"*.

### `3` — G4. El presupuesto de contexto no está medido

`AGENTS.md` son ~13,8 KB y entran en cada turno, más la parte viva de
`lessons_learned.md`, más `current_execution_map.md`, más la skill del área (§11), más el
PRD relevante (§0).

`AGENTS.md` declara ser *"terso a propósito, porque entra en el contexto de cada turno"*,
con un criterio de concisión que es de lo mejor del documento. Pero **no hay cifra**.
Si un arranque en frío consume el 15-20 % de la ventana, el harness compite con el
trabajo — y en una sesión larga con compactaciones, esa competencia decide qué se pierde.

Es medible con un script y encaja en `tools/metrics/`. Por el propio criterio del sistema,
una regla sin detector se cumple leyéndola; una cifra sin medir no se cumple de ninguna
forma.

---

## Lo que se llevó `spm-pro` de aquí

- La distinción **"no medido" ≠ "medido y da cero"** como estructura de datos, no como
  comentario.
- La disciplina de **romper la línea a propósito** antes de dar un test por bueno. Se
  aplicó a los ~40 tests de interacción escritos en la sesión y encontró dos que pasaban
  con el código roto.
- **Un test que cuelga no es un test que falla.** Corolario nuevo de §14.3 encontrado en
  la sesión: un test sin límite de tiempo, ante la regresión que dice cubrir, se cuelga y
  consume el timeout del job entero sin decir por qué. Se resolvió con `.timeLimit`. Es
  el mismo modo de fallo que *"un gate que no corrió nunca debe parecer un gate que
  pasó"*, un nivel más abajo, y merece una línea en `verification-loop.md`.

---

## Lo que no se revisó

Los tres anillos, `ci/run-gates.sh`, los sub-agentes de `.claude/agents/`, el backlog, las
métricas y los adapters de Cursor/Codex. Este informe cubre `AGENTS.md`,
`verification-loop.md`, los dos ficheros de trinquete y la superficie de `tools/tests/`.

Y la conclusión general, que no cabe en ninguna clasificación: **la honestidad estructural
del harness es su mejor propiedad.** `measured:false` que se niega a escribir un piso
falso, `f-8b74d177` y `f-marker-spoof` abiertos y declarados, y el límite del nivel 8
explicado en vez de vendido. La frase que lo resume ya está escrita en el propio
documento:

> Decir "infalsificable" cuando solo tienes la primera garantía es el mismo fallo que
> anunciar un gate que no está implementado: falsa confianza, que es un modo de fallo, no
> un estado neutro.
