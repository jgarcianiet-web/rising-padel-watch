// El entrenador IA, del lado del servidor.
//
// ## Por qué existe este fichero
//
// Hasta ahora el Coach llamaba a `api.anthropic.com` **desde el iPhone con la clave de
// API del propio usuario**, guardada en su Llavero. Para desarrollar está bien; para
// vender la app no vale: nadie va a abrir una cuenta en Anthropic, meter una tarjeta y
// pegar una clave para poder usar una función de una app de pádel. El Coach era, de
// hecho, lo que hacía que el producto no se pudiera cobrar.
//
// Aquí la clave es del servicio (`ANTHROPIC_API_KEY`, secreto del Worker) y el usuario
// solo necesita su cuenta de la comunidad, que ya tiene.
//
// ## Lo que eso obliga a defender
//
// Un endpoint que reenvía un texto libre a un modelo con MI clave es, si se deja
// abierto, Claude gratis para quien se registre. Las defensas, por orden de importancia:
//
//  1. **Cuenta obligatoria.** Sin token de la comunidad no hay Coach.
//  2. **Cuota mensual por cuenta**, contada en el servidor (tabla `coach_usage`). El
//     cliente no puede pedir más de lo que le queda, y el contador no vive en el móvil.
//  3. **El servidor manda el prompt de sistema**, no el cliente. Encajona al modelo en
//     "entrenador de pádel sobre estos datos" y, sobre todo, hace que el endpoint no
//     sirva como asistente de propósito general.
//  4. **Topes de tamaño**: el prompt del cliente y los tokens de salida se recortan
//     aquí. Un cliente modificado no puede pedir una respuesta de 100.000 tokens.
//
// Si `ANTHROPIC_API_KEY` no está configurada, el endpoint **no existe** (404) y la app
// cae sola a la clave propia del usuario. Es el mismo patrón que `TANDAS_TOKEN`: una
// función que depende de un secreto no debe fingir que está ahí cuando no lo está.

import { usuarioDe } from "./comunidad.js";

const MODELO = "claude-opus-5";

/** Cuánto puede pedir un cliente de una vez. Un análisis largo cabe de sobra. */
const MAX_PROMPT = 24_000;
const MAX_TOKENS_SALIDA = 4_000;

/**
 * Peticiones al mes por cuenta en el plan gratuito.
 *
 * 30 da para un análisis por partido de alguien que juega dos veces por semana, más
 * conversación. El plan de pago sube el número; mientras no haya suscripción, `plan`
 * es 'free' para todo el mundo y el límite es este.
 */
const CUOTA = { free: 30, pro: 300, elite: 1000 };

/** El prompt de sistema lo pone el servidor. Ver la cabecera, punto 3. */
const SISTEMA = [
  "Eres el entrenador de pádel de la app Rising Pádel.",
  "Respondes SOLO sobre el pádel del jugador y los datos de sus partidos que te pasan:",
  "golpeos detectados por su reloj, niveles por golpe, objetivos, frecuencia cardíaca y",
  "evolución. Si te preguntan cualquier otra cosa, responde que solo sabes de su pádel.",
  "",
  "Distingue SIEMPRE entre lo que el dato dice y lo que tú interpretas. Puedes decir",
  '"tu pulso fue más alto en el segundo set y tu nota técnica bajó"; no puedes decir',
  '"la fatiga causó tus errores". No des consejos médicos ni diagnósticos.',
  "",
  "No te inventes números. Si un dato no está entre los que te pasan, di que no lo",
  "sabes en vez de estimarlo.",
].join("\n");

const json = (status, obj) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const error = (status, code, message) => json(status, { error: { code, message } });

/** Primer día del mes en curso, la ventana de la cuota. */
const periodoActual = () => new Date().toISOString().slice(0, 7);

/**
 * Cuántas peticiones lleva este usuario en el mes en curso y cuántas le tocan.
 *
 * El plan sale de la propia tabla y por defecto es 'free': cuando exista la
 * suscripción, lo único que cambia es quién escribe esa columna.
 */
async function consumo(env, userId) {
  const fila = await env.DB.prepare(
    "SELECT plan, used FROM coach_usage WHERE user = ?1 AND period = ?2"
  )
    .bind(userId, periodoActual())
    .first();
  const plan = fila?.plan || "free";
  return { plan, usadas: fila?.used ?? 0, limite: CUOTA[plan] ?? CUOTA.free };
}

/**
 * Rutas del Coach. Devuelve null si `path` no es suya, para que el router siga.
 *
 *   POST /v1/coach/mensaje   — una petición al modelo (análisis, crónica o chat)
 *   GET  /v1/coach/cuota     — cuántas le quedan este mes, para pintarlo en la app
 */
export async function coach(request, env, path) {
  if (!path.startsWith("/v1/coach")) return null;

  // Sin clave del servicio, la función no existe: la app lo detecta y usa la del
  // usuario, que es como funcionaba antes.
  if (!env.ANTHROPIC_API_KEY) {
    return error(404, "coach_no_configurado", "Este servidor no tiene entrenador IA");
  }
  if (!env.DB) return error(500, "sin_base_de_datos", "Falta la base de datos D1");

  const user = await usuarioDe(request, env);
  if (!user) return error(401, "sin_cuenta", "Hace falta una cuenta de la comunidad");

  if (path === "/v1/coach/cuota" && request.method === "GET") {
    const { plan, usadas, limite } = await consumo(env, user.id);
    return json(200, { plan, usadas, limite, restantes: Math.max(0, limite - usadas) });
  }

  if (path !== "/v1/coach/mensaje" || request.method !== "POST") {
    return error(405, "metodo_no_soportado", "Método no soportado");
  }

  let cuerpo;
  try {
    cuerpo = await request.json();
  } catch {
    return error(400, "cuerpo_invalido", "El cuerpo tiene que ser JSON");
  }

  // El cliente manda turnos de conversación (el chat) o uno solo (el análisis). Se
  // normalizan a la forma de la API y se recortan aquí, no en el móvil.
  const turnos = Array.isArray(cuerpo.messages) ? cuerpo.messages : null;
  const mensajes = turnos
    ? turnos
        .filter((m) => m && typeof m.content === "string" && m.content.trim())
        .slice(-20)
        .map((m) => ({
          role: m.role === "assistant" ? "assistant" : "user",
          content: m.content.slice(0, MAX_PROMPT),
        }))
    : typeof cuerpo.prompt === "string" && cuerpo.prompt.trim()
      ? [{ role: "user", content: cuerpo.prompt.slice(0, MAX_PROMPT) }]
      : null;

  if (!mensajes || mensajes.length === 0) {
    return error(400, "cuerpo_invalido", "Falta prompt o messages");
  }
  // La API exige que el primer turno sea del usuario.
  if (mensajes[0].role !== "user") mensajes.shift();
  if (mensajes.length === 0) {
    return error(400, "cuerpo_invalido", "La conversación tiene que empezar por el usuario");
  }

  const { plan, usadas, limite } = await consumo(env, user.id);
  if (usadas >= limite) {
    return json(429, {
      error: {
        code: "cuota_agotada",
        message: `Has usado las ${limite} consultas de este mes al entrenador.`,
      },
      plan,
      usadas,
      limite,
    });
  }

  const maxTokens = Math.min(
    Number(cuerpo.maxTokens) > 0 ? Number(cuerpo.maxTokens) : MAX_TOKENS_SALIDA,
    MAX_TOKENS_SALIDA
  );

  let respuesta;
  try {
    respuesta = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: maxTokens,
        // Pensamiento adaptativo: el análisis de un partido es justo el tipo de tarea
        // que mejora razonando antes de responder.
        thinking: { type: "adaptive" },
        system: SISTEMA,
        messages: mensajes,
      }),
    });
  } catch {
    return error(502, "sin_conexion", "No se pudo hablar con el modelo");
  }

  if (!respuesta.ok) {
    // El error del proveedor no se reenvía tal cual: puede llevar detalles de la
    // cuenta del servicio que no son del usuario.
    const estado = respuesta.status === 429 ? 429 : 502;
    return error(estado, "modelo_no_disponible", "El entrenador no está disponible ahora");
  }

  const datos = await respuesta.json();
  const texto = (datos.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("\n");

  // Se cobra la petición DESPUÉS de que el modelo conteste: si falla, no se descuenta.
  // Un UPSERT y no un SELECT+UPDATE para que dos peticiones a la vez no se pisen.
  await env.DB.prepare(
    `INSERT INTO coach_usage (user, period, plan, used)
       VALUES (?1, ?2, ?3, 1)
     ON CONFLICT(user, period) DO UPDATE SET used = used + 1`
  )
    .bind(user.id, periodoActual(), plan)
    .run();

  return json(200, {
    texto,
    usadas: usadas + 1,
    limite,
    restantes: Math.max(0, limite - usadas - 1),
  });
}
