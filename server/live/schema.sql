-- La comunidad, en D1 (SQLite gestionado por Cloudflare).
-- Se aplica con: wrangler d1 execute rising-padel --file=schema.sql --remote

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alias TEXT NOT NULL UNIQUE,
  -- El token es la identidad entera: se genera aquí, viaja al Llavero del móvil y no
  -- hay contraseña que olvidar ni email que filtrar. Para una comunidad de amigos.
  token TEXT NOT NULL UNIQUE,
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
