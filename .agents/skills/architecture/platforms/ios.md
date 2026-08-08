# Arquitectura — específico iOS (SwiftUI vanilla + MVVM-C)

> Referencia **rellenada** del template. Stack: iOS 17+, Swift 6.2, SwiftUI, Swift Testing.
> Patrón: **View + @Observable @MainActor ViewModel + Logic/UseCase puro + Coordinator + DI por ctor**.
> Ajusta los `<!-- FILL -->` a los nombres reales de tu app.
>
> **Lee también `swift-estado-del-arte.md`** (misma carpeta): el estado VIVO del lenguaje —
> concurrencia 6.2 (approachable, actors, @concurrent), qué está prohibido (try!/as!/GCD) y
> qué aún no se usa. Evita que el agente programe "el Swift que memorizó".

## Estructura de carpetas (por feature)

```
Features/Profile/
  ProfileView.swift          // SwiftUI: renderiza estado, emite intención
  ProfileViewModel.swift     // @Observable @MainActor: orquesta estado de pantalla
  ProfileLogic.swift         // (o UseCase) Swift puro, 100% testeable
Domain/                      // entidades + puertos (protocolos) + errores (ver skill domain)
Data/                        // implementaciones de puertos (red/DB/Keychain)
App/                         // composition root + Coordinator
```

## Patrón de pantalla (3 capas)

| Capa | Hace | NO hace |
|---|---|---|
| **View** (SwiftUI) | renderiza `state`, emite intención | lógica de negocio, llamadas a datos |
| **ViewModel** (`@Observable @MainActor`) | mantiene el estado de pantalla, llama UseCases | reglas de negocio, acceso directo a red/DB |
| **Logic/UseCase** (Swift puro) | la regla de negocio, composición de puertos | tocar UI, conocer navegación |

```swift
// ProfileViewModel.swift
@Observable @MainActor
final class ProfileViewModel {
    enum State: Equatable { case loading, content(Profile), error(String) }
    private(set) var state: State = .loading
    private let loadProfile: LoadProfileUseCase   // puerto inyectado por ctor

    init(loadProfile: LoadProfileUseCase) { self.loadProfile = loadProfile }

    func onAppear() async {
        do { state = .content(try await loadProfile()) }
        catch { state = .error(ProfileError.from(error).userMessageKey) }
    }
}
```

## Navegación — Coordinator

Un Coordinator/Router central posee el `NavigationStack` (path). Las Views **emiten intención** de
navegar; no construyen rutas ni anidan stacks.

```swift
@Observable @MainActor final class AppCoordinator {
    var path: [Route] = []
    func show(_ route: Route) { path.append(route) }
}
enum Route: Hashable { case profile(id: String), settings }
```
<!-- FILL: tu enum Route real + dónde se monta el NavigationStack(path:). -->

## DI — inyección por constructor

Constructor injection por defecto. El **composition root** (en `App`) arma el grafo:
repos concretos → UseCases → ViewModels. Nada de singletons globales mutables ni service locator
dentro del dominio.

```swift
@main struct MyApp: App {
    private let env = AppEnvironment.live()   // arma repos + usecases concretos
    var body: some Scene { WindowGroup { RootView(env: env) } }
}
```

## Estado / carga / error

- Máquina de estados de pantalla (`loading/empty/content/error`) en el ViewModel o un contenedor
  reutilizable. Prohibido `if phase == ...` regado por cada View.
- Errores de infra **nunca** llegan crudos a la UI: se mapean a un error de dominio tipado con
  `userMessageKey` que la View localiza (ver skill `domain`).

## Acceso a datos

- La View/VM hablan con **puertos (protocolos)** del dominio, no con el SDK/red directo.
- Implementaciones concretas en `Data/`, inyectadas por ctor. `async/await`; tipos `Sendable`.
- <!-- FILL: tu cliente HTTP/DB real, estrategia de caché/refresh. -->

## Design System

Tokens (color/tipografía/spacing/radius) en un namespace único. **Prohibido** `Color(hex:)` /
`Font.system(size:)` / padding numérico suelto en una View (lo caza `check-drift`).
<!-- FILL: el namespace de tokens real de tu app. -->

## iPhone ↔ iPad

La adaptación vive DENTRO del componente reutilizable, no como `if idiom == .pad` repetido en pantallas.
