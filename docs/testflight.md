# Desarrollar para Apple Watch sin tener un Mac

Compilar para watchOS necesita Xcode, y Xcode solo corre en macOS. Pero **no hace falta
que el Mac sea tuyo**: los runners de GitHub Actions lo son, y el workflow
[`testflight.yml`](../.github/workflows/testflight.yml) los usa para compilar, firmar y
subir la app a TestFlight. Desde el iPhone la instalas con la app TestFlight, y el reloj
coge la suya desde ahí.

## Lo que cuesta

| | Coste |
|---|---|
| Apple Developer Program | **99 €/año, obligatorio** |
| Runners macOS en repo privado | 10 min/build × 10 de multiplicador = 100 min del cupo |
| Todo lo demás | 0 € |

El programa de pago **no es opcional aquí**. La firma gratuita con Apple ID solo funciona
desde Xcode en local, que es justo lo que no tienes. Sin Mac, TestFlight es la única vía, y
TestFlight exige cuenta de pago.

Si el cupo de minutos se queda corto, los repos **públicos** tienen runners macOS gratis.

## Los cinco secretos

En GitHub: **Settings → Secrets and variables → Actions → New repository secret**.

| Secreto | Qué es |
|---|---|
| `APPLE_TEAM_ID` | Los 10 caracteres de tu equipo |
| `APPSTORE_ISSUER_ID` | UUID del emisor de la clave de API |
| `APPSTORE_KEY_ID` | ID de la clave de API |
| `APPSTORE_PRIVATE_KEY` | Contenido del `.p8`, entero |
| `BUILD_CERTIFICATE_BASE64` | Tu certificado de distribución en `.p12`, en base64 |
| `P12_PASSWORD` | La contraseña que le pongas al `.p12` |

### 1. Team ID

[developer.apple.com/account](https://developer.apple.com/account) → **Membership
details**. Son 10 caracteres tipo `A1B2C3D4E5`.

### 2. Clave de App Store Connect

Es una clave de API: sustituye a usuario y contraseña para que el workflow pueda hablar
con Apple sin pelearse con el doble factor.

1. Entra en [App Store Connect](https://appstoreconnect.apple.com) con la cuenta que pagó
   el programa.
2. **Users and Access** (arriba).
3. Pestaña **Integrations**.
4. En la barra izquierda, **App Store Connect API** → **Team Keys**.

   > **Que sea Team Keys, no Individual Keys.** Las individuales van atadas a tu persona y
   > heredan tu rol: no tienen selector de rol, así que si acabas ahí no vas a encontrar el
   > desplegable de App Manager y no sabrás por qué. Las de equipo son de la organización,
   > que es lo que quiere un CI.

5. Botón **+** (o **Generate API Key** si es la primera).
6. **Name**: algo reconocible, `GitHub Actions TestFlight`. Es solo una etiqueta.
7. **Access**: **App Manager**.
8. **Generate**.

Ahora, en la fila que acaba de aparecer:

- **Download** → baja un fichero `AuthKey_XXXXXXXXXX.p8`. **Solo se puede descargar una
  vez**; en cuanto recargues la página el enlace desaparece para siempre. Si lo pierdes,
  hay que revocar la clave y crear otra.
- **KEY ID**: los 10 caracteres de esa misma fila → secreto `APPSTORE_KEY_ID`.
- **ISSUER ID**: el UUID largo **encima de la tabla**, con un enlace *Copy* al lado. Es el
  mismo para todas las claves del equipo → secreto `APPSTORE_ISSUER_ID`.

Para `APPSTORE_PRIVATE_KEY`, abre el `.p8` con un editor de texto y pega **el contenido
completo**, incluidas las líneas `-----BEGIN PRIVATE KEY-----` y
`-----END PRIVATE KEY-----`. Los secretos de GitHub admiten varias líneas sin problema.

Sobre el rol: **App Manager** es el que cubre subir builds *y* gestionar TestFlight
(grupos, probadores, notas). **Developer** sí puede subir builds, pero se queda corto en la
parte de TestFlight y en los metadatos de la app, así que tarde o temprano da un error de
permisos. **Admin** funcionaría, pero da más poder del necesario a una credencial que vive
en un CI. El rol **no se puede cambiar después**: para cambiarlo hay que revocar la clave y
crear otra.

### 3. Certificado de distribución (sin Mac, con `openssl`)

Aquí es donde todo el mundo asume que hace falta Keychain Access. No hace falta: un
certificado es una clave y una petición firmada, y `openssl` hace las dos cosas en
Linux, en Windows con WSL o en el propio Git Bash.

```bash
# 1. Clave privada y petición de firma
openssl genrsa -out distribucion.key 2048
openssl req -new -key distribucion.key -out distribucion.csr \
  -subj "/emailAddress=tu@email.com/CN=Tu Nombre/C=ES"
```

Sube `distribucion.csr` en [Certificates](https://developer.apple.com/account/resources/certificates/list)
→ **+** → **Apple Distribution** → descarga `distribution.cer`.

```bash
# 2. Convertir a .p12, que es lo que entiende el llavero de macOS
openssl x509 -inform DER -in distribution.cer -out distribucion.pem

openssl pkcs12 -export -legacy \
  -inkey distribucion.key \
  -in distribucion.pem \
  -name "Apple Distribution" \
  -out distribucion.p12 \
  -passout pass:LA-QUE-QUIERAS

# 3. A base64, en una sola línea
base64 -w0 distribucion.p12 > distribucion.p12.txt   # en macOS/BSD: base64 -i ... -o ...
```

> **`-legacy` no es opcional.** OpenSSL 3 cifra los `.p12` con AES-256, y el `security
> import` de macOS no sabe leerlos: el job falla con un `MAC verification failed` que no
> dice nada sobre la causa real. Con `-legacy` usa el cifrado antiguo, que sí acepta.

El contenido de `distribucion.p12.txt` va en `BUILD_CERTIFICATE_BASE64`, y la contraseña
que pusiste en `-passout` va en `P12_PASSWORD`.

**Guarda `distribucion.key` y el `.p12` en un sitio seguro.** Solo puedes tener **3
certificados de distribución** por cuenta; si los pierdes hay que revocarlos, y revocar
uno invalida las builds firmadas con él.

### 4. Registrar la app

[App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:

- Bundle ID: **`com.risingpadel.watch`** (el de la app de reloj,
  `com.risingpadel.watch.watchkitapp`, lo crea Xcode solo).
- Plataforma: iOS.
- Nombre y SKU: los que quieras.

Los identificadores y los perfiles de aprovisionamiento los crea el propio workflow
contra la API de App Store Connect (`.github/scripts/preparar_perfiles.py`), incluida la
capability de HealthKit del reloj. No hay que crear nada a mano en el portal.

Se hace así y no con la firma automática de Xcode porque la automática archiva con un
perfil de desarrollo, y esos exigen **un dispositivo registrado en el equipo** — que en
una cuenta sin Mac ni cable no hay forma cómoda de registrar. Los perfiles de App Store
no piden dispositivos.

## Lanzar una build

**Actions → TestFlight → Run workflow.** Tarda unos 10-15 minutos.

Cuando termine, la build aparece en App Store Connect → tu app → **TestFlight**. La
primera vez solo tienes que **añadirte como probador interno**: TestFlight → **Internal
Testing** → **+**.

El cuestionario de **cifrado de exportación** no aparece: va declarado en el `Info.plist`
con `ITSAppUsesNonExemptEncryption: false`, así que las builds pasan directas a los
probadores en vez de quedarse esperando a que alguien lo responda a mano.

> Usa **probadores internos**, no externos. Los internos (hasta 100, cuentas de App Store
> Connect) **no pasan por Beta App Review**: la build está disponible en cuanto Apple
> termina de procesarla. Los externos sí pasan revisión la primera vez, y eso son horas o
> días.

Después, instala **TestFlight** en el iPhone, acepta la invitación e instala. En el reloj
la app aparece sola si tienes activada la instalación automática; si no, ve a la app
**Watch** en el iPhone → busca Rising Padel → **Instalar**.

Cada ejecución usa `github.run_number` como número de build, así que nunca chocan.

## Cuando falle

Errores vistos de verdad al poner esto en marcha, más los previsibles:

| Error | Causa |
|---|---|
| `Error Downloading App Information` al exportar | **La app no existe en App Store Connect** con el bundle ID `com.risingpadel.watch`. Es el único paso que no se puede hacer por API: créala en la web (paso 4). Visto en el run #4 |
| `Your team has no devices from which to generate a provisioning profile` | Alguien cambió la firma a automática: la automática archiva con perfil de desarrollo, que exige un dispositivo registrado. Vuelve a la firma manual de `ios/project.yml`. Visto en el run #1 |
| `conflicting provisioning settings` | Se pasó `CODE_SIGN_IDENTITY` por línea de comandos con firma automática. O todo automático o todo manual. Visto en el run #2 |
| `PARAMETER_ERROR.ILLEGAL` en el paso de perfiles | Un endpoint de relación de la API no admite un parámetro de colección (p. ej. `limit`). Visto en el run #3 |
| `MAC verification failed` al importar | Falta `-legacy` al generar el `.p12` |
| `No signing certificate "Apple Distribution" found` | El `.p12` no entró bien, o es de tipo Development y no Distribution |
| `Authentication credentials are missing or invalid` | El `.p8`, el Key ID o el Issuer ID no cuadran. Comprueba que el Issuer ID es el UUID de encima de la tabla y no otro identificador |
| `Forbidden` / `not permitted` al subir | La clave se creó con un rol insuficiente. Revócala y crea otra con App Manager |
| `xcodebuild` se cuelga en la firma | Falta `set-key-partition-list`; ya está en el workflow, pero si tocas ese paso no lo quites |

El job sube los logs de `xcodebuild` como artefacto cuando falla. Si te atascas, pásamelos.

## Alternativas si esto no te encaja

- **Alquilar un Mac por horas**: MacStadium, Scaleway o AWS EC2 Mac. Desde ~1 €/hora, con
  Xcode completo y depuración interactiva. Vale la pena si necesitas depurar en el reloj y
  no solo instalar.
- **Mac mini M1 de segunda mano**: unos 350-450 €. Si el proyecto va a durar, sale más
  barato que el tiempo perdido peleándose con CI a ciegas.
- **Un Wear OS**: se desarrolla desde cualquier sistema operativo, sin cuota anual y con
  depuración por Wi-Fi. El core es el mismo y la app también existe. Ver
  [`setup.md`](./setup.md).
