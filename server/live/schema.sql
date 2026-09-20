-- La comunidad, en D1 (SQLite gestionado por Cloudflare).
-- Se aplica con: wrangler d1 execute rising-padel --file=schema.sql --remote

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alias TEXT NOT NULL UNIQUE,
  -- El token es la identidad entera: se genera aquí, viaja al Llavero del móvil y no
  -- hay contraseña que olvidar ni email que filtrar. Para una comunidad de amigos.
  token TEXT NOT NULL UNIQUE,
  -- Qué es esta cuenta: player | coach | club | admin.
  --
  -- Hoy todas son 'player' y nada lo mira. Existe porque añadir una columna a una tabla
  -- con datos es barato y REPARTIR una tabla que nació sin ella no lo es: el día que un
  -- entrenador vea a sus jugadores, la relación entrenador-jugador cuelga de aquí. Ver
  -- el §36.22 del documento de producto.
  role TEXT NOT NULL DEFAULT 'player',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS follows (
  follower INTEGER NOT NULL REFERENCES users(id),
  followed INTEGER NOT NULL REFERENCES users(id),
  PRIMARY KEY (follower, followed)
);

CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user INTEGER NOT NULL REFERENCES users(id),
  text TEXT NOT NULL,
  -- Tarjeta de partido opcional (JSON): resultado, sets, nivel... La pinta la app.
  card TEXT,
  -- Foto opcional: el id del objeto en R2 (GET /v1/comunidad/foto/{id}).
  photo TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS post_tags (
  post INTEGER NOT NULL REFERENCES posts(id),
  user INTEGER NOT NULL REFERENCES users(id),
  PRIMARY KEY (post, user)
);

CREATE TABLE IF NOT EXISTS devices (
  apns TEXT PRIMARY KEY,
  user INTEGER NOT NULL REFERENCES users(id)
);

-- Los dos mínimos de una app con contenido de usuarios: bloquear y denunciar.
CREATE TABLE IF NOT EXISTS blocks (
  user INTEGER NOT NULL REFERENCES users(id),
  blocked INTEGER NOT NULL REFERENCES users(id),
  PRIMARY KEY (user, blocked)
);

-- Una reacción por persona y post; repetir la misma la quita, otra la sustituye.
CREATE TABLE IF NOT EXISTS reactions (
  post INTEGER NOT NULL REFERENCES posts(id),
  user INTEGER NOT NULL REFERENCES users(id),
  emoji TEXT NOT NULL,
  PRIMARY KEY (post, user)
);

CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  post INTEGER NOT NULL REFERENCES posts(id),
  user INTEGER NOT NULL REFERENCES users(id),
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Un resultado por partido en vivo terminado: lo apunta el worker solo, con el último
-- estado (completed=true). Es lo que alimenta el ranking semanal.
CREATE TABLE IF NOT EXISTS results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user INTEGER NOT NULL REFERENCES users(id),
  session TEXT NOT NULL UNIQUE,
  date TEXT NOT NULL,
  won INTEGER NOT NULL DEFAULT 0,
  shots INTEGER NOT NULL DEFAULT 0,
  -- Recuento por tipo de golpe (JSON), enriquecido cuando la sesión completa llega al
  -- buzón. Es lo que arbitra los retos de "más bandejas".
  by_type TEXT
);

-- Retos entre amigos: una métrica medida por el reloj, una ventana de días, y el
-- servidor arbitra con los resultados reales. Nadie puede inflar un reto a mano.
CREATE TABLE IF NOT EXISTS challenges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  challenger INTEGER NOT NULL REFERENCES users(id),
  challenged INTEGER NOT NULL REFERENCES users(id),
  -- 'golpes' | 'victorias' | un tipo de golpe del reloj ('bandeja', 'vibora', 'smash')
  metric TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Torneos entre amigos: bracket de 2, 4 u 8. Los cruces avanzan al reportar ganador.
CREATE TABLE IF NOT EXISTS tournaments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  creator INTEGER NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'activo',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tmatches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  t INTEGER NOT NULL REFERENCES tournaments(id),
  round INTEGER NOT NULL,
  slot INTEGER NOT NULL,
  p1 INTEGER REFERENCES users(id),
  p2 INTEGER REFERENCES users(id),
  winner INTEGER REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reporter INTEGER NOT NULL REFERENCES users(id),
  post INTEGER NOT NULL REFERENCES posts(id),
  reason TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

-- El código de recuperación: la única puerta de vuelta a una cuenta sin token.
-- Se genera una vez y no cambia.
CREATE TABLE IF NOT EXISTS recovery_codes (
  user_id INTEGER PRIMARY KEY REFERENCES users(id),
  code TEXT NOT NULL
);

-- El ancla del nivel: qué mide el reloj a jugadores que declaran un nivel conocido.
-- Una fila por usuario, siempre la última medición.
CREATE TABLE IF NOT EXISTS levels (
  user INTEGER PRIMARY KEY REFERENCES users(id),
  declared REAL NOT NULL,
  measured REAL NOT NULL,
  updated_at TEXT NOT NULL
);

-- El consumo del entrenador IA, una fila por usuario y mes. Existe porque la clave de
-- Anthropic es del servicio y no del usuario: sin un contador en el servidor, el
-- endpoint sería un asistente gratis para quien se registre. El plan vive aquí para que
-- el día que haya suscripción lo único que cambie sea quién escribe esta columna.
CREATE TABLE IF NOT EXISTS coach_usage (
  user INTEGER NOT NULL REFERENCES users(id),
  period TEXT NOT NULL,          -- 'yyyy-mm'
  used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user, period)
);

-- La suscripción del jugador. Va aparte de coach_usage a propósito: el consumo se
-- reinicia cada mes y el plan NO. Con el plan dentro de coach_usage, el día 1 no había
-- fila todavía, se leía 'free' y se escribía 'free' — un suscriptor de pago habría
-- vuelto al plan gratuito cada primero de mes sin que nadie tocara nada.
--
-- expires_at permite que una suscripción vencida caiga sola a gratuito aunque el aviso
-- de Apple se pierda: el sistema no depende de que el webhook llegue siempre.
CREATE TABLE IF NOT EXISTS subscriptions (
  user INTEGER PRIMARY KEY REFERENCES users(id),
  plan TEXT NOT NULL DEFAULT 'free',        -- free | pro | elite
  product TEXT NOT NULL DEFAULT '',         -- el id del producto de App Store Connect
  original_transaction_id TEXT,             -- la identidad estable de la suscripción
  expires_at TEXT,                          -- ISO 8601; NULL = sin caducidad conocida
  updated_at TEXT NOT NULL
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Competición: clubes, ligas y sus partidos (§36.14, §36.16, §36.19)
--
-- Todo cuelga de identificadores y nada duplica información, que es lo que pide el
-- §36.20: un jugador pertenece a un club, compite en una liga de ese club y juega
-- partidos de esa liga, y ninguno de los tres guarda copias del otro.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS clubs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  city TEXT NOT NULL DEFAULT '',
  creator INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL
);

-- Quién pertenece a qué club y con qué papel. El papel es del club y no de la cuenta:
-- la misma persona puede ser jugador en un club y entrenador en otro, y guardarlo en
-- users obligaría a elegir uno.
CREATE TABLE IF NOT EXISTS club_members (
  club INTEGER NOT NULL REFERENCES clubs(id),
  user INTEGER NOT NULL REFERENCES users(id),
  role TEXT NOT NULL DEFAULT 'player',   -- player | coach | admin
  joined_at TEXT NOT NULL,
  PRIMARY KEY (club, user)
);

-- Una liga. `club` es opcional: una liga entre amigos no necesita club.
CREATE TABLE IF NOT EXISTS leagues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  club INTEGER REFERENCES clubs(id),
  format TEXT NOT NULL DEFAULT 'individual',  -- individual | parejas
  status TEXT NOT NULL DEFAULT 'abierta',     -- abierta | en curso | cerrada
  starts_on TEXT NOT NULL DEFAULT '',
  ends_on TEXT NOT NULL DEFAULT '',
  creator INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL
);

-- Una inscripción: un jugador solo, o una pareja. `partner` nulo = individual.
--
-- La pareja se guarda como DOS columnas de la misma fila y no como dos filas enlazadas
-- porque en una liga de parejas la unidad que compite es la pareja: si fueran dos filas,
-- nada impediría que uno de los dos se borrara y quedara media pareja en la tabla.
CREATE TABLE IF NOT EXISTS league_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  league INTEGER NOT NULL REFERENCES leagues(id),
  user INTEGER NOT NULL REFERENCES users(id),
  partner INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL,
  UNIQUE (league, user)
);

-- Un partido del calendario. Se crea vacío al generar la liga y se rellena al jugarse.
CREATE TABLE IF NOT EXISTS league_matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  league INTEGER NOT NULL REFERENCES leagues(id),
  round INTEGER NOT NULL,
  home INTEGER NOT NULL REFERENCES league_entries(id),
  away INTEGER NOT NULL REFERENCES league_entries(id),
  -- Juegos ganados por cada lado. Nulos mientras no se haya jugado: un 0-0 guardado
  -- sería un partido jugado y empatado, que en pádel no existe.
  home_games INTEGER,
  away_games INTEGER,
  played_on TEXT NOT NULL DEFAULT '',
  -- La sesión del reloj que respalda el resultado, si la hay. Es lo que une la
  -- competición con lo que de verdad midió el reloj.
  session TEXT NOT NULL DEFAULT ''
);
