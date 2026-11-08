-- Local Daily Signal, explicit reading places and source-backed event candidates.
CREATE TABLE IF NOT EXISTS signal_settings (id INTEGER PRIMARY KEY CHECK(id=1), config_json TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS signal_editions (id INTEGER PRIMARY KEY CHECK(id=1), generated_ts INTEGER NOT NULL, edition_json TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS signal_dismissals (entry_key TEXT PRIMARY KEY, dismissed_ts INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS reading_places (
    item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    block_idx INTEGER,
    status TEXT NOT NULL CHECK(status IN ('started','completed')),
    updated_ts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS signal_events (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    block_idx INTEGER NOT NULL,
    title TEXT NOT NULL,
    event_ts INTEGER NOT NULL,
    category TEXT NOT NULL CHECK(category IN ('renewal','trial_end','warranty_expiry','appointment','delivery','project_deadline','document_expiry','date_mention')),
    confidence REAL NOT NULL CHECK(confidence BETWEEN 0 AND 1),
    evidence TEXT NOT NULL,
    extracted_ts INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'unconfirmed' CHECK(status IN ('unconfirmed','confirmed','dismissed')),
    UNIQUE(item_id,block_idx,event_ts,category)
);
CREATE INDEX IF NOT EXISTS idx_signal_events_date ON signal_events(event_ts,status);
UPDATE meta SET value='7' WHERE key='schema_version';
