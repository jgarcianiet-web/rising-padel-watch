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

134 tests: detección de golpeos, clasificación de los seis tipos, reglas del marcador
(puntos, los tres formatos de 40-40, tie-break, saque, cambios de pista y deshacer),
captura de ventanas de entrenamiento, replicación de ajustes al reloj, zonas de frecuencia
cardiaca, contrato JSON, política de reintentos y almacenamiento local. Es un build independiente a propósito, así
que **no** necesita el SDK de Android.

## Entrenar el clasificador

```bash
pip install numpy scikit-learn
python3 tools/make_synthetic_dataset.py sinteticas.jsonl   # probar la tubería
python3 tools/train_classifier.py sinteticas.jsonl
```

Proceso completo en [`training-data.md`](./training-data.md).

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

### Instalar en un reloj Wear OS de verdad

**Hay que instalar las dos apps**, no solo la del reloj: la del reloj declara
`standalone=false` y los ajustes se configuran en el móvil.

1. **Activa opciones de desarrollador en el reloj**: Ajustes → Información → Versiones →
   toca 7 veces en **Número de compilación**.
2. Ajustes → Opciones de desarrollador → **Depuración por ADB** y **Depuración por Wi-Fi**.
3. El reloj muestra su IP. Desde el ordenador, en la misma red Wi-Fi:

   ```bash
   adb pair <ip-del-reloj>:<puerto-de-emparejamiento>   # el código sale en el reloj
   adb connect <ip-del-reloj>:5555
   adb devices                                          # comprueba que aparece
   ```
4. Instala las dos:

   ```bash
   cd android
   ./gradlew :mobile:installDebug        # con el móvil también conectado
   ./gradlew :wear:installDebug
   ```

Si `adb devices` ve el móvil y el reloj a la vez, `installDebug` se queja de que hay
varios dispositivos: usa `adb -s <serie> install <ruta-al-apk>` para cada uno.

> **Las dos apps tienen que estar firmadas con la misma clave.** El Data Layer de Wear
> solo deja hablar a apps con el mismo `applicationId` **y** la misma firma. Compilando las
> dos desde el mismo ordenador esto se cumple solo, porque comparten
> `~/.android/debug.keystore`. Si compilas cada una en un sitio, no se verán y no sabrás
> por qué: ni sesiones, ni ajustes.

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

### Instalar en un Apple Watch de verdad

Hace falta **un Mac con Xcode**. No hay forma de compilar para watchOS sin él.

1. Xcode → Settings → Accounts → añade tu Apple ID. En `ios/project.yml`, pon tu Team ID
   en `DEVELOPMENT_TEAM` y ejecuta `xcodegen generate` otra vez.
2. Conecta el iPhone por cable, y en el iPhone: Ajustes → Privacidad y seguridad → **Modo
   de desarrollador** → activar (reinicia).
3. En Xcode, elige el iPhone como destino y **Run**. La app del reloj va **embebida** en la
   del iPhone: no se instala por separado.
4. En el iPhone, abre la app **Watch** → busca "Rising Padel" → **Instalar**. Suele tardar
   un par de minutos. Si no aparece, verifica que el reloj esté cargando y desbloqueado.
5. La primera vez que abras la app en el reloj te pedirá permisos de movimiento y salud.

**Lo que caduca:** con un Apple ID gratuito el perfil dura **7 días** y hay que reinstalar
desde Xcode; con el Apple Developer Program (99 €/año) dura un año. Para grabar datos
durante varias semanas, el programa de pago ahorra bastante fricción.

Si al compilar falla la firma por el *entitlement* de HealthKit, es que tu cuenta no lo
tiene habilitado: entra en el portal de Apple Developer, activa HealthKit para el App ID y
vuelve a generar el perfil.

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
2. Configura mano y muñeca **en el móvil**. Se replican solas al reloj; no hay que tocar
   nada en la muñeca. Si el reloj estaba apagado, los recibe al encenderse.
3. Decide si quieres compartir datos de salud. Si lo dejas apagado, el reloj **no los
   mide siquiera**.
4. Valida el signo del giróscopo: juega diez derechas y diez reveses y mira el desglose
   por tipo. Si salen cambiados, pon `invertAxialSign = true` en `DetectorConfig` (ver
   [`shot-detection.md`](./shot-detection.md)).

Los ajustes que cambies a mitad de partido no se aplican hasta que termine: la sesión en
curso se mide entera con la configuración con la que empezó.
