# TDD Workflow — 🔴 red → 🟢 green → ♻️ refactor

> El loop canónico de implementación del proyecto. La **disciplina** es universal; los comandos y
> patrones de abajo son de **iOS** (Swift Testing + XCTest). Otras plataformas: el mismo loop con su runner.

## La regla dura

**Ninguna unidad de lógica o de orquestación entra sin un test que haya FALLADO antes de escribir
la implementación.** Si el test pasa antes de implementar, no prueba lo que crees.

- **Aplica a:** lógica de dominio / casos de uso, ViewModels/orquestadores, mapeos, validaciones,
  parsing, reducers, formateadores.
- **NO obligatorio para:** glue de UI puro sin lógica, spikes desechables (márcalos y bórralos),
  wiring de DI trivial. Si dudas, escribe el test.

## El ciclo

1. 🔴 **RED** — escribe UN test del comportamiento esperado (happy path). Córrelo y míralo
   **fallar por la razón correcta** (aserción, no un error de compilación/typo).
2. 🟢 **GREEN** — la implementación **mínima** que lo pone verde. Nada fuera del test (scope = el test).
3. ♻️ **REFACTOR** — con el test en verde, limpia (nombres, duplicación, capas) y re-corre.
4. Repite por cada comportamiento. Añade **≥2 ramas de error/borde** antes de cerrar la unidad.

> **Bug fix = regresión primero:** 🔴 un test que **reproduce el bug** (falla) → 🟢 fix → ♻️ limpia.
> Ese test es la prueba de que lo arreglaste y de que no vuelve.

## iOS — runner y estructura

- **Framework:** **Swift Testing** (Xcode 16+, `import Testing`, `@Test`, `#expect`, `#require`).
  XCTest sigue válido para casos legacy y UI tests (`import XCTest`, `XCTestCase`).
- **Correr:**
  - `swift test` — paquetes SwiftPM; rápido para lógica pura.
  - `xcodebuild test -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 16'`
  - <!-- FILL: el comando/scheme/destino reales de tu proyecto. -->
- **Dónde viven:** target de tests espejo del de producción (`Sources/Domain` → `Tests/DomainTests`).
- **Naming por comportamiento:** `loadProfile_whenOffline_returnsCachedValue`.

## Patrones iOS clave

- **Fakes por protocolo (puerto), no por clase concreta.** La lógica depende de un protocolo; el
  test inyecta un fake. **Nada de red real** en unit tests.
- **Async:** `@Test func ...() async throws { ... }` + `await`; `#expect(try await sut.x() == y)`.
- **`@MainActor`** en tests de ViewModels que tocan estado de UI.
- **Determinismo:** inyecta reloj/fecha/UUID; nunca `Date()`/`UUID()` directo dentro de la lógica testeable.

## Ejemplo (red → green → refactor)

Caso: `GreetingUseCase` saluda según la hora; de noche (≥21h) devuelve un saludo distinto.

```swift
// 🔴 RED — Tests/DomainTests/GreetingUseCaseTests.swift
import Testing
@testable import Domain

@Test func greeting_atNight_saysGoodNight() {
    let sut = GreetingUseCase(clock: FixedClock(hour: 23))   // FixedClock: fake del puerto, vive en el target de tests
    #expect(sut.greeting() == .goodNight)
}
```
```swift
// 🟢 GREEN — Sources/Domain/GreetingUseCase.swift
struct GreetingUseCase {
    let clock: Clock                                  // puerto (protocolo), inyectado por ctor
    func greeting() -> Greeting {
        clock.hour() >= 21 ? .goodNight : .hello
    }
}
```
```swift
// ♻️ REFACTOR — con el test en verde, añade ramas de borde como @Test extra:
//   greeting_atMidnight_saysGoodNight (0h), greeting_atNoon_saysHello (12h).
```

## Anti-patrones

- ❌ Escribir el test **después** de la implementación "para tener cobertura" — no es TDD y suele
  testear la implementación, no el comportamiento.
- ❌ Tests acoplados a detalles internos (privados, orden de llamadas) → se rompen al refactorizar.
- ❌ Mocks que verifican "se llamó a X" en vez del **resultado observable**.
- ❌ Lógica en la View/ViewModel que no se puede testear sin levantar UI → muévela a la capa pura.

## Qué exige el enforcement (no es solo doc)

- **`tester`** (sub-agente): escribe los tests siguiendo este loop.
- **`reviewer`**: marca RED si una unidad de lógica nueva no trae test happy + ≥2 errores.
- **`check-drift.sh`**: señala lógica nueva sin archivo de test espejo.
- **DoD del PRD**: "tests (happy + errores) verdes" es checkbox obligatorio de cierre.
