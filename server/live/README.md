# Servidor del marcador en vivo (Cloudflare Worker)

El trozo que faltaba para que un partido se pueda seguir **desde cualquier móvil**: el
reloj publica cada punto, el iPhone lo reenvía aquí, y quien tenga el enlace lo ve en
una página que se refresca sola.

Es un servicio gestionado a propósito: sin servidor que mantener ni apagar, y el plan
gratuito de Cloudflare Workers (100.000 peticiones/día) sobra de largo para una liga
personal — un partido entero son unos cientos de PUTs.

## Qué expone

| Ruta | Quién | Qué |
|---|---|---|
| `PUT /v1/live/{sessionId}` | el iPhone, con token | Publica el estado del partido (cada PUT sustituye al anterior) |
| `GET /v1/live/{sessionId}` | cualquiera | El último estado, en JSON |
| `GET /{sessionId}` | cualquiera | **La página del espectador**: marcador grande, sets, quién saca, pulso — se refresca sola y se para en el FINAL |
| `POST /v1/padel-sessions` | el iPhone, con token | Buzón de sesiones: guarda la sesión completa (idempotente), para que la app pueda apuntar aquí su URL de liga sin que el envío falle |

El estado en vivo caduca solo a las 6 horas: un marcador no es un archivo histórico.
El `GET` es público a propósito — el enlace se comparte —, pero el id es un UUID
aleatorio imposible de adivinar y el estado no lleva salud más allá del pulso, que
solo va si el emisor comparte salud en Ajustes.

## Desplegar (una vez, ~5 minutos)

Hace falta una cuenta gratuita de [Cloudflare](https://dash.cloudflare.com/sign-up) y
Node instalado.

```bash
cd server/live

# 1. Instalar la CLI y entrar en la cuenta (abre el navegador)
npm install -g wrangler
wrangler login

# 2. Crear el almacén clave-valor y copiar su id en wrangler.toml
wrangler kv namespace create LIVE
#    → devuelve algo como  id = "0f2ac74b498b48..."
#    Pega ese id en wrangler.toml donde pone PON_AQUI_EL_ID_DEL_NAMESPACE.

# 3. Crear el token de escritura (invéntalo largo; este comando genera uno)
openssl rand -hex 32
wrangler secret put LIVE_TOKEN
#    → pega el token generado cuando lo pida

# 4. Desplegar
wrangler deploy
#    → devuelve la URL, algo como https://rising-padel-live.<tu-subdominio>.workers.dev
```

## Conectar la app

En **Rising Padel → Ajustes → Liga**:

- **URL**: la URL del deploy (`https://rising-padel-live.<tu-subdominio>.workers.dev`)
- **Token**: el mismo que pusiste en `LIVE_TOKEN`

Desde ese momento, al arrancar un partido en el reloj el iPhone republica cada punto, y
el enlace para compartir es:

```
https://rising-padel-live.<tu-subdominio>.workers.dev/<sessionId>
```

(El `sessionId` de la sesión en curso; la app enseña el enlace en la portada del
partido en vivo.)

## La comunidad

El mismo worker lleva la comunidad: cuentas por alias, seguir, muro con etiquetas y la
notificación de "está jugando ahora". Necesita dos cosas más:

```bash
# 1. La base de datos (una vez)
wrangler d1 create rising-padel
#    → copia el database_id en wrangler.toml
wrangler d1 execute rising-padel --file=schema.sql --remote

# 2. Las notificaciones push (la misma clave .p8 de App Store Connect que usa CI)
wrangler secret put APNS_KEY_P8    # pega el contenido del AuthKey_XXXX.p8
wrangler secret put APNS_KEY_ID    # su Key ID
wrangler secret put APNS_TEAM_ID   # el Team ID de Apple

wrangler deploy
```

En la app, pestaña **Comunidad**: URL del worker + alias, y listo — el registro deja
configurada también la liga (mismo token para subir sesiones, publicar el marcador en
vivo y la comunidad). Al empezar un partido, tus seguidores reciben "«tu-alias» está
jugando ahora" y un toque les abre el marcador en vivo.

Moderación mínima de serie (lo que exige el App Store para contenido de usuarios):
denunciar publicaciones y bloquear usuarios, desde el menú contextual de cada post.

## Actualizar

Cambios en `src/index.js` se publican con `wrangler deploy` otra vez. El token y el
almacén no se tocan.
