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

/** Apunta el resultado de un partido en vivo terminado. Una vez por sesión. */
export async function apuntarResultado(env, user, sessionId, estado) {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO results (user, session, date, won, shots) VALUES (?, ?, ?, ?, ?)"
  ).bind(
    user.id,
    sessionId,
    new Date().toISOString().slice(0, 10),
    estado?.score?.winner === "us" ? 1 : 0,
    estado?.shotCount ?? 0
  ).run();
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

  // Recuperar la cuenta: alias + código de recuperación → el token de siempre.
  // Es la única puerta de vuelta si se pierde el token (móvil nuevo, Android
  // desinstalado): sin código, la cuenta es irrecuperable a propósito — no hay
  // correo ni contraseña que resetear.
  if (ruta === "/recuperar" && metodo === "POST") {
    const { alias, codigo } = await request.json().catch(() => ({}));
    const fila = await env.DB.prepare(
      `SELECT u.alias, u.token FROM users u
         JOIN recovery_codes r ON r.user_id = u.id
        WHERE u.alias = ? AND r.code = ?`
    ).bind((alias || "").toLowerCase().trim(), (codigo || "").toUpperCase().trim()).first();
    if (!fila) return error(401, "no_coincide", "Ese alias y código no coinciden");
    return json(200, { alias: fila.alias, token: fila.token });
  }

  // Todo lo demás exige cuenta.
  const yo = await usuarioDe(request, env);
  if (!yo) return error(401, "sin_cuenta", "Token inválido");

  // El código de recuperación del usuario: se crea una vez y no cambia. Quien lo
  // pide, debe guardarlo — es lo único que devuelve la cuenta si se pierde el token.
  if (ruta === "/recuperacion" && metodo === "POST") {
    // Legible a propósito: 8 caracteres sin ambiguos (ni 0/O ni 1/I/L).
    const alfabeto = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    let codigo = "";
    const bytes = crypto.getRandomValues(new Uint8Array(8));
    for (const b of bytes) codigo += alfabeto[b % alfabeto.length];
    await env.DB.prepare(
      "INSERT OR IGNORE INTO recovery_codes (user_id, code) VALUES (?, ?)"
    ).bind(yo.id, codigo).run();
    const fila = await env.DB.prepare(
      "SELECT code FROM recovery_codes WHERE user_id = ?"
    ).bind(yo.id).first();
    return json(200, { codigo: fila.code });
  }

  // ─── El ancla del nivel: la comunidad como patrón de medida ───
  //
  // El reloj mide en su propia escala (velocidad de pala, amplitud, regularidad) y el
  // jugador quiere saber a qué nivel de pista equivale. Unir las dos escalas solo se
  // puede hacer con jugadores de nivel conocido, así que se acumulan pares (nivel que
  // declara el usuario, nivel que midió su reloj) y de ahí sale la tabla. No se inventa
  // nada: con pocos datos la app no enseña equivalencia.
  if (ruta === "/nivel" && metodo === "POST") {
    const { declarado, medido } = await request.json().catch(() => ({}));
    const d = Number(declarado);
    const m = Number(medido);
    if (!(d >= 1 && d <= 7) || !(m >= 1 && m <= 7)) {
      return error(400, "fuera_de_rango", "El nivel va de 1 a 7");
    }
    await env.DB.prepare(
      `INSERT INTO levels (user, declared, measured, updated_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(user) DO UPDATE SET declared = ?2, measured = ?3, updated_at = ?4`
    ).bind(yo.id, d, m, ahora()).run();
    return new Response(null, { status: 204 });
  }

  if (ruta === "/nivel" && metodo === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT declared, measured FROM levels"
    ).all();
    const filas = results ?? [];

    // Las anclas: por cada nivel declarado (redondeado a medio punto), la mediana de
    // lo que midieron los relojes de esos jugadores.
    const porNivel = new Map();
    for (const fila of filas) {
      const clave = Math.round(fila.declared * 2) / 2;
      if (!porNivel.has(clave)) porNivel.set(clave, []);
      porNivel.get(clave).push(fila.measured);
    }
    const anclas = [...porNivel.entries()]
      .map(([nivelDeclarado, medidos]) => {
        const ordenados = medidos.slice().sort((a, b) => a - b);
        return {
          nivelDeclarado,
          medidoMediana: ordenados[Math.floor(ordenados.length / 2)],
          jugadores: ordenados.length,
        };
      })
      .sort((a, b) => a.nivelDeclarado - b.nivelDeclarado);

    // Las mediciones sueltas, sin alias: son números para calcular el percentil en el
    // móvil, no un ranking de nadie.
    return json(200, {
      anclas,
      mediciones: filas.map((f) => f.measured),
    });
  }

  // La copia de seguridad del usuario: un único objeto en R2 que se machaca en cada
  // subida. Es lo que hace que reinstalar la app no borre nada: el token sobrevive
  // en el Llavero y con él vuelve el historial entero.
  if (ruta === "/copia" && metodo === "PUT") {
    if (!env.FOTOS) return error(500, "sin_r2", "El servidor no tiene R2 configurado");
    const cuerpo = await request.arrayBuffer();
    if (cuerpo.byteLength > 20 * 1024 * 1024) {
      return error(413, "muy_grande", "La copia supera los 20 MB");
    }
    await env.FOTOS.put(`copias/${yo.id}.json`, cuerpo, {
      httpMetadata: { contentType: "application/json" },
    });
    return json(200, { guardada: true, bytes: cuerpo.byteLength });
  }
  // Las tandas etiquetadas para entrenar el clasificador.
  //
  // Es el único sitio de toda la app por el que sale señal cruda de sensores, y sale
  // porque el usuario le da a un botón que se lo dice con esas palabras. Nunca es
  // automático: el resto de la app manda recuentos y nunca series.
  //
  // Cada subida es un objeto nuevo con su marca de tiempo, no un fichero que se
  // machaca: dos tandas del mismo día son dos tandas, y perder una por subir la
  // siguiente sería tirar el trabajo de una tarde de pista.
  if (ruta === "/tandas" && metodo === "POST") {
    if (!env.FOTOS) return error(500, "sin_r2", "El servidor no tiene R2 configurado");
    const cuerpo = await request.arrayBuffer();
    if (cuerpo.byteLength === 0) return error(400, "vacio", "No hay nada que subir");
    if (cuerpo.byteLength > 50 * 1024 * 1024) {
      return error(413, "muy_grande", "La tanda supera los 50 MB");
    }
    const nombre = `tandas/${yo.id}-${Date.now()}.jsonl`;
    await env.FOTOS.put(nombre, cuerpo, {
      httpMetadata: { contentType: "application/x-ndjson" },
    });
    return json(200, { guardada: true, bytes: cuerpo.byteLength, nombre });
  }

  if (ruta === "/copia" && metodo === "GET") {
    if (!env.FOTOS) return error(404, "sin_r2", "Sin copias");
    const objeto = await env.FOTOS.get(`copias/${yo.id}.json`);
    if (!objeto) return error(404, "sin_copia", "No hay ninguna copia guardada");
    return new Response(objeto.body, {
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }

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
      `SELECT p.id, u.alias, p.text, p.card, p.photo, p.created_at AS creado,
              (SELECT GROUP_CONCAT(u2.alias) FROM post_tags t
                 JOIN users u2 ON u2.id = t.user WHERE t.post = p.id) AS etiquetas,
              (SELECT COUNT(*) FROM reactions r WHERE r.post = p.id) AS reacciones,
              (SELECT emoji FROM reactions r WHERE r.post = p.id AND r.user = ?1) AS miReaccion,
              (SELECT COUNT(*) FROM comments c WHERE c.post = p.id) AS comentarios
         FROM posts p JOIN users u ON u.id = p.user
        WHERE (p.user = ?1 OR p.user IN (SELECT followed FROM follows WHERE follower = ?1))
          AND p.user NOT IN (SELECT blocked FROM blocks WHERE user = ?1)
        ORDER BY p.id DESC LIMIT 50`
    ).bind(yo.id).all();
    return json(200, { posts: results ?? [] });
  }

  if (ruta === "/reaccion" && metodo === "POST") {
    const { postId, emoji } = await request.json().catch(() => ({}));
    if (!postId) return error(400, "falta_post", "Falta el post");
    const limpio = String(emoji || "🎾").slice(0, 8);
    const actual = await env.DB.prepare(
      "SELECT emoji FROM reactions WHERE post = ? AND user = ?"
    ).bind(postId, yo.id).first();
    if (actual?.emoji === limpio) {
      // La misma otra vez la quita: el toggle de toda la vida.
      await env.DB.prepare("DELETE FROM reactions WHERE post = ? AND user = ?")
        .bind(postId, yo.id).run();
    } else {
      await env.DB.prepare(
        `INSERT INTO reactions (post, user, emoji) VALUES (?1, ?2, ?3)
           ON CONFLICT(post, user) DO UPDATE SET emoji = ?3`
      ).bind(postId, yo.id, limpio).run();
    }
    return new Response(null, { status: 204 });
  }

  const comentarios = ruta.match(/^\/comentarios\/(\d+)$/);
  if (comentarios && metodo === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT c.id, u.alias, c.text, c.created_at AS creado
         FROM comments c JOIN users u ON u.id = c.user
        WHERE c.post = ?1
          AND c.user NOT IN (SELECT blocked FROM blocks WHERE user = ?2)
        ORDER BY c.id LIMIT 100`
    ).bind(comentarios[1], yo.id).all();
    return json(200, { comentarios: results ?? [] });
  }

  if (ruta === "/comentar" && metodo === "POST") {
    const { postId, texto } = await request.json().catch(() => ({}));
    const text = (texto || "").trim().slice(0, 300);
    if (!postId || !text) return error(400, "vacio", "Escribe algo");
    await env.DB.prepare(
      "INSERT INTO comments (post, user, text, created_at) VALUES (?, ?, ?, ?)"
    ).bind(postId, yo.id, text, ahora()).run();
    // El comentario avisa al dueño del post (si no soy yo mismo).
    const dueno = await env.DB.prepare("SELECT user FROM posts WHERE id = ?")
      .bind(postId).first();
    if (dueno && dueno.user !== yo.id) {
      await push(env, [dueno.user], "Nuevo comentario",
        `${yo.alias}: ${text.slice(0, 80)}`, { post: { id: postId } });
    }
    return new Response(null, { status: 204 });
  }

  if (ruta === "/ranking" && metodo === "GET") {
    // La semana en curso (lunes a hoy), entre tú y los que sigues. Los datos salen de
    // los partidos en vivo terminados, que el worker apunta él solo.
    const hoy = new Date();
    const lunes = new Date(hoy);
    lunes.setUTCDate(hoy.getUTCDate() - ((hoy.getUTCDay() + 6) % 7));
    const desde = lunes.toISOString().slice(0, 10);
    const { results } = await env.DB.prepare(
      `SELECT u.alias, COUNT(*) AS partidos, SUM(r.won) AS victorias, SUM(r.shots) AS golpeos
         FROM results r JOIN users u ON u.id = r.user
        WHERE r.date >= ?1
          AND (r.user = ?2 OR r.user IN (SELECT followed FROM follows WHERE follower = ?2))
        GROUP BY u.alias
        ORDER BY partidos DESC, victorias DESC LIMIT 20`
    ).bind(desde, yo.id).all();
    return json(200, { desde, ranking: results ?? [] });
  }

  if (ruta === "/publicar" && metodo === "POST") {
    const { texto, tarjeta, etiquetas, foto } = await request.json().catch(() => ({}));
    const text = (texto || "").trim().slice(0, 500);
    if (!text) return error(400, "vacio", "Escribe algo");
    const insercion = await env.DB.prepare(
      "INSERT INTO posts (user, text, card, photo, created_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(
      yo.id, text,
      tarjeta ? JSON.stringify(tarjeta).slice(0, 4096) : null,
      typeof foto === "string" && /^[a-f0-9]{48}$/.test(foto) ? foto : null,
      ahora()
    ).run();
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

  // ─── retos ───

  if (ruta === "/reto" && metodo === "POST") {
    const { alias, metrica, dias } = await request.json().catch(() => ({}));
    const METRICAS = ["golpes", "victorias", "bandeja", "vibora", "smash"];
    if (!METRICAS.includes(metrica)) return error(400, "metrica", "Métrica desconocida");
    const otro = await env.DB.prepare("SELECT id FROM users WHERE alias = ?")
      .bind(String(alias || "").toLowerCase()).first();
    if (!otro || otro.id === yo.id) return error(404, "no_existe", "No hay nadie con ese alias");
    const hoy = new Date();
    const fin = new Date(hoy);
    fin.setUTCDate(hoy.getUTCDate() + Math.min(30, Math.max(1, Number(dias) || 7)));
    await env.DB.prepare(
      `INSERT INTO challenges (challenger, challenged, metric, start_date, end_date, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).bind(yo.id, otro.id, metrica, hoy.toISOString().slice(0, 10),
           fin.toISOString().slice(0, 10), ahora()).run();
    await push(env, [otro.id], "Te han retado",
      `${yo.alias} te reta: más ${metrica} hasta el ${fin.toISOString().slice(0, 10)}.`);
    return json(201, {});
  }

  if (ruta === "/retos" && metodo === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT c.id, c.metric, c.start_date AS desde, c.end_date AS hasta,
              u1.alias AS retador, u2.alias AS retado
         FROM challenges c
         JOIN users u1 ON u1.id = c.challenger JOIN users u2 ON u2.id = c.challenged
        WHERE c.challenger = ?1 OR c.challenged = ?1
        ORDER BY c.id DESC LIMIT 20`
    ).bind(yo.id).all();
    // El progreso sale de los resultados reales del rango; el reloj es el árbitro.
    const retos = [];
    for (const reto of results ?? []) {
      const cuenta = async (alias) => {
        const fila = await env.DB.prepare(
          `SELECT SUM(CASE ?1
                    WHEN 'golpes' THEN r.shots
                    WHEN 'victorias' THEN r.won
                    ELSE COALESCE(json_extract(r.by_type, '$.' || ?1), 0) END) AS total
             FROM results r JOIN users u ON u.id = r.user
            WHERE u.alias = ?2 AND r.date >= ?3 AND r.date <= ?4`
        ).bind(reto.metric, alias, reto.desde, reto.hasta).first();
        return fila?.total ?? 0;
      };
      retos.push({
        ...reto,
        marcadorRetador: await cuenta(reto.retador),
        marcadorRetado: await cuenta(reto.retado),
        terminado: reto.hasta < new Date().toISOString().slice(0, 10),
      });
    }
    return json(200, { retos });
  }

  // ─── torneos ───

  if (ruta === "/torneo" && metodo === "POST") {
    const { nombre, jugadores } = await request.json().catch(() => ({}));
    const aliases = [...new Set([yo.alias, ...(jugadores ?? []).map((a) => String(a).toLowerCase())])];
    if (![2, 4, 8].includes(aliases.length)) {
      return error(400, "jugadores", "Un torneo es de 2, 4 u 8 jugadores (contándote a ti)");
    }
    const ids = [];
    for (const alias of aliases) {
      const u = await env.DB.prepare("SELECT id FROM users WHERE alias = ?").bind(alias).first();
      if (!u) return error(404, "no_existe", `No existe @${alias}`);
      ids.push(u.id);
    }
    const t = await env.DB.prepare(
      "INSERT INTO tournaments (name, creator, status, created_at) VALUES (?, ?, 'activo', ?)"
    ).bind((nombre || "Torneo").slice(0, 60), yo.id, ahora()).run();
    const torneoId = t.meta.last_row_id;
    // Ronda 1 emparejada en orden; las siguientes se crean vacías y se van rellenando.
    for (let ronda = 1, cruces = ids.length / 2; cruces >= 1; ronda++, cruces /= 2) {
      for (let slot = 0; slot < cruces; slot++) {
        const p1 = ronda === 1 ? ids[slot * 2] : null;
        const p2 = ronda === 1 ? ids[slot * 2 + 1] : null;
        await env.DB.prepare(
          "INSERT INTO tmatches (t, round, slot, p1, p2) VALUES (?, ?, ?, ?, ?)"
        ).bind(torneoId, ronda, slot, p1, p2).run();
      }
    }
    await push(env, ids.filter((id) => id !== yo.id), "Torneo nuevo",
      `${yo.alias} te ha metido en «${(nombre || "Torneo").slice(0, 40)}».`);
    return json(201, { id: torneoId });
  }

  if (ruta === "/torneo" && metodo === "GET") {
    const torneo = await env.DB.prepare(
      `SELECT t.id, t.name AS nombre, t.status FROM tournaments t
        WHERE t.id IN (SELECT tm.t FROM tmatches tm WHERE tm.p1 = ?1 OR tm.p2 = ?1)
        ORDER BY t.id DESC LIMIT 1`
    ).bind(yo.id).first();
    if (!torneo) return json(200, { torneo: null });
    const { results } = await env.DB.prepare(
      `SELECT m.id, m.round AS ronda, m.slot,
              (SELECT alias FROM users WHERE id = m.p1) AS p1,
              (SELECT alias FROM users WHERE id = m.p2) AS p2,
              (SELECT alias FROM users WHERE id = m.winner) AS ganador
         FROM tmatches m WHERE m.t = ? ORDER BY m.round, m.slot`
    ).bind(torneo.id).all();
    return json(200, { torneo: { ...torneo, cruces: results ?? [] } });
  }

  if (ruta === "/torneo/ganador" && metodo === "POST") {
    const { matchId, alias } = await request.json().catch(() => ({}));
    const cruce = await env.DB.prepare("SELECT * FROM tmatches WHERE id = ?")
      .bind(matchId).first();
    if (!cruce || cruce.winner) return error(400, "cruce", "Ese cruce no está pendiente");
    const ganador = await env.DB.prepare("SELECT id FROM users WHERE alias = ?")
      .bind(String(alias || "").toLowerCase()).first();
    if (!ganador || ![cruce.p1, cruce.p2].includes(ganador.id)) {
      return error(400, "ganador", "El ganador tiene que ser uno de los dos");
    }
    // Solo los implicados reportan: es su cruce.
    if (![cruce.p1, cruce.p2].includes(yo.id)) {
      return error(403, "ajeno", "Solo los jugadores del cruce reportan su resultado");
    }
    await env.DB.prepare("UPDATE tmatches SET winner = ? WHERE id = ?")
      .bind(ganador.id, matchId).run();
    // El ganador sube a su hueco de la siguiente ronda; si no la hay, torneo acabado.
    const campo = cruce.slot % 2 === 0 ? "p1" : "p2";
    const siguiente = await env.DB.prepare(
      "SELECT id FROM tmatches WHERE t = ? AND round = ? AND slot = ?"
    ).bind(cruce.t, cruce.round + 1, Math.floor(cruce.slot / 2)).first();
    if (siguiente) {
      await env.DB.prepare(`UPDATE tmatches SET ${campo} = ? WHERE id = ?`)
        .bind(ganador.id, siguiente.id).run();
    } else {
      await env.DB.prepare("UPDATE tournaments SET status = 'terminado' WHERE id = ?")
        .bind(cruce.t).run();
    }
    return new Response(null, { status: 204 });
  }

  // ─── perfil público (con el duelo de retos incluido) ───

  const perfil = ruta.match(/^\/perfil\/([a-z0-9-]+)$/);
  if (perfil && metodo === "GET") {
    const otro = await env.DB.prepare("SELECT id, alias, created_at FROM users WHERE alias = ?")
      .bind(perfil[1]).first();
    if (!otro) return error(404, "no_existe", "No hay nadie con ese alias");
    const stats = await env.DB.prepare(
      `SELECT COUNT(*) AS partidos, COALESCE(SUM(won), 0) AS victorias,
              COALESCE(SUM(shots), 0) AS golpeos, MAX(date) AS ultimo
         FROM results WHERE user = ?`
    ).bind(otro.id).first();
    // El duelo: retos terminados entre los dos, contados por quién ganó cada uno.
    const { results: retos } = await env.DB.prepare(
      `SELECT c.metric, c.start_date AS desde, c.end_date AS hasta,
              c.challenger, c.challenged
         FROM challenges c
        WHERE ((c.challenger = ?1 AND c.challenged = ?2)
            OR (c.challenger = ?2 AND c.challenged = ?1))
          AND c.end_date < ?3`
    ).bind(yo.id, otro.id, new Date().toISOString().slice(0, 10)).all();
    let duelo = { yo: 0, el: 0 };
    for (const reto of retos ?? []) {
      const total = async (userId) => {
        const fila = await env.DB.prepare(
          `SELECT SUM(CASE ?1 WHEN 'golpes' THEN shots WHEN 'victorias' THEN won
                    ELSE COALESCE(json_extract(by_type, '$.' || ?1), 0) END) AS t
             FROM results WHERE user = ?2 AND date >= ?3 AND date <= ?4`
        ).bind(reto.metric, userId, reto.desde, reto.hasta).first();
        return fila?.t ?? 0;
      };
      const mio = await total(yo.id);
      const suyo = await total(otro.id);
      if (mio > suyo) duelo.yo++;
      else if (suyo > mio) duelo.el++;
    }
    const sigo = await env.DB.prepare(
      "SELECT 1 AS s FROM follows WHERE follower = ? AND followed = ?"
    ).bind(yo.id, otro.id).first();
    return json(200, {
      alias: otro.alias,
      desde: String(otro.created_at).slice(0, 10),
      partidos: stats?.partidos ?? 0,
      victorias: stats?.victorias ?? 0,
      golpeos: stats?.golpeos ?? 0,
      ultimo: stats?.ultimo,
      duelo,
      siguiendo: !!sigo,
    });
  }

  // ─── fotos (R2) ───

  if (ruta === "/foto" && metodo === "POST") {
    if (!env.FOTOS) return error(500, "sin_r2", "El servidor no tiene R2 configurado");
    const tipo = request.headers.get("content-type") || "image/jpeg";
    if (!tipo.startsWith("image/")) return error(400, "tipo", "Solo imágenes");
    const cuerpo = await request.arrayBuffer();
    if (cuerpo.byteLength > 3_000_000) return error(413, "grande", "Máximo 3 MB");
    const id = tokenAleatorio();
    await env.FOTOS.put(id, cuerpo, { httpMetadata: { contentType: tipo } });
    return json(201, { id });
  }

  const foto = ruta.match(/^\/foto\/([a-f0-9]{48})$/);
  if (foto && metodo === "GET") {
    if (!env.FOTOS) return error(404, "sin_r2", "Sin fotos");
    const objeto = await env.FOTOS.get(foto[1]);
    if (!objeto) return error(404, "no_existe", "No hay foto");
    return new Response(objeto.body, {
      headers: {
        "content-type": objeto.httpMetadata?.contentType || "image/jpeg",
        "cache-control": "public, max-age=31536000, immutable",
      },
    });
  }

  return error(404, "ruta_desconocida", "Nada por aquí");
}
