---
id: NNNN
titulo: <verbo + resultado, como el summary de un ticket>
status: ready        # ready | in-progress | in-review | done | blocked | ejemplo
depends_on: []       # ids que deben estar DONE (= mergeados a la base) antes: [0001, 0002]
base: develop        # rama desde la que se crea story/NNNN-<slug>
scope: |             # los archivos/módulos que la historia PUEDE tocar (§8: scope exclusivo)
  <rutas o globs>
---

# <mismo título>

## Historia
Como <rol> quiero <acción> para <valor>.

## Contexto
<Lo que el agente no puede deducir del código: decisiones ya tomadas, enlaces
a PRD/diseño, por qué ahora. 3-6 líneas.>

## Criterios de aceptación
<!-- OBLIGATORIOS y en formato verificable. Son los escenarios golden: cada uno
     se convierte PRIMERO en un test que falla (TDD §5). El runner BLOQUEA la
     historia si faltan — sin contrato verificable no se trabaja (§1.4). -->
1. Dado <estado inicial> cuando <acción> entonces <resultado observable>.
2. Dado <caso de error> cuando <acción> entonces <manejo esperado>.

## Fuera de scope
- <Lo que NO entra, explícito. Es tu mejor defensa contra el scope creep.>

## Notas técnicas (opcional)
<Pistas, no órdenes: patrón a seguir, archivo de referencia, gotchas.>
