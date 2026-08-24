# PRD — Superficie de enforcement fail-closed, y un criterio de cierre para el harness

> **Tipo:** Forward · **Status:** **On hold** — el owner decidió el 2026-08-24 que el freeze de
> WF-09 SIGUE VIGENTE y se hace cumplir. Este PRD NO se ejecuta hasta que cierre la fase 3 de
> PRD 0005 (medir el valor de cada gate). Las vías 8 y 9 quedan como findings documentados.
> **Autor:** agente del template · **Fecha:** 2026-08-24 · **Tracking:** pendiente
> **Design-review:** OK (2026-08-24) — RED sobre la propuesta original, 9 hallazgos, todos incorporados

---

## 1. Contexto

`tools/lib/scope.sh` decide qué rutas exigen review de código. Su función
`scope_siempre_producto()` existe para que la maquinaria de enforcement no pueda eximirse a sí
misma. **Se quedó corta ocho veces seguidas en una sola sesión** (2026-08-22/24):

| # | Lo que no cubría | Naturaleza |
|---|---|---|
| 1 | `project.conf` leído del árbol y no del índice | dato |
| 2 | `project.conf` bajo `tools/`, que el criterio de app exime | dato |
| 3 | Los propios `check-review-marker.sh` / `check-verify-marker.sh` | implementación |
| 4 | `.claude/agents/reviewer.md`, `.github/workflows/`, `.codex/`, `.cursor/` | cableado |
| 5 | `.gitleaks.toml`, `.semgrepignore` | config |
| 6 | `run-tests.sh`, `lesson-detector-link.sh` | implementación |
| 7 | Gates invocados por `bash "$var"` | fallo del detector |
| 8 | `bash  "$var"` con dos espacios | fallo del detector |

Las rondas 7 y 8 no encontraron agujeros en la superficie: **la superficie no falla desde la
ronda 6.** Encontraron agujeros en el detector construido para vigilarla. Se estaba parcheando al
vigilante.

Y hay una novena instancia, viva y peor que la octava, que el design-review destapó y esta sesión
verificó: bajo criterio de `application`, **`tools/agent-prompts/review.md` está exento**. Editar
ese prompt para que el revisor de IA apruebe siempre degrada el nivel 7 entero y no dispara nada.

## 2. Problema

Dos problemas distintos, y el segundo es el que hace que el primero se repita.

**2.1 — La clasificación es fail-open.** Lo no enumerado queda exento, así que cada ronda tapa el
agujero recién visto y deja abierto el siguiente. No existe criterio de "completa": ocho rondas
demostraron que faltaba algo y ninguna pudo demostrar que ya no falta nada.

**2.2 — El harness dejó de converger y nadie lo estaba midiendo.** Del ledger, hallazgos abiertos
frente a cerrados por día:

| fecha | nuevos | cerrados |
|---|---:|---:|
| 10 ago | 12 | 12 |
| 11 ago | 15 | 13 |
| 12 ago | 34 | 34 |
| 15 ago | 3 | 4 |
| 19 ago | 17 | 11 |
| 21 ago | 8 | 3 |
| 22 ago | 20 | 6 |
| 24 ago | 7 | 5 |

Hasta el 15 de agosto se cerraba lo que se abría. Desde el 19 se abre 2–3× lo que se cierra,
mientras los commits/día caían de 13–17 a 2–3. El proyecto pasó de **construir** a **auditar**, y
auditar un sistema que se audita a sí mismo no tiene final natural: cada defensa nueva es
superficie nueva que auditar.

`PRD 0005 §3` declaró un freeze de gates nuevos exactamente para frenar esto. Desde entonces cada
detector nuevo ha entrado "por la excepción declarada del freeze". **La excepción se comió la
regla, y no había ningún mecanismo que lo hiciera visible.**

## 3. Objetivo

1. Que un archivo nuevo bajo la superficie de enforcement sea producto **sin que nadie lo
   enumere**. Criterio falsable, propuesto por el design-review: un test crea un archivo con
   nombre aleatorio bajo `tools/`, `ci/` y `.claude/agents/` y comprueba que exige review.
2. Que el harness tenga un **criterio de cierre declarado** y una medición de convergencia que se
   imprima sola, para que "¿está listo?" deje de ser una impresión.

## 4. Filosofía / principios

- **Fail-closed dentro de la superficie de enforcement.** La duda sobre un archivo se resuelve
  hacia "exige review", no hacia "exento".
- **La inversión debe RETIRAR mecanismos, no añadirlos.** Si al terminar hay más piezas que
  mantener, se eligió mal. Con fail-closed, `test_los_anillos_no_invocan_gates_por_indireccion`
  deja de tener razón de existir y `_sup_invocadores` baja de gate a informe.
- **Lo que se protege es el cierre transitivo de un gate** — su entry point, sus libs, sus
  prompts, sus backends, sus tests y sus configs — no su punto de entrada.
- **Toda afirmación de cobertura es un test.** Si no puede ser un test, no puede ser una
  afirmación. De los ocho fallos de la sesión, cuatro fueron comentarios que afirmaban más de lo
  que el código hacía.

## 5. Estructura de archivos a crear / tocar

```
tools/lib/scope.sh          ← inversión a fail-closed; retirada de la ERE de formas
tools/project.conf          ← clave `scope_exempt:` (el adoptante SOLO añade exenciones)
tools/tests/test_scope_kind.sh        ← los golden de §9
tools/tests/test_scope_superficie.sh  ← `_sup_invocadores` baja a informe; se retira la regla
                                         anti-indirección si la inversión la deja sin objeto
scripts/agent-hooks/session-start.sh  ← imprime nº de exenciones del adoptante y convergencia
docs/process/current_execution_map.md ← estado
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```text
lefthook.yml            ← congelado para adoptantes por copia (finding propio). Cualquier diseño
                          que asuma "lo cambio y llega" es falso HOY. Se arregla en su propio PRD,
                          no de paso.
tools/upgrade.sh        ← SYNC_PATHS y _es_maquinaria son ENTRADA de §13-Q2, no material a editar
ratchets                ← §9: solo los mueve su script
ci/run-gates.sh         ← el manifiesto de gates es OTRO PRD (§8)
PRDs 0001-0005          ← histórico
```

## 5b. Fases entregables

| Fase | Entrega (mergeable) | Depende de | Gate de cierre |
|---|---|---|---|
| 1 | **Medición antes de tocar nada.** Contra un árbol de adoptante real: cuántos archivos pasan de exento a producto con la inversión, desglosado por directorio. Sin este número la fase 2 no se aprueba. | — | el número existe y el owner lo ve |
| 2 | Inversión a fail-closed acotada según §13-Q1/Q2, con `scope_exempt:` en `project.conf` y auto-escalada (avisa hasta que el adoptante declara, bloquea después) | 1 | golden §9 1-4; FP medidos < 10% |
| 3 | Retirada de lo que la inversión deja sin objeto: la regla anti-indirección y el estatus de gate de `_sup_invocadores` | 2 | el nº de piezas mantenidas BAJA respecto al inicio |
| 4 | Criterio de cierre y medición de convergencia impresa en `session-start` | — | §9 golden 5 |

## 6. Modelo de datos

`tools/project.conf` gana una clave. Se elige ese archivo, y no uno nuevo, porque ya tiene las
cuatro propiedades que costaron dos rondas conseguir: es always-product por forma, es propiedad
del adoptante y está fuera del sync, **se lee del índice y no del árbol** (hereda el cierre de la
vía 1), y su contradicción ya se reporta una vez por sesión.

```
scope_exempt: <ruta-o-prefijo>     # repetible. SOLO AÑADE al default que viaja en scope.sh.
```

El default de exentos viaja en `tools/lib/scope.sh` (que sí sincroniza). El adoptante solo puede
ensanchar, y ensanchar **cuesta un review y deja diff**, porque `project.conf` es always-product.
Esa es la propiedad estructural que hace la inversión superior a la lista actual, y no un efecto
colateral: sin ella, es la misma lista con el signo cambiado.

## 7. Flujo de la solución

- Como **mantenedor del harness**, quiero que añadir un gate nuevo no requiera acordarse de
  ninguna lista, para que la novena vía no exista.
- Como **adoptante de tipo app**, quiero que mi `tools/deploy.sh` siga sin pedir review, para que
  el gate no se me haga insoportable y acabe en `--no-verify`.

### Edge cases

- Adoptante que sincroniza y ve de golpe que `ci/`, `scripts/` y `.github/` pasan a producto →
  auto-escalada: avisa hasta que declara, bloquea después. Mismo patrón que ya usan
  `check-source-sets` y `mutation-score`.
- `project.conf` con `scope_exempt:` apuntando a la superficie de enforcement → se ignora la
  exención y se avisa. Un adoptante no puede eximir el gate que le protege.

## 8. Anti-features (qué NO entra)

- **El manifiesto de gates de `ci/run-gates.sh`.** Cierra 4 de las 8 vías —las otras 4 son datos,
  no invocaciones—, añade cuatro piezas (manifiesto, iterador, piso, schema) y conserva la ERE.
  Su valor real es de mantenibilidad, no de scope. **Es un PRD aparte**, con dos requisitos que
  este deja escritos para que no se pierdan: un manifiesto vacío o ilegible debe salir 3 y nunca
  "cero gates ejecutados = verde", y el conteo de gates es trinquete que **solo sube**.
- Arreglar el congelamiento de `lefthook.yml`.
- Retirar o relajar cualquier gate existente.
- Nada que toque `ios/ android/ web/`.

## 9. Escenarios golden (deben pasar al terminar)

1. Un archivo con **nombre aleatorio** creado bajo `tools/`, `ci/` y `.claude/agents/` exige
   review, sin que nadie lo haya enumerado. *(Éste es el criterio de parada: es falsable, mientras
   que "la lista está completa" no lo es.)*
2. `tools/agent-prompts/review.md` y `tools/agent-backends/claude.sh` exigen review bajo criterio
   de `application`. *(La novena vía, viva hoy.)*
3. `tools/deploy.sh` de un adoptante **no** exige review. *(La promesa de la fase 1b de PRD 0005:
   cero falsos positivos nuevos. Ya tumbó un intento anterior.)*
4. Un `scope_exempt:` que apunte a la superficie de enforcement se ignora y avisa.
5. `session-start` imprime, con estas dos cifras concretas y no una impresión: **hallazgos abiertos
   y cerrados en los últimos 14 días**, y marca la línea cuando abiertos > cerrados. Falsable: se
   planta un ledger con 9 abiertos y 3 cerrados en la ventana y el arranque debe decirlo; con 3 y 9,
   no debe marcar nada. (El reviewer señaló que la versión anterior de este golden no fijaba ni
   umbral ni forma de salida, o sea que no era comprobable.)

## 10. Métricas de éxito

- **Piezas mantenidas**: menor al terminar que al empezar. Si sube, el diseño falló.
- **Falsos positivos** de la inversión medidos contra un árbol de adoptante real: < 10% (§14.2).
- **Convergencia del ledger**: cerrados ≥ nuevos en dos semanas consecutivas. Es la métrica que
  responde "¿está listo?" y hoy no existe.
- **Vías nuevas de esta clase**: cero en la ventana de observación.

## 11. Rollout

Auto-escalada, con el precedente que ya existe dos veces en el repo: los paths que pasan de exento
a producto **avisan** hasta que el adoptante declara, y bloquean después. Rollback: retirar la
clave del conf y volver a la ERE anterior, que queda en el historial.

## 12. Riesgos

- **El más probable, y ya materializado una vez:** la inversión pide review por el script de
  deploy del adoptante y el gate se apaga entero en dos semanas. Mitigación: fase 1 antes que
  fase 2, y el golden 3.
- **Que este PRD repita el patrón que denuncia**: añadir mecanismo para vigilar el mecanismo.
  Mitigación: la fase 3 es explícitamente de retirada, y §10 mide piezas.
- **Que el freeze de WF-09 se vuelva a saltar por excepción.** Este PRD **es** una excepción al
  freeze; §13-Q6 pide al owner que decida si sigue vigente o se retira, porque un freeze que
  siempre se excepciona es peor que no tenerlo: da la sensación de control sin el control.

## 13. Open Questions

- [ ] **Q1 — ¿La inversión se acota por `project_kind`?** Bajo `harness`, `tools/`/`scripts/`/`ci/`
      ya son producto y casi nada cambia; el rediseño es para el criterio de app. La respuesta
      decide contra qué árbol se miden los falsos positivos de la fase 1.
- [ ] **Q2 — ¿La superficie se deriva de `SYNC_PATHS`/`_es_maquinaria` o se escribe a mano?**
      La derivada resuelve dos clases de golpe y **se auto-corrige** (si añades maquinaria fuera
      de esa lista, no le llega al adoptante y alguien lo nota en días). Coste: acopla scope a
      upgrade y exige materializar la lista con su check de frescura. Es la decisión arquitectónica
      del PRD y no la puede tomar el implementador.
- [ ] **Q3 — ¿Los trinquetes `tools/*-ratchet.json` pasan a exigir review?** A favor: hoy su única
      defensa es `permissions.deny`, que es Anillo 0 de **un solo cliente**; desde Codex o una
      terminal, subir el número no pide review, y esta sesión vio su `_note` cambiar sin autor
      identificable. En contra: `drift-ratchet --update` baja deuda a menudo y pedir review ahí
      penaliza la conducta correcta.
- [ ] **Q4 — ¿`tools/tests/test_*.sh` son producto?** El runner ya lo es; los archivos que
      contienen la verdad, no. Vaciar un test de aserciones no dispara review.
- [ ] **Q5 — ¿El manifiesto de gates entra aquí o en el siguiente PRD?** Recomendación: el
      siguiente (§8).
- [x] **Q6 — ¿Sigue vigente el freeze de WF-09?** RESUELTA 2026-08-24: **sí, y se hace cumplir**.
      Consecuencia directa: este PRD queda On hold y el trabajo pasa a la fase 3 de PRD 0005.
      Pregunta original: Desde el 19 de agosto todo detector nuevo entró
      por su excepción. O se retira y se dice, o se hace cumplir con un mecanismo. Mantenerlo como
      está es la peor de las tres.

## 15. Definition of Done

- [ ] Los cinco escenarios golden pasan.
- [ ] **TDD**: cada golden con su test rojo ANTES, verificado contra la versión previa.
- [ ] El número de piezas mantenidas es menor que al empezar (§10).
- [ ] FP medidos contra árbol de adoptante real, < 10%.
- [ ] `reviewer` GREEN · `design-reviewer` sobre el diseño **antes** de la fase 2.
- [ ] Cada afirmación de cobertura del código nuevo existe como test.
- [ ] Los findings de esta clase en estado terminal; los que queden abiertos, con su razón.

## 16. Próximos pasos

- PRD del manifiesto de gates de `ci/run-gates.sh`.
- PRD del congelamiento de `lefthook.yml` para adoptantes por copia.
- Integrar las cuatro divisiones de la fase 2a de PRD 0005, que siguen pendientes.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-24 | On hold por decisión del owner sobre Q6: el freeze sigue vigente y se cumple. El siguiente trabajo es la fase 3 de PRD 0005, no este PRD | owner |
| 2026-08-24 | Draft. La propuesta original (manifiesto de gates) fue a design-review y volvió RED con 9 hallazgos: cierra 4 de 8 vías, añade piezas en vez de retirarlas, y la premisa de coste era falsa (`review.md` explotable hoy). El PRD adopta la alternativa que el design-review defendió —inversión a fail-closed— y manda el manifiesto a un PRD aparte | agente del template |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._ Uno ya identificado antes de empezar: veinte minutos de design-review encontraron más
que ocho rondas de revisión de código, porque miraban la forma de la solución en vez de la
corrección del código. Las ocho rondas nunca podían encontrar "el diseño es fail-open" — solo
podían encontrar instancias de ese fallo, una por ronda.
