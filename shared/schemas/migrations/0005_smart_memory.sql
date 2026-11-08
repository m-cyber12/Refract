-- REFRACT schema v5 — Phase II master, Phase 3: SMART MEMORY
-- Topics, entities, relationships, temporal context, project spaces.
-- All rule-based and local; nothing here infers beliefs or identity.

CREATE TABLE IF NOT EXISTS topics (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    origin     TEXT NOT NULL DEFAULT 'automatic', -- automatic | user
    created_ts INTEGER NOT NULL,
    pinned     INTEGER NOT NULL DEFAULT 0
);

-- Durable user choices: NULL rejects a keyword category; otherwise redirects
-- future organization to the renamed/merged canonical topic.
CREATE TABLE IF NOT EXISTS topic_rules (
    keyword_topic TEXT PRIMARY KEY COLLATE NOCASE,
    topic_id TEXT REFERENCES topics(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS item_topics (
    item_id    TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    topic_id   TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    is_primary INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (item_id, topic_id)
);

CREATE INDEX IF NOT EXISTS idx_item_topics_topic ON item_topics (topic_id);

CREATE TABLE IF NOT EXISTS entities (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL COLLATE NOCASE,
    kind       TEXT NOT NULL CHECK (kind IN ('person', 'organization', 'date', 'email', 'concept', 'place', 'other')),
    created_ts INTEGER NOT NULL,
    UNIQUE (name, kind)
);

CREATE TABLE IF NOT EXISTS item_entities (
    item_id   TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_item_entities_entity ON item_entities (entity_id);

-- Suggested relationships. Every row carries a basis and a confidence level.
-- Weak similarity is never presented as a factual relationship; users may
-- inspect and remove (dismiss) any connection. Dismissed rows are kept for
-- auditability.
CREATE TABLE IF NOT EXISTS relationships (
    id            TEXT PRIMARY KEY,
    source_item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    target_item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    kind          TEXT NOT NULL CHECK (kind IN (
        'shared_concept', 'same_topic', 'same_organization',
        'related_topic', 'supporting_reference', 'contradicting_source',
        'earlier_version', 'follow_up', 'same_project', 'user_added'
    )),
    basis         TEXT NOT NULL,          -- human-readable evidence for the link
    confidence    REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    dismissed     INTEGER NOT NULL DEFAULT 0,
    created_ts    INTEGER NOT NULL,
    UNIQUE (source_item_id, target_item_id, kind)
);

CREATE INDEX IF NOT EXISTS idx_relationships_target ON relationships (target_item_id);

-- Temporal context: distinct timestamp kinds, never conflated.
-- kind: capture | publication | modification | event | deadline
CREATE TABLE IF NOT EXISTS item_times (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    kind    TEXT NOT NULL CHECK (kind IN ('capture', 'publication', 'modification', 'event', 'deadline')),
    ts      INTEGER NOT NULL,
    note    TEXT,
    UNIQUE (item_id, kind, ts)
);

CREATE INDEX IF NOT EXISTS idx_item_times_ts ON item_times (ts DESC);

-- Project Spaces
CREATE TABLE IF NOT EXISTS projects (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE COLLATE NOCASE,
    description TEXT,
    created_ts  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS project_items (
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    item_id    TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    added_ts   INTEGER NOT NULL,
    PRIMARY KEY (project_id, item_id)
);

UPDATE meta SET value = '5' WHERE key = 'schema_version';
