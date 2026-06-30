# <PROJECT> iOS — overrides de plataforma

> `AGENTS.md` anidado. Se **combina** con el raíz; el más cercano al archivo editado gana.
> Pon aquí SOLO lo específico de iOS; lo común queda en el raíz. Lo lee Cursor/Codex nativo.

## Stack iOS
<!-- FILL: Swift X, deployment target, SwiftUI/UIKit, SPM/Cocoapods, Xcode scheme -->

## Build & test iOS
<!-- FILL:
- build: xcodebuild -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 17' build
- test:  xcodebuild -scheme <Scheme> -destination '...' test
- spm:   swift test --package-path Packages/<Pkg>
-->

## Convenciones iOS específicas
<!-- OPINIÓN: la adaptación iPhone↔iPad vive DENTRO del componente reutilizable (SPM/módulo),
     no como `if idiom == .pad` repetido en pantallas. Design System tokeniza color/tipografía/
     spacing — prohibido `Color(hex:)`/`Font.system(size:)` suelto en una View. -->
<!-- FILL: tu Design System, tu patrón de pantalla, dónde vive cada cosa. -->

## Seguridad iOS
<!-- OPINIÓN: secretos/sesión → Keychain (no UserDefaults). Datos sensibles en disco →
     NSFileProtection. App Lock biométrico opcional. -->
