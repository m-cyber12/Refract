-- REFRACT schema v1 (Phase 1: Reality Compiler MVP)
-- Local-first: SQLite is the primary source of truth.

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '1');

CREATE TABLE IF NOT EXISTS items (
    id                    TEXT PRIMARY KEY,
    source_url            TEXT,
    source_type           TEXT NOT NULL,
    import_ts             INTEGER NOT NULL,
    content_hash          TEXT NOT NULL,          -- SHA-256 of original bytes
    title                 TEXT,
    author                TEXT,
    language              TEXT,
    extraction_confidence REAL NOT NULL DEFAULT 0,
    status                TEXT NOT NULL DEFAULT 'ready'
);

CREATE INDEX IF NOT EXISTS idx_items_import_ts ON items (import_ts DESC);

-- Immutable blobs: original + transformed representations, integrity-hashed.
CREATE TABLE IF NOT EXISTS blobs (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    kind    TEXT NOT NULL CHECK (kind IN ('original', 'transformed')),
    path    TEXT NOT NULL,
    sha256  TEXT NOT NULL
);

-- Structured, transformed representation of an item.
CREATE TABLE IF NOT EXISTS blocks (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    idx     INTEGER NOT NULL,
    kind    TEXT NOT NULL,
    text    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_blocks_item ON blocks (item_id, idx);

-- Full-text search over extracted text (SQLite FTS5).
CREATE VIRTUAL TABLE IF NOT EXISTS blocks_fts USING fts5(
    text,
    content = 'blocks',
    content_rowid = 'id'
);

CREATE TRIGGER IF NOT EXISTS blocks_ai AFTER INSERT ON blocks BEGIN
    INSERT INTO blocks_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS blocks_ad AFTER DELETE ON blocks BEGIN
    INSERT INTO blocks_fts(blocks_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS blocks_au AFTER UPDATE ON blocks BEGIN
    INSERT INTO blocks_fts(blocks_fts, rowid, text) VALUES ('delete', old.id, old.text);
    INSERT INTO blocks_fts(rowid, text) VALUES (new.id, new.text);
END;
