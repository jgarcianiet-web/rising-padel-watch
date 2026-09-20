// Competición: clubes y ligas (§36.14, §36.19 y §36.20 del documento de producto).
//
// ## La diferencia con lo que ya había
//
// La app tiene desde hace tiempo una "Liga Personal", que es el jugador contra sí mismo:
// su historial, sus objetivos y sus temporadas, todo dentro de su móvil. Esto es otra
// cosa — **la liga contra otros**, con inscripciones, calendario y clasificación — y las
// dos tienen que convivir, porque contestan a preguntas distintas: "¿estoy mejorando?" y
// "¿quién va primero?".
//
// También había torneos (cuadro de eliminatorias, en `comunidad.js`). Una liga no es un
// torneo: en el torneo pierdes y te vas a casa, en la liga juegas contra todos. Por eso
// son tablas distintas y no un `tipo` dentro de la misma.
//
// ## Cómo se puntúa, y por qué así
//
// **Un partido ganado es un punto y no hay empates.** En pádel no se empata: o ganas o
// pierdes. Muchas ligas reparten 3/1/0 copiando al fútbol, y ahí el 1 del empate es lo
// que hace que 3 tenga sentido; sin empates, 3-0 y 1-0 ordenan exactamente igual y el 3
// solo sirve para que los números parezcan más grandes.
//
// El desempate es la **diferencia de juegos**, y esa sí cambia clasificaciones: premia
// ganar 6-1 sobre ganar 7-5, que es lo que de verdad distingue a dos parejas con los
// mismos partidos ganados.

import { usuarioDe } from "./comunidad.js";

const json = (status, obj) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const error = (status, code, message) => json(status, { error: { code, message } });

const ahora = () => new Date().toISOString();

/**
 * Calendario de todos contra todos por el método del círculo.
 *
 * Se fija el primer participante y los demás rotan; en cada ronda se emparejan los
 * extremos. Con número impar entra un hueco (`null`) que significa "descansa esta
 * ronda", que es lo correcto: quien descansa no juega, no gana por incomparecencia.
 *
 * Devuelve rondas de pares de índices.
 */
function calendario(n) {
  // Con un participante no hay liga; con dos, un partido y ya.
  if (n < 2) return [];
  const indices = [...Array(n).keys()];
  if (n % 2 === 1) indices.push(null);

  const total = indices.length;
  const rondas = [];
  let vuelta = indices.slice();

  for (let ronda = 0; ronda < total - 1; ronda++) {
    const partidos = [];
    for (let i = 0; i < total / 2; i++) {
      const a = vuelta[i];
      const b = vuelta[total - 1 - i];
      if (a !== null && b !== null) partidos.push([a, b]);
    }
    rondas.push(partidos);
    // El primero se queda quieto y el resto rota una posición.
    vuelta = [vuelta[0], vuelta[total - 1], ...vuelta.slice(1, total - 1)];
  }
  return rondas;
}

/**
 * La clasificación a partir de los partidos jugados.
 *
 * Se calcula al vuelo y no se guarda: una tabla de clasificación almacenada es una copia
 * que se desincroniza en cuanto alguien corrige un resultado, y corregir resultados pasa
 * constantemente en una liga de amigos.
 */
function clasificar(inscripciones, partidos) {
  const filas = new Map(
    inscripciones.map((i) => [
      i.id,
      {
        entryId: i.id,
        nombre: i.partner_alias ? `${i.alias} / ${i.partner_alias}` : i.alias,
        jugados: 0,
        ganados: 0,
        perdidos: 0,
        juegosFavor: 0,
        juegosContra: 0,
        puntos: 0,
      },
    ])
  );

  for (const partido of partidos) {
    if (partido.home_games === null || partido.away_games === null) continue;
    const local = filas.get(partido.home);
    const visitante = filas.get(partido.away);
    if (!local || !visitante) continue;

    local.jugados++;
    visitante.jugados++;
    local.juegosFavor += partido.home_games;
    local.juegosContra += partido.away_games;
    visitante.juegosFavor += partido.away_games;
    visitante.juegosContra += partido.home_games;

    if (partido.home_games > partido.away_games) {
      local.ganados++;
      local.puntos++;
      visitante.perdidos++;
    } else {
      visitante.ganados++;
      visitante.puntos++;
      local.perdidos++;
    }
  }

  return [...filas.values()]
    .map((f) => ({ ...f, diferencia: f.juegosFavor - f.juegosContra }))
    .sort(
      (a, b) =>
        b.puntos - a.puntos ||
        b.diferencia - a.diferencia ||
        b.juegosFavor - a.juegosFavor ||
        a.nombre.localeCompare(b.nombre)
    )
    .map((fila, indice) => ({ ...fila, puesto: indice + 1 }));
}

/** Las inscripciones de una liga, con los alias ya resueltos. */
async function inscripcionesDe(env, ligaId) {
  const { results } = await env.DB.prepare(
    `SELECT e.id, e.user, e.partner, u.alias AS alias, p.alias AS partner_alias
       FROM league_entries e
       JOIN users u ON u.id = e.user
       LEFT JOIN users p ON p.id = e.partner
      WHERE e.league = ?1
      ORDER BY e.id`
  )
    .bind(ligaId)
    .all();
  return results || [];
}

/**
 * Rutas de competición. Devuelve null si `path` no es suya, para que el router siga.
 *
 *   POST /v1/competicion/clubes           — crear club
 *   GET  /v1/competicion/clubes           — mis clubes
 *   POST /v1/competicion/clubes/{id}/unirme
 *   GET  /v1/competicion/clubes/{id}      — panel del club
 *   POST /v1/competicion/ligas            — crear liga
 *   GET  /v1/competicion/ligas            — mis ligas
 *   POST /v1/competicion/ligas/{id}/inscribirme
 *   POST /v1/competicion/ligas/{id}/calendario  — generar el calendario y arrancar
 *   GET  /v1/competicion/ligas/{id}       — calendario + clasificación
 *   POST /v1/competicion/ligas/{id}/resultado
 */
export async function competicion(request, env, path) {
  if (!path.startsWith("/v1/competicion")) return null;
  if (!env.DB) return error(500, "sin_base_de_datos", "Falta la base de datos D1");

  const user = await usuarioDe(request, env);
  if (!user) return error(401, "sin_cuenta", "Hace falta una cuenta de la comunidad");

  const ruta = path.replace("/v1/competicion", "");
  const metodo = request.method;
  const cuerpo = metodo === "POST" ? await request.json().catch(() => ({})) : {};

  // ─── Clubes ───

  if (ruta === "/clubes" && metodo === "POST") {
    const nombre = String(cuerpo.nombre || "").trim().slice(0, 80);
    if (!nombre) return error(400, "nombre", "El club necesita un nombre");
    const creado = await env.DB.prepare(
      "INSERT INTO clubs (name, city, creator, created_at) VALUES (?1, ?2, ?3, ?4)"
    )
      .bind(nombre, String(cuerpo.ciudad || "").slice(0, 80), user.id, ahora())
      .run();
    const clubId = creado.meta.last_row_id;
    // Quien crea el club es su administrador: si no, nadie podría gestionarlo.
    await env.DB.prepare(
      "INSERT INTO club_members (club, user, role, joined_at) VALUES (?1, ?2, 'admin', ?3)"
    )
      .bind(clubId, user.id, ahora())
      .run();
    return json(201, { id: clubId, nombre });
  }

  if (ruta === "/clubes" && metodo === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT c.id, c.name AS nombre, c.city AS ciudad, m.role AS papel
         FROM club_members m JOIN clubs c ON c.id = m.club
        WHERE m.user = ?1 ORDER BY c.name`
    )
      .bind(user.id)
      .all();
    return json(200, { clubes: results || [] });
  }

  const unirmeClub = ruta.match(/^\/clubes\/(\d+)\/unirme$/);
  if (unirmeClub && metodo === "POST") {
    await env.DB.prepare(
      `INSERT INTO club_members (club, user, role, joined_at) VALUES (?1, ?2, 'player', ?3)
       ON CONFLICT(club, user) DO NOTHING`
    )
      .bind(Number(unirmeClub[1]), user.id, ahora())
      .run();
    return json(200, { ok: true });
  }

  const verClub = ruta.match(/^\/clubes\/(\d+)$/);
  if (verClub && metodo === "GET") {
    const clubId = Number(verClub[1]);
    const club = await env.DB.prepare(
      "SELECT id, name AS nombre, city AS ciudad FROM clubs WHERE id = ?1"
    )
      .bind(clubId)
      .first();
    if (!club) return error(404, "no_existe", "No hay club con ese id");

    const { results: miembros } = await env.DB.prepare(
      `SELECT u.id, u.alias, m.role AS papel
         FROM club_members m JOIN users u ON u.id = m.user
        WHERE m.club = ?1 ORDER BY m.role, u.alias`
    )
      .bind(clubId)
      .all();
    const { results: ligas } = await env.DB.prepare(
      "SELECT id, name AS nombre, status AS estado FROM leagues WHERE club = ?1 ORDER BY id DESC"
    )
      .bind(clubId)
      .all();

    return json(200, {
      club,
      miembros: miembros || [],
      ligas: ligas || [],
      // El panel del §36.19. Son cuentas, no estimaciones.
      resumen: {
        jugadores: (miembros || []).filter((m) => m.papel === "player").length,
        entrenadores: (miembros || []).filter((m) => m.papel === "coach").length,
        ligas: (ligas || []).length,
      },
    });
  }

  // ─── Ligas ───

  if (ruta === "/ligas" && metodo === "POST") {
    const nombre = String(cuerpo.nombre || "").trim().slice(0, 80);
    if (!nombre) return error(400, "nombre", "La liga necesita un nombre");
    const formato = cuerpo.formato === "parejas" ? "parejas" : "individual";
    const creada = await env.DB.prepare(
      `INSERT INTO leagues (name, club, format, status, starts_on, ends_on, creator, created_at)
       VALUES (?1, ?2, ?3, 'abierta', ?4, ?5, ?6, ?7)`
    )
      .bind(
        nombre,
        cuerpo.club ? Number(cuerpo.club) : null,
        formato,
        String(cuerpo.desde || "").slice(0, 10),
        String(cuerpo.hasta || "").slice(0, 10),
        user.id,
        ahora()
      )
      .run();
    return json(201, { id: creada.meta.last_row_id, nombre, formato });
  }

  if (ruta === "/ligas" && metodo === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT DISTINCT l.id, l.name AS nombre, l.format AS formato, l.status AS estado,
              l.starts_on AS desde, l.ends_on AS hasta
         FROM leagues l
         LEFT JOIN league_entries e ON e.league = l.id
        WHERE l.creator = ?1 OR e.user = ?1 OR e.partner = ?1
        ORDER BY l.id DESC`
    )
      .bind(user.id)
      .all();
    return json(200, { ligas: results || [] });
  }

  const inscribirme = ruta.match(/^\/ligas\/(\d+)\/inscribirme$/);
  if (inscribirme && metodo === "POST") {
    const ligaId = Number(inscribirme[1]);
    const liga = await env.DB.prepare("SELECT format, status FROM leagues WHERE id = ?1")
      .bind(ligaId)
      .first();
    if (!liga) return error(404, "no_existe", "No hay liga con ese id");
    // Una vez generado el calendario no se puede entrar: los partidos ya están repartidos
    // y meter a alguien a mitad dejaría una liga con rondas desiguales.
    if (liga.status !== "abierta") {
      return error(409, "cerrada", "Esta liga ya empezó: no admite inscripciones");
    }

    let parejaId = null;
    if (liga.format === "parejas") {
      const alias = String(cuerpo.pareja || "").trim();
      if (!alias) return error(400, "pareja", "En una liga de parejas hay que decir con quién");
      const pareja = await env.DB.prepare("SELECT id FROM users WHERE alias = ?1")
        .bind(alias)
        .first();
      if (!pareja) return error(404, "pareja", "No existe esa cuenta");
      if (pareja.id === user.id) return error(400, "pareja", "No puedes emparejarte contigo");
      parejaId = pareja.id;
    }

    await env.DB.prepare(
      `INSERT INTO league_entries (league, user, partner, created_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(league, user) DO UPDATE SET partner = ?3`
    )
      .bind(ligaId, user.id, parejaId, ahora())
      .run();
    return json(200, { ok: true });
  }

  const generar = ruta.match(/^\/ligas\/(\d+)\/calendario$/);
  if (generar && metodo === "POST") {
    const ligaId = Number(generar[1]);
    const liga = await env.DB.prepare("SELECT creator, status FROM leagues WHERE id = ?1")
      .bind(ligaId)
      .first();
    if (!liga) return error(404, "no_existe", "No hay liga con ese id");
    if (liga.creator !== user.id) {
      return error(403, "no_eres_organizador", "Solo quien creó la liga genera el calendario");
    }
    if (liga.status !== "abierta") return error(409, "ya_generado", "El calendario ya existe");

    const inscripciones = await inscripcionesDe(env, ligaId);
    if (inscripciones.length < 2) {
      return error(400, "pocos", "Hacen falta al menos dos inscripciones");
    }

    const rondas = calendario(inscripciones.length);
    const inserciones = [];
    rondas.forEach((partidos, indice) => {
      for (const [a, b] of partidos) {
        inserciones.push(
          env.DB.prepare(
            "INSERT INTO league_matches (league, round, home, away) VALUES (?1, ?2, ?3, ?4)"
          ).bind(ligaId, indice + 1, inscripciones[a].id, inscripciones[b].id)
        );
      }
    });
    inserciones.push(
      env.DB.prepare("UPDATE leagues SET status = 'en curso' WHERE id = ?1").bind(ligaId)
    );
    // En lote: media liga con calendario y media sin él sería imposible de arreglar
    // desde la app.
    await env.DB.batch(inserciones);

    return json(201, { rondas: rondas.length, partidos: inserciones.length - 1 });
  }

  const verLiga = ruta.match(/^\/ligas\/(\d+)$/);
  if (verLiga && metodo === "GET") {
    const ligaId = Number(verLiga[1]);
    const liga = await env.DB.prepare(
      `SELECT id, name AS nombre, format AS formato, status AS estado,
              starts_on AS desde, ends_on AS hasta, creator
         FROM leagues WHERE id = ?1`
    )
      .bind(ligaId)
      .first();
    if (!liga) return error(404, "no_existe", "No hay liga con ese id");

    const inscripciones = await inscripcionesDe(env, ligaId);
    const { results: partidos } = await env.DB.prepare(
      `SELECT id, round AS ronda, home, away, home_games, away_games,
              played_on AS fecha, session AS sesion
         FROM league_matches WHERE league = ?1 ORDER BY round, id`
    )
      .bind(ligaId)
      .all();

    const nombres = Object.fromEntries(
      inscripciones.map((i) => [
        i.id,
        i.partner_alias ? `${i.alias} / ${i.partner_alias}` : i.alias,
      ])
    );

    return json(200, {
      liga: { ...liga, soyOrganizador: liga.creator === user.id },
      inscripciones: inscripciones.map((i) => ({ id: i.id, nombre: nombres[i.id] })),
      calendario: (partidos || []).map((p) => ({
        id: p.id,
        ronda: p.ronda,
        local: nombres[p.home] || "?",
        visitante: nombres[p.away] || "?",
        juegosLocal: p.home_games,
        juegosVisitante: p.away_games,
        fecha: p.fecha,
        sesion: p.sesion,
      })),
      clasificacion: clasificar(inscripciones, partidos || []),
    });
  }

  const resultado = ruta.match(/^\/ligas\/(\d+)\/resultado$/);
  if (resultado && metodo === "POST") {
    const ligaId = Number(resultado[1]);
    const partidoId = Number(cuerpo.partido);
    const local = Number(cuerpo.juegosLocal);
    const visitante = Number(cuerpo.juegosVisitante);
    if (!Number.isInteger(local) || !Number.isInteger(visitante) || local < 0 || visitante < 0) {
      return error(400, "resultado", "Los juegos tienen que ser dos números");
    }
    // En pádel no hay empate: un resultado igualado es un resultado mal apuntado, y
    // aceptarlo rompería la clasificación en silencio (los dos sumarían derrota).
    if (local === visitante) return error(400, "empate", "Un partido de pádel no acaba en empate");

    const partido = await env.DB.prepare(
      `SELECT m.id, e1.user AS u1, e1.partner AS p1, e2.user AS u2, e2.partner AS p2
         FROM league_matches m
         JOIN league_entries e1 ON e1.id = m.home
         JOIN league_entries e2 ON e2.id = m.away
        WHERE m.id = ?1 AND m.league = ?2`
    )
      .bind(partidoId, ligaId)
      .first();
    if (!partido) return error(404, "no_existe", "Ese partido no es de esta liga");

    // Solo lo apunta quien lo jugó. Sin esto, cualquiera con cuenta podría escribir
    // resultados de una liga ajena.
    const jugadores = [partido.u1, partido.p1, partido.u2, partido.p2].filter(Boolean);
    if (!jugadores.includes(user.id)) {
      return error(403, "no_jugaste", "Solo quien jugó el partido puede apuntar el resultado");
    }

    await env.DB.prepare(
      `UPDATE league_matches
          SET home_games = ?1, away_games = ?2, played_on = ?3, session = ?4
        WHERE id = ?5`
    )
      .bind(
        local,
        visitante,
        String(cuerpo.fecha || "").slice(0, 10) || ahora().slice(0, 10),
        String(cuerpo.sesion || "").slice(0, 64),
        partidoId
      )
      .run();

    return json(200, { ok: true });
  }

  return error(404, "ruta_desconocida", "Esa ruta de competición no existe");
}
