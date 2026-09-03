# Por qué AGENTS.md dice lo que dice

> Este fichero es el **racional** de las reglas: las mediciones, los incidentes y
> los cambios de criterio que las produjeron. Vive aquí y no en `AGENTS.md`
> porque ese fichero se carga en el contexto de **cada turno de cada agente**, y
> el racional no cambia lo que un agente hace en el momento de actuar — eso lo
> hace el detector. Aquí lo lee quien decida si una regla sigue valiendo.
>
> Regla de mantenimiento: si añades una regla a `AGENTS.md` con su medición,
> la medición baja aquí y arriba queda la regla. Si una regla pierde su
> racional, es candidata a retirarse, no a quedarse "por si acaso".

---

## §2 — Por qué el modo estricto es el nivel 0

**Ningún gate posterior compensa una API donde el mal uso compila.** Un detector,
un reviewer y un juez de IA solo pueden encontrar un error que ya está escrito;
un tipo que no deja expresar el estado inválido impide que llegue a escribirse.
Por eso el modo estricto no es "una capa más": es la única que actúa antes de que
el defecto exista.

(Esta frase se quedó huérfana al recortar `AGENTS.md` el 2026-09-02 — no migró
con el resto del racional. La cazó el `reviewer` comparando párrafo a párrafo,
no por secciones. Que el criterio del propio recorte fuera "el racional se MUEVE,
no se borra" es lo que la hizo un hallazgo en vez de una omisión aceptable.)

---

## §5 — Por qué el nivel 4 se mide a mano

`AGENTS.md` decía que el veredicto de la calidad de un test lo daba el
**mutation score** de `tools/mutation-score.sh`, "el gate que distingue un test
que verifica de uno escrito para que pase".

**Esa frase nunca ha sido verdad en este repo.** `tools/mutation-ratchet.json`
lleva `measured: false` desde el día uno y no hay runner de mutación para shell,
que es el lenguaje del harness (`f-mutation-score-nunca-medido`, `f-298e3cd2`).
Un nivel de la pirámide anunciado y mudo es peor que uno ausente: da por
cubierto lo que nadie mide.

La maquinaria se queda porque es honesta —`--update` se niega a escribir un piso
de 0 y el script sale 3 sin runner— pero hasta que mida, el árbitro es el de
arriba: **mutantes dirigidos, a mano.** Práctica validada el 2026-09-01: cinco
mutantes contra `canon-enforce`, los cinco muertos, y el `reviewer` encontró un
sexto vivo.

Por qué NO hay detector por grep para las aserciones/DbC: contar aserciones sin
un parser real por lenguaje produciría ruido, y un detector ruidoso se descarta
entero (ley del 10%, §14.2).

---

## §9 — Por qué el trinquete de mutación está dormido

`tools/mutation-ratchet.json` lleva `measured:false`. **No es un piso de 0: es
la ausencia de veredicto.** Un número que se puede aflojar no es un trinquete,
es una sugerencia; y un número que nunca se midió no es ni eso.

---

## §10 — La divergencia del ledger, medida

La regla decía "se resuelve en el mismo turno: o lo arreglas, o lo registras",
sin distinguir severidad ni scope. Esa versión es el motor documentado de la
divergencia del ledger:

> revisar produce hallazgos → cerrarlos cambia el diff → el marker ligado a
> `sha256(diff staged)` se invalida → hay que volver a revisar, que produce
> hallazgos.

**Medido en este repo:** del 5 al 15 de agosto de 2026 se cerraba lo que se
abría; desde el 19 se abrió 2–3× más de lo que se cerró y la brecha no volvió a
cerrarse (el 31 de agosto: 226 entradas registradas, 155 cerradas, 71 sin cerrar
— 67 `open` + 4 `accepted`). La causa próxima ya estaba nombrada en
`docs/process/reviews/2026-08-24-valor-por-gate-fase3.md`: *"muchas de esas
rondas existían solo porque el marker se invalidaba tras un cambio de una línea
en el ledger"*.

### Por qué existe el filtro de refutación

Un revisor al que se le pide encontrar huecos encuentra huecos aunque el trabajo
esté bien: es exactamente lo que se le pidió, y es el modo de fallo que la
literatura de 2026 mide como sobre-corrección sistemática. El filtro de
refutación es lo que separa un revisor de alta precisión de un generador de
ruido.

### Por qué toda lección se convierte en detector

Sin detector, las lecciones son prosa que nadie relee y que el agente pierde en
la primera compactación. Con él, cada error cometido una vez se vuelve
mecánicamente imposible la segunda — que es el único mecanismo por el que la
necesidad de revisión humana **decrece** en vez de mantenerse plana.

Y no es teórico: el 2026-09-02 la trampa del orden de `stat` publicó main en
rojo por CUARTA vez, la primera con el detector ya existiendo. Estaba
documentada en comentarios de dos ficheros y en una resolución de ledger que
afirmaba "detector nuevo que barre todo el repo" — no barría. Una resolución que
AFIRMA cobertura es tan peligrosa como un comentario que la afirma.

---

## §11 — Por qué el tooling no está en la matriz

Tocar `tools/**`, `ci/**` o `scripts/agent-hooks/**` **no** está en la tabla, y
no es un olvido: `skill-reminder` excluye esas rutas a propósito. Editar la doc
o el tooling de un área no es editar el código de ese área — era un falso
positivo real, fijado por `test_skill_reminder.sh`.

Su gate es otro y es más fuerte: §8 exige **aprobación explícita del owner** para
tocar tooling compartido. La lectura recomendada antes de hacerlo sigue siendo
`process/references/verification-loop.md`, pero es una recomendación, no un
bloqueo — y decirlo así es la diferencia entre documentar un gate y fingirlo.

### Por qué la tabla falla en una dirección y no en la otra

Una fila en la tabla sin respaldo en el conf es una defensa **anunciada que no
existe**, que es el único pecado que este harness no comete. Por eso
`check-skill-matrix-doc.sh` falla en esa dirección a propósito.

Nota honesta: la carga automática por `paths:` en el frontmatter de una skill NO
es parte del estándar portable de skills (agentskills). No dependas de ella para
clientes distintos de Claude Code; el conf + el hook son lo que de verdad se
cumple.

---

## §13 — Los tres datos que fijan el tope de dos rondas

Todos de este repo y recalculables:

- De **107** unidades de trabajo revisadas, solo **29 (27%)** pasaron en verde a
  la primera — `.agents/state/review-history.jsonl`, campo `verdict`: 53 GREEN ·
  52 AMBER · 28 RED.
- Un mismo encargo llegó a **17 rondas** y otro a 9.
- El `reviewer` rinde **0,84** hallazgos por invocación y el `design-reviewer`
  **4–9**; en la sesión de las ocho rondas, lo que el reviewer no podía
  encontrar ronda a ronda (un diseño fail-open) lo encontró el design-review en
  una. Fuente: `docs/process/reviews/2026-08-24-valor-por-gate-fase3.md`.

Un cambio que llega en rojo a la tercera ronda no tiene un problema que una
ronda más vaya a encontrar: tiene un lote demasiado grande o un diseño
equivocado.

### Por qué el marker se liga al sha del diff staged

Durante meses ninguna ejecución de build o de tests se ligaba a ese mismo diff,
así que se podía commitear un árbol que **nadie llegó a compilar** con todo en
verde — el reviewer no compila, los trinquetes no compilan y las capas no
compilan. De ahí `tools/verify-run.sh`.

`git add X && git commit` en una línea, o `commit -a/-am`, evaden la validación
porque el gate corre antes del add.

---

## §14 — Por qué el Anillo 3 es obligatorio en `full`

No es burocracia: es lo que hace verdadero el fail-open local de §14.3. Todo ese
fail-open está justificado *por* la existencia del backstop. Sin Anillo 3, un
exit 3 no es "avisa y luego CI bloquea": es **fail-open definitivo y
silencioso**, y el razonamiento de todos los niveles se cae con él.

Corolario del contrato de exit codes: bloquear el exit 3 en local crearía un
deadlock — un typo en las reglas impediría hasta el commit que lo arregla — pero
tratarlo como éxito convertiría un scanner roto en luz verde permanente.

### La ley del 10%

Un detector con más de ~10% de falsos positivos se descarta — y un agente
además aprende a evadirlo. Por eso los patrones van en Semgrep (AST) y no en
`grep`. Prefiere 5 reglas exactas a 50 ruidosas. Google midió que por encima de
ese umbral los analizadores se descartan sistemáticamente.
