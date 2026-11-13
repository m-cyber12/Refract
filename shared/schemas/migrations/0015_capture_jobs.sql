-- Only explicitly approved saves enter durable staging. Previews remain ephemeral.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS capture_jobs (
 id TEXT PRIMARY KEY,
 request_hash TEXT NOT NULL,
 item_id TEXT NOT NULL UNIQUE,
 format TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('queued','processing','failed','completed','cancelled')),
 payload TEXT,
 created_ts INTEGER NOT NULL,
 updated_ts INTEGER NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0,
 error TEXT,
 result_item_id TEXT,
 CHECK ((status IN ('completed','cancelled') AND payload IS NULL) OR
        (status IN ('queued','processing','failed') AND payload IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_capture_jobs_status ON capture_jobs(status,created_ts);
INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','15');
COMMIT;
