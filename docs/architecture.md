# Arquitectura

`rising-padel-watch` mide los golpeos de una sesión de pádel con el reloj, recoge las
métricas de salud del entrenamiento y las envía a la app de liga/torneos.

## Vista general

```
┌───────────────────────┐        ┌───────────────────────┐
│  Apple Watch          │        │  Wear OS              │
│  watchOS app          │        │  wear app             │
│                       │        │                       │
│  CoreMotion 50 Hz     │        │  SensorManager 50 Hz  │
│  HKWorkoutSession     │        │  ExerciseClient       │
│  ShotDetector         │        │  ShotDetector         │
└──────────┬────────────┘        └──────────┬────────────┘
           │ WatchConnectivity              │ Wearable Data Layer
           │ (transferUserInfo)             │ (DataClient)
           ▼                                ▼
┌───────────────────────┐        ┌───────────────────────┐
│  iPhone app           │        │  Android app          │
│  SessionStore (JSON)  │        │  SessionStore (JSON)  │
│  SyncQueue            │        │  SyncQueue            │
└──────────┬────────────┘        └──────────┬────────────┘
           │                                │
           └───────────┬────────────────────┘
                       ▼  HTTPS + Bearer token
           ┌───────────────────────────────┐
           │  App de liga / torneos        │
           │  POST /v1/padel-sessions      │
           └───────────────────────────────┘
```

La detección corre **en el reloj**, no en el móvil: el reloj es el único que tiene los
sensores en la muñeca, y así la sesión se puede jugar con el móvil en la bolsa o sin
móvil delante (los datos se encolan y se envían cuando hay conectividad).

## Decisiones

**100% nativo en las dos plataformas.** watchOS y Wear OS no admiten React Native ni
Flutter para la app de reloj, así que un stack híbrido obligaría igualmente a escribir
dos apps de reloj nativas. Aquí se escriben las cuatro apps nativas y se comparte el
*diseño* del core (mismo algoritmo, mismos modelos, mismo contrato JSON) entre Swift y
Kotlin, con la misma batería de tests en ambos lados.

**El core está aislado y es testeable sin dispositivo.**
- Swift: `ios/Packages/PadelCore` (Swift Package, sin dependencias de UIKit/WatchKit).
- Kotlin: `android/core` (módulo JVM puro, sin dependencias de Android).

Ambos módulos contienen: modelos de dominio, `ShotDetector`, `ShotClassifier`,
serialización del payload de sync y el cliente HTTP. Sus tests se ejecutan en CI sin
emulador ni simulador.

**Integración con la liga vía contrato REST propio.** El core no conoce el esquema
interno de la app de liga: habla el contrato de [`api-contract.md`](./api-contract.md)
contra una `baseURL` y un token configurables. Para conectar con
`rising-padel-manager` / `app-liga-padel` basta con implementar ese endpoint (o poner
un adaptador delante).

## Módulos

| Ruta | Qué es |
|---|---|
| `ios/Packages/PadelCore` | Core Swift compartido por iOS y watchOS |
| `ios/RisingPadel` | App iPhone (SwiftUI) |
| `ios/RisingPadelWatch` | App watchOS (SwiftUI + HealthKit + CoreMotion) |
| `android/core` | Core Kotlin JVM compartido por móvil y reloj |
| `android/mobile` | App Android (Compose) |
| `android/wear` | App Wear OS (Compose for Wear + Health Services) |
| `docs/` | Contrato, spec del algoritmo, setup |

## Flujo de una sesión

1. El jugador abre la app en el reloj y pulsa **Empezar**.
2. Arranca el workout (`HKWorkoutSession` / `ExerciseClient`) y el muestreo de
   acelerómetro y giroscopio a 50 Hz.
3. `ShotDetector` procesa cada muestra en streaming y emite un `Shot` por golpeo
   detectado (tipo, intensidad, velocidad estimada de pala, instante).
4. Al parar, el reloj cierra el workout, recoge las métricas de salud agregadas
   (FC media/máx, calorías activas, pasos, distancia) y construye una `PadelSession`.
5. La sesión viaja al móvil por WatchConnectivity / Data Layer.
6. El móvil la persiste y la encola en `SyncQueue`.
7. `SyncQueue` hace `POST` a la app de liga con `Idempotency-Key`; reintenta con
   backoff exponencial hasta confirmar.

## Privacidad

Los datos de salud son categoría especial. Reglas del proyecto:

- Nada sale del dispositivo hasta que el usuario configura la liga y da el
  consentimiento explícito de compartir (`shareHealthMetrics` en ajustes).
- Si el consentimiento está desactivado, se envían golpeos y duración pero **no** FC,
  calorías ni distancia (el payload omite el bloque `health`).
- El token de la liga se guarda en Keychain (iOS) / EncryptedSharedPreferences
  (Android), nunca en el store de sesiones ni en logs.
- Las series crudas de sensores no se suben nunca: se quedan en el reloj y se
  descartan al cerrar la sesión. Solo se suben eventos de golpeo agregados.
