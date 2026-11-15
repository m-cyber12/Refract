-- A row means diagnostics were recorded, even when the warning list is empty.
-- Legacy captures deliberately have no row: their extraction history is unknown.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS capture_diagnostics (
 item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
 warnings_json TEXT NOT NULL
);
INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','17');
COMMIT;
