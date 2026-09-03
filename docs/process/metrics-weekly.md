# Métricas de entrega — resumen semanal

> Lo genera `bash tools/metrics/dora.sh --rollup` a partir de
> `.agents/state/metrics/series.jsonl`. **No se edita a mano.**
> El crudo es local y volátil; esto es lo que se versiona, así que
> es idempotente a propósito: sin fecha de generación, para que el
> diff solo cambie cuando cambian los datos.

> `n/a` = no hay evento que medir en este repo, y la razón está en la
> salida de `dora.sh`. No es lo mismo que 0.

| semana | frecuencia de entrega | tasa de fallo | tiempo de recuperación | tasa de aceptación |
|---|---|---|---|---|
| 2026-W36 | 12.1 | 0.0 | 2.4 | 25.4 |
