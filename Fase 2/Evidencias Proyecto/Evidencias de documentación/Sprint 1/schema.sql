PRAGMA foreign_keys = ON;

-- =========================
-- Tabla: users
-- =========================
CREATE TABLE IF NOT EXISTS users (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    email     TEXT    NOT NULL UNIQUE,
    password  TEXT    NOT NULL,
    role      TEXT    NOT NULL CHECK (role IN ('artist','client')),
    name      TEXT    NOT NULL
    -- created_at DATETIME DEFAULT CURRENT_TIMESTAMP  -- opcional
);

-- Índice auxiliar (SQLite ya optimiza UNIQUE(email), pero dejamos explícito si quieres)
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- =========================
-- Tabla: designs
-- =========================
CREATE TABLE IF NOT EXISTS designs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    title      TEXT     NOT NULL,
    description TEXT,
    image_url  TEXT,
    price      INTEGER,              -- en CLP u otra moneda
    artist_id  INTEGER  NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (artist_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_designs_artist ON designs(artist_id);
CREATE INDEX IF NOT EXISTS idx_designs_created_at ON designs(created_at);

-- =========================
-- Tabla: appointments
-- =========================
CREATE TABLE IF NOT EXISTS appointments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    design_id   INTEGER NOT NULL,
    client_id   INTEGER NOT NULL,
    artist_id   INTEGER NOT NULL,
    start_time  DATETIME NOT NULL,
    end_time    DATETIME NOT NULL,
    status      TEXT DEFAULT 'booked' CHECK (status IN ('booked','canceled','done')),
    pay_now     INTEGER DEFAULT 0,   -- 0/1 en SQLite; el backend lo maneja como boolean
    paid        INTEGER DEFAULT 0,   -- 0/1
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (design_id) REFERENCES designs(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (client_id) REFERENCES users(id)  ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (artist_id) REFERENCES users(id)  ON DELETE RESTRICT ON UPDATE CASCADE,

    -- Evita doble booking exacto mismo inicio para un artista
    CONSTRAINT uq_artist_slot UNIQUE (artist_id, start_time)
);

-- Índices para acelerar búsquedas frecuentes
CREATE INDEX IF NOT EXISTS idx_appt_artist_start ON appointments(artist_id, start_time);
CREATE INDEX IF NOT EXISTS idx_appt_client ON appointments(client_id);
CREATE INDEX IF NOT EXISTS idx_appt_design ON appointments(design_id);
CREATE INDEX IF NOT EXISTS idx_appt_status ON appointments(status);
