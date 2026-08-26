# Auditoría del workflow — PRD 0007, arranque de proyecto y autonomía medida

> **Fecha:** 2026-08-25 · **Tipo:** auditoría de diseño; no se modificó código ni tooling
> **Dictamen:** **AMBER** · **Objeto:** `b5a41bb`, `40c981b`, `a20be1c` (`db371f2..a20be1c`)
> **Archivos modificados por esos commits:**
> `docs/process/prds/0007-arranque-de-proyecto-y-modulo-de-referencia.md` y
> `docs/process/current_execution_map.md`

Este informe es autocontenido para que otro agente pueda reauditar el cambio sin depender del chat
que lo originó. Separa hechos demostrados, riesgos pendientes de validación y opinión de diseño. No
autoriza a implementar los arreglos: antes de tocar el PRD o el workflow, el siguiente agente debe
contrastar cada hallazgo contra el árbol actual y contra cualquier commit posterior a `a20be1c`.

---

## 1. Resumen ejecutivo

La dirección del PRD es buena y corrige problemas reales del workflow:

- convierte decisiones arquitectónicas implícitas en ADRs y ejemplos ejecutables;
- usa un módulo vertical de referencia como fuente canónica;
- separa contrato, lógica y vertical completa en entregas revisables;
- distingue decisión del owner, design-review, seguridad y verificación del adoptante;
- reconoce honestamente el freeze de gates nuevos;
- sustituye anclas por línea por símbolos o marcadores estables;
- incorpora guards de falsos positivos desde el diseño del detector.

El PRD no está, sin embargo, listo para implementación sin aclarar tres contradicciones centrales:

1. la evidencia TDD por orden de commits exige un commit rojo que el gate de verificación impide;
2. la fase 3 entrega un solo módulo autónomo, pero el criterio de autonomía exige dos consecutivos;
3. `ARCH_DEVIATIONS:` se llama parseable, pero no existe un consumidor que lo exija, lo vincule al
   módulo o acumule los dos resultados.

Además hay problemas de trazabilidad del design-review, una ruta retroactiva que puede leerse como
bypass de 1c y un posible waiver demasiado amplio en el gate de fase 2.

**Opinión global:** aprobar la dirección fue razonable; iniciar código con el contrato actual no lo
sería. El estado adecuado del diseño es **AMBER: enfoque sano, contrato operativo aún inconsistente**.

---

## 2. Alcance y método

### 2.1 Fuentes leídas

Se leyeron `AGENTS.md`, el tramo vivo de `lessons_learned.md`, el mapa de ejecución, la skill
`process` y sus referencias de lifecycle, feature workflow y TDD; el PRD 0007 completo y las dos
rondas locales de design-review; los contratos de `design-reviewer`/`reviewer`; los hooks y tests de
veredictos, skill-reminder y verify-marker; `skill-matrix.conf`, `project.conf` y el parser de scope.

### 2.2 Delta auditado

El delta inicial contra `origin/main` contenía tres commits:

| Commit | Propósito declarado |
|---|---|
| `b5a41bb` | PRD 0007 v2 tras design-review RED; Approved acotado a 0–1 |
| `40c981b` | v2.1 tras re-review AMBER; re-cosido de 13 hallazgos |
| `a20be1c` | Approved completo; Q4 y Q6 resueltas por el owner |

Durante la auditoría esos commits aparecieron ya publicados en `origin/main`. El rango estable que
debe usar otro agente para reproducir esta revisión es `db371f2..a20be1c`, no `origin/main..HEAD`.

### 2.3 Comandos de evidencia

```bash
git diff --stat db371f2..a20be1c
git diff --name-status db371f2..a20be1c
git diff --check db371f2..a20be1c
git log --reverse --format='%H%n%s%n%b%n---' db371f2..a20be1c
bash tools/tests/run-tests.sh
git status --short --branch
```

No se editó ningún archivo durante la auditoría original. La creación de **este** informe es el único
cambio posterior solicitado por el owner.

---

## 3. Fortalezas del cambio

- **Problema correcto:** separa decisiones no tomadas de novedades técnicas; el patrón lo decide el
  owner y el agente escribe contra una verdad de base independiente.
- **Fuente canónica ejecutable:** una vertical que compila y tiene tests es mejor referencia que
  snippets. Las skills citan símbolos o `@decision:NNNN`, no líneas móviles.
- **Entregas revisables:** 1a contrato → 1b lógica → 1c vertical evita un lote red + dominio + UI.
- **Un solo sistema de decisiones:** reutiliza el ADR existente, declara el ciclo de reemplazo y
  excluye template/README por construcción.
- **Freeze honesto:** reconoce que `check-decision-coverage.sh` sería un gate nuevo, aplaza su entrega
  y declara manual la comprobación provisional y la imposibilidad de llegar a `Shipped`.
- **Seguridad explícita:** el módulo canónico pasa por `security-reviewer` y aceptación del owner.
- **Mapa al día:** Approved, freeze y rondas de review quedaron reflejados en el mapa, no solo en chat.

---

## 4. Hallazgos demostrados

### AUD-0007-01 — ALTA — La evidencia TDD por orden de commits es incompatible con `verify-run`

**Evidencia del PRD:** fase 1b, línea aproximada 159:

> “Evidencia con artefacto: el ciclo queda en el orden de commits (test que falla ANTES del fix)”.

**Evidencia del gate:** `tools/verify-run.sh` ejecuta el comando de `tools/verify.conf` y, si su exit
code no es cero, termina con:

> “el comando salió con … NO firmo nada”.

`tools/check-verify-marker.sh` exige esa firma para cambios de producto en preset `full`. Un commit que
introduce deliberadamente un test rojo no puede obtener el marker. Esto crea un contrato imposible:

```text
PRD exige commit rojo anterior
        ↓
verify-run ejecuta tests
        ↓
tests rojos → no firma
        ↓
commit bloqueado
```

**Consecuencia:** el implementador tendría incentivos para usar un override, commitear un test que no
corre o afirmar TDD sin evidencia. Las tres salidas contradicen el objetivo.

**Dirección de solución para analizar, no aplicar automáticamente:** elegir un artefacto de RED que
no requiera commitear una suite rota. Debe quedar ligado al comportamiento/test y demostrar que el
fallo ocurrió por la razón correcta antes de GREEN. No se debe debilitar `verify-run` para resolverlo.

---

### AUD-0007-02 — ALTA — La fase 3 no puede producir el N=2 que exige su gate

**Evidencia:**

- fase 3 entrega “el SEGUNDO módulo” construido por la IA;
- golden 1 exige `ARCH_DEVIATIONS: 0` en **DOS módulos consecutivos**;
- Q5 aclara que son “dos módulos autónomos”.

El módulo de referencia no es una prueba autónoma: fue diseñado con decisiones humanas y aceptación
por archivo. Por tanto, tras construir “el segundo módulo” solo existe **una** observación autónoma.

**Consecuencia:** la fase 3 puede completar su única entrega y seguir sin poder cerrar su gate.

**Decisión que falta:** o la fase 3 entrega dos verticales autónomas posteriores al módulo de
referencia, o el criterio cambia. Si N=2 se mantiene —la opción coherente con el racional de varianza—,
la tabla, el rollout, el techo de intentos y el coste estimado deben hablar de dos pruebas autónomas.

---

### AUD-0007-03 — ALTA — `ARCH_DEVIATIONS:` es parseable en teoría, pero no tiene consumidor

**Evidencia del PRD:** golden 1 añade al `reviewer` una cuarta línea:

```text
ARCH_DEVIATIONS: <n>
```

**Evidencia del sistema actual:** `capture-review-verdict.sh` y `lib/verdict.sh` solo exigen y extraen:

```text
VERDICT: GREEN|AMBER|RED
FINDINGS: <n>
SCOPE: <texto>
```

No existe actualmente ninguna referencia a `ARCH_DEVIATIONS` fuera del PRD y el mapa. La fase 3 solo
lista como archivos a cambiar `.claude/agents/reviewer.md` y `.claude/agents/README.md`; no asigna un
parser, validator, marker o historial para la nueva métrica.

**Faltan cuatro propiedades para que el gate sea ejecutable:**

1. rechazar ausencia, duplicado o valor inválido;
2. ligar el número al diff y al módulo concreto;
3. persistir el resultado fuera del transcript local;
4. comprobar mecánicamente dos ceros consecutivos.

**Consecuencia:** el reviewer puede omitir la línea y aun satisfacer el contrato actual. Incluso si
la emite, nadie demuestra la conjunción N=2. Llamarla “parseable” describe una posibilidad, no una
defensa existente.

**Dirección de solución:** el PRD debe nombrar el consumidor y el artefacto de historial, o declarar
explícitamente que el cierre es manual. Si se añade maquinaria, debe respetar el freeze vigente.

---

### AUD-0007-04 — MEDIA — El informe de design-review citado no es evidencia durable

El encabezado y el change log del PRD enlazan:

```text
.agents/state/reviews/e3b0c44298fc-design-reviewer.md
```

Pero `.gitignore` excluye `.agents/state/` entero. El propio hook documenta que el cuerpo del review
es “local y gitignored” y que lo que deba sobrevivir debe ir al ledger. Por tanto:

- el informe no existe en otro clon;
- el PRD contiene una referencia que parece persistente, pero no lo es;
- el prefijo `e3b0c44298fc` es el SHA-256 del diff staged vacío, de modo que las dos rondas no quedaron
  ligadas a una versión staged del PRD;
- el contenido acumula ronda 1 y ronda 2 en el mismo archivo local porque comparten esa identidad.

Los commits y el change log conservan un resumen, pero no permiten revalidar F1–F15 contra el reporte
original.

**Dirección de solución:** no es obligatorio versionar todo transcript, pero la evidencia durable debe
tener un hogar canónico: informe trackeado, entradas del ledger o resumen estructurado ligado al commit
revisado. El PRD no debería citar como fuente durable un path que el repositorio excluye por diseño.

---

### AUD-0007-05 — MEDIA — El rollout retroactivo puede interpretarse como bypass de 1c

La sección Rollout dice que proyectos existentes pueden ejecutar retroactivamente fases 0 y 2
eligiendo un módulo existente. Q4, en cambio, exige que el módulo “coronado” pase design-review y
`security-reviewer` antes de declararse canónico, igual que uno nuevo.

**Consecuencia:** un lector que siga Rollout como camino operativo puede aplicar 0 → 2 y omitir la
auditoría/aceptación equivalente a 1c.

**Dirección de solución:** escribir el camino retroactivo completo, por ejemplo 0 → auditoría y gate
de coronación equivalente a 1c → 2. No hace falta fingir que se reconstruyen 1a/1b si ya existen, pero
sí nombrar qué evidencia sustituye su ejecución.

---

## 5. Riesgos adicionales que el siguiente agente debe validar

Estos puntos surgieron al contrastar el diseño con el sistema actual. Son plausibles y tienen evidencia,
pero conviene que el siguiente agente los someta a una segunda revisión antes de elevarlos a bloqueantes.

### AUD-0007-R1 — ALTA potencial — `pending` puede convertir fallos obligatorios en waivers

El gate de fase 2 permite cerrar si `session-start --report` no emite ningún `⚠️` **o** si cada aviso
restante se registra como decisión `pending` con disparador.

El instrumento puede emitir, entre otros:

- `SIN COMPILADOR EN LOS GATES`;
- `ANILLO 3 AUSENTE`;
- `ANILLO 1 DORMIDO`;
- capacidad Semgrep ausente/rota;
- stack o matriz sin cobertura.

No todos son decisiones arquitectónicas diferibles. En preset `full`, AGENTS.md §14.4 declara el
Anillo 3 obligatorio. Permitir que cualquier warning se convierta en `pending` podría cerrar la fase
2 exactamente con el harness sin cablear, el riesgo que ese gate pretende impedir.

**Pregunta para resolver:** ¿qué avisos son legítimamente diferibles y cuáles son hard blockers? La
regla debería tiparlos o enumerar la categoría, no permitir un waiver universal por prosa.

### AUD-0007-R2 — MEDIA potencial — `AMBER-atendido` no tiene un artefacto terminal definido

El gate 1c acepta `security-reviewer` GREEN o “AMBER-atendido”. El reporte local prueba que hubo un
AMBER, no que todos sus hallazgos terminaron fixed/accepted/dropped ni que el diff corregido fue el
revisado.

**Pregunta:** ¿qué demuestra “atendido”? Una re-review, findings terminales en ledger o una aceptación
explícita y auditada deben producir un artefacto identificable. Sin eso, el término permite juicio
retrospectivo.

### AUD-0007-R3 — MEDIA potencial — La matriz usa refs estáticas, pero “el registro” son varios ADRs

El PRD propone que la fila del módulo de referencia en `skill-matrix.conf` exija leer la skill y “el
registro de decisiones”. El hook actual consume una lista estática de rutas; cada ref debe existir,
ser registrable por `track-reads` y aparecer también en la vista humana de AGENTS.md §11.

**Preguntas:**

- ¿la fila exigirá todos los ADRs decididos, un índice generado o un único registro agregado?;
- ¿quién actualiza la matriz cuando nace una decisión nueva?;
- ¿cómo se evita que AGENTS.md §11 se convierta en una lista de ADRs que crece sin límite?;
- ¿qué detector prueba que la lectura obligatoria cubre la decisión vigente y no un índice viejo?

La idea es implementable, pero el artefacto exacto no está definido y la afirmación “exige leer el
registro” es más fuerte que lo que hoy puede demostrarse.

### AUD-0007-R4 — BAJA — Falta una entrada de change log para el Approved completo

El encabezado y el mapa dicen `Approved COMPLETO`, y el commit `a20be1c` resuelve Q4/Q6. El change log
termina con Draft, v2.1 y v2; no tiene una fila que registre la extensión final del Approved. No rompe
el diseño, pero deja el evento terminal fuera del historial que debería explicarlo.

### AUD-0007-R5 — BAJA — El mapa repite parcialmente la ronda RED

El bloque del PRD 0007 en `current_execution_map.md` explica la ronda RED al principio y vuelve a
afirmar que “el design-review dio RED con 15 hallazgos” al final del resumen. Es redundancia, no
contradicción, pero aumenta el área de drift en el documento que debe mantenerse a una pantalla.

---

## 6. Verificación ejecutada

### 6.1 Checks documentales y de Git

- `git diff --check db371f2..a20be1c`: **verde**.
- El delta original solo tocó PRD 0007 y el mapa de ejecución.
- El árbol estaba limpio antes de crear este informe.
- Los tests de execution-map, skill-matrix, skill-reminder, verdict y verify-marker pasaron dentro de
  la suite completa.

### 6.2 Suite completa

Comando:

```bash
bash tools/tests/run-tests.sh
```

Resultado:

```text
633 pasaron
11 fallaron
exit 1
```

Fallos reportados:

```text
test_el_fixture_malo_dispara_todas_las_reglas
test_las_reglas_de_semgrep_cargan
test_androidmain_si_puede_importar_plataforma
test_el_registro_de_semgrep_no_pisa_ni_duplica_el_conf
test_un_comentario_que_nombra_el_paquete_no_es_un_import
test_un_commonmain_bajo_una_ruta_con_espacios_se_sigue_mirando
test_un_import_dentro_de_un_bloque_comentado_no_es_un_import
test_un_import_dentro_de_un_string_triple_no_es_un_import
test_androidx_multiplataforma_no_cuenta_como_import_de_plataforma
test_el_ancla_de_com_google_android_no_acusa_a_paquetes_vecinos
test_el_conf_amplia_la_lista_de_prohibidos
```

Todos se concentran en Semgrep/source-sets y sus fallbacks. El mapa ya declara que la capacidad runtime
de Semgrep en esta máquina está `broken`. Uno de los fallos mostró además
`tools/semgrep-scan.sh: TARGETS[@]: unbound variable`, y varios tests de KMP recibieron exit 3 o el
fallback textual produjo falsos positivos.

**Interpretación cauta:** estos tres commits son documentales y no modificaron las rutas de Semgrep o
source-sets, así que no introdujeron esos fallos. Sin embargo, la suite global **no está verde** y este
informe no debe presentarla como tal. El estado preexistente merece auditoría separada si no está ya
representado por findings abiertos.

---

## 7. Qué NO se considera un defecto

- AMBER no invalida el Approved: el contrato lo define como “OK con reservas” y aprueba el owner.
- `Tracking: pendiente` es coherente antes del primer commit de implementación.
- Aplazar el detector por el freeze es honesto; sería defecto fingir que existe o declarar `Shipped`.
- La comprobación manual temporal es válida si se declara como tal y deja evidencia.
- No actualizar tooling respeta el freeze y el alcance documental del rediseño.

---

## 8. Orden recomendado para una segunda auditoría

1. Abrir el árbol en `a20be1c` o identificar y leer commits posteriores que toquen PRD 0007.
2. Reproducir `AUD-0007-01` contra `verify-run` y `check-verify-marker` en preset `full`.
3. Dibujar los módulos reales de fase 1/3 y contar cuántas observaciones autónomas produce la entrega.
4. Buscar globalmente consumidores de `ARCH_DEVIATIONS`:

   ```bash
   rg -n "ARCH_DEVIATIONS" . --glob '!docs/process/reviews/2026-08-25-auditoria-prd-0007-workflow.md'
   ```

5. Enumerar los warnings reales de `session-start --report` y clasificarlos en:
   hard blocker / diferible / informativo.
6. Verificar qué artefacto durable guarda el resultado de design-review y el cierre de AMBER.
7. Simular el camino retroactivo de un adoptante existente y comprobar que no omita 1c.
8. Decidir si R1–R3 se confirman como findings; si se confirman, registrarlos en el ledger antes de
   editar el PRD, conforme a AGENTS.md §10.
9. Solo después proponer una v2.2. No implementar fases 0–3 mientras las contradicciones altas sigan
   abiertas.

---

## 9. Criterio de cierre de esta auditoría

La auditoría puede considerarse atendida cuando exista evidencia verificable de que:

- TDD rojo-primero tiene un artefacto compatible con commits verdes y markers ligados al diff;
- la fase 3 produce dos observaciones autónomas si N=2 sigue siendo el criterio;
- `ARCH_DEVIATIONS` tiene contrato, parser, persistencia y agregación, o se declara manual sin fingir
  enforcement mecánico;
- el camino retroactivo incluye el gate de coronación del módulo;
- la evidencia de design-review citada por el PRD sobrevive a otro clon;
- los warnings obligatorios no pueden dispensarse simplemente declarándolos `pending`;
- “AMBER-atendido” llega a un estado terminal visible.

Hasta entonces, el dictamen se mantiene en:

```text
VERDICT: AMBER
FINDINGS DEMOSTRADOS: 5 (3 altos, 2 medios)
RIESGOS A VALIDAR: 5 (1 alto potencial, 2 medios potenciales, 2 bajos)
SCOPE: PRD 0007 y mapa de ejecución, commits db371f2..a20be1c
```
