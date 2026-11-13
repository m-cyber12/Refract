-- REFRACT schema v3 (Phase 3: Consumer X-Ray & Proof Vault)
-- Subscriptions, evidence records (append-only), and evidence-linked claims.

CREATE TABLE IF NOT EXISTS subscriptions (
    id              TEXT PRIMARY KEY,
    service         TEXT NOT NULL,
    plan            TEXT,
    price           REAL,
    currency        TEXT,
    frequency       TEXT,                -- monthly | yearly | weekly | one_time
    renewal_date    INTEGER,             -- unix ts, nullable
    trial_end       INTEGER,             -- unix ts, nullable
    status          TEXT NOT NULL DEFAULT 'unverified'
                        CHECK (status IN ('confirmed','imported','suspected','unverified')),
    confidence      REAL NOT NULL DEFAULT 0,
    source_doc_id   TEXT,                -- linked evidence record
    created_ts      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_subs_renewal ON subscriptions (renewal_date);

-- Append-only evidence log. Rows are never updated or deleted.
CREATE TABLE IF NOT EXISTS evidence_records (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,           -- receipt | contract | invoice | screenshot | note
    note        TEXT,
    blob_path   TEXT NOT NULL,
    sha256      TEXT NOT NULL,
    imported_ts INTEGER NOT NULL
);

-- Claims extracted from evidence, each linked back to its source record.
-- Direct quotations vs interpretations are distinguished by `claim_type`.
CREATE TABLE IF NOT EXISTS evidence_claims (
    id         TEXT PRIMARY KEY,
    record_id  TEXT NOT NULL REFERENCES evidence_records(id),
    claim_type TEXT NOT NULL,           -- quote | extracted | interpretation
    text       TEXT NOT NULL,
    offset     INTEGER,                 -- byte offset into source text when known
    confidence REAL NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_claims_record ON evidence_claims (record_id);

INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '3');
