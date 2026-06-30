# PRD — [Nombre del feature]

> **Tipo:** [Forward | Retrospective] · **Status:** [Draft | Approved | In progress | Shipped | Deprecated]
> **Autor:** [nombre] · **Fecha:** YYYY-MM-DD · **Tracking:** [tickets / commits / migraciones]
> **Design-review:** [pendiente | OK (fecha) | waiver del owner (razón)]

---

## 1. Contexto
[¿Qué existe hoy? ¿Por qué surge esto ahora?]

## 2. Problema
[El dolor concreto. ¿Para quién? ¿Qué pasa si NO lo construimos?]

## 3. Objetivo
[Qué cambia cuando esté hecho. Medible si se puede.]

## 4. Filosofía / principios
[Las 1-3 decisiones de diseño que guían el resto.]

## 5. Estructura de archivos a crear / tocar
```
[ruta]   ← [qué hace]
```
### NO-TOUCH (contrato — el implementador NO toca esto)
```
[ruta]   ← [por qué es intocable]
```

## 6. Modelo de datos
[Entidades, schema, contratos de API/edge nuevos o modificados. Contrato PRIMERO si aplica.]

## 7. Flujo de la solución
### User stories
- Como [rol] quiero [acción] para [valor].
### Edge cases
- [Qué pasa cuando … ]

## 8. Anti-features (qué NO entra)
- [Explícitamente fuera de scope.]

## 9. Escenarios golden (deben pasar al terminar)
1. [Dado … cuando … entonces … ]

## 10. Métricas de éxito
[Cómo sabremos si funcionó, 2-4 semanas después.]

## 11. Rollout
[Flag, fases, migración de datos, rollback.]

## 12. Riesgos
[Qué puede salir mal + mitigación.]

## 13. Open Questions
- [ ] [Pregunta sin resolver — bloquea `Approved` si es crítica.]

## 14. Mockups / referencias
[Links o ASCII.]

## 15. Definition of Done
- [ ] Escenarios golden pasan
- [ ] **TDD**: cada unidad de lógica tiene test escrito primero (happy + ≥2 errores), todos verdes · build verde · check-drift sin errores nuevos
- [ ] `reviewer` GREEN/AMBER atendido · `security-reviewer` si tocó datos sensibles
- [ ] Docs/skills actualizados en el mismo PR
- [ ] Sin secretos (gitleaks limpio)

## 16. Próximos pasos
[Follow-ups conocidos.]

## 17. Change log
| Fecha | Cambio | Quién |
|---|---|---|

## 18. Gaps detectados (llenar post-ship)
[Lo que aprendimos construyéndolo — alimenta lessons_learned + ledger.]
