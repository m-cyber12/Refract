-- Explicitly approved fetched-page handoff copies, not library originals.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS web_previews (
 id TEXT PRIMARY KEY,
 requested_url TEXT NOT NULL,
 final_url TEXT NOT NULL,
 html BLOB NOT NULL,
 sha256 TEXT NOT NULL,
 consent_ts INTEGER NOT NULL
);
INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','16');
COMMIT;
