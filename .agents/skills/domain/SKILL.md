---
name: domain
description: Referencia de la capa de dominio — entidades, puertos de repositorio, casos de uso, invariantes y errores de dominio. Invocar al escribir lógica de dominio o de datos. El dominio NO depende de UI ni de infraestructura.
---

# Dominio — <PROJECT>

> **Esta skill la rellena la empresa.** Define el contrato puro de tu negocio. Regla dura
> (universal): el dominio **no importa** UI, frameworks de red, ni SDKs de backend.

## Entidades
<!-- FILL: tus entidades de negocio y sus invariantes. -->
<!-- OPINIÓN: entidades sin lógica pesada ni dependencias de infra; value types/inmutables donde se pueda. -->

## Puertos de repositorio (interfaces)
<!-- FILL: las interfaces que la lógica usa para hablar con datos. -->
<!-- OPINIÓN: define el puerto por capability ("LoadX", "SaveY"), no un repo gigante. Sendable/thread-safe donde aplique. -->

## Casos de uso / reglas
<!-- FILL: las reglas de negocio reusables (composición de repos, validaciones). -->

## Errores de dominio
<!-- FILL: el tipo de error de dominio y su mapeo a mensajes de usuario. -->
<!-- OPINIÓN: errores TIPADOS, no strings; nunca propagues el error crudo de infra a la UI. -->

## Invariantes (qué nunca debe pasar)
<!-- FILL: lista de invariantes que tests/triggers/CI deben proteger. -->
