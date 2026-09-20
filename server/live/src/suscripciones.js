// La suscripción Pro, validada contra Apple.
//
// ## Por qué existe este fichero
//
// `coach.js` ya cobra el entrenador IA por plan: `consumo()` lee `subscriptions` y de
// ahí sale el tope del mes (free 30, pro 300, elite 1000). Lo que faltaba era **quién
// escribe esa tabla**. Hasta ahora nadie: todo el mundo caía en 'free' porque no había
// ninguna fila. Este módulo es el único sitio que la escribe.
//
// ## La regla que ordena todo lo demás: el cliente no decide qué plan tiene
//
// El iPhone manda **un identificador**, el `originalTransactionId` de StoreKit, y nada
// más. No manda el plan, ni el producto, ni la fecha de caducidad, ni el recibo. Si
// mandara el plan, la suscripción de pago sería un `curl` con `{"plan":"elite"}`, y el
// coste real de eso no es simbólico: son peticiones a Claude pagadas con la clave del
// servicio.
//
// Con ese identificador el Worker le pregunta a Apple —autenticándose con su propia
// clave privada— y escribe en `subscriptions` lo que Apple conteste. La fuente de la
// verdad está siempre al otro lado de una llamada HTTPS autenticada a
// `api.storekit.itunes.apple.com`.
//
// ## Por qué el webhook NO escribe el plan
//
// App Store Server Notifications V2 manda un JWS firmado por Apple cuya firma se valida
// con la cadena de certificados que viene en la cabecera `x5c`, encadenada hasta la CA
// raíz de Apple. Eso exige parsear X.509 a mano (ASN.1, validez, encadenado de emisores,
// verificación de cada firma) porque el Worker no tiene ninguna librería que lo haga:
// WebCrypto sabe verificar ES256 con una clave, pero no sabe validar una cadena de
// certificados. **Escribir un validador de X.509 casero para decidir quién tiene acceso
// de pago es peor idea que no fiarse del payload.**
//
// Así que aquí el webhook **no verifica la firma** —dicho sin rodeos— y por eso su único
// poder es *disparar una re-sincronización*: del payload solo se saca el
// `originalTransactionId`, y con él se vuelve a preguntar a la API de Apple, que sí está
// autenticada y sí es fuente de la verdad. El peor caso de un webhook falsificado es que
// el Worker le pregunte a Apple por una suscripción que ya conoce y escriba... exactamente
// lo mismo que ya tenía. Además solo se re-sincronizan identificadores que YA están en
// la tabla: un desconocido no crea ninguna fila.
//
// Y aunque el aviso no llegue nunca, el sistema no se rompe: `expires_at` hace que una
// suscripción vencida caiga sola a gratuito (ver `consumo()` en coach.js), y la app
// re-sincroniza al arrancar y en cada renovación que StoreKit le cuenta.
//
// ## Sin secretos, el endpoint no existe
//
// Mismo patrón que `ANTHROPIC_API_KEY` en coach.js y que `TANDAS_TOKEN` en index.js: sin
// las credenciales de la App Store Server API esto devuelve 404 en vez de fingir que
// funciona. Una función que depende de un secreto no debe existir a medias.

import { usuarioDe } from "./comunidad.js";

/**
 * Los productos de App Store Connect y el plan que dan.
 *
 * Aquí arriba y en una sola constante a propósito: el día que haya un plan 'elite', o
 * que el anual cambie de identificador, este mapa es el único sitio que se toca. El
 * identificador tiene que coincidir **carácter a carácter** con el de App Store Connect
 * y con `TiendaModel.identificadores` del iPhone.
 */
const PLANES = {
  "com.risingpadel.watch.pro.mensual": "pro",
  "com.risingpadel.watch.pro.anual": "pro",
};

const API_PRODUCCION = "https://api.storekit.itunes.apple.com";
const API_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

/**
 * Estados de `lastTransactions[].status` que dan derecho al plan.
 *
 * 1 = activa, 2 = caducada, 3 = reintento de cobro, 4 = periodo de gracia, 5 = revocada.
 *
 * El 4 entra porque el periodo de gracia es justo para esto: Apple no ha podido cobrar
 * todavía pero el jugador sigue siendo cliente, y quitarle el entrenador el día que le
 * caduca la tarjeta es la forma más rápida de perderlo. El 3 (reintento SIN gracia) no
 * entra: ahí Apple ya ha dado la suscripción por vencida.
 */
const ESTADOS_CON_DERECHO = new Set([1, 4]);

/** Apple contesta 404 con este código cuando el id no existe en ese entorno. */
const ERROR_TRANSACCION_DESCONOCIDA = 4040010;

const json = (status, obj) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const error = (status, code, message) => json(status, { error: { code, message } });

const ahora = () => new Date().toISOString();

const base64url = (bytes) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

// ─── El JWT de la App Store Server API ───

let jwtCache = null; // { token, mintedAt }

/**
 * Firma el token ES256 que exige la App Store Server API.
 *
 * **Sí, esto se parece mucho a `jwtApns()` de comunidad.js, y está copiado de ahí a
 * propósito.** Lo que comparten son seis líneas de WebCrypto (importar el .p8 como PKCS8
 * y firmar); lo que NO comparten es todo lo que importa: otra clave (la de In-App
 * Purchase, no la de APNs), otro emisor (el Issuer ID de App Store Connect, no el Team
 * ID), una audiencia y un `bid` que APNs no tiene, y una caducidad explícita que Apple
 * exige aquí (máximo 60 minutos) y que en APNs no existe.
 *
 * Extraer un firmador común obligaría a tocar comunidad.js, que es por donde sale el push
 * de "está jugando" — la ruta caliente de la app. Un cambio hecho para contentar a la API
 * de la App Store rompería los avisos en silencio, y ese riesgo no compensa ahorrar seis
 * líneas. Si algún día aparece un tercer JWT, entonces sí: tres copias ya son un patrón.
 */
async function jwtAppStore(env) {
  // 20 minutos de vida útil de caché sobre 40 de validez: sobra margen para que un
  // token recién sacado de la caché no caduque a mitad de la petición.
  if (jwtCache && Date.now() - jwtCache.mintedAt < 20 * 60 * 1000) return jwtCache.token;

  const der = Uint8Array.from(
    atob(env.APPSTORE_IAP_KEY_P8.replace(/-----[^-]+-----|\s/g, "")),
    (c) => c.charCodeAt(0)
  );
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );

  const b64 = (obj) => base64url(new TextEncoder().encode(JSON.stringify(obj)));
  const emitido = Math.floor(Date.now() / 1000);
  const cuerpo = `${b64({ alg: "ES256", kid: env.APPSTORE_IAP_KEY_ID, typ: "JWT" })}.${b64({
    iss: env.APPSTORE_ISSUER_ID,
    iat: emitido,
    exp: emitido + 40 * 60,
    // Estas dos las exige la App Store Server API y no admiten variación: sin `aud`
    // exacto o sin el bundle id, Apple contesta 401 sin más explicación.
    aud: "appstoreconnect-v1",
    bid: env.APPSTORE_BUNDLE_ID,
  })}`;

  // ECDSA en WebCrypto devuelve la firma ya en crudo (r‖s, 64 bytes), que es justo lo
  // que quiere JOSE. No hay que desenvolver ningún DER.
  const firma = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(cuerpo)
  );
  const token = `${cuerpo}.${base64url(new Uint8Array(firma))}`;
  jwtCache = { token, mintedAt: Date.now() };
  return token;
}

// ─── Hablar con Apple ───

/**
 * El payload de un JWS **sin verificar la firma**.
 *
 * Se usa en dos sitios con dos justificaciones distintas:
 *
 *  - En la respuesta de la API (`signedTransactionInfo`): el JWS llegó dentro de una
 *    respuesta HTTPS autenticada de `api.storekit.itunes.apple.com`, y lo que lo hace
 *    creíble es esa llamada, no la firma de dentro. Verificarla otra vez no añadiría
 *    nada: quien pudiera falsificar la respuesta ya habría roto TLS.
 *  - En el webhook: ahí NO es creíble, y por eso del payload solo se saca el
 *    identificador con el que volver a preguntar. Ver la cabecera del fichero.
 */
function payloadDeJws(jws) {
  const partes = String(jws || "").split(".");
  if (partes.length !== 3) return null;
  try {
    const b64 = partes[1].replace(/-/g, "+").replace(/_/g, "/");
    const relleno = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const bytes = Uint8Array.from(atob(relleno), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

/**
 * Le pregunta a Apple por una suscripción y traduce la respuesta a lo que guarda la
 * tabla: plan, producto, caducidad y el identificador de cuenta que el cliente pegó a la
 * compra (ver `cuentaEsperada`).
 *
 * **Producción primero y sandbox como respaldo.** Apple no da una forma de saber de qué
 * entorno viene un `originalTransactionId` antes de preguntar: la receta oficial es
 * probar en producción y, si contesta 404 con el código 4040010 ("transaction id not
 * found"), repetir en sandbox. Hace falta de verdad — TestFlight compra en sandbox, así
 * que sin este respaldo ninguna build de pruebas podría suscribirse.
 */
async function consultarApple(env, originalTransactionId) {
  const datosDe = (cuerpo) => (Array.isArray(cuerpo?.data) ? cuerpo.data : []);
  const jwt = await jwtAppStore(env);

  const pedir = async (base) => {
    const respuesta = await fetch(
      `${base}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`,
      { headers: { authorization: `Bearer ${jwt}` } }
    );
    if (respuesta.ok) return { ok: true, datos: await respuesta.json() };
    const detalle = await respuesta.json().catch(() => ({}));
    return { ok: false, status: respuesta.status, codigo: detalle?.errorCode };
  };

  let resultado = await pedir(API_PRODUCCION);
  let entorno = "produccion";
  if (
    !resultado.ok &&
    resultado.status === 404 &&
    resultado.codigo === ERROR_TRANSACCION_DESCONOCIDA
  ) {
    resultado = await pedir(API_SANDBOX);
    entorno = "sandbox";
  }
  if (!resultado.ok) return { encontrada: false, status: resultado.status };

  // La respuesta viene por grupo de suscripción; a nosotros solo nos interesa la última
  // transacción de cada uno. Se recorren todas y gana la que dé derecho y caduque más
  // tarde: si alguien tuvo mensual y se pasó a anual, el derecho bueno es el segundo.
  let mejor = null;
  for (const grupo of datosDe(resultado.datos)) {
    for (const transaccion of grupo.lastTransactions ?? []) {
      const info = payloadDeJws(transaccion.signedTransactionInfo) ?? {};
      const producto = info.productId ?? "";
      const plan = ESTADOS_CON_DERECHO.has(transaccion.status)
        ? (PLANES[producto] ?? null)
        : null;
      if (!plan) continue;
      const caduca = info.expiresDate ? new Date(info.expiresDate).toISOString() : null;
      if (!mejor || (caduca ?? "") > (mejor.expiresAt ?? "")) {
        mejor = {
          plan,
          producto,
          expiresAt: caduca,
          // Lo que el iPhone pegó a la compra: identifica la CUENTA de Rising Pádel que
          // compró, no al comprador de Apple. Ver `cuentaEsperada`.
          cuenta: typeof info.appAccountToken === "string" ? info.appAccountToken : null,
        };
      }
    }
  }

  return {
    encontrada: true,
    entorno,
    plan: mejor?.plan ?? "free",
    producto: mejor?.producto ?? "",
    expiresAt: mejor?.expiresAt ?? null,
    cuenta: mejor?.cuenta ?? null,
  };
}

// ─── Quién es el dueño de una suscripción ───

/**
 * El `appAccountToken` que le corresponde a esta cuenta: un UUID derivado del token de
 * la comunidad, que el iPhone calcula igual y pega a la compra (`TiendaModel`).
 *
 * **Para qué sirve.** Un `originalTransactionId` no es un secreto ni identifica a nadie
 * de Rising Pádel: es un número de Apple. Sin más defensa, cualquiera que consiguiera el
 * de un suscriptor podría mandarlo desde su propia cuenta y quedarse con su plan de pago.
 * Con esto, la transacción lleva dentro —firmado por Apple, escrito por el iPhone que
 * compró— a qué cuenta pertenece, y la comparación es directa.
 *
 * Es una derivación y no un valor guardado porque así no hay nada nuevo que persistir ni
 * que sincronizar: el token de la cuenta ya existe, ya es aleatorio y ya vive en el
 * Llavero del móvil. Se usan los 32 primeros caracteres hexadecimales (16 bytes) porque
 * un UUID es exactamente eso, y el token tiene 48.
 */
function cuentaEsperada(request) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim().toLowerCase() : "";
  if (!/^[0-9a-f]{32}/.test(token)) return null;
  const h = token.slice(0, 32);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/** Escribe (o actualiza) la suscripción del usuario. Una fila por usuario. */
async function guardar(env, userId, { plan, producto, originalTransactionId, expiresAt }) {
  await env.DB.prepare(
    `INSERT INTO subscriptions (user, plan, product, original_transaction_id, expires_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)
     ON CONFLICT(user) DO UPDATE SET
       plan = ?2, product = ?3, original_transaction_id = ?4, expires_at = ?5, updated_at = ?6`
  )
    .bind(userId, plan, producto, originalTransactionId, expiresAt, ahora())
    .run();
}

/**
 * El plan que vale HOY, con la misma regla que `consumo()` en coach.js: una fila con
 * `expires_at` pasado es gratuito aunque ponga 'pro'.
 *
 * La regla está escrita dos veces (aquí y allí) a sabiendas. Podría importarse, pero
 * coach.js es el que cobra y esta pantalla es la que informa: prefiero que el que cobra
 * no dependa de este fichero. Si las dos se separan alguna vez, el error sería enseñar
 * "Pro" y no dar cuota — visible y chillón — y no al revés, que sería regalar el servicio.
 */
function planVigente(fila) {
  if (!fila) return { plan: "free", producto: "", expiraEl: null };
  const vigente = !fila.expires_at || fila.expires_at > ahora();
  return {
    plan: vigente ? fila.plan : "free",
    producto: vigente ? fila.product : "",
    expiraEl: fila.expires_at ?? null,
  };
}

// ─── Rutas ───

/**
 * Rutas de la suscripción. Devuelve null si `path` no es suya, para que el router siga.
 *
 *   POST /v1/suscripcion/sincronizar  — el cliente da un originalTransactionId; el
 *                                       servidor le pregunta a Apple y escribe el plan
 *   POST /v1/suscripcion/apple        — App Store Server Notifications V2 (solo dispara
 *                                       una re-sincronización; ver la cabecera)
 *   GET  /v1/suscripcion              — el plan vigente, para pintarlo
 */
export async function suscripciones(request, env, path) {
  if (!path.startsWith("/v1/suscripcion")) return null;

  // Sin credenciales de la App Store Server API no hay forma de comprobar nada con
  // Apple, y un endpoint de suscripción que no comprueba nada es peor que no existir.
  if (
    !env.APPSTORE_IAP_KEY_P8 ||
    !env.APPSTORE_IAP_KEY_ID ||
    !env.APPSTORE_ISSUER_ID ||
    !env.APPSTORE_BUNDLE_ID
  ) {
    return error(404, "suscripcion_no_configurada", "Este servidor no vende suscripciones");
  }
  if (!env.DB) return error(500, "sin_base_de_datos", "Falta la base de datos D1");

  // ── El webhook de Apple ──
  //
  // Va ANTES de pedir cuenta porque Apple no manda ningún token nuestro: la petición
  // llega de sus servidores y no de un jugador. Por eso mismo no puede escribir nada
  // que venga en el cuerpo.
  if (path === "/v1/suscripcion/apple") {
    if (request.method !== "POST") return error(405, "metodo_no_soportado", "Método no soportado");
    return await avisoDeApple(request, env);
  }

  const user = await usuarioDe(request, env);
  if (!user) return error(401, "sin_cuenta", "Hace falta una cuenta de la comunidad");

  if (path === "/v1/suscripcion" && request.method === "GET") {
    const fila = await env.DB.prepare(
      "SELECT plan, product, expires_at FROM subscriptions WHERE user = ?1"
    ).bind(user.id).first();
    return json(200, planVigente(fila));
  }

  if (path === "/v1/suscripcion/sincronizar" && request.method === "POST") {
    const cuerpo = await request.json().catch(() => ({}));
    const id = String(cuerpo?.originalTransactionId ?? "").trim();
    // Los identificadores de Apple son numéricos. Filtrarlos aquí evita que una cadena
    // rara acabe en la URL de la llamada a Apple o en la tabla.
    if (!/^\d{1,25}$/.test(id)) {
      return error(400, "identificador_invalido", "Falta un originalTransactionId válido");
    }

    let respuesta;
    try {
      respuesta = await consultarApple(env, id);
    } catch {
      return error(502, "apple_no_disponible", "No se pudo comprobar la compra con Apple");
    }
    if (!respuesta.encontrada) {
      return error(404, "compra_desconocida", "Apple no reconoce esa compra");
    }

    // ── De quién es esta suscripción ──
    //
    // Primero, lo que dice Apple: si la transacción trae `appAccountToken`, es la propia
    // compra la que declara a qué cuenta pertenece, y si no es esta, se acabó.
    const esperada = cuentaEsperada(request);
    if (respuesta.cuenta && esperada && respuesta.cuenta.toLowerCase() !== esperada) {
      return error(403, "compra_de_otro", "Esa compra pertenece a otra cuenta");
    }
    // Y si no lo trae (compras hechas antes de que la app lo mandara), se cae al
    // criterio de siempre: el primero que la reclama se la queda. No es perfecto, pero
    // impide lo importante — que reclamar un identificador ajeno le quite el plan a
    // quien pagó.
    if (!respuesta.cuenta) {
      const dueno = await env.DB.prepare(
        "SELECT user FROM subscriptions WHERE original_transaction_id = ?1"
      ).bind(id).first();
      if (dueno && dueno.user !== user.id) {
        return error(403, "compra_de_otro", "Esa compra ya está en otra cuenta");
      }
    }

    await guardar(env, user.id, {
      plan: respuesta.plan,
      producto: respuesta.producto,
      originalTransactionId: id,
      expiresAt: respuesta.expiresAt,
    });

    return json(200, {
      plan: respuesta.plan,
      producto: respuesta.producto,
      expiraEl: respuesta.expiresAt,
      entorno: respuesta.entorno,
    });
  }

  return error(405, "metodo_no_soportado", "Método no soportado");
}

/**
 * El aviso de Apple: renovaciones, cancelaciones, reembolsos y cambios de plan.
 *
 * Lo único que se saca del cuerpo es el `originalTransactionId`, y solo para volver a
 * preguntarle a la API de Apple por esa suscripción. El plan NUNCA sale de aquí — ver la
 * explicación larga en la cabecera del fichero.
 *
 * Siempre se contesta 200, incluso cuando el aviso no sirve para nada. Un 4xx hace que
 * Apple lo reintente durante días, y reintentar un aviso que no tiene dueño en nuestra
 * base de datos no lo va a arreglar nunca.
 */
async function avisoDeApple(request, env) {
  const cuerpo = await request.json().catch(() => ({}));
  const aviso = payloadDeJws(cuerpo?.signedPayload);
  if (!aviso) return json(200, { ignorado: "payload_ilegible" });

  // Un filtro barato, no una comprobación de seguridad: un aviso de otra app no tiene
  // nada que hacer aquí, y así el ruido no llega a gastar llamadas contra Apple.
  const bundle = aviso?.data?.bundleId;
  if (bundle && bundle !== env.APPSTORE_BUNDLE_ID) {
    return json(200, { ignorado: "otro_bundle" });
  }

  const transaccion = payloadDeJws(aviso?.data?.signedTransactionInfo) ?? {};
  const id = String(
    transaccion.originalTransactionId ?? aviso?.data?.originalTransactionId ?? ""
  ).trim();
  if (!/^\d{1,25}$/.test(id)) return json(200, { ignorado: "sin_identificador" });

  // Solo se re-sincroniza lo que ya tiene dueño. Un identificador que no está en la
  // tabla no puede crear una fila: sin esto, el endpoint —que no exige autenticación
  // porque Apple no la manda— sería una forma de hacer que el Worker llame a Apple
  // tantas veces como uno quiera.
  const fila = await env.DB.prepare(
    "SELECT user FROM subscriptions WHERE original_transaction_id = ?1"
  ).bind(id).first();
  if (!fila) return json(200, { ignorado: "desconocida" });

  let respuesta;
  try {
    respuesta = await consultarApple(env, id);
  } catch {
    // Que Apple no conteste ahora no es motivo para pedirle que reintente: la app
    // re-sincroniza al arrancar y `expires_at` caduca sola.
    return json(200, { ignorado: "apple_no_disponible" });
  }
  if (!respuesta.encontrada) return json(200, { ignorado: "compra_desconocida" });

  await guardar(env, fila.user, {
    plan: respuesta.plan,
    producto: respuesta.producto,
    originalTransactionId: id,
    expiresAt: respuesta.expiresAt,
  });

  return json(200, { sincronizada: true, tipo: aviso.notificationType ?? null });
}
