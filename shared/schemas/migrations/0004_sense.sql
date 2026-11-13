-- REFRACT schema v4 (Phase II master, Phase 2: REFRACT SENSE)
-- Classification decisions, value scores, capture policies (rules + presets),
-- and an append-only-ish capture decision log with undo support.

ALTER TABLE items ADD COLUMN sense_decision TEXT NOT NULL DEFAULT 'smart_suggest'
    CHECK (sense_decision IN ('auto_save','smart_suggest','ignore'));
ALTER TABLE items ADD COLUMN sense_score REAL NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS sense_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- User-editable capture policies. `kind` controls how the pattern is applied:
--   allow_source     | auto-save anything from a matching source (domain/url prefix)
--   deny_source      | ignore anything from a matching source
--   allow_category   | auto-save a matching classified category
--   confirm_category | force smart-suggest review for a matching category
CREATE TABLE IF NOT EXISTS sense_rules (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL CHECK (kind IN ('allow_source','deny_source','allow_category','confirm_category')),
    pattern    TEXT NOT NULL,
    enabled    INTEGER NOT NULL DEFAULT 1,
    preset     TEXT NOT NULL DEFAULT 'custom',  -- which preset installed this rule
    created_ts INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sense_rules_kind ON sense_rules (kind, enabled);

-- Decision log: one row per pipeline decision. `undone` supports review/undo;
-- rows are never deleted so capture history is preserved.
CREATE TABLE IF NOT EXISTS capture_decisions (
    id          TEXT PRIMARY KEY,
    item_id     TEXT,                     -- nullable for rejected-before-persist
    decision    TEXT NOT NULL CHECK (decision IN ('auto_save','smart_suggest','ignore')),
    score       REAL NOT NULL,
    category    TEXT NOT NULL,
    explanation TEXT NOT NULL,
    rule_id     TEXT,
    ts          INTEGER NOT NULL,
    undone      INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_decisions_item ON capture_decisions (item_id);
CREATE INDEX IF NOT EXISTS idx_decisions_ts ON capture_decisions (ts);

INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '4');
