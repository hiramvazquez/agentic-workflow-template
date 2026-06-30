# Arquitectura — específico iOS

> Rellena con las decisiones reales de tu app iOS. Mi opinión por defecto abajo.

## Patrón de pantalla
<!-- FILL -->
<!-- OPINIÓN: View (SwiftUI) + ViewModel (@MainActor) + Logic (Swift puro). La View renderiza
     estado y emite eventos; el ViewModel orquesta; la Logic tiene la regla de negocio (100% testeable). -->

## Navegación
<!-- FILL -->
<!-- OPINIÓN: Coordinator/Router central; NavigationStack solo en el Coordinator, no en cada View. -->

## DI
<!-- FILL -->
<!-- OPINIÓN: inyección por constructor; composition root en el App. -->

## Estado / carga / error
<!-- FILL -->
<!-- OPINIÓN: una máquina de estados de pantalla (loading/empty/content/error) en un contenedor
     reutilizable, no `if phase ==` regado en cada View. -->

## Design System
<!-- FILL -->
<!-- OPINIÓN: tokens (color/tipografía/spacing/radius) en un namespace único; prohibido
     `Color(hex:)`/`Font.system(size:)`/padding numérico suelto en una View. -->
