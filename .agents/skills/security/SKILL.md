---
name: security
description: Usar al manejar secretos, credenciales, datos sensibles (PII/PHI), almacenamiento, logging, autorización o dependencias. Reglas de seguridad básicas que aplican a CUALQUIER plataforma + checklist del sub-agente security-reviewer.
when_to_use: Al tocar autenticación, autorización, secretos, criptografía, almacenamiento de datos personales, logging de datos de usuario, migraciones de base de datos o dependencias nuevas.
paths:
  - "**/auth/**"
  - "**/Auth/**"
  - "**/security/**"
  - "**/crypto/**"
  - "**/migrations/**"
  - "**/*Keychain*"
  - "**/*Credential*"
  - "**/*Token*"
---

<!-- Esta skill es el conocimiento. El ENFORCEMENT vive en tres sitios distintos,
     de más barato a más caro:
       .claude/security-patterns.yaml  → match determinista por edición (0 tokens)
       .claude/claude-security-guidance.md → contexto del revisor de modelo
       .gitleaks.toml + canon-enforce  → gates que bloquean
     Si añades una regla aquí y no la reflejas en al menos uno de esos, es prosa. -->

# Seguridad — <PROJECT>

> Skill mayormente rellenada (las reglas base son universales). Lo específico de plataforma va en
> §Por plataforma. La detección mecánica la hace `gitleaks` (Anillo 1+3); la semántica, el
> sub-agente `security-reviewer`. Esta skill es lo que el scanner NO ve.

## Las 6 reglas base (no negociables)

1. **Cero secretos en código.** API keys, tokens, claves privadas, connection strings, certificados →
   variables de entorno / secret manager. Nunca hardcoded, nunca commiteado, nunca en el bundle del cliente.
2. **Cero secretos en logs / telemetría / mensajes de error** que salgan del proceso o lleguen al cliente.
3. **Datos sensibles (PII/PHI) → almacenamiento seguro** de la plataforma (cifrado / Keychain / Keystore),
   nunca en almacenamiento en claro (UserDefaults / SharedPreferences / localStorage planos).
4. **Autorización por recurso.** Toda lectura/escritura de datos de usuario valida identidad y permiso
   (RLS / policies / checks server-side). Nunca confíes solo en el cliente.
5. **Cifrado in-transit y at-rest.** TLS para todo; cifrado at-rest verificado en la DB/almacenamiento.
6. **Dependencias auditadas.** Sin paquetes no confiables para cripto/secretos; revisa el lockfile en cada PR.

## Manejo de errores en paths sensibles

- **Fail-closed** en authz/cripto: ante duda, denegar. **Loguea la señal, nunca el dato** ("auth falló para user X", no el token).
- No tragues silenciosamente errores de seguridad (fail-silent oculta brechas).

## Checklist del `security-reviewer` (qué revisa por PR)

- [ ] ¿Hay literales que parezcan secretos? (incluso "de prueba" con formato real)
- [ ] ¿Algún secreto/token/PII llega a un log, analytics, o crash report?
- [ ] ¿Datos sensibles van a almacenamiento inseguro?
- [ ] ¿Endpoints/queries nuevos tienen authz por fila/recurso?
- [ ] ¿Input externo se valida/sanitiza? (inyección, XSS, deserialización)
- [ ] ¿Se añadió una dependencia que toca cripto/secretos sin auditar?
- [ ] ¿`.gitignore` cubre los archivos de secretos nuevos?

## §Por plataforma

<!-- FILL: completa lo de TU stack. Opiniones por defecto: -->
- **iOS:** secretos/sesión → Keychain. Archivos sensibles → `NSFileProtection`. App Lock biométrico opcional.
- **Android:** `EncryptedSharedPreferences` / Keystore; `EncryptedFile`. Sin claves en `strings.xml` ni en el APK.
- **Web:** sesión en cookies `httpOnly`+`Secure`, no `localStorage`. Secretos solo server-side, nunca en `NEXT_PUBLIC_*`/bundle. CSP + sanitización.
- **Backend/DB:** RLS/policies activas; service-role keys solo server-side; rota credenciales expuestas de inmediato.

## Si encuentras un secreto ya commiteado

1. **Rótalo YA** (asume comprometido). 2. Quítalo del código + añade a `.gitignore`.
3. Considera limpiar historial (`git filter-repo`) si era válido. 4. Registra en el ledger (`tools/findings/`).
