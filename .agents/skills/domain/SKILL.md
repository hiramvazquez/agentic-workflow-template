---
name: domain
description: Referencia de la capa de dominio — entidades, puertos de repositorio, casos de uso, invariantes y errores de dominio. Invocar al escribir lógica de dominio o de datos. El dominio NO depende de UI ni de infraestructura.
---

# Dominio — <PROJECT>

> Define el contrato puro del negocio. **Regla dura (universal):** el dominio **no importa** UI,
> frameworks de red, ni SDKs de backend. Ejemplos en Swift (iOS de referencia); el principio es
> agnóstico. Rellena los `<!-- FILL -->` con TU negocio. La lógica aquí es TDD-first (`process/references/tdd-workflow.md`).

## Entidades

Value types inmutables donde se pueda; sin lógica pesada ni dependencias de infra; `Sendable`.

```swift
struct Profile: Equatable, Sendable {
    let id: String
    let name: String
    let plan: Plan
}
enum Plan: String, Sendable { case free, pro }
```
<!-- FILL: tus entidades reales y sus invariantes. -->

## Puertos de repositorio (protocolos)

Define el puerto **por capability** ("LoadX", "SaveY"), no un repo gigante. `Sendable` donde aplique.

```swift
protocol LoadProfileUseCase: Sendable {            // puerto = capability, invocable como función
    func callAsFunction() async throws -> Profile
}
protocol ProfileRepository: Sendable {
    func fetch(id: String) async throws -> Profile
}
```
<!-- FILL: los puertos que tu lógica necesita. -->

## Casos de uso / reglas

Componen puertos + validaciones. Swift puro, testeable sin UI ni red (inyecta reloj/UUID, no `Date()`).

```swift
struct LoadProfile: LoadProfileUseCase {
    let repo: ProfileRepository
    let currentUserId: () -> String
    func callAsFunction() async throws -> Profile {
        try await repo.fetch(id: currentUserId())
    }
}
```
<!-- FILL: tus reglas de negocio reusables. -->

## Errores de dominio (tipados)

Errores **tipados**, no strings; nunca propagues el error crudo de infra a la UI. Mapea a `userMessage`.

```swift
enum ProfileError: Error, Equatable {
    case notFound, offline, unknown
    static func from(_ error: Error) -> ProfileError { (error as? ProfileError) ?? .unknown }
    var userMessageKey: String {            // i18n: clave, no texto suelto (ver AGENTS.md §3)
        switch self {
        case .notFound: "profile.error.notFound"
        case .offline:  "profile.error.offline"
        case .unknown:  "profile.error.unknown"
        }
    }
}
```
<!-- FILL: tu tipo de error de dominio y su mapeo a claves de localización (NO texto natural en la lógica). -->

## Invariantes (qué nunca debe pasar)

<!-- FILL: invariantes que tests/CI deben proteger. Ej.: "un Profile con plan .pro siempre tiene método de pago". -->
