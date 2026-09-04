# PRD 0010 — V1: un cambio normal llega a commit sin arreglar el workflow

**Estado:** Approved (owner, 2026-09-04) · **Owner:** hiram · **Tipo:** estabilización

---

## 1. Contexto

El harness tiene tres anillos de gates, una suite grande y un ledger con decenas de
hallazgos abiertos (las cifras exactas las dan `run-tests.sh` y `findings.sh list`, no
este documento). Lo que no tiene es una **frontera declarada**: cada sesión encuentra
trabajo nuevo porque nada dice dónde termina. Este PRD la fija y deja de moverla.

## 2. Problema

Un cambio pequeño no llega a commit de forma predecible. En las últimas sesiones,
cada unidad de trabajo abrió trabajo auxiliar: un detector que se dispara en falso,
una cita que caduca, un gate que reescribe el árbol. El coste real no es el cambio,
es la cascada.

## 2b. El baseline, medido el 2026-09-04

| Nivel | Tiempo | Exit | Nota |
|---|---:|---|---|
| Cuatro detectores sueltos | 0,65 s | 0 | drift, capas, mapa, matriz |
| Gates de pre-commit (lefthook) | 4,0 s | — | es el fast path que ya existe |
| `validate-harness` | 3,8 s | 0 | |
| Suite completa | ~140 s | 0 | tras cerrar el bloqueante del mapa |

Dependencias: `semgrep` 1.172.0 **operational** (el mapa afirmaba `broken`; era falso),
`gh` 2.97, `gitleaks` 8.30.1, `lefthook` 2.1.10, `python3` 3.14.6, `shellcheck`.
Ausente: `timeout` (no viene en macOS).

**El baseline arrancó ROJO y determinista**: tres corridas, los mismos dos fallos. La
causa no era flaky, era el detector del mapa exigiendo una edición por commit. Eso lo
convierte en el primer bloqueante de V1, y está cerrado.

## 3. Objetivo

**Un cambio pequeño llega a commit con pruebas verdes, UNA revisión en el caso
normal, y sin corregir el propio workflow por el camino.**

No es cero findings. No es el workflow perfecto.

## 4. Filosofía / principios

- **P1 — La línea de meta está congelada.** Mientras este PRD corre no se abren
  auditorías generales, no se añaden gates "que estaría bien tener", y un hallazgo
  fuera de scope se registra pero no se arregla.
- **P2 — Un `exit 3` no es una regresión, pero tampoco es verde.** El baseline
  conserva esa distinción en todos sus informes.
- **P3 — Un gate corrector modifica SOLO lo que declara, o se limita a avisar.** Si
  la reparación automática compromete la identidad del diff, falla con instrucción.
- **P4 — Los `high` se clasifican, no se cierran todos.** Cuatro estados posibles:
  bloqueante de V1, corregido con evidencia, aceptado con límite y mitigación, o
  fuera de la ruta crítica.

## 5. Estructura de archivos a crear / tocar

```
docs/process/prds/0010-v1-estable.md   ← este contrato
tools/verify.conf                       ← declara los tres niveles si hoy solo expresa uno
tools/verify-run.sh                     ← f-5a4e0204: firma un árbol con ficheros sin trackear
scripts/agent-hooks/capture-review-verdict.sh ← f-cb48c808: el marker se firma al PARAR
tools/check-exec-bits.sh                ← Paso 7: repara el fichero entero para un bit de modo
docs/process/current_execution_map.md   ← criterio 8: un estado, un próximo paso
docs/process/findings-ledger.md · tools/findings/ledger.jsonl ← clasificación de los high
```

### NO-TOUCH

```
tools/mutation-ratchet.json · tools/drift-ratchet.json  ← trinquetes (§9)
.github/workflows/**        ← el entorno oficial se DECLARA aquí, se cablea con autorización
proyecto adoptante          ← criterio 9; sin autorización no se toca
```

## 5b. Fases entregables

| Fase | Entrega | Criterio que cierra |
|---|---|---|
| **1** | Baseline medido y clasificado; entorno oficial declarado | 1, 2 |
| **2** | Los tres niveles (fast / targeted / full) con sus tiempos reales | 3, 4 |
| **3** | Los 9 `high` clasificados; los de la ruta crítica, cerrados como unidades | 5, 6, 7 |
| **4** | Gates correctores acotados a lo que declaran | 7 (Paso 7) |
| **5** | Prueba de uso end-to-end medida | 9 |

## 6. Modelo de datos

Ninguno nuevo. La clasificación de los `high` vive en el campo `detail` del ledger,
no en un fichero aparte.

## 7. Flujo de la solución

Cada unidad: objetivo y ficheros → `check-diff-nature` → test rojo por la razón
correcta → implementación mínima → test verde → mutante dirigido **con assert de que
se aplicó** → fast path → suite proporcional → reviewer → commit.

## 8. Anti-features (qué NO entra)

- Cerrar los 85 findings.
- Métricas, agentes, dashboards o gates nuevos.
- Un runner nuevo: los tres niveles salen de configuración del actual.
- Sustituir la prueba end-to-end real por una simulación presentada como equivalente.
- Documentación auxiliar que no cierre un criterio.

## 9. Escenarios golden (deben pasar al terminar)

1. `bash tools/tests/run-tests.sh` → exit 0 en el entorno oficial.
2. Una herramienta ausente produce `exit 3` con su razón, y ningún informe lo cuenta
   como verde ni como regresión.
3. El fast path corre en segundos y se mide, no se estima.
4. Un cambio pequeño real: rojo → verde → una review → commit, sin tocar ficheros
   auxiliares que no sean su propio test y su ledger.
5. Ningún `high` queda en estado ambiguo.

## 10. Métricas de éxito

Las del Paso 8, medidas sobre la prueba de uso: tiempo total, número de revisiones,
ficheros auxiliares tocados, findings nuevos, intervenciones manuales, y si la suite
falló por algo ajeno al cambio.

## 11. Rollout

Sin push ni tag hasta autorización del owner.

## 12. Riesgos

- **El reviewer muta el árbol de trabajo compartido.** Cualquier medición o `git add`
  concurrente puede capturar un mutante; existe `.agents/mutation.lock` para
  declararlo pero nada obliga a esperarlo. Ya causó un incidente (`check-exec-bits`
  stageó un mutante). Mitigación en esta sesión: no medir con el lock puesto.
- **`f-wf01-ci-macos-intermitente` (la familia flaky de macOS)** no se reprodujo en el baseline: tres corridas
  seguidas dieron el MISMO fallo determinista, no fallos intermitentes. Sigue abierto
  como riesgo pero deja de ser el argumento para descartar el entorno local.

## 13. Open Questions

- [x] **OQ-1 — CERRADA por el owner, 2026-09-04.** La frescura del mapa deja de
      bloquear y pasa a avisar; las violaciones de contenido siguen duras. Era la
      causa del rojo determinista: en un repo donde el producto es `tools/`, exigir
      el mapa en cada commit pide historia a un documento que no la guarda.
- [ ] **OQ-2.** ¿El entorno oficial de certificación es local o CI? El baseline local
      da verde; falta caracterizar la estabilidad con varias corridas y decidir si CI
      ejecuta realmente todas las dependencias.

## 15. Definition of Done

Los diez criterios del encargo, cada uno con comando, exit code y estado. La tabla
final es la entrega.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-09-04 | Nace para fijar la frontera de V1 y dejar de moverla | sesión de estabilización |
