# Rising Padel Watch

[![CI](https://github.com/jgarcianiet-web/rising-padel-watch/actions/workflows/ci.yml/badge.svg)](https://github.com/jgarcianiet-web/rising-padel-watch/actions/workflows/ci.yml)

Mide los golpeos de una sesión de pádel con el reloj, recoge las métricas de salud del
entrenamiento y las envía a tu app de liga y torneos.

Cuatro apps nativas — Apple Watch, iPhone, Wear OS y Android — sobre un core compartido
que contiene el algoritmo de detección, el modelo de datos y el cliente de
sincronización.

```
Reloj (sensores + workout) ──► Móvil (historial + cola) ──► App de liga
```

## Qué mide

- **Marcador**: puntuación completa de pádel llevada desde el reloj — puntos, juegos,
  sets, tie-break y cambios de pista — con el resultado sincronizado a la liga. A 40-40
  se elige entre ventajas, punto de oro y star point.
- **Golpeos**: total, ritmo por minuto y desglose en derecha, revés, volea de derecha,
  volea de revés, bandeja, víbora, smash y saque.
- **Intensidad**: g de impacto y velocidad estimada de pala, media y máxima.
- **Nivel técnico**: cada golpeo puntuado de 1 a 7 y un nivel de sesión con el desglose
  por golpe, para ver cuál va por detrás. Es una estimación sin calibrar: mide el swing,
  no la colocación ni la táctica. Ver [`docs/level.md`](docs/level.md).
- **Salud**: frecuencia cardiaca media y máxima, tiempo en cada zona, calorías activas,
  pasos y distancia. Solo si das el consentimiento explícito.

## Empezar

```bash
# Lo único que corre sin SDK de móvil: el core y sus 156 tests
cd android/core && ./gradlew test
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
- [Marcador](docs/scoring.md) — reglas del partido y por qué la interacción es así
- [Nivel técnico](docs/level.md) — cómo se puntúa de 1 a 7, qué mide y qué no
- [Ajustes](docs/architecture.md#ajustes-el-móvil-manda-el-reloj-obedece) — se configuran
  en el móvil y se replican al reloj
- [Entrenar el clasificador](docs/training-data.md) — grabar golpeos etiquetados y
  entrenar un modelo propio
- [Puesta en marcha](docs/setup.md) — compilar, conectar la liga, calibrar
- [Apple Watch sin Mac](docs/testflight.md) — compilar y subir a TestFlight desde CI
- [Pendiente](docs/backlog.md) — lo decidido pero no hecho, y las limitaciones conocidas

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
- La única excepción es el modo de recogida de datos para entrenar el clasificador, que
  viene apagado, hay que activarlo a mano, no se sube nunca a la liga y solo sale del
  móvil si lo exportas tú. Ver [`docs/training-data.md`](docs/training-data.md).
