# <PROJECT> Android — overrides de plataforma

> `AGENTS.md` anidado. Se combina con el raíz; el más cercano gana. Solo lo específico de Android.

## Stack Android
<!-- FILL: Kotlin X, minSdk/targetSdk, Jetpack Compose/Views, Gradle, módulos -->

## Build & test Android
<!-- FILL:
- build: ./gradlew assembleDebug
- test:  ./gradlew testDebugUnitTest
- lint:  ./gradlew ktlintCheck
-->

## Convenciones Android específicas
<!-- OPINIÓN: una sola fuente de adaptación a tamaños (window size classes) dentro de
     componentes reutilizables. Tokens de tema en un solo lugar (no colores hardcoded en Composables). -->
<!-- FILL: tu patrón (MVVM/MVI), navegación (Navigation Compose), DI (Hilt/Koin). -->

## Seguridad Android
<!-- OPINIÓN: secretos/sesión → EncryptedSharedPreferences / Keystore (no SharedPreferences planas).
     Datos sensibles → EncryptedFile. Sin claves en strings.xml ni en el APK. -->
