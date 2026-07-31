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

[App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations**
→ **App Store Connect API** → **+**.

- Rol: **App Manager** (con Developer no puede subir builds).
- Descarga el `.p8`. **Solo se puede descargar una vez.** Si lo pierdes, se revoca y se
  crea otra.
- Apunta el **Key ID** y el **Issuer ID** de esa pantalla.

Para `APPSTORE_PRIVATE_KEY`, pega el contenido completo del `.p8`, con las líneas
`-----BEGIN PRIVATE KEY-----` y `-----END PRIVATE KEY-----` incluidas.

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

Los identificadores y los perfiles de aprovisionamiento se crean solos: el workflow pasa
`-allowProvisioningUpdates` con la clave de API, y Xcode los genera en el portal.

## Lanzar una build

**Actions → TestFlight → Run workflow.** Tarda unos 10-15 minutos.

Cuando termine, la build aparece en App Store Connect → tu app → **TestFlight**. La
primera vez tienes que:

1. Rellenar el cuestionario de **cifrado de exportación** (esta app no usa criptografía
   propia; solo HTTPS, así que es la respuesta estándar de exención).
2. Añadirte como probador interno: **TestFlight → Internal Testing → +**.

Después, instala **TestFlight** en el iPhone, acepta la invitación e instala. En el reloj
la app aparece sola si tienes activada la instalación automática; si no, ve a la app
**Watch** en el iPhone → busca Rising Padel → **Instalar**.

Cada ejecución usa `github.run_number` como número de build, así que nunca chocan.

## Cuando falle

No he podido probar este workflow: hace falta una cuenta de Apple de verdad. Estos son los
fallos previsibles y qué significan:

| Error | Causa |
|---|---|
| `MAC verification failed` al importar | Falta `-legacy` al generar el `.p12` |
| `No signing certificate "Apple Distribution" found` | El `.p12` no entró bien, o es de tipo Development y no Distribution |
| `No profiles for 'com.risingpadel.watch' were found` | La app no está registrada en App Store Connect (paso 4) |
| `Authentication credentials are missing or invalid` | La clave de API tiene rol Developer en vez de App Manager |
| `xcodebuild` se cuelga en la firma | Falta `set-key-partition-list`; ya está en el workflow, pero si tocas ese paso no lo quites |
| `method` no válido en ExportOptions | Xcode viejo: cambia `app-store-connect` por `app-store` |

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
