# Rising Padel Watch

Mide los golpeos de una sesión de pádel con el reloj, recoge las métricas de salud del
entrenamiento y las envía a tu app de liga y torneos.

Cuatro apps nativas — Apple Watch, iPhone, Wear OS y Android — sobre un core compartido
que contiene el algoritmo de detección, el modelo de datos y el cliente de
sincronización.

```
Reloj (sensores + workout) ──► Móvil (historial + cola) ──► App de liga
```

## Qué mide

- **Golpeos**: total, ritmo por minuto y desglose en derecha, revés, volea de derecha,
  volea de revés, bandeja/smash y saque.
- **Intensidad**: g de impacto y velocidad estimada de pala, media y máxima.
- **Salud**: frecuencia cardiaca media y máxima, tiempo en cada zona, calorías activas,
  pasos y distancia. Solo si das el consentimiento explícito.

## Empezar

```bash
# Lo único que corre sin SDK de móvil: el core y sus 51 tests
cd android/core && gradle test
```

Para compilar las apps, ver [`docs/setup.md`](docs/setup.md).

## Estructura

| Ruta | Qué es |
|---|---|
| `android/core` | Core Kotlin: detección, modelo, sync. Módulo JVM puro, con tests |
| `android/wear` | App Wear OS (Compose for Wear + Health Services) |
| `android/mobile` | App Android (Compose + WorkManager) |
| `ios/Packages/PadelCore` | Core Swift: el mismo algoritmo y contrato, con tests |
| `ios/RisingPadelWatch` | App watchOS (SwiftUI + HealthKit + CoreMotion) |
| `ios/RisingPadel` | App iPhone (SwiftUI) |
| `docs/` | Contrato con la liga, spec del algoritmo, setup, pendientes |

## Documentación

- [Arquitectura](docs/architecture.md) — cómo encajan las piezas y por qué
- [Contrato con la liga](docs/api-contract.md) · [OpenAPI](docs/openapi.yaml) — el
  endpoint que tu app de liga tiene que exponer
- [Detección de golpeos](docs/shot-detection.md) — el algoritmo, sus umbrales y sus
  límites
- [Puesta en marcha](docs/setup.md) — compilar, conectar la liga, calibrar
- [Pendiente](docs/backlog.md) — marcador de partido en el reloj y otras cosas decididas
  pero no hechas

## Dos cosas que conviene saber antes de usarlo

**El reloj tiene que ir en la muñeca de la pala.** Es el brazo que hace el swing; en la
otra muñeca el detector no ve nada útil. La app avisa cuando la configuración dice lo
contrario.

**La velocidad de pala es una estimación**, calculada a partir de la velocidad angular
de la muñeca. Sirve para comparar golpeos entre sí y seguir tu evolución, no como
velocímetro absoluto.

## Integración con la liga

La app no conoce el esquema interno de ninguna liga: habla un contrato REST propio
contra una URL base y un token que configuras en Ajustes. Para conectarla con
`rising-padel-manager` o `app-liga-padel` basta con implementar
`POST /v1/padel-sessions` según [el contrato](docs/api-contract.md), o poner un
adaptador delante.

La subida es idempotente (`Idempotency-Key: <sessionId>`), así que los reintentos nunca
duplican sesiones. Si no hay red o la liga está caída, las sesiones se guardan en el
móvil y se suben solas con backoff exponencial.

## Privacidad

Los datos de salud son categoría especial y se tratan como tal:

- Nada sale del dispositivo hasta que configuras la liga y activas el consentimiento.
- Con el consentimiento apagado, el reloj **ni siquiera arranca el workout**: no se
  miden.
- El token de la liga vive en el Llavero (iOS) y en `EncryptedSharedPreferences`
  (Android), nunca junto a las sesiones ni en logs.
- Las series crudas de sensores no se suben jamás: se quedan en el reloj y se descartan
  al cerrar la sesión.
