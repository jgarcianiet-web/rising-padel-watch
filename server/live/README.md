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

## Actualizar

Cambios en `src/index.js` se publican con `wrangler deploy` otra vez. El token y el
almacén no se tocan.
