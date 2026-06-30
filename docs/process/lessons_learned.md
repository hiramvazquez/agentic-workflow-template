# Lecciones aprendidas — no repetir

> **Léelo antes de escribir código.** Registro de trampas CONCRETAS ya pisadas. Si tocas un área
> cubierta aquí, sus reglas son obligatorias. Si cazas un patrón de error nuevo, **agrégalo en el
> mismo cambio** (no en un follow-up que nunca llega).

## Cómo usar este doc

- Cada entrada = un error real + la regla para no repetirlo + (idealmente) el detector que lo previene.
- Si una lección se puede automatizar, abre el detector en `tools/check-drift.sh` o un check del `reviewer`.
- El racional largo vive aquí; las reglas duras destiladas viven en `AGENTS.md`.

## Plantilla de entrada

```
### [AAAA-MM-DD] <título corto del error>
- **Qué pasó:** <síntoma observable>
- **Causa raíz:** <por qué>
- **Regla:** <qué hacer/no hacer a partir de ahora>
- **Detector:** <check-drift / reviewer / test / "manual"> 
- **Área:** <path o módulo>
```

---

<!-- FILL: aquí van TUS lecciones. Ejemplos de categorías universales que casi todo proyecto acumula: -->

<!--
### [AAAA-MM-DD] Secreto de prueba con formato real commiteado
- Qué pasó: un fixture de test tenía una API key con formato válido; gitleaks la marcó tarde.
- Causa raíz: usar formato real "para que parezca de verdad".
- Regla: en fixtures usa formatos OBVIAMENTE inválidos (AKIAFAKE…); secretos reales van por env en CI.
- Detector: gitleaks + allowlist por PATH (no por categoría).
- Área: tests/fixtures
-->

<!--
### [AAAA-MM-DD] Lógica ramificó sobre texto en lenguaje natural
- Qué pasó: `if frecuencia == "diaria"` rompió al añadir un segundo idioma.
- Regla: clasifica por enum/clave keyed por idioma, nunca por el texto visible.
- Detector: check-drift grep por comparaciones de strings de UI en la capa de lógica.
-->
