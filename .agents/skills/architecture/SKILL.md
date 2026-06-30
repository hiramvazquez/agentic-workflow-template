---
name: architecture
description: Usar cuando la pregunta toca la arquitectura del código — patrón de pantalla/módulo, navegación, inyección de dependencias, capas, manejo de errores, acceso a datos. Es el HOW del código (no el WHAT del producto).
---

# Arquitectura — <PROJECT>

> **Esta skill la rellena la empresa.** Aquí va el HOW de TU código. Dejo la estructura y mi
> opinión por defecto (`<!-- OPINIÓN: ... -->`); reemplaza los `<!-- FILL: ... -->` con tus decisiones reales.
> Lo específico de cada plataforma vive en `platforms/{ios,android,web}.md`.

## Qué cargar por tema

| Pregunta | Dónde está |
|---|---|
| "¿Cómo construyo una pantalla/módulo nuevo?" | esta skill §Patrón + `platforms/<plataforma>.md` |
| "¿Qué va en la capa de orquestación vs lógica?" | esta skill §Capas |
| "¿Cómo navego entre pantallas?" | esta skill §Navegación |
| "¿Cómo registro/inyecto una dependencia?" | esta skill §DI |
| "¿Cómo llamo a datos/backend?" | esta skill §Datos |

## §Patrón de pantalla/módulo

<!-- FILL: define TU patrón canónico y sus capas. -->
<!-- OPINIÓN: separa en archivos distintos (1) presentación/UI, (2) orquestación de estado,
     (3) lógica de negocio pura y testeable. La lógica NO vive en la UI ni en el orquestador.
     Ej. iOS: View+ViewModel+Logic · Android: Composable+ViewModel+UseCase · Web: Component+hook+service. -->

| Capa | Qué hace | Qué NO hace |
|---|---|---|
| Presentación | <!-- FILL --> | lógica condicional de negocio, llamadas a datos |
| Orquestación | <!-- FILL --> | validación de reglas, acceso directo a repos |
| Lógica pura | <!-- FILL --> | tocar UI, conocer navegación |

## §Capas y límites

<!-- FILL: cómo se apilan App / Feature / Domain / Data / Core en tu repo. -->
- Toda dependencia que cruza capa va por **interfaz/protocolo** + **inyección por constructor**.
- El **dominio** (entidades, puertos, errores) NO importa UI ni infraestructura (ver skill `domain`).

## §Navegación

<!-- FILL: tu mecanismo (Coordinator / Router / Navigation Compose / file-based routing). -->
<!-- OPINIÓN: centraliza la navegación en una capa dedicada; las pantallas emiten intención,
     no construyen rutas. Evita stacks de navegación anidados. -->

## §Inyección de dependencias (DI)

<!-- FILL: cómo registras e inyectas (manual ctor / Hilt / Koin / container / context). -->
<!-- OPINIÓN: inyección por constructor por defecto; el service locator global solo en el
     composition root, nunca dentro de la lógica de dominio. -->

## §Acceso a datos

<!-- FILL: cómo se habla con el backend/DB, dónde viven los repositorios, caché/refresh. -->

## Fuentes de verdad

- <!-- FILL: rutas reales del composition root, navegación, paquetes/módulos. -->

## Mantenimiento

- Cuando cambies un patrón arquitectónico, **actualiza esta skill en el mismo PR** (nunca solo en el código).
- Marca con `<!-- TODO: validar -->` lo que infieras sin certeza; resuélvelo antes de usarlo en producción.
