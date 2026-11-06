-- REFRACT schema v2 (Phase 2: Personal Memory MVP)
-- Tags, collections, and annotations (highlights/notes anchored to content).

CREATE TABLE IF NOT EXISTS tags (
    id    TEXT PRIMARY KEY,
    name  TEXT NOT NULL UNIQUE,
    color TEXT
);

CREATE TABLE IF NOT EXISTS item_tags (
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, tag_id)
);

CREATE TABLE IF NOT EXISTS collections (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    created_ts INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS item_collections (
    item_id       TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, collection_id)
);

-- Annotations are attached to content (block index + quote anchor), never to
-- screen coordinates (spec §C1/C2).
CREATE TABLE IF NOT EXISTS annotations (
    id         TEXT PRIMARY KEY,
    item_id    TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    quote      TEXT NOT NULL,          -- selected text (anchor quote)
    note       TEXT,
    block_idx  INTEGER,                -- block the quote was taken from
    visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','shared','workspace','public')),
    created_ts INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_annotations_item ON annotations (item_id);

INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '2');
