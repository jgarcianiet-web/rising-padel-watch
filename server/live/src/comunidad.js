// La comunidad: usuarios, seguir, muro con etiquetas, y el aviso de "está jugando".
//
// Vive en D1 (los datos con relaciones) mientras el marcador en vivo sigue en KV (un
// valor por clave que caduca solo). El push va directo a APNs desde el worker, con la
// misma clave .p8 de App Store Connect que ya usa la subida de builds.

const ALIAS = /^[a-z0-9-]{2,24}$/;

// ─── util ───

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const error = (status, code, message) => json(status, { error: { code, message } });

const ahora = () => new Date().toISOString();

function tokenAleatorio() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** El usuario del bearer token, o null. */
export async function usuarioDe(request, env) {
  const auth = request.headers.get("authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  const token = auth.slice(7).trim();
  if (!token) return null;
  return env.DB.prepare("SELECT id, alias FROM users WHERE token = ?")
    .bind(token)
    .first();
}

// ─── APNs ───

let apnsJwt = null; // { token, mintedAt } — se reusa hasta 40 min, como pide Apple.

async function jwtApns(env) {
  if (apnsJwt && Date.now() - apnsJwt.mintedAt < 40 * 60 * 1000) return apnsJwt.token;

  const der = Uint8Array.from(
    atob(env.APNS_KEY_P8.replace(/-----[^-]+-----|\s/g, "")),
    (c) => c.charCodeAt(0)
  );
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );
  const b64 = (obj) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const cuerpo = `${b64({ alg: "ES256", kid: env.APNS_KEY_ID })}.${b64({
    iss: env.APNS_TEAM_ID,
    iat: Math.floor(Date.now() / 1000),
  })}`;
  const firma = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(cuerpo)
  );
  const token = `${cuerpo}.${btoa(String.fromCharCode(...new Uint8Array(firma)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`;
  apnsJwt = { token, mintedAt: Date.now() };
  return token;
}

/** Manda un push a todos los dispositivos de unos usuarios. Fuego y olvido. */
export async function push(env, userIds, titulo, cuerpo, payload = {}) {
  if (!env.APNS_KEY_P8 || userIds.length === 0) return;
  const marcas = userIds.map(() => "?").join(",");
  const { results } = await env.DB.prepare(
    `SELECT apns FROM devices WHERE user IN (${marcas})`
  ).bind(...userIds).all();
  if (!results?.length) return;

  const jwt = await jwtApns(env);
  const aps = JSON.stringify({
    aps: { alert: { title: titulo, body: cuerpo }, sound: "default" },
    ...payload,
  });
  await Promise.allSettled(
    results.map(({ apns }) =>
      fetch(`https://api.push.apple.com/3/device/${apns}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": env.APNS_TOPIC,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        body: aps,
      })
    )
  );
}

/** Avisa a los seguidores de que este usuario acaba de empezar un partido. */
export async function avisarPartidoEnVivo(env, user, sessionId) {
  const { results } = await env.DB.prepare(
    `SELECT follower FROM follows WHERE followed = ?
       AND follower NOT IN (SELECT user FROM blocks WHERE blocked = ?)`
  ).bind(user.id, user.id).all();
  await push(
    env,
    (results ?? []).map((r) => r.follower),
    "Partido en vivo",
    `${user.alias} está jugando ahora. Toca para seguirlo.`,
    { live: { alias: user.alias, sessionId } }
  );
}

// ─── rutas ───

/** Atiende las rutas /v1/comunidad/*; devuelve null si la ruta no es de aquí. */
export async function comunidad(request, env, path) {
  const ruta = path.replace(/^\/v1\/comunidad/, "");
  if (ruta === path) return null;
  const metodo = request.method;

  // Registro: abierto, por alias. El token que devuelve ES la cuenta: a Llavero.
  if (ruta === "/registro" && metodo === "POST") {
    const { alias } = await request.json().catch(() => ({}));
    const limpio = (alias || "").toLowerCase().trim();
    if (!ALIAS.test(limpio)) {
      return error(400, "alias_invalido", "Alias: 2-24 caracteres, letras, números o guiones");
    }
    const token = tokenAleatorio();
    try {
      await env.DB.prepare(
        "INSERT INTO users (alias, token, created_at) VALUES (?, ?, ?)"
      ).bind(limpio, token, ahora()).run();
    } catch {
      return error(409, "alias_ocupado", "Ese alias ya existe");
    }
    return json(201, { alias: limpio, token });
  }

  // Todo lo demás exige cuenta.
  const yo = await usuarioDe(request, env);
  if (!yo) return error(401, "sin_cuenta", "Token inválido");

  if (ruta === "/usuarios" && metodo === "GET") {
    const q = new URL(request.url).searchParams.get("q")?.toLowerCase() ?? "";
    const { results } = await env.DB.prepare(
      `SELECT u.alias,
              EXISTS(SELECT 1 FROM follows f WHERE f.follower = ?1 AND f.followed = u.id) AS siguiendo
         FROM users u
        WHERE u.alias LIKE ?2 AND u.id != ?1
          AND u.id NOT IN (SELECT blocked FROM blocks WHERE user = ?1)
        ORDER BY u.alias LIMIT 25`
    ).bind(yo.id, `%${q}%`).all();
    return json(200, { usuarios: results ?? [] });
  }

  const seguir = ruta.match(/^\/seguir\/([a-z0-9-]+)$/);
  if (seguir) {
    const otro = await env.DB.prepare("SELECT id FROM users WHERE alias = ?")
      .bind(seguir[1]).first();
    if (!otro) return error(404, "no_existe", "No hay nadie con ese alias");
    if (metodo === "POST") {
      await env.DB.prepare(
        "INSERT OR IGNORE INTO follows (follower, followed) VALUES (?, ?)"
      ).bind(yo.id, otro.id).run();
      return new Response(null, { status: 204 });
    }
    if (metodo === "DELETE") {
      await env.DB.prepare("DELETE FROM follows WHERE follower = ? AND followed = ?")
        .bind(yo.id, otro.id).run();
      return new Response(null, { status: 204 });
    }
  }

  if (ruta === "/muro" && metodo === "GET") {
    // Lo mío y lo de quien sigo, sin bloqueados; las etiquetas van aparte por post.
    const { results } = await env.DB.prepare(
      `SELECT p.id, u.alias, p.text, p.card, p.created_at AS creado,
              (SELECT GROUP_CONCAT(u2.alias) FROM post_tags t
                 JOIN users u2 ON u2.id = t.user WHERE t.post = p.id) AS etiquetas
         FROM posts p JOIN users u ON u.id = p.user
        WHERE (p.user = ?1 OR p.user IN (SELECT followed FROM follows WHERE follower = ?1))
          AND p.user NOT IN (SELECT blocked FROM blocks WHERE user = ?1)
        ORDER BY p.id DESC LIMIT 50`
    ).bind(yo.id).all();
    return json(200, { posts: results ?? [] });
  }

  if (ruta === "/publicar" && metodo === "POST") {
    const { texto, tarjeta, etiquetas } = await request.json().catch(() => ({}));
    const text = (texto || "").trim().slice(0, 500);
    if (!text) return error(400, "vacio", "Escribe algo");
    const insercion = await env.DB.prepare(
      "INSERT INTO posts (user, text, card, created_at) VALUES (?, ?, ?, ?)"
    ).bind(yo.id, text, tarjeta ? JSON.stringify(tarjeta).slice(0, 4096) : null, ahora()).run();
    const postId = insercion.meta.last_row_id;

    const avisados = [];
    for (const alias of [...new Set(etiquetas ?? [])].slice(0, 10)) {
      const otro = await env.DB.prepare("SELECT id FROM users WHERE alias = ?")
        .bind(String(alias).toLowerCase()).first();
      if (otro && otro.id !== yo.id) {
        await env.DB.prepare("INSERT OR IGNORE INTO post_tags (post, user) VALUES (?, ?)")
          .bind(postId, otro.id).run();
        avisados.push(otro.id);
      }
    }
    // La etiqueta avisa: es la mitad de su gracia.
    await push(env, avisados, "Te han mencionado", `${yo.alias}: ${text.slice(0, 80)}`, {
      post: { id: postId },
    });
    return json(201, { id: postId });
  }

  const borrar = ruta.match(/^\/publicacion\/(\d+)$/);
  if (borrar && metodo === "DELETE") {
    await env.DB.prepare("DELETE FROM post_tags WHERE post = ?").bind(borrar[1]).run();
    await env.DB.prepare("DELETE FROM posts WHERE id = ? AND user = ?")
      .bind(borrar[1], yo.id).run();
    return new Response(null, { status: 204 });
  }

  if (ruta === "/dispositivo" && metodo === "POST") {
    const { token } = await request.json().catch(() => ({}));
    if (!token || token.length > 200) return error(400, "token_invalido", "Token APNs inválido");
    await env.DB.prepare(
      "INSERT INTO devices (apns, user) VALUES (?1, ?2) ON CONFLICT(apns) DO UPDATE SET user = ?2"
    ).bind(token, yo.id).run();
    return new Response(null, { status: 204 });
  }

  const bloquear = ruta.match(/^\/bloquear\/([a-z0-9-]+)$/);
  if (bloquear && metodo === "POST") {
    const otro = await env.DB.prepare("SELECT id FROM users WHERE alias = ?")
      .bind(bloquear[1]).first();
    if (!otro) return error(404, "no_existe", "No hay nadie con ese alias");
    await env.DB.prepare("INSERT OR IGNORE INTO blocks (user, blocked) VALUES (?, ?)")
      .bind(yo.id, otro.id).run();
    await env.DB.prepare("DELETE FROM follows WHERE follower = ? AND followed = ?")
      .bind(yo.id, otro.id).run();
    return new Response(null, { status: 204 });
  }

  if (ruta === "/reportar" && metodo === "POST") {
    const { postId, motivo } = await request.json().catch(() => ({}));
    if (!postId) return error(400, "falta_post", "Falta el post");
    await env.DB.prepare(
      "INSERT INTO reports (reporter, post, reason, created_at) VALUES (?, ?, ?, ?)"
    ).bind(yo.id, postId, (motivo || "").slice(0, 200), ahora()).run();
    return new Response(null, { status: 204 });
  }

  if (ruta === "/en-vivo" && metodo === "GET") {
    // Quién de los que sigo está jugando ahora: KV con TTL, escrito en cada PUT live.
    const { results } = await env.DB.prepare(
      `SELECT u.alias FROM follows f JOIN users u ON u.id = f.followed WHERE f.follower = ?`
    ).bind(yo.id).all();
    const jugando = [];
    for (const { alias } of results ?? []) {
      const sessionId = await env.LIVE.get(`live-user:${alias}`);
      if (sessionId) jugando.push({ alias, sessionId });
    }
    return json(200, { jugando });
  }

  return error(404, "ruta_desconocida", "Nada por aquí");
}
