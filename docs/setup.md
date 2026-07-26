# Puesta en marcha

## Requisitos

| Plataforma | Necesitas |
|---|---|
| Core Kotlin | JDK 17+ (Gradle lo trae el wrapper) |
| Android + Wear OS | Android Studio Ladybug o superior, SDK 35 |
| iOS + watchOS | Xcode 15.4+, macOS 14+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

## Core Kotlin (lo único que corre sin SDK de móvil)

```bash
cd android/core
./gradlew test
```

51 tests: detección de golpeos, clasificación de los seis tipos, zonas de frecuencia
cardiaca, contrato JSON, política de reintentos y almacenamiento local. Es un build
independiente a propósito, así que **no** necesita el SDK de Android.

## Android (móvil + reloj)

```bash
cd android
./gradlew :mobile:assembleDebug :wear:assembleDebug
```

Si Gradle se queja de que no encuentra el SDK, crea `android/local.properties`:

```properties
sdk.dir=/ruta/a/Android/sdk
```

Para instalar en un reloj Wear OS emparejado por adb:

```bash
./gradlew :wear:installDebug
```

Las apps de móvil y reloj comparten `applicationId` (`com.risingpadel.watch`), que es lo
que exige Google Play para distribuir la app de reloj junto a la de móvil.

## iOS + watchOS

El `.xcodeproj` no está versionado: se genera desde `ios/project.yml`.

```bash
cd ios
xcodegen generate
open RisingPadel.xcodeproj
```

Antes de firmar, rellena `DEVELOPMENT_TEAM` en `project.yml` con tu Team ID y vuelve a
generar.

Los tests del core Swift no necesitan simulador:

```bash
cd ios/Packages/PadelCore
swift test
```

## Conectar con la app de liga

1. En la app de liga, genera un token para el jugador.
2. En el iPhone o el Android: **Ajustes → Liga**, pega la URL base (por ejemplo
   `https://mi-liga.example.com/api`) y el token.
3. La app hará `POST <URL>/v1/padel-sessions` con `Authorization: Bearer <token>`.

El contrato completo está en [`api-contract.md`](./api-contract.md) y
[`openapi.yaml`](./openapi.yaml). Mientras la liga no lo implemente, las sesiones se
quedan guardadas en el móvil y se suben solas en cuanto el endpoint responda.

### Probar el contrato sin tener la liga lista

Cualquier servidor que acepte el POST vale para validar el circuito. Por ejemplo, con
Python:

```python
# servidor_de_pruebas.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        print(json.dumps(json.loads(body), indent=2, ensure_ascii=False))
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"id":"psession_test","sessionId":"x"}')

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
```

Apunta la app a `http://<ip-de-tu-portatil>:8080` y juega un punto: verás el JSON de la
sesión por consola.

> En iOS, una URL `http://` sin TLS necesita una excepción de App Transport Security en
> el `Info.plist`. Es solo para probar en local; en producción la liga tiene que ir por
> HTTPS.

## Antes de la primera sesión de verdad

1. **Ponte el reloj en la muñeca de la pala.** Es el requisito que más veces se pasa por
   alto: en la otra muñeca el reloj no ve el swing. La app avisa, pero conviene saberlo.
2. Configura mano y muñeca en Ajustes.
3. Decide si quieres compartir datos de salud. Si lo dejas apagado, el reloj **no los
   mide siquiera**.
4. Valida el signo del giróscopo: juega diez derechas y diez reveses y mira el desglose
   por tipo. Si salen cambiados, pon `invertAxialSign = true` en `DetectorConfig` (ver
   [`shot-detection.md`](./shot-detection.md)).
