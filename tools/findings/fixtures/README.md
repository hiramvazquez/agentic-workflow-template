# Corpus de prosa AJENA para los checks del ledger

> El fixture BUENO es el que importa. Es el guard de falsos positivos de los dos
> detectores que leen prosa (`check-version-claims.sh`, `check-finding-refs.sh`),
> y existe por una lección concreta y cara.

`check-version-claims.sh` se validó contra el ledger del template: 38 entradas,
disparó en 1, y era la defectuosa. Parecía cirugía. El primer adoptante lo corrió
contra el suyo —61 entradas, prosa española densa, historias y criterios
numerados— y disparó 3 veces con **2 falsos positivos: 67%**, muy por encima del
10% que el propio detector cita como criterio de diseño.

Las dos causas eran invisibles desde dentro:

- `<palabra> <número>` casa sin parar en prosa española real: *criterio 6*,
  *la 0006*, *Los 3 únicos casts*, *nivel 4*.
- `tiene` estaba en la lista de verbos de incapacidad, y en español **"no tiene"
  es CARECER**, no "no soporta": *no tiene test*, *no tiene alternativa*.

De ahí la regla que este directorio mecaniza:

> **"Contra el artefacto real" incluye el artefacto real de OTRO.** Un detector
> que lee prosa se valida contra prosa que no escribiste tú. Quien escribe el
> detector escribe, sin querer, el corpus que lo aprueba.

## Los dos archivos

| Archivo | Qué es | Qué debe pasar |
|---|---|---|
| `ledger-bueno.jsonl` | prosa real de un adoptante, densa en números y en negaciones que NO son de soporte | **cero** hallazgos |
| `ledger-malo.jsonl` | una afirmación de no-existencia por cada forma que el detector caza | dispara en **todas** |

Las entradas marcadas `[adoptante]` son texto REAL, copiado literal del informe
del proyecto que las produjo. No las reescribas para que "queden mejor": su valor
está justamente en no haberlas escrito nosotros.

Al añadir una forma nueva al detector, añade su caso a `ledger-malo.jsonl`; al
arreglar un falso positivo, añade el texto que lo produjo a `ledger-bueno.jsonl`.
Los fija `tools/tests/test_finding_refs.sh`.
