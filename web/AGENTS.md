# <PROJECT> Web — overrides de plataforma

> `AGENTS.md` anidado. Se combina con el raíz; el más cercano gana. Solo lo específico de web.

## Stack Web
<!-- FILL: framework (Next/React/Svelte/…), TypeScript X, package manager, runtime -->

## Build & test Web
<!-- FILL:
- build:     npm run build
- test:      npm test
- typecheck: npx tsc --noEmit
- lint:      npx eslint .
-->

## Convenciones Web específicas
<!-- OPINIÓN: separar componentes de presentación de hooks/lógica; estado de servidor vs cliente
     explícito; design tokens vía CSS vars / theme, no valores mágicos en componentes. -->
<!-- FILL: tu arquitectura de carpetas, routing, data-fetching, DI/context. -->

## Seguridad Web
<!-- OPINIÓN: NUNCA secretos en el bundle del cliente ni en NEXT_PUBLIC_*. Tokens de sesión en
     cookies httpOnly+Secure, no en localStorage. CSP + sanitización de HTML. Secretos solo server-side. -->
