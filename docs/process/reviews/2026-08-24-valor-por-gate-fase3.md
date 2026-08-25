# Fase 3 de PRD 0005 — valor por defensa: keep / tune / retire

> **Fecha:** 2026-08-24 · **Alcance:** la MEDICIÓN es solo lectura; el commit que trae este informe
> **no lo es** — instrumenta las tres primitivas de bloqueo de `lib/io.sh` y añade 465 líneas de
> tests. Ningún gate cambia su comportamiento de bloqueo (dos guards lo fijan:
> `test_telemetria_rota_no_impide_que_hook_block_bloquee` y `…_que_el_gate_bloquee`), pero decir
> "solo lectura" era falso y lo desmentía el propio §1 tres párrafos más abajo (`f-18a2c2ef`).
> **Estado: PARCIAL.** Este informe responde la pregunta para las defensas de revisión y **no puede
> responderla para los gates mecánicos** — la razón está en §1 y es el hallazgo principal.

---

## 1. Lo primero que encontró la fase 3 fue un agujero en su propio instrumento

`gate-value.sh` sobre los últimos 30 días devuelve **cero eventos** para `semgrep`, `check-layers`,
`drift-ratchet`, `reviewer-gate`, `secret-scan`, `check-review-marker`, `conflict-markers`,
`mutation-score` y `exec-bits`. La cabecera del propio script avisa de que un cero es ambiguo entre
**disuasión** (funciona tan bien que nadie lo intenta) y **mudo**.

Pero aquí no era ninguna de las dos. Había un **tercer estado que la herramienta no contemplaba**:

> el gate disparó, bloqueó, hizo su trabajo — y no dejó rastro.

Evidencia directa: en la sesión que produjo este informe, el **git-guard del `reviewer-gate`
bloqueó dos veces** y el **`skill-reminder` otras dos**. Ambos figuraban con cero. Causa:
ninguna de las primitivas de bloqueo de `lib/io.sh` registraba telemetría, y `skill-reminder.sh`
no tenía ni una llamada a `hook_log_detection`.

**Arreglado en dos tiempos, y el primero estuvo mal — conviene decirlo porque es el mismo patrón
que el error de atribución del §3.** La primera versión instrumentó `hook_block_or_warn` y escribió
encima que era "por donde pasan TODOS los bloqueos". Son **tres** primitivas —`hook_block`,
`hook_json_block` y `hook_block_or_warn`— y la que quedó fuera es justamente la del git-guard, o
sea la del bloqueo que este párrafo usa como evidencia. Peor: esa versión decía "verificado en vivo,
el gate bloqueó y quedó registrado", y el evento que lo respaldaba venía del camino `git add` +
`commit` —que sí pasa por `hook_block_or_warn`—, **no del git-guard que la frase nombraba**. Se
verificó una cosa y se afirmó otra (`f-2bd11525`).

La versión que quedó instrumenta las **tres** primitivas en un único punto (`_hook_log_block`), con
guard anti-doble-conteo para la delegación. Y la afirmación de cobertura ya no es una frase: la
enumera `test_toda_primitiva_de_bloqueo_esta_instrumentada`, que relee `lib/io.sh` con
`tools/tests/lib/primitivas-de-bloqueo.sh`, deriva qué funciones deniegan y falla si aparece una
nueva sin registrar. La ruta del git-guard se cubre de punta a punta en `test_git_guard.sh`
(`--no-verify` y `reset --hard`), que es el hook real y no la primitiva aislada: el bug vivía
exactamente en esa distancia.

**Y hubo una cuarta ronda y una quinta, porque la tercera versión de este mismo párrafo volvió a
pasarse, y la cuarta también.** El `reviewer` demostró por mutación que el meta-test —el que se
presentaba como la cura— tenía puntos ciegos reales, y luego demostró que la corrección de esos
puntos ciegos tenía otros. En total, cuatro formas de bash perfectamente válidas que el parser
escrito a mano no veía: la keyword `function`, el `}` de cierre indentado, las definiciones de una
línea (`io.sh` tiene una: `hook_allow() { exit 0; }`), y la llave abierta en la línea siguiente. Más
un quinto defecto peor, porque no era una forma sino un cálculo: el conteo de llaves quitaba `${` y
dejaba su `}`, así que con un `echo ${1}` el cuerpo se cerraba antes de tiempo y el `exit 2` de
después desaparecía sin dejar rastro.

**La conclusión que importa no es "faltaba una forma más", es que arreglarlas de una en una era la
estrategia equivocada:** la lista de shapes válidos de bash la decide bash. El inventario
(`tools/tests/lib/primitivas-de-bloqueo.sh`) sourcea la librería en un subshell limpio y le pregunta
a `declare -f`, que devuelve el cuerpo tal y como bash lo parseó — normalizado, sin comentarios y
con todas las formas colapsadas a una. No hay shape que reconocer, así que no hay shape que se
escape. La contrapartida está declarada en el propio script: sourcear ejecuta el nivel superior del
archivo, lo cual vale para una librería y no para un ejecutable con efectos.

Y `test_el_inventario_contiene_lo_que_encuentra_un_grep_ingenuo` sustituye a un test que era una
**tautología**: comparaba el conteo del parser contra un `grep` con la misma regex de cabecera, así
que ambos compartían el punto ciego y daba verde con una función entera invisible para los dos.
Ahora la relación es de inclusión y en la dirección que dice algo.

Balance de verificación. **El conteo no se congela aquí** —ya se escribió mal tres veces en este
mismo párrafo, 10 → 13 → 14— así que va la lista, que es a la vez la cifra y su evidencia, y el
comando que la reproduce: `git diff --cached | grep -E '^\+test_'`.

**Vistos ROJOS contra la versión anterior de `io.sh`** (reproducen el bug):
`test_toda_primitiva_de_bloqueo_esta_instrumentada` · `test_hook_block_directo_deja_rastro` ·
`test_hook_json_block_deja_rastro` · `test_un_bloqueo_delegado_no_cuenta_dos_veces` ·
`test_el_git_guard_registra_cuando_bloquea` · `test_reset_hard_bloqueado_tambien_se_registra`.

**Guards de regresión**, que no reproducen el bug y por eso cada uno murió con un mutante dirigido:
`test_telemetria_rota_no_impide_que_hook_block_bloquee` y `test_telemetria_rota_no_impide_que_el_gate_bloquee`
(insertar `mkdir … || exit 3` **dentro de `_hook_log_block`**) ·
`test_el_inventario_caza_una_primitiva_no_instrumentada_en_toda_forma` (`declare -f` → `declare -F`) ·
`test_el_inventario_no_inventa_primitivas_ni_falsos_incumplimientos` (marcar todo como denegación) ·
`test_el_inventario_contiene_lo_que_encuentra_un_grep_ingenuo` (omitir una función del inventario) ·
`test_analizar_un_archivo_que_lee_stdin_no_cuelga` (quitar el `< /dev/null`).

**Heredados de las rondas anteriores sin commitear**, no escritos aquí:
`test_un_gate_que_bloquea_deja_rastro_en_la_telemetria` y `test_un_aviso_en_preset_lite_tambien_deja_rastro`.

**Una precisión sobre el mutante del `mkdir`, que el `reviewer` cazó y tiene razón en señalar.** El
mismo `mkdir … || exit 3` colocado dentro de `hook_log_detection` **sobrevive**, y no por un hueco
de los tests: es un **mutante equivalente**. Esa función corre en un subshell y la envolvente hace
`return 0` incondicional, así que ningún exit code de dentro llega jamás al caller — el fail-open
ahí es estructural, no verificado por test, y esa distinción merecía estar escrita. La versión
anterior de este párrafo decía "un `mkdir … || exit 3`" sin decir dónde, y esa imprecisión bastó
para que un lector cuidadoso aplicara el mutante equivalente y concluyera —razonablemente— que la
afirmación era falsa. Los mutantes del `reviewer` sobre el `io.sh` real (`function`, cierre
indentado, una línea, llave en la línea siguiente, `${1}` sin comillas) mueren todos.

**Consecuencia para este informe:** los gates mecánicos empiezan a acumular historial **hoy**. No
hay base para decidir sobre ellos, y **recomendar retirar uno por "cero detecciones" cuando bloqueó
dos veces esta tarde sería el error que este proyecto persigue.**

## 2. Lo que sí es medible: 127 hallazgos históricos del ledger

Estos datos no dependen de la telemetría de hooks. Son los hallazgos reales acumulados.

### Quién los cazó

| Defensa | Hallazgos | % |
|---|---:|---:|
| `reviewer` (code review) | 47 | 37% |
| Serendipia y otros | 27 | 21% |
| **El adoptante, usándolo de verdad** | **25** | **19%** |
| Jueces adversariales | 10 | 7% |
| Evaluación externa | 9 | 7% |
| `design-reviewer` | 4 | 3% |
| `process-judge` | 3 | 2% |
| La propia sesión | 2 | 1% |

### Y el número que de verdad decide: rendimiento por invocación

| Defensa | Invocaciones | Hallazgos | **Por invocación** |
|---|---:|---:|---:|
| `design-reviewer` | **1** | 4 en el ledger · **9 autorreportados** | **4.0 – 9.0** |
| Juez adversarial | 3 ⚠️ | 10 | **3.3** |
| `reviewer` | 56 invocaciones · **31 diffs distintos** | 47 | **0.84 / invocación · 1.5 / diff** |
| `process-judge` | 0 (cola sin procesar: `wc -l < .agents/state/judge-queue.txt`) | — | n/a |

### Cómo se atribuyeron, y por qué hay dos cifras para el `design-reviewer`

**Las invocaciones** de `reviewer` y `design-reviewer` salen de `review-history.jsonl`, que es
registro mecánico. **Pero no se citan como cifra fija y hay una razón:** al escribir este informe
pasaron de 53 a 55 a 56 en el rato que llevó revisarlo, porque las revisiones seguían ocurriendo.
Recalcúlalas, no las copies:

```
python3 -c "import json,collections; c=collections.Counter(json.loads(l)['agent'] for l in open('.agents/state/review-history.jsonl') if l.strip()); print(c)"
```

**Y el dato que apareció al recontar es más informativo que el total:** esas ~56 invocaciones se
reparten sobre solo **31 diffs distintos**. Uno se revisó **17 veces** y otro **9**. Son las rondas
repetidas sobre el mismo cambio — el bypass de `scope` y el cierre de 1c. Por eso se dan las dos
tasas: **por invocación (0.84)** mide el coste de cada corrida, y **por diff revisado (1.5)** mide
lo que el `reviewer` encuentra en un cambio. La primera estaba deprimida por un artefacto del
flujo, no por la calidad del agente — y eso es justamente lo que la recomendación "TUNE la
invocación" quiere corregir. **⚠️ Las 3 de los jueces adversariales NO tienen respaldo
mecánico** — se infieren agrupando texto libre del campo `source` del ledger, porque esos agentes no
escriben en `review-history.jsonl`. Es la cifra más débil de la tabla y se marca como tal.

**Los hallazgos** se atribuyeron buscando subcadenas en el `source`. **Ese método ya falló aquí y
conviene decirlo**: la primera versión de este informe dio 5.0 al `design-reviewer` porque el
clasificador se tragó `f-review-sin-reporte-persistido` — una entrada del **15 de agosto**, sobre un
incidente anterior y distinto, que encontró **el adoptante** y que solo *menciona* al design-review.
Un detector de texto atribuyendo mal por parecido, en el informe que denuncia justo eso. Lo cazó el
reviewer al pedirle que recalculara las cifras desde las fuentes.

Y de ahí el rango: la invocación del 24 de agosto **autorreportó 9 hallazgos** (F1–F9, en
`.agents/state/reviews/…-design-reviewer.md`), de los cuales **4** llegaron al ledger como entradas
propias; los otros cinco se incorporaron al PRD sin entrada individual. Las dos cifras son
defendibles y miden cosas distintas — encontrados frente a registrados — así que se dan las dos en
vez de elegir la que más favorece la conclusión.

## 3. Lectura, con sus límites por delante

**Los tamaños de muestra son pequeños y hay que decirlo antes que la conclusión.** El
`design-reviewer` tiene **n=1** y los jueces **n=3**. Un 4.0 —o un 9.0— sobre una sola invocación no
es una tasa: es una observación. Y "hallazgos encontrados" no es lo mismo que "valor": un hallazgo trivial
cuenta igual que uno que evita un bypass de seguridad.

**Y el propio método de atribución es texto libre**, no un registro estructurado: produjo al menos
un error confirmado (arriba). Los números de la primera tabla son indicativos, no exactos; los de
`reviewer` y `design-reviewer` en invocaciones sí son mecánicos.

Dicho eso, la señal sobrevive a las tres correcciones y es coherente con lo observado — el rango
4.0–9.0 sigue estando muy por encima de las dos tasas del `reviewer` (0.84 y 1.5). Esta frase citaba
0.89, que es 47/53: la cifra de ANTES del recuento de esta misma ronda, sobreviviendo dentro del
informe que la corrigió tres párrafos más arriba. Misma clase que `f-wf02-mapa-cifras-podridas`.

**La defensa menos usada del harness es la de mayor rendimiento.** El `design-reviewer` se ha
invocado **una vez en toda la vida del proyecto**. Esa vez tumbó un rediseño **antes de escribir
código** y destapó una novena vía de bypass viva. En la misma sesión, el `reviewer` estándar hizo
**ocho rondas** sobre el código ya escrito sin poder encontrar el problema de fondo: solo podía
encontrar instancias de un diseño fail-open, una por ronda.

**El `reviewer` produce el volumen y su peor tasa es un artefacto del flujo, no del agente.** Sus
56 invocaciones cubren 31 diffs: un cambio se revisó 17 veces. No es argumento para retirarlo —es
la red que cubre lo que los demás no miran— sino para **invocarlo mejor**: muchas de esas rondas
existían solo porque el marker se invalidaba tras un cambio de una línea en el ledger.

**El adoptante usándolo de verdad es la tercera fuente, con 25 hallazgos y coste cero por
invocación.** No hay defensa sintética que compita con eso.

**El `process-judge` tiene una cola sin procesar** —cuántas lo dice `wc -l < .agents/state/judge-queue.txt`, no este informe: es un contador vivo que solo vacía el propio `process-judge` al correr, y esta línea llegó a decir "3" cuando ya iba por 7. Es la única defensa que lee la *trayectoria*
—cómo se trabajó— y no solo el diff. Con 3 hallazgos y cero invocaciones registradas no se puede
juzgar, pero está sin usar.

**Y dónde duele:** `scripts/agent-hooks` (18), `tools/tests` (13) y `tools/lib` (12) concentran el
34% de los hallazgos. La maquinaria de enforcement es la parte más defectuosa del repo — coherente
con que sea la que más ha cambiado.

## 4. Recomendación por defensa

| Defensa | Veredicto | Por qué |
|---|---|---|
| `design-reviewer` | **KEEP y subir su uso** | Mayor rendimiento observado. Hoy es opcional en la práctica; debería ser obligatorio antes de código en cambios de diseño, que es lo que §12 ya dice y no se cumple. |
| Jueces adversariales | **KEEP para maquinaria de enforcement** | 3.3 por invocación y encontraron lo que 8 rondas de reviewer no. Caros: reservarlos para cambios a los gates. |
| `reviewer` | **KEEP, TUNE la invocación** | Es la red de seguridad. El ajuste no es al agente sino al flujo: menos rondas por cambios triviales. |
| `process-judge` | **Sin datos — usarlo antes de decidir** | Cola sin procesar (`wc -l < .agents/state/judge-queue.txt`). Procesarlas es el experimento barato. |
| Gates mecánicos | **Sin datos — NO decidir todavía** | El instrumento estaba roto hasta hoy (§1). Volver a medir cuando haya ventana real. |
| Nivel 4 (mutación) | **Sigue MUDO** | `min_score: 0, measured: false`. No es candidato a retire porque nunca fue candidato a nada: no ha medido jamás. Ver §5. |

## 5. Lo que este informe NO puede decidir, y qué haría falta

1. **Nada sobre los gates mecánicos.** Hace falta una ventana real con la telemetría ya arreglada.
   Sin eso, cualquier keep/tune/retire sobre ellos es intuición con formato de tabla.
2. **Si el nivel 4 se cablea, se cambia o se retira.** La conversación con el owner apuntó a
   sustituirlo o complementarlo con **cobertura sobre el diff** y **property-based**, y a que
   `AGENTS.md §5` deje de llamarlo *"el árbitro"* cuando no ha medido nunca.
3. **El valor real de cada hallazgo.** Todo aquí cuenta hallazgos, no impacto. Un juez que encuentra
   un bypass de seguridad y un reviewer que encuentra un typo cuentan igual.

## 6. La conclusión que responde a "¿por qué no está listo?"

El ledger dice que hasta el 15 de agosto se cerraba lo que se abría, y que desde el 19 se abre 2–3×
más de lo que se cierra. Este informe añade el porqué: **el proyecto pasó de construir a auditar, y
las defensas que mejor rinden —design-review antes de escribir, jueces adversariales sobre la
maquinaria— son precisamente las que menos se usan**, mientras el volumen lo lleva la que menos
rinde por corrida.

No falta maquinaria. Falta **usar antes la que ya existe**: el `design-reviewer` una vez en toda la
vida del proyecto es el dato más elocuente de los 127 hallazgos.

## 7. Qué haría el harness más sólido, según lo medido aquí

La pregunta del owner que originó esta fase fue *"¿qué nos falta para ser más sólidos? ¿O hay que
ser más estrictos con nosotros mismos?"*. La respuesta que sostienen los datos es **no**: hoy la
estrictez no faltó — los gates bloquearon media docena de veces en la sesión y los reviewers fueron
duros. El problema es **cuándo** se aplica.

Agrupando los fallos de la sesión que produjo este informe, casi todos caen en cuatro cubos, y cada
uno tiene una medida que lo ataca:

**1. Detectores de texto para propiedades sintácticas.** El grep de KMP, el de `git add -A`, el de
invocaciones de semgrep, la regla anti-indirección y —dentro de este mismo informe— el clasificador
que atribuyó mal la cifra insignia. **Los cinco** tuvieron falsos positivos o negativos.
→ *Medida: si la propiedad la decide una gramática o una estructura, el motor parsea o el dato se
declara. Nunca coincidencia de subcadenas.*

**2. Comentarios que afirman más de lo que el código hace.** *"para que no haya quinta"* (la quinta
llegó esa sesión), *"semgrep parsea, no hay nada que anclar"* (los espacios lo evaden), *"misma
convención que semgrep-scan.sh"* (era distinta), *"31 sobre 57"* (fueron 20 de 57).
→ *Medida, y la de más rendimiento de las cuatro: **toda afirmación de cobertura es un test**. Si
escribes "este detector NO ve X" o "esto solo avisa", eso es un test. Si no puede serlo, no puede
ser una afirmación. Sola elimina los cubos 2 y 3 casi enteros.*

**3. Tests que pasaban sin verificar nada.** Uno de señales apuntando al proceso equivocado; un
fixture cuyo vecino satisfacía la precondición; uno midiendo un `TMPDIR` compartido; uno midiendo
por posición en un orden no determinista. **Los cuatro se escribieron después o a la vez que la
implementación.** Los que se verificaron rojo-primero aguantaron ocho rondas sin un problema.
→ *Medida: rojo-primero **por comportamiento**, no por feature. Y cuando el test se escriba después,
rómpelo 30 segundos y míralo fallar — es el 80% del valor de verificación del TDD sin cambiar la
forma de trabajar.*

**4. Clasificación fail-open** en un mecanismo de seguridad: ocho rondas sobre un mismo defecto de
diseño, descubierto ocho veces.
→ *Medida: **design-review antes de escribir**, que §12 ya exige y no se cumplía. Es la defensa que
esta fase mide como la de mayor rendimiento, y la que se había usado una sola vez.*

**Y una quinta, transversal:** red-team obligatorio al tocar la maquinaria de enforcement. Los tres
jueces adversariales encontraron en una pasada lo que ocho rondas del reviewer estándar no tocaron —
porque a ellos se les pidió **refutar**, no revisar.
