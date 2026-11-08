-- Derived consumer claims retain exact parsed-source evidence and audit history.
-- Original blobs, prior subscriptions and legacy Vault evidence are unchanged.
CREATE TABLE IF NOT EXISTS consumer_scans (
    item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    scanned_ts INTEGER NOT NULL,
    extractor_version TEXT NOT NULL,
    examined_blocks INTEGER NOT NULL,
    total_blocks INTEGER NOT NULL,
    truncated INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS consumer_claims (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    block_idx INTEGER NOT NULL,
    category TEXT NOT NULL,
    field TEXT NOT NULL,
    value TEXT NOT NULL,
    value_type TEXT NOT NULL CHECK(value_type IN ('text','money','date','clause','frequency')),
    amount_minor INTEGER,
    currency TEXT,
    date_ts INTEGER,
    quote TEXT NOT NULL,
    start_byte INTEGER NOT NULL,
    end_byte INTEGER NOT NULL,
    confidence REAL NOT NULL CHECK(confidence BETWEEN 0 AND 1),
    extracted_ts INTEGER NOT NULL,
    extractor_version TEXT NOT NULL,
    source_text_sha256 TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unconfirmed' CHECK(status IN ('unconfirmed','user_confirmed','rejected')),
    UNIQUE(item_id,block_idx,start_byte,end_byte,field,value,extractor_version,source_text_sha256)
);
CREATE INDEX IF NOT EXISTS idx_consumer_claims_item ON consumer_claims(item_id,field,status);
CREATE INDEX IF NOT EXISTS idx_consumer_claims_field ON consumer_claims(field,status,date_ts);
CREATE TABLE IF NOT EXISTS consumer_reviews (
    id TEXT PRIMARY KEY,
    claim_id TEXT NOT NULL REFERENCES consumer_claims(id),
    from_status TEXT NOT NULL,
    to_status TEXT NOT NULL,
    reviewed_ts INTEGER NOT NULL
);
-- Linking is explicit and idempotent, never automatic subscription activation.
CREATE TABLE IF NOT EXISTS consumer_subscription_links (
    item_id TEXT PRIMARY KEY REFERENCES items(id),
    subscription_id TEXT NOT NULL REFERENCES subscriptions(id),
    created_ts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS consumer_subscription_claims (
    subscription_id TEXT NOT NULL REFERENCES subscriptions(id),
    claim_id TEXT NOT NULL REFERENCES consumer_claims(id),
    PRIMARY KEY(subscription_id,claim_id)
);
UPDATE meta SET value='8' WHERE key='schema_version';
