// El servidor de la liga como Cloudflare Worker: el trozo que faltaba para que un
// partido se pueda seguir desde cualquier móvil.
//
// Implementa el contrato de docs/openapi.yaml:
//
//   PUT  /v1/live/{sessionId}   — el iPhone publica el estado (Bearer LIVE_TOKEN)
//   GET  /v1/live/{sessionId}   — el último estado, JSON, sin autenticación
//   GET  /{sessionId}           — página de espectador (HTML que refresca solo)
//   POST /v1/padel-sessions     — buzón de sesiones (Bearer), para que la app pueda
//                                 apuntar su URL de liga aquí sin que el envío de
//                                 sesiones falle. Idempotente por sessionId.
//
// Las rutas aceptan también el prefijo /api, porque la URL de liga configurada en la
// app puede llevarlo (el contrato define servers como https://{host}/api).
//
// El GET en vivo es público a propósito: el enlace se comparte con quien quiera seguir
// el partido. El sessionId es un UUID aleatorio — no se puede enumerar — y el estado no
// lleva salud más allá del pulso instantáneo, que solo va si el emisor comparte salud.

import { apuntarResultado, avisarPartidoEnVivo, comunidad, usuarioDe } from "./comunidad.js";

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// Un partido dura dos horas; 6 de margen dejan ver el FINAL a quien llega tarde, y
// después el estado desaparece solo — un marcador en vivo no es un archivo histórico.
const LIVE_TTL_SECONDS = 6 * 60 * 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // La app construye <URL de liga>/v1/… y esa URL puede acabar en /api.
    const path = url.pathname.replace(/^\/api(?=\/)/, "");

    const live = path.match(/^\/v1\/live\/([^/]+)$/);
    if (live) {
      if (!UUID.test(live[1])) return texto(404, "No hay partido con ese id");
      const key = `live:${live[1].toLowerCase()}`;

      if (request.method === "PUT") {
        // Dos formas de escribir: el token de usuario de la comunidad (lo normal una
        // vez registrado) o el LIVE_TOKEN clásico de instalación a mano.
        const user = env.DB ? await usuarioDe(request, env) : null;
        if (!user && !autorizado(request, env)) return texto(401, "Token inválido");
        const body = await request.text();
        if (body.length > 16_384) return texto(413, "Estado demasiado grande");
        let estado;
        try {
          estado = JSON.parse(body);
        } catch {
          return texto(400, "El estado tiene que ser JSON");
        }
        // El aviso a los seguidores sale solo con el PRIMER estado del partido: si ya
        // había clave, es un punto más, no un partido nuevo.
        const esNuevo = user && (await env.LIVE.get(key)) === null;
        // Con cuenta, el estado guarda el alias: la página del espectador pone
        // nombre a la fila azul. Los decodificadores de las apps lo ignoran.
        if (user) estado.alias = user.alias;
        await env.LIVE.put(key, JSON.stringify(estado), { expirationTtl: LIVE_TTL_SECONDS });
        if (user) {
          const sessionId = live[1].toLowerCase();
          await env.LIVE.put(`live-user:${user.alias}`, sessionId, {
            expirationTtl: 2 * 60 * 60,
          });
          if (esNuevo) await avisarPartidoEnVivo(env, user, sessionId);
          if (estado?.completed) {
            // Partido terminado: al ranking semanal, y fuera de "está jugando".
            await apuntarResultado(env, user, sessionId, estado);
            await env.LIVE.delete(`live-user:${user.alias}`);
          }
        }
        return new Response(null, { status: 204 });
      }

      if (request.method === "GET") {
        const estado = await env.LIVE.get(key);
        if (!estado) return texto(404, "No hay partido con ese id");
        return new Response(estado, {
          headers: {
            "content-type": "application/json; charset=utf-8",
            // Sin caché y con CORS abierto: es un marcador que cambia cada punto y
            // que cualquier página debe poder leer.
            "cache-control": "no-store",
            "access-control-allow-origin": "*",
          },
        });
      }

      return texto(405, "Método no soportado");
    }

    // La comunidad entera vive en su módulo; D1 tiene que estar configurada.
    if (path.startsWith("/v1/comunidad")) {
      if (!env.DB) return texto(500, "Falta la base de datos D1 (ver README)");
      const respuesta = await comunidad(request, env, path);
      if (respuesta) return respuesta;
    }

    if (path === "/v1/padel-sessions" && request.method === "POST") {
      const user = env.DB ? await usuarioDe(request, env) : null;
      if (!user && !autorizado(request, env)) return error(401, "unauthorized", "Token inválido");
      let sesion;
      try {
        sesion = await request.json();
      } catch {
        return error(400, "invalid_payload", "El cuerpo tiene que ser JSON");
      }
      const id = request.headers.get("idempotency-key") || sesion.sessionId;
      if (!id || !UUID.test(id)) {
        return error(400, "invalid_payload", "Falta un sessionId UUID");
      }
      const key = `session:${id.toLowerCase()}`;
      const ref = JSON.stringify({ id, sessionId: id });
      // Idempotencia del contrato: repetir la clave devuelve 200, no crea un duplicado.
      const existente = await env.LIVE.get(key);
      if (existente) return json(200, ref);
      await env.LIVE.put(key, JSON.stringify(sesion));
      // La sesión completa trae el desglose por golpe: se enriquece el resultado, que
      // es lo que arbitra los retos de "más bandejas". El won del vivo no se pisa.
      if (user && sesion.shots?.byType) {
        await env.DB.prepare(
          `INSERT INTO results (user, session, date, won, shots, by_type)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
           ON CONFLICT(session) DO UPDATE SET by_type = ?6, shots = ?5`
        ).bind(
          user.id, id.toLowerCase(),
          String(sesion.startedAt ?? "").slice(0, 10) || new Date().toISOString().slice(0, 10),
          sesion.score?.winner === "us" ? 1 : 0,
          sesion.shots?.total ?? 0,
          JSON.stringify(sesion.shots.byType).slice(0, 2048)
        ).run();
      }
      return json(201, ref);
    }

    // La página del espectador: /<uuid> (o /live/<uuid>), lo que se comparte por chat.
    const pagina = path.match(/^\/(?:live\/)?([0-9a-fA-F-]{36})$/);
    if (pagina && request.method === "GET" && UUID.test(pagina[1])) {
      return new Response(paginaEspectador(pagina[1].toLowerCase()), {
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
      });
    }

    // La descarga del conjunto de entrenamiento entero, para el workflow que entrena
    // el clasificador. Va con su propio secreto (`TANDAS_TOKEN`) y no con el token de
    // un usuario: quien entrena necesita las tandas de TODOS, y ese permiso no puede
    // colgar de la cuenta de nadie.
    //
    // Sin el secreto configurado el endpoint no existe, en vez de existir con un token
    // vacío que cualquiera acierta mandando `Bearer undefined`.
    if (path === "/v1/tandas/export" && request.method === "GET") {
      if (!env.TANDAS_TOKEN) return texto(404, "Nada por aquí");
      if (request.headers.get("authorization") !== `Bearer ${env.TANDAS_TOKEN}`) {
        return texto(401, "Token inválido");
      }
      if (!env.FOTOS) return texto(500, "El servidor no tiene R2 configurado");

      // Se concatenan los JSONL en uno: es el formato que espera el entrenador y el
      // que digieren pandas y jq sin ceremonia. En streaming para no cargar en
      // memoria del Worker un dataset que puede pesar cientos de megas.
      const listado = await env.FOTOS.list({ prefix: "tandas/" });
      const { readable, writable } = new TransformStream();
      (async () => {
        const writer = writable.getWriter();
        try {
          for (const objeto of listado.objects) {
            const cuerpo = await env.FOTOS.get(objeto.key);
            if (!cuerpo) continue;
            await writer.write(new Uint8Array(await cuerpo.arrayBuffer()));
            // Cada fichero puede no acabar en salto de línea, y sin él la última
            // muestra de uno y la primera del siguiente se pegarían en una sola.
            await writer.write(new TextEncoder().encode("\n"));
          }
        } finally {
          await writer.close();
        }
      })();
      return new Response(readable, {
        headers: {
          "content-type": "application/x-ndjson; charset=utf-8",
          "x-tandas-ficheros": String(listado.objects.length),
        },
      });
    }

    return texto(404, "Nada por aquí");
  },
};

function autorizado(request, env) {
  return request.headers.get("authorization") === `Bearer ${env.LIVE_TOKEN}`;
}

function texto(status, mensaje) {
  return new Response(mensaje, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function json(status, body) {
  return new Response(body, {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function error(status, code, message) {
  return json(status, JSON.stringify({ error: { code, message } }));
}

// La página entera va inline en el worker: un fichero, cero dependencias, y el
// espectador solo necesita ver un marcador que se refresca solo cada pocos segundos.
function paginaEspectador(id) {
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rising Padel · En vivo</title>
<style>
  :root { --fondo:#f7f4ec; --tinta:#1c1b17; --suave:#77746a; --pista:#1f6f8b; --verde:#2e7d32; --rojo:#c62828; --carta:#ffffff; --borde:#e4e0d4; }
  @media (prefers-color-scheme: dark) {
    :root { --fondo:#161512; --tinta:#f0ede4; --suave:#98948a; --carta:#211f1a; --borde:#35322a; }
  }
  * { box-sizing: border-box; margin: 0; }
  body { background: var(--fondo); color: var(--tinta); font-family: ui-rounded, -apple-system, "SF Pro Rounded", system-ui, sans-serif; display: flex; justify-content: center; padding: 24px 16px; }
  main { width: 100%; max-width: 420px; }
  .carta { background: var(--carta); border: 1px solid var(--borde); border-radius: 16px; padding: 20px; margin-bottom: 12px; }
  .cabecera { display: flex; align-items: center; gap: 8px; font-size: 12px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--suave); }
  .punto { width: 8px; height: 8px; border-radius: 50%; background: var(--rojo); animation: latido 1.2s infinite; }
  .final .punto { animation: none; background: var(--suave); }
  @keyframes latido { 50% { opacity: .25; } }
  /* El marcador de retransmisión: una fila por equipo, los mismos colores que la app. */
  .equipos { display: flex; flex-direction: column; gap: 8px; margin-top: 14px; }
  .equipo { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 12px; }
  .equipo.azul { background: rgba(41,98,255,.10); color: #2962ff; }
  .equipo.naranja { background: rgba(255,122,26,.12); color: #f06d0a; }
  .equipo .bola { flex: 0 0 10px; color: #f4d03f; font-size: 10px; }
  .equipo .nombre { flex: 0 1 auto; min-width: 0; font-size: 13px; font-weight: 900; letter-spacing: .06em; text-transform: uppercase; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .equipo .set { width: 22px; text-align: center; font-size: 19px; font-weight: 700; color: var(--suave); font-variant-numeric: tabular-nums; }
  .equipo .set.actual { color: var(--tinta); font-weight: 900; }
  .equipo .chip { margin-left: auto; min-width: 56px; text-align: center; font-size: 24px; font-weight: 900; color: #fff; border-radius: 9px; padding: 2px 8px; font-variant-numeric: tabular-nums; }
  .equipo.azul .chip { background: #2962ff; }
  .equipo.naranja .chip { background: #f06d0a; }
  #crono { margin-left: auto; font-variant-numeric: tabular-nums; }
  .metricas { display: flex; justify-content: space-around; margin-top: 16px; text-align: center; }
  .metricas b { display: block; font-size: 20px; font-variant-numeric: tabular-nums; }
  #ritmo { width: 100%; height: 64px; margin-top: 14px; display: none; }
  .metricas span { font-size: 11px; color: var(--suave); text-transform: uppercase; letter-spacing: .08em; }
  .aviso { text-align: center; color: var(--suave); font-size: 14px; padding: 24px 0; }
  .ganador { text-align: center; font-size: 15px; font-weight: 800; color: var(--verde); margin-top: 10px; }
</style>
</head>
<body>
<main>
  <div class="carta" id="carta">
    <div class="cabecera"><span class="punto"></span><span id="estado">EN VIVO</span><span id="crono"></span></div>
    <div id="cuerpo" class="aviso">Buscando el partido…</div>
    <canvas id="ritmo" width="760" height="128"></canvas>
  </div>
</main>
<script>
const ID = ${JSON.stringify(id)};
const $ = (s) => document.querySelector(s);
let fallos = 0;
// La curva de golpeos se acumula mientras se mira: cada estado trae el total y el
// minuto, y con dos puntos ya hay pendiente — el ritmo del partido, en vivo.
const serie = [];

function pintaRitmo() {
  if (serie.length < 2) return;
  const c = $("#ritmo");
  c.style.display = "block";
  const ctx = c.getContext("2d");
  ctx.clearRect(0, 0, c.width, c.height);
  const xs = serie.map((p) => p.t), ys = serie.map((p) => p.c);
  const x0 = xs[0], x1 = Math.max(xs[xs.length - 1], x0 + 1);
  const y1 = Math.max(...ys, 1);
  ctx.beginPath();
  ctx.strokeStyle = "#1f6f8b";
  ctx.lineWidth = 4;
  serie.forEach((p, i) => {
    const x = 8 + (c.width - 16) * (p.t - x0) / (x1 - x0);
    const y = c.height - 8 - (c.height - 16) * (p.c / y1);
    i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
  });
  ctx.stroke();
}

// La fila de un equipo: bolita de saque, nombre, sets en columnas y el punto en
// juego en grande — el mismo marcador de retransmisión que la app.
function fila(clase, nombre, sets, lado, s) {
  const saca = !s.completed && s.serving === lado;
  const setsHtml = sets
    .map((v, i) => '<span class="set' + (i === sets.length - 1 ? " actual" : "") + '">' + v + "</span>")
    .join("");
  const puntos = lado === "us" ? s.pointsUs : s.pointsThem;
  const chip = !s.completed && puntos != null ? '<span class="chip">' + puntos + "</span>" : "";
  return '<div class="equipo ' + clase + '"><span class="bola">' + (saca ? "●" : "") +
         '</span><span class="nombre">' + nombre + "</span>" + setsHtml + chip + "</div>";
}

function pinta(s) {
  const sets = (s.score && s.score.sets) || [];
  // El alias solo viaja si el que publica tiene cuenta; el marcador se ve igual.
  const quien = s.alias ? "@" + s.alias : "JUGADOR";
  let html =
    '<div class="equipos">' +
    fila("azul", quien, sets.map((x) => x.us), "us", s) +
    fila("naranja", "RIVALES", sets.map((x) => x.them), "them", s) +
    "</div>";
  if (s.completed && s.score && s.score.winner) {
    html += '<div class="ganador">' +
      (s.score.winner === "us" ? "Gana " + quien : "Ganan los rivales") + "</div>";
  }
  if (s.elapsedSeconds) {
    const m = Math.floor(s.elapsedSeconds / 60), seg = s.elapsedSeconds % 60;
    $("#crono").textContent = m + ":" + String(seg).padStart(2, "0");
  }
  const m = [];
  if (s.shotCount) m.push("<div><b>" + s.shotCount + "</b><span>golpeos</span></div>");
  if (s.heartRateBpm) m.push("<div><b>" + s.heartRateBpm + "</b><span>ppm</span></div>");
  if (s.elapsedSeconds) m.push("<div><b>" + Math.floor(s.elapsedSeconds / 60) + "'</b><span>jugados</span></div>");
  if (m.length) html += '<div class="metricas">' + m.join("") + "</div>";
  $("#cuerpo").className = "";
  $("#cuerpo").innerHTML = html || '<div class="aviso">Partido en marcha, sin marcador todavía.</div>';
  if (s.completed) {
    $("#carta").classList.add("final");
    $("#estado").textContent = "FINAL";
  }
  return s.completed;
}

async function tick() {
  try {
    const r = await fetch("/v1/live/" + ID, { cache: "no-store" });
    if (r.status === 404) {
      $("#cuerpo").innerHTML = "El partido no está publicado (o ya expiró).";
      $("#cuerpo").className = "aviso";
      setTimeout(tick, 10000);
      return;
    }
    const s = await r.json();
    fallos = 0;
    const ultimo = serie[serie.length - 1];
    if (!ultimo || s.shotCount !== ultimo.c) {
      serie.push({ t: s.elapsedSeconds || 0, c: s.shotCount || 0 });
      pintaRitmo();
    }
    if (pinta(s)) return; // FINAL: se deja de refrescar.
  } catch (e) {
    if (++fallos > 3) $("#estado").textContent = "SIN SEÑAL";
  }
  setTimeout(tick, 5000);
}
tick();
</script>
</body>
</html>`;
}
